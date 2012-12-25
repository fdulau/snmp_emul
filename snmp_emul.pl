#!/usr/bin/perl

##########################################################
# snmp_emul
# Gnu GPL2 license
#
# $Id: agentx_redis.pl 2 2010-12-18 13:54:15Z fabrice $
#
# Fabrice Dulaunoy <fabrice@dulaunoy.com>
# copyright 2010,2011,2012 Fabrice Dulaunoy
###########################################################

use strict;
use warnings;

use Data::Dumper;
use Getopt::Std;
use POSIX qw(setsid);
use NetSNMP::agent ( ':all' );
use NetSNMP::ASN qw(:all);
use NetSNMP::default_store        ( ':all' );
use NetSNMP::agent::default_store ( ':all' );
use SNMP;
use Redis;

my $VERSION = '2.07';
my %opts;

getopts( 'Dd:hv', \%opts );

if ( $opts{ 'h' } )
{
    print "usage $0 [-D] [-d level] [-h] [-v]\n\n";
    print "\t -h \t\t this help\n";
    print "\t -d level\t\t debug level\n";
    print "\t -D \t\t detach and daemonize\n";
    print "\t -v \t\t print version and die\n";
    exit;
}

if ( $opts{ 'v' } )
{
    die "$0 v$VERSION (c) DULAUNOY Fabrice, 20012-2013\n";
}

daemonize() if ( $opts{ 'D' } );

my $REDIS = '127.0.0.1:6379';
my $redis = Redis->new(
    server => $REDIS,
    debug  => 0
);

$redis->select( 4 );    # use DB nbr 4 ( why not !!!)
use subs qw(say);

my $AGENT_NAME = "agent_fab_$$";
my $DEBUG      = 3;
my $DEBUG_SNMP = 0;
my $file_name  = '/tmp/snmp.log';

sub myhandler
{
    my ( $handler, $registration_info, $request_info, $requests ) = @_;
    my $request;

    for ( $request = $requests ; $request ; $request = $request->next() )
    {
        my $oid            = $request->getOID();
        my $translated_oid = SNMP::translateObj( $oid );
        my $next           = $redis->hget( 'next', $translated_oid ) || $translated_oid;
        last if ( $next eq $translated_oid );
# say "mode=".$request_info->getMode() ;
        if ( $request_info->getMode() == MODE_GET )
        {

            if ( $redis->hexists( 'access', $translated_oid ) )
            {
                my $type = $redis->hget( 'type', $translated_oid );
                next if ( $type == 0 );
                my $value;
                if ( length $redis->hget( 'val', $translated_oid ) )
                {
                    $value = $redis->hget( 'val', $translated_oid );
                }
                else
                {
                    $value = create_val( $type );
                }

                no strict;
                if ( $redis->hexists( 'do', $translated_oid ) )
                {
                    eval( $redis->hget( 'do', $translated_oid ) );
                }
                if ( $value && $value =~ /^\$_SE_/ )
                {
                    $value = format_val( eval( $value ), $type );
                }
                use strict;
                $value = format_val( $value, $type );
                $request->setValue( $type, $value ) if ( defined $value );
            }
        }
        elsif ( $request_info->getMode() == MODE_GETNEXT )
        {

            if (   $redis->hexists( 'type', $translated_oid )
                && $redis->hget( 'type', $translated_oid ) != 0 )
            {

                my $type = $redis->hget( 'type', $translated_oid );
                next if ( $type == 0 );
                my $value;
                if ( length $redis->hget( 'val', $translated_oid ) )
                {
                    $value = $redis->hget( 'val', $translated_oid );
                }
                else
                {
                    $value = create_val( $type );
                }

                no strict;
                if ( $redis->hexists( 'do', $translated_oid ) )
                {
                    eval( $redis->hget( 'do', $translated_oid ) );
                }
                if ( $value =~ /^\$_SE_/ )
                {

                    $value = format_val( eval( $value ), $type );
                }
                use strict;

                $value = format_val( $value, $type );
                $request->setValue( $type, $value );

            }

# say "===== <$oid>  <$translated_oid> <$next>";
            $request->setOID( $next );

            if ( defined $redis->hget( 'type', $next ) )
            {
                my $type = $redis->hget( 'type', $next );

                my $value;
                if ( length $redis->hget( 'val', $next ) )
                {
                    $value = $redis->hget( 'val', $next );
                }
                else
                {
                    $value = create_val( $type );
                }

                no strict;
                if ( $redis->hexists( 'do', $next ) )
                {
                    eval( $redis->hget( 'do', $next ) );
                }
                if ( $value =~ /^\$_SE_/ )
                {

                    $value = format_val( eval( $value ), $type );
                }
                use strict;
                $value = format_val( $value, $type );
                $request->setValue( $type, $value );
            }
        }
        elsif ( $request_info->getMode() == MODE_SET_RESERVE1 )
        {
            if ( !$redis->hexists( 'access', $translated_oid ) )
            {
                $request->setError( $request_info, SNMP_ERR_NOSUCHNAME );
            }
        }
        elsif ($request_info->getMode() == MODE_SET_ACTION
            && $redis->hexists( 'access', $translated_oid ) )
        {
            if ( $redis->hget( 'access', $translated_oid ) =~ /(rw)|(read\s*write)/i )
            {
                if ( $redis->hexists( 'do_set', $translated_oid ) )
                {
                    eval( $redis->hget( 'do_set', $translated_oid ) );
                }
                my $val = $request->getValue();
                $val =~ s/"(.*)"$/$1/;
                if ( $val =~ /(\d+):(\d+):(\d+):(\d+(\.\d+)?)/ )
                {
                    $val = ( ( ( ( ( $1 * 24 ) + $2 ) * 60 ) + $3 ) * 60 + $4 ) * 100;
                }
                $redis->hget( 'val', $translated_oid ) = $val;
            }
            else
            {
                $request->setError( $request_info, SNMP_ERR_READONLY );
            }
        }
        elsif ($request_info->getMode() == MODE_SET_FREE
            && $redis->hexists( 'access', $translated_oid ) )
        {
            if ( $redis->hget( 'access', $translated_oid ) =~ /(rw)|(read\s*write)/i )
            {
                if ( $redis->hexists( 'do_set', $translated_oid ) )
                {
                    eval( $redis->hget( 'do_set', $translated_oid ) );
                }
                my $val = $request->getValue();
                $val =~ s/"(.*)"$/$1/;
                $redis->hget( 'val', $translated_oid ) = $val;
            }
            else
            {
                $request->setError( $request_info, SNMP_ERR_READONLY );
            }
        }
    }
}

