#!/usr/bin/perl

##########################################################
# snmp_emul
# Gnu GPL2 license
#
# $Id: agentx_redis.pl 2 2011-01-25 09:47:32 fabrice $
#
# Fabrice Dulaunoy <fabrice@dulaunoy.com>
# copyright 2010,2011,2012,2013 Fabrice Dulaunoy
###########################################################

use strict;
use warnings;

use Data::Dumper;
use SNMP;
use Redis;
use File::Basename;
use NetSNMP::ASN qw(:all);
use Config::General;
use IO::All;
use Getopt::Long;
Getopt::Long::Configure( "bundling", "ignore_case" );

use subs qw(say);

my $VERSION = '1.19';

my $enterprise_oid = '.1.3.6.1.4.1.';

my $file;
my @Debug;
my $DELETE = 0;
my $help;
my $version;

GetOptions(
    'f=s' => \$file,
    'd=i' => \@Debug,
    'D'   => \$DELETE,
    'h'   => \$help,
    'v'   => \$version,
);

if ( $version ) { print "$0 $VERSION \n"; exit; }
if ( $help )
{
    print "Usage: $0 [options ...]\n\n";
    print "Tool to parse MIB, snmpwalk or agentx config file and put the OID in th eredis DB for snmp_emul ( agentx_redis )\n";
    print "\n";
    print "Where options include:\n";
    print "\t -h \t\t This help \n";
    print "\t -f file \t file to parse \n";
    print "\t -D \t\t delete the entries \n";
    print "\t -d nbr \t debug level to show \n";
    print "\t\t\t could be repeated to show divers level\n";
    print "\t\t\t e.g. -d 0 -d 3 \n";
    exit;
}

my %DEBUG = map { $_ => $_ } @Debug;

say "file=<$file>" if ( exists $DEBUG{ 0 } );
my $enterprise_full;
my %enterprises_full;
my %mib;

my $REDIS = '127.0.0.1:6379';
my $redis = Redis->new(
    server => $REDIS,
    debug  => 0
);

$redis->select( 4 );    # use DB nbr 4

my $all = io( $file )->chomp->slurp;
if ( $all =~ /::=\s*\{\s*enterprises\s+(\d+)\s*\}/ )
{
    $enterprise_full = $enterprise_oid . $1;
    say "MIB file <$enterprise_full>" if ( exists $DEBUG{ 0 } );
    parse_mib();
}

my @lines = split /\n/, $all;
my $line_nbr = scalar @lines;

my $flag = 0;
foreach my $line ( @lines )
{
    $flag += ( $line =~ /^((\.\d+)+)\s+=\s+((\S+):\s+)*(.+)/ );
}

if ( $line_nbr == $flag )
{
    say "WALK file <$line_nbr>  <$flag>" if ( exists $DEBUG{ 0 } );
    parse_walk();
}

my $CONFIG = new Config::General(
    -LowerCaseNames => 1,
    -ConfigFile     => $file,
    -SaveSorted     => 1
);

my %Conf;

eval { %Conf = $CONFIG->getall(); };

if ( $@ )
{
    say "NOK $@";
    exit;
}

say \%Conf if ( exists $DEBUG{ 5 } );

my $agentx = 0;
if ( ( ref $Conf{ oid } ) eq 'HASH' && scalar keys %{ $Conf{ oid } } )
{
    foreach my $base ( keys %{ $Conf{ oid } } )
    {
        if ( exists $Conf{ oid }{ $base } )
        {
            my @ind = keys %{ $Conf{ oid }{ $base } };
            if ( scalar @ind )
            {
                $agentx++;
            }
        }
    }
}

if ( $agentx )
{
    say "agentx conf ($agentx)" if ( exists $DEBUG{ 0 } );
    parse_agentx();
}

sub parse_agentx
{
    foreach my $base_oid ( keys %{ $Conf{ oid } } )
    {
        $base_oid =~ /^($enterprise_oid\d+)/;
        my $ent_oid = $1;
        $enterprises_full{ $ent_oid } = '';
        foreach my $index_oid ( keys %{ $Conf{ oid }{ $base_oid }{ index } } )
        {
            my $oid = $base_oid . '.' . $index_oid;
            $oid =~ s/\.+/./g;
            $mib{ $oid }{ val }    = $Conf{ oid }{ $base_oid }{ index }{ $index_oid }{ val };
            $mib{ $oid }{ type }   = get_type( $Conf{ oid }{ $base_oid }{ index }{ $index_oid }{ type } );
            $mib{ $oid }{ access } = $Conf{ oid }{ $base_oid }{ index }{ $index_oid }{ access } // 'ro';
            $mib{ $oid }{ do }     = $Conf{ oid }{ $base_oid }{ index }{ $index_oid }{ do } if ( exists $Conf{ oid }{ $base_oid }{ index }{ $index_oid }{ do } );
        }
    }

    my @sorted = sort { sort_oid( $a, $b ) } keys %mib;

    foreach my $ent_full ( keys %enterprises_full )
    {
        $redis->sadd( 'enterprise', $ent_full );
        $mib{ $ent_full }{ next } = $sorted[ next_leaf( 0, \@sorted ) ];
    }

    @sorted = sort { sort_oid( $a, $b ) } keys %mib;

    foreach my $o ( reverse @sorted )
    {
        $o =~ /^($enterprise_oid\d+)\.(.*)/;
        my $base  = $1;
        my $trail = $2;
        my @each  = split /\./, $trail;
        pop @each;
        my $append;
        my $new_oid = $base;
        foreach my $l ( @each )
        {
            $new_oid .= '.' . $l;
            $mib{ $new_oid }{ next } = $o;
            say "<$o> <$new_oid>" if ( $DEBUG{ 4 } );
            $mib{ $new_oid }{ next } = $o;
        }
    }

    @sorted = sort { sort_oid( $a, $b ) } keys %mib;

    foreach my $ind ( 0 .. $#sorted )
    {
        my $oid = $sorted[$ind];
        my $next = next_leaf( $ind, \@sorted );
        my $next_oid = $sorted[$next] // '';
        $next_oid =~ /^$oid\.(\d+)/;
        my $sub_oid_ind = $1;
        if ( $sub_oid_ind )
        {
            $sub_oid_ind++;
            my $sub_oid = $oid . '.' . $sub_oid_ind;
            if ( !exists $mib{ $sub_oid }{ next } )
            {
                $mib{ $sub_oid }{ next } = '' if ( $sub_oid_ind <= $#sorted );
            }
        }
    }

    @sorted = sort { sort_oid( $a, $b ) } keys %mib;

    foreach my $ind ( 0 .. $#sorted )
    {
        my $oid = $sorted[$ind];
        my $next = next_leaf( $ind, \@sorted );
        $mib{ $oid }{ next } = $sorted[$next] // '';
        if ( $DELETE )
        {
            $redis->hdel( 'next',   $oid );
            $redis->hdel( 'val',    $oid );
            $redis->hdel( 'type',   $oid );
            $redis->hdel( 'do',     $oid );
            $redis->hdel( 'access', $oid );
        }
        else
        {
            $redis->hset( 'type',   $oid, $mib{ $oid }{ type }   // 0 );
            $redis->hset( 'access', $oid, $mib{ $oid }{ access } // 'ro' );
            $redis->hset( 'val',    $oid, $mib{ $oid }{ val }    // '' );
            $redis->hset( 'do',   $oid, $mib{ $oid }{ do } ) if ( exists $mib{ $oid }{ do } );
            $redis->hset( 'next', $oid, $sorted[$next] )     if ( $next <= $#sorted );
        }
    }

    foreach my $ent_full ( keys %enterprises_full )
    {
        if ( $DELETE )
        {
            $redis->srem( 'enterprise', $ent_full );
        }
    }

    say Dumper( \%mib )              if ( $DEBUG{ 2 } );
    say Dumper( \@sorted )           if ( $DEBUG{ 3 } );
    say Dumper( \%enterprises_full ) if ( $DEBUG{ 1 } );

}

sub parse_walk
{
    foreach my $line ( @lines )
    {
        $line =~ /^((\.\d+)+)\s+=\s+((\S+):\s+)*(.+)/;
        my $oid      = $1;
        my $type_raw = $4 // '';
        my $val      = $5 // '';

        my $type = get_type( $type_raw );
        $val =~ s/"//g;

        $mib{ $oid }{ type }   = $type;
        $mib{ $oid }{ val }    = $val;
        $mib{ $oid }{ access } = 'ro';

        my $res = ( $oid =~ /^($enterprise_oid\d+)/ );
        my $ent = $1;
        $enterprises_full{ $ent } = '';
        say "<$res> [$line]  <$oid> <$type>  <$val>" if ( $DEBUG{ 4 } );
    }

    my @all_oid = sort { sort_oid( $a, $b ) } keys %mib;
    foreach my $ent_full ( keys %enterprises_full )
    {
        if ( $DELETE )
        {
            $redis->srem( 'enterprise', $ent_full );
        }
        else
        {
            $redis->sadd( 'enterprise', $ent_full );
        }
    }

    my @sorted = sort { sort_oid( $a, $b ) } keys %mib;
    foreach my $ind ( 0 .. $#sorted )
    {
        my $oid = $sorted[$ind];
        $mib{ $oid }{ next } = $sorted[ $ind + 1 ] // '';
        my $next = next_leaf( $ind, \@sorted );
        $mib{ $oid }{ next } = $sorted[$next];
        if ( !$DELETE )
        {
            $redis->hset( 'type',   $oid, $mib{ $oid }{ type } );
            $redis->hset( 'access', $oid, $mib{ $oid }{ access } );
            $redis->hset( 'val',    $oid, $mib{ $oid }{ val } );
            $redis->hset( 'next',   $oid, $sorted[$next] ) if ( $next <= $#sorted );
        }
    }

    foreach my $o ( @all_oid )
    {
        next if ( !exists $mib{ $o }{ next } || !defined $mib{ $o }{ next } );
        my $next = $mib{ $o }{ next };

        if ( $next =~ /^$o\.(.*)/ )
        {
            my $trail = $1;
            my @each = split /\./, $trail;
            pop @each;
            my $append;
            my $new_oid = $o;
            foreach my $l ( @each )
            {
                $new_oid .= '.' . $l;
                $mib{ $new_oid }{ next } = $next;
                say "<$o> <$new_oid> <$next>" if ( $DEBUG{ 4 } );
                if ( !$DELETE )
                {
                    $redis->hset( 'next', $new_oid, $next );
                }
            }
        }
    }

    if ( $DELETE )
    {
        foreach my $oid ( keys %mib )
        {
            $redis->hdel( 'next',   $oid );
            $redis->hdel( 'val',    $oid );
            $redis->hdel( 'type',   $oid );
            $redis->hdel( 'do',     $oid );
            $redis->hdel( 'access', $oid );
        }

    }

    say Dumper( \%mib )              if ( $DEBUG{ 2 } );
    say Dumper( \@all_oid )          if ( $DEBUG{ 3 } );
    say Dumper( \%enterprises_full ) if ( $DEBUG{ 1 } );

}

sub parse_mib
{
    $redis->sadd( 'enterprise', $enterprise_full );

    my $base_folder = dirname( $file );
    &SNMP::addMibDirs( $base_folder );

# &SNMP::loadModules;

    &SNMP::addMibFiles( $file );
    &SNMP::initMib();

    foreach my $oid ( keys( %SNMP::MIB ) )
    {
        next if ( $oid !~ /^$enterprise_full/ );
        my $type = $SNMP::MIB{ $oid }{ 'type' };
        my $access = $SNMP::MIB{ $oid }{ 'access' } // 'ro';
        if ( $DEBUG{ 4 } )
        {
            print "OID=", $oid, "\n";
            print "\tTYPE=",  $SNMP::MIB{ $oid }{ 'type' },  "\n";
            print "\tLABEL=", $SNMP::MIB{ $oid }{ 'label' }, "\n";
            print "\tACCESS=", $SNMP::MIB{ $oid }{ 'access' } // 'RO', "\n";
            print "\tDESCRIPTION=", $SNMP::MIB{ $oid }{ 'description' }, "\n" if ( defined $SNMP::MIB{ $oid }{ 'description' } );
        }
        $mib{ $oid }{ type }   = get_type( $type );
        $mib{ $oid }{ access } = $access;
    }

    my @sorted = sort { sort_oid( $a, $b ) } keys %mib;
    foreach my $ind ( 0 .. $#sorted )
    {
        my $oid = $sorted[$ind];
        my $next = next_leaf( $ind, \@sorted );
        $mib{ $oid }{ next } = $sorted[ $ind + 1 ] // '';
        if ( $DELETE )
        {
            $redis->hdel( 'next',   $oid );
            $redis->hdel( 'val',    $oid );
            $redis->hdel( 'type',   $oid );
            $redis->hdel( 'do',     $oid );
            $redis->hdel( 'access', $oid );
        }
        else
        {
            $redis->hset( 'type',   $oid, $mib{ $oid }{ type } );
            $redis->hset( 'access', $oid, $mib{ $oid }{ access } );
            $redis->hset( 'next',   $oid, $sorted[$next] ) if ( $next <= $#sorted );
        }
    }
    if ( $DELETE )
    {
        $redis->srem( 'enterprise', $enterprise_full );
    }

    say Dumper( \%mib )    if ( $DEBUG{ 3 } );
    say Dumper( \@sorted ) if ( $DEBUG{ 1 } );
}

sub next_leaf
{
    my $indx   = shift;
    my $s      = shift;
    my @sorted = @$s;
    $indx++;
    my $i;
    for ( $i = $indx ; $i <= $#sorted ; $i++ )
    {
        my $oid = $sorted[$i];

        if ( exists $mib{ $oid }{ type } && $mib{ $oid }{ type } != 0 )
        {
            return $i;
        }
    }
    return $i;
}

sub sort_oid
{
    my $o1 = shift;
    my $o2 = shift;
    $o1 =~ s/^\.//;
    $o2 =~ s/^\.//;
    my @O1 = split /\./, $o1;
    my @O2 = split /\./, $o2;
    my @b = $#O1 < $#O2 ? @O2 : @O1;
    foreach my $i ( 0 .. $#b )
    {
        no warnings;
        my $res = ( $O1[$i] <=> $O2[$i] );
        use warnings;
        next if ( $res == 0 );
        return $res;
    }
}

sub get_type
{
    my $type = shift;
    my $asn  = 0;
    if ( $type =~ /(OCTETSTR)|(STRING)/i )
    {
        $asn = ASN_OCTET_STR;
    }

    if ( $type =~ /^INTEGER$/i || $type =~ /^INTEGER32$/i )
    {
        $asn = ASN_INTEGER;
    }

    if ( $type =~ /^INTEGER64$/i )
    {
        $asn = ASN_INTEGER64;
    }

    if ( $type =~ /^COUNTER64$/i )
    {
        $asn = ASN_COUNTER64;
    }
    if ( $type =~ /^COUNTER$/i || $type =~ /^COUNTER32$/i )
    {
        $asn = ASN_COUNTER;
    }

    if ( $type =~ /^UNSIGNED64$/ )
    {
        $asn = ASN_UNSIGNED64;
    }
    if ( $type =~ /^UNSIGNED$/i || $type =~ /^UNSIGNED32$/i )
    {
        $asn = ASN_UNSIGNED;
    }

    if ( $type =~ /IPADDR/i )
    {
        $asn = ASN_IPADDRESS;
    }

    if ( $type =~ /TICKS/i )
    {
        $asn = ASN_TIMETICKS;
    }

    if ( $type =~ /^GAUGE$/i )
    {
        $asn = ASN_GAUGE;
    }

    if ( $type =~ /^OBJECTID$/i )
    {
        $asn = ASN_OBJECT_ID;
    }

# if ( $type =~ /^BITS$/i ) {
# $asn = ASN_BIT_STR;
# }

    if ( $type =~ /^OPAQUE$/i )
    {
        $asn = ASN_OPAQUE;
    }

    if ( $type =~ /^NULL$/i )
    {
        $asn = ASN_NULL;
    }

    if ( $type =~ /^DOUBLE$/i )
    {
        $asn = ASN_DOUBLE;
    }

    if ( $type =~ /^FLOAT$/i )
    {
        $asn = ASN_FLOAT;
    }

    if ( $type =~ /^BOOL/i )
    {
        $asn = ASN_BOOLEAN;
    }

# if ( $type =~ /^$/i ) {
# $asn = ASN_;
# }

# if ( $type =~ /^$/i ) {
# $asn = ASN_;
# }
# if ( $type =~ /^$/i ) {
# $asn = ASN_;
# }

    return $asn;
}

sub say
{
    my $msg = shift;

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