my $agent = new NetSNMP::agent( 'AgentX' => 1 );

my %registred;

my $running = 1;
while ( $running )
{
    $agent->agent_check_and_process( 0 );

    foreach my $b_o ( $redis->smembers( 'enterprise' ) )
    {
        next if ( exists $registred{ $b_o } );
        say( $b_o );
        $agent->register( $AGENT_NAME, $b_o, \&myhandler );
        $registred{ $b_o } = '';
        say "NAME $AGENT_NAME";
    }
}

$agent->shutdown();

sub aton
{
    my $ip_in = shift;
    my $ip_out = pack "C*", split /\./, $ip_in;

    return $ip_out;
}

sub fab_debug
{
    my $msg = shift;

    if ( $DEBUG )
    {
        my ( $pkg, $file, $line, $sub ) = ( caller( 0 ) )[ 0, 1, 2, 3 ];
        if ( ref $msg )
        {
            $msg = "[$line] [$pkg] [$sub] [$file] " . Dumper( $msg );
            chomp $msg;
        }
        else
        {
            $msg = "[$line] [$pkg] [$sub] [$file] " . $msg;
        }
        open LOG, '>>', $file_name;
        my $old_fh = select( LOG );
        $| = 1;
        select( $old_fh );
        print LOG "$msg\n";
        close LOG;
    }
}

sub say
{
    my $msg = shift;

    if ( $DEBUG )
    {
        my ( $pkg, $file, $line, $sub ) = ( caller( 0 ) )[ 0, 1, 2, 3 ];
        if ( ref $msg )
        {
            $msg = "[$line] " . Dumper( $msg );
            chomp $msg;
        }
        else
        {
            $msg = "[$line] " . $msg;
        }
        print "$msg\n";
    }
}

sub generate_random_string
{
    my $length_of_randomstring = shift;    # the length of
                                           # the random string to generate

# my @chars = ( 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-', '.', ';', ',' );
    my @chars = ( 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-', );
    my $random_string;
    foreach ( 1 .. $length_of_randomstring )
    {

# rand @chars will generate a random
# number between 0 and scalar @chars
        $random_string .= $chars[ rand @chars ];
    }
    return $random_string;
}

sub create_val
{
    my $type = shift;
    return if ( !$type );
    my $value;

    if ( $type == 1 )    # ASN_BOOLEAN
    {
        $value = ( rand 10 ) % 2;
    }
    elsif ( $type == 2 )    # ASN_INTEGER 2
    {
        $value = int rand( 2**32 ) - ( 2**31 );
    }
    elsif ( $type == 3 )    # ASN_BIT_STR 3
    {
        $value = generate_random_string( 2 + int rand( 10 ) );

    }
    elsif ( $type == 4 )    # ASN_OCTET_STR 4
    {
        $value = generate_random_string( 2 + int rand( 10 ) );
    }
    elsif ( $type == 5 )    # ASN_NULL 5
    {
        $value = 0;
    }
    elsif ( $type == 6 )    # ASN_OBJECT_ID 6
    {

    }
    elsif ( $type == 16 )    # ASN_SEQUENCE 16
    {
    }
    elsif ( $type == 17 )    # ASN_SET 17
    {
    }
    elsif ( $type == 64 )    # ASN_APPLICATION 64 or  ASN_IPADDRESS 64
    {
        $value = ( ( int( rand( 253 ) ) + 1 ) . '.' . ( int( rand( 254 ) ) ) . '.' . ( int( rand( 254 ) ) ) . '.' . ( int( rand( 254 ) ) ) );
    }
    elsif ( $type == 65 )    # ASN_COUNTER 65
    {
        $value = int rand( 2**32 );
    }
    elsif ( $type == 66 )    # ASN_UNSIGNED 66 or  ASN_GAUGE 66
    {
        $value = int rand( 2**32 );
    }
    elsif ( $type == 67 )    # ASN_TIMETICKS 67
    {
        $value = time - rand( int rand 10 );
    }
    elsif ( $type == 68 )    # ASN_OPAQUE 68
    {
    }
    elsif ( $type == 70 )    # ASN_COUNTER64 70
    {
        $value = int rand( 2**64 );
    }
    elsif ( $type == 72 )    # ASN_FLOAT 72
    {
        $value = rand( int rand 2**32 );
    }
    elsif ( $type == 73 )    # ASN_DOUBLE 73
    {
        $value = rand( int rand 2**32 );
    }
    elsif ( $type == 74 )    # ASN_INTEGER64 74
    {
        $value = int rand( 2**64 ) - ( 2**63 );
    }
    elsif ( $type == 75 )    # ASN_UNSIGNED64 75
    {
        $value = int rand( 2**64 );
    }

# my ( $pkg, $file, $line, $sub ) = ( caller(0) )[ 0, 1, 2, 3 ];
# say "[$line] create val=<$value> type=<$type>";
    return $value;

}

sub format_val
{
    my $val  = shift // '';
    my $type = shift;
    my $res  = $val;

    if ( defined $val )
    {
        if ( $type == 1 )    # ASN_BOOLEAN
        {

        }
        elsif ( $type == 2 )    # ASN_INTEGER 2
        {
            $res = 0 + $val;
        }
        elsif ( $type == 3 )    # ASN_BIT_STR 3
        {
            $res = sprintf "%s", $val;
        }
        elsif ( $type == 4 )    # ASN_OCTET_STR 4
        {
            $res = sprintf "%s", $val;
        }
        elsif ( $type == 5 )    # ASN_NULL 5
        {
            $res = 0;
        }
        elsif ( $type == 6 )    # ASN_OBJECT_ID 6
        {
        }
        elsif ( $type == 16 )    # ASN_SEQUENCE 16
        {
        }
        elsif ( $type == 17 )    # ASN_SET 17
        {
        }
        elsif ( $type == 64 )    # ASN_APPLICATION 64 or  ASN_IPADDRESS 64
        {
            $res = aton( $val );
        }
        elsif ( $type == 65 )    # ASN_COUNTER 65
        {
            say "<$val>";
            $res = int $val % ( 2**32 );
        }
        elsif ( $type == 66 )    # ASN_UNSIGNED 66 or  ASN_GAUGE 66
        {
        }
        elsif ( $type == 67 )    # ASN_TIMETICKS 67
        {
        }
        elsif ( $type == 68 )    # ASN_OPAQUE 68
        {
        }
        elsif ( $type == 70 )    # ASN_COUNTER64 70
        {

            $res = int( $val % ( 2**64 ) );
        }
        elsif ( $type == 72 )    # ASN_FLOAT 72
        {
            $res = sprintf "%f", $val;
        }
        elsif ( $type == 73 )    # ASN_DOUBLE 73
        {
        }
        elsif ( $type == 74 )    # ASN_INTEGER64 74
        {

        }
        elsif ( $type == 75 )    # ASN_UNSIGNED64 75
        {
        }
    }

# eval($res);
    $res = sprintf "%s", $res;

# my ( $pkg, $file, $line, $sub ) = ( caller(0) )[ 0, 1, 2, 3 ];
# say "[$line] format val=<$val> type=<$type> res=<$res>";
    return $res;
}

sub daemonize
{
    chdir '/' or die "Can't chdir to /: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '>/dev/null'
      or die "Can't write to /dev/null: $!";
    defined( my $pid = fork ) or die "Can't fork: $!";
    exit if $pid;
    POSIX::setsid() or die "Can't start a new session: $!";
    open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
}
