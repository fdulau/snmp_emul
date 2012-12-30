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
use Data::Serializer;
use Getopt::Std;
use POSIX qw(setsid);
use NetSNMP::agent ( ':all' );
use NetSNMP::ASN qw(:all);
use NetSNMP::default_store        ( ':all' );
use NetSNMP::agent::default_store ( ':all' );
use SNMP;
use Redis;

my $VERSION = '2.10';
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

my $obj      = Data::Serializer->new( compress => 1 );
my @raw      = <DATA>;
my @RAND_OID = @{ $obj->deserialize( $raw[0] ) };

sub myhandler
{
    my ( $handler, $registration_info, $request_info, $requests ) = @_;
    my $request;

    for ( $request = $requests ; $request ; $request = $request->next() )
    {
        my $oid            = $request->getOID();
        my $translated_oid = SNMP::translateObj( $oid );
        my $next           = $redis->hget( 'next', $translated_oid ) || $translated_oid;

# say "<$translated_oid> mode=".$request_info->getMode() ;
        if ( $request_info->getMode() == MODE_GET )
        {
            if ( $redis->hexists( 'access', $translated_oid ) )
            {
                my $type = $redis->hget( 'type', $translated_oid );
                next if ( $type == 0 );
                my $value;
                if ( $redis->hexists( 'val', $translated_oid ) && length $redis->hget( 'val', $translated_oid ) )
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
            last if ( $next eq $translated_oid );
            if (   $redis->hexists( 'type', $translated_oid )
                && $redis->hget( 'type', $translated_oid ) != 0 )
            {
                my $type = $redis->hget( 'type', $translated_oid );
                next if ( $type == 0 );
                my $value;
                if ( $redis->hexists( 'val', $translated_oid ) && length $redis->hget( 'val', $translated_oid ) )
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
# say "<$translated_oid>  <$value>";
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
                if ( $redis->hexists( 'val', $translated_oid ) && length $redis->hget( 'val', $next ) )
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
    my $length_of_randomstring = shift;

    my @chars = ( 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-', );
    my $random_string;
    foreach ( 1 .. $length_of_randomstring )
    {
        $random_string .= $chars[ rand @chars ];
    }
    return $random_string;
}

sub generate_oid
{
    my $base = '.1.3.6.1.2.1';
    return ( $RAND_OID[ rand @RAND_OID ] );
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
        $value = generate_oid();
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
# say "<$val>";
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

__DATA__
^Data::Dumper|||hex|Compress::Zlib^789cc5dd5d96f23a92a8e1b9f44ddff4ca85e34f30965e3dff6934901f5860e90dc986acb3cfeeaa222ccbb264590ef390fffbdf3fcb8ffec4f5ffcaf5dfdb3fa7fffe9ff70fa5f5a1b63eb4d687defa305a1f96d687e7d68797dfffd60b482fa0bd80f502de0b442f507a81733ba0bd7668af1dda6b87f6daa1bd7668af1dda6b87f6da61bd7658af1dd66b87f5da61bd7658af1dd66b876ddb71fb7733d8e47169f4029bc63d029bc63d029b363c029b363c029b36c8e3807b81ce51352e8147a073548d91fe08748eaa31a01f81ce513506f423d039aac6b87d043a47d5189e8f40e7a81ac3f311e81c5563143e029da3f2de5179efa8bc7754de3b2aef1d95f78e2a7a4715bda38ade5145efa8a27754d13baad23baad23baad23baad23baad23baad23baa73efa8cebda33af78eeadc3baa73efa8cebda3baf48eead23baa4befa82ebda3baf48eead23baae5d49d464fdd79f4d49d484fdd99f4d49d4a4fdd63eb4ff1fd39be3fc9f767f9fe34df9de797ee44bf7467faa53bd52fddb97ee94ef64b77b65fbad3fdd29def97ee84bf7467fca53be52fdd397fe94efa4b77d65fbad3fed29df797eec4bf7467fea53bf52fddb97fe94efe4b77f65fbad3ffd29dff97ee0d60e9de0196ee2d60e9de0396ee4d60e9de0596ee6d60e9de0796ee8d60e9de0996eead60e9de0b96eecd60e9de0d96eeed60e9de0f96ee0d61e9de1196ee2d61e9de1396ee4d61e9de1596ee6d61e9de17a47b5f90ee7d41baf705e9de17a47b5f90ee7d41baf7856ba4776cddfb8274ef0bd2bd2f487ffddfbd2f48ff09a0ff08d07f06e83f0434ee0bfaf39b4ab8f7f9e97733df3cd03db6f2fbc8b87e12d78be776089b2730fdb7b791fdc9f0fe74687f3ab0bfeb4d66fbd878bdbfb43e6ca44dac9536b156dae47a97697dd8489b582b6d62d78559ebe04fcd4f9b6d5a9a8d5a9aad5a9acd5a9aed5a9a0d5b9a2d5b9a4d5b9a6dbb4d2c6b2f6fae957503b956f5d39885d62daa21d0db4ab28a24ad48862ad2ac224d2bd2a18a2cabc8d28a2cade85fe2f1f79f6efc7e20b8415c6ed7316f531d4a6f2b490e45b24391814391a143d1e450343b141d38141d3a94921c4ac90ea50c1c4a193a94737228e7ec50ce0387721e3a944b722897ec502e038772193a9425bd84f26b68e8221abb8a966cec2ee9e05d4646ef920fdffbfcb54ece8d7bfd73234f6ff5f25cfb647b93d1bde9c8de74746f36b2371bd95bf3ae2e765fef3c075bf50fd6fa28f6e8f3fb3fe27efff70463e559701d0af365eb1152951d2b2ffbda2a7bdb2a07da2a07dbaafbdaaa7bdbaa07daaa07db6afbda6a7bdb6a07da6a07dbeafbdaea7bdbea07daea07db1afbda1a7bdb1a07da1a07db5af6b5b5ec6d6b39d0d672b0ad977d6dbdec6debe5405b2f07dbba6c9b3a76833dedbec39e8edc624f47dbbb7741b17f4571684971744db1ec5c542cbb5715cb9165c572745db1ec5c582cbb5716cb91a5c5fb53c57c7b772e2e96ddab8be5c8f26239babe58762e3096dd2b8ce5c8126339bac658762e3296ddab8ce5c8326339b2ce68e666e59677bedfd35fd6d1bffbae1287bd93b1167e9e8f65dd800ea72a599d8ff9c22fe743fe2d3c878a4bbbfb5f86c275bfd77ddfbe04926f9cd6756be46d7fb493f86dc19f56175fab4eee6fd7f4df08bd75f56d5296fb44753fb197ef55edf273b69fd35ab7fefe87c7bfba7f87f6df54eefa53ae9b8a3eea5e3e54776bc2aeffb957267f5999fe656576acb2f39179efbc7bde3b1f99f7cec7e6bda1a9ec43f3def96fe7bdd9ea0ece7b50ddb7e73daafaebf3de4ce59f9ef7ce53b3c3c1796faeb283f3de5c6507e7bdcb9179efb27bdebb1c99f72ec7e6bda12bee43f3dee56fe7bdd9ea0ece7b50ddb7e73daafaebf3de4ce59f9ef72e53b3c3c1796faeb283f3de5c6507e7bde57464e25baa2defc5c627af47d17d53dfa3f4deb96f6ce47f68f27b54f657b3df747d07a73faaefdbf31fd6fdf50970aaf64fcf806be57f31054ed676700e9cacede824b81c9a0497fd93e07268125c0e4e824303f05393e0f2c793e06c7d472741a8efeb9320d5fdfd4970a6f68f4f82cbd4447174129cabede8243857dbd149f065d2f9999d0465ff24288726413938090e0d894f4d82f2c793e06c7d472741a8efeb9320d5fdfd4970a6f68f4f823235511c9d04e76a3b3a09ced5767412d44393a0ee9f04f5d024a80727c1a14efad424a87f3c09ced677741284fabe3e0952dddf9f04676afff824a85313c5d14970aeb6a393e05c6d4727413b3409dafe49d00e4d827670121c3a6d9f9a04ed8f27c1d9fa8e4e8250dfd72741aafbfb93e04ced1f9f046d6aa2383a09ced57674129cabede824f83269fccc4e82be7f12f44393a01f9c0487e6994f4d82fec793e06c7d472741a8efeb9320d5fdfd4970a6f68f4f823e35511c9d04e76a3b3a09ced57674128c439360ec9f04e3d024180727c1a1ebfe539360fcf124385bdfd14910eafbfa2448757f7f129ca9fde393604c4d144727c1b9da8e4e8273b51d9d04cba149b0ec9f04cba149b01c9c04ffd2832c7f0c42a6eb3b3a09fe074908d6fdfd49f03f8942963f552193b51d9d04ffc885347fd74c9a764e975b4d3f8d1f4ead629b9fef7bc60cca19940b28d7f859cf67ac40b9c64f6e3e638d1f9cac62fd72ad5f09ae835052a864e32711d7207546eb876cd7207547eb6766d760e31760eb2094a4ae5ca82f5bbf9e5a07a1e4994a367ede740dd24068fdf8e833d8fa5dd03a0825172ab950491a43ad9fd55c833412844682d048101a0942bd22d42b42bd22d42b46a3cf68f4198d3e6b8f3ebb7f50ad225b7ba836eaff1c61bd15ff24e1bf2d47d6755c786e1db3635ffd75c90776f65c6674f66523dd6243ddb27d27d5dff240b7ec7adbb2635fd3ddb2eb6548675f3ed22d3ed42ddb2c797fcb03ddb22bffbb635fd3ddb22b3ddbd9578c744b0c75cb366fd7dff240b7ecca48edd8d774b7ec4a1875f65546baa50c75cb3693d0dff240b7ec7a46deb1afe96ed9f508dbd9d779a45bce43ddb275effd2d0f74cb2ed5bd635fd3ddb28b5d77f67519e996cb50b76c596e7fcb03ddb20b9deed8d774b7ec52a19d7d2da7917e796c95744c030dc2a607ba661f88dbb3b3e9ced927d67a3b5b867a6719eb9d65bc779643bdb37cb2776867f3bd33b337ea9ddff5add4ddd37c49f16fc3ed72b8f5c3c9f78d6374af31b3d732bad732b3d7f3e85ecf437bbd6dd3f8b0f1e3dcfed3f88d69ff69fce1086ffd3d0cff69a457fda7f15723bcf5f730bcf5f730bcf9f730bcf9f730fca7f5f730bcf9f730bcf9f730bcf9f730fc7ed1363e6db6acf5f730bcf9f730fc96336b7ddaeeaf66db5abf0aeeb7ec56ebd366db5a39f1680d99680d99680d99680d99680d99680d99680d99680d99680d99680e99680e99680e99f89509eb6fa04af5f3a0e9c64bfde3a9035bebccd636b3b52f33c7ed5347e2f54f6ae65beb79666b9bd9fa729a3adf9732b37339d96562735d6ce694dba5cc1c7b68993998f3e9749ada7c99dabc04fc52656bf398d8fc72bacc9c99cbf5ffcdf4aa9d4e65627bbd9e9b99edcd2f3e350ec274e672b2a23ad35ebb2c53c773bdb86727031dd9ff63c9fd6332723a9f9bdf2fabebffba2d36c5aff55d57959b75f258b1cd3b8d81627a2a9bd56aa358f1721d89b7fbf73d7c9dc4ce236dbb165bf615937dc5745f31db57ccf7158b7dc5cabe62e77dc52ef3c5ece4765db9df06d83562d751263f6603c3cbe27cbaad2ecf3f71abb3fc5c0f7a6434fbe9747b43782d777f22bcf6be9c4e43877a2b79de5bf27addec2d297b4bde9e7af795bce8ee92bebb64d95df2b2afa49e96faa9726cf8f8727b5c3fc9f55143ee0376b16b49987d1f0993fbf3463ec73f371fbc273cb70f1d5921acdb2f638be7b702ebfff4cb723a0f357bb2e172b1b996ebb553e64e6d195a09566d1dbc9fbf16a82a5c4237d9a256b1cbec815dce230ba57a945c67e9aafce922975dc574a8b6986ccfb2c8d0e3e2dba97d3bf32327eed6f0b7068e15d3d38e62b76be5ed52ea17ab73a7b7fce0c0e97829727f487b4d825d9f37464bebc575539ca6c697d2b7a5fe7b060e67e34de9f73ffd36573a0e952e874a9f0f95de76d944e9381d2a7da8c7e2508fc5a11e8b433d16877a2c0ef55839d4636539545a0e95d6e1d2d55f12c9ef9feb162329c37aeb7c8aacb61e58f5ac5b8fa40cebade7f69ddfbaabad075286d5d60329c375eb919461750647528655cf8fa40cd7cd875286eb164329c375f3a194e1baf950cab0de7c2065586d3e92327cd93c4f19d69d3a9032ac361f491956bd3a9432acba75286558f5eb50cab0da7e2865586d3f9432acc7d948caf0e5e29e9d0c061e31642e6528fb528649b1de52908a41ca50f6a50c655fca50f6a50c655fca50f6a50c655fca50f6a50c655fca50f6a50c655fca50f6a60c6567ca5076a70c6577ca5076a70c6577ca5076a70c6577ca5076a70c6577ca5076a70c654fca5076a70c652e65586f3e784f984a19d6db0fa50c3705c65286afcd9e6cf850cab02e3094327c39b52329c3bac050ca7053602c65f8526c2465f85a602065f83a4a8653865cac9b327c293692327c1d632329c3cda91d4b19ca7bc3c7727ff2def01dc5c65386329f327c2f3297327c2f3d97327c2f3d97326c951e4f40b54ac7a1d2e309a856e9f10454abf47802aa517a2265d82a7da8c7265286add2877a6c2265d82a7da8c72652868dd21329c356e9f19461abb41c2a3d9e325ce7ae8194e1baf148cab0de3a9f22abad07563deb162329c37aebb97de7b7ee6aeb819461b5f540ca70dd7a2465589dc1919461d5f32329c375f3a194e1baf950ca70dd7c2865b86e3e9432ac371f4819569b8fa40c5f36cf538675a70ea40cabcd47528655af0ea50cab6e1d4a1956fd3a9432acb61f4a1956db0fa50ceb713692327cb9b867278381470c9d4b19eabe946152acb714a4629032d47d2943dd9732d47d2943dd9732d47d2943dd9732d47d2943dd9732d47d2943dd9732d4bd2943dd9932d4dd2943dd9d32d4dd2943dd9d32d4dd2943dd9d32d4dd2943dd9d32d4dd2943dd9332d4dd29c33ac7369039ab371fbc274ca50cebed8752869b026329c3d7664f367c28655817184a19be9cda9194e14b5b07efe77b5286afe774f6c0465286afa3643865c8c5ba29c397622329c3d731369232d4f7533b9632d4f7868fe5fef4bde13b8a8da70c753e65f85e642e65f85e7a2e65f85e7a2e65d82a3d9e806a958e43a5c71350add2e309a856e9f10454a3f444cab055fa508f4da40c5ba50ff5d844cab055fa508f4da40c1ba5275286add2e329c3566939545a874baff7a68194e1baf148cab0de3a9f22abad07563debd62329c37aebb97de7b7ee6aeb819461b5f540ca70dd7a2465589dc1919461d5f32329c375f3a194e1baf950ca70dd7c2865b86e3e9432ac371f4819569b8fa40c5f36cf538675a70ea40cabcd47528655af0ea50cab6e1d4a1956fd3a9432acb61f4a1956db0fa50ceb713692327cb9b867278381470c9b4b19dabe946152acb714a4629032b47d2943db9732b47d2943db9732b47d2943db9732b47d2943db9732b47d2943db9732b4bd2943db9932b4dd2943db9d32b4dd2943db9d32b4dd2943db9d32b4dd2943db9d32b4dd2943db9332b4dd29c3ea97dc465286f5e683f784a99461bdfd50ca7053602c65f8daecc9860fa50ceb024329c397533b9232ac0b0ca50c3705c652862fc5465286af05065286afa3643865c8c5ba29c397622329c3d731369232b4f7533b9632b4f7868fe5feecbde13b8a8da70cdf7ed4712465f85e642e65f85e7a2e65f85e7a2e65d82a3d9e806a958e43a5c71350add2e309a856e9f10454a3f444cab055fa508f4da40c5ba50ff5d844cab055fa508f4da40c1ba5275286add2e329c3566939547a3c65b8def8075286ebc62329c37aeb7c8aacb61e58f5ac5b8fa40cebade7f69ddfbaabad075286d5d60329c375eb919461750647528655cf8fa40cd7cd875286ebe64329c375f3a194e1baf950cab0de7c2065586d3e92327cd93c4f19d69d3a9032ac361f491956bd3a9432acba75286558f5eb50cab0da7e2865586d3f9432acc7d948caf0e5e29e9d0c061e317c2e65e8fb528649b1de52908a41cad0f7a50c7d5fcad0f7a50c7d5fcad0f7a50c7d5fcad0f7a50c7d5fcad0f7a50c7d5fcad0f7a60c7d67cad077a70c7d77cad077a70c7d77cad077a70c7d77cad077a70c7d77cad077a70c7d4fcad077a70c7d2e65586f3e784f984a19d6db0fa50c3705c65286afcd9e6cf850cab02e3094327c39b52329c3bac050ca7053602c65f8526c2465f85a602065f83a4a8653865cac9b327c293692327c1d632329437f3fb56329437f6ff858eecfdf1bbea3d878cad0df9ed1075286ef45e65286efa5e75286efa5e75286add2e309a856e938547a3c01d52a3d9e806a951e4f40354a4fa40c5ba50ff5d844cab055fa508f4da40c5ba50ff5d844cab0517a2265d82a3d9e326c959643a5c75286cdbfdfd2fadb38b701f0f3fe571bff3d75fe7e923de74e146fcd63a3c53bcfbdade2f767dfdb47f90351a7f872acb81c2baec78adbb1e27eac781c2b5e8e153f1f2b7ed95ffcf759faf6d1c8f3746b07bfcfd4b78ff2e7ea46f97fcfd6ffcaa7cf639d3d9c8feec14f87f72047f710cbd13d5cf4d81e7e9f6ed78fba4fb8adc2f7a7dcdb47434fbad51ede9e16b72fce078bff3e406dbf1c3058fcf77965fb258143c59b8f3cade2ff9e49360d1a6dfbefb3c9e688c68bebe940f1df67954d6772f1c603c8dbc7dd8790de5efe3d886c77938de2d60349e360668ee5df83c907f6121fd9cbf6f33d7b397f642fedae9edc4b9c3eb2978ff4747ca4a7e3233d1d1fe9e9f8484fc7477aba7ca4a7ffad8f8fee453eb297ed772b682ffffa62ef83ce60f1de1c39521c1e74de8b4f3ee8348acf3ce8348acbb1e2330f3a8de2330f3a8de2330f3a8de2330f3a8de2330f3a8de2330f3a8de2330f3a6fc5e71f74de7730fba0f3567ec7834e630f930f3adb3dcc3ee834f62047f730fba0b3ddc3ec83cefb1ea61e74de0bcf3fe8b4d6c66f1fd183ce7bf1c9079df7e2930f3a63c5bb0f3aefc5271f74366d9f7bd069149f79d0d9149f7bd0d92ea1f63ce8b4f632ffa0d3dacbfc834e6f2f73cbdfde5ee696bfbdbdcc2d7f7b7b995bfef6f632b7fcedec65f241a7b7978ff4f4e4834e6f2f1fe9e9c9079dde5e3ed2d3930f3a9dbd4c3ee8f4f632f7a0d3db8b7c642fc30f3af2afed3ff5ef4c0c6db62c8d1b6f73bbc644dddaae35a137b6f365ecf87cb05e5f6c6c3b6dac145adbd9d87697d3e0f9bb94b11ddeee71431bde1e258736bc7dcd7b68c3f6cdbcb1e1edabdd831b2e831b96f0d10d1b6bb566c75cc65a7dfbf2f658cfdcbeb63dd635b72f6c8ff5cdedabda635bdebea43db6e5edebd983236319acfdfe95ecd12d5b0bd26acbfa6bd8bc61f5a5b6c10dc77719cac3235ba4768e73f8486f5fbb1bdcf4f685bbd1f697e4cacc1e1cda9b5ec6f77a39f3287dfdb6da701748729f7aff165777e3db66cfc1dafb076e9e43e5e11e3d549eeeca833b387a06e83634b407bc3f0dedc12e478fe17c3a1feec9f3c13379befebf839d2967b83b8e75862ea57f5d8ef5869c8e0eaaeb8c03f7b0a15df08d686c1752ece0e9f4b31e1b167cff19da01de9686f68077aba13d5c97969bebebf660b999fecaf5ff363ed4d6878d6fb295db17e37ed66f2ac7e6d6f9be456306dd6c229bf3b7d944f38ab60f149b4d223d96c663c9a6cddb01f3bec9f9bc992f37c7d2b895bf6fd39afbb707bcbdc7be6f735d586fc657639bcd7afe7d9bebfaa7a43b523f477a0ef5fa1496eec996f3a531aadf3632db4eeb9b8dce12e99e9a33da76a3c8ab8beb234f774fcf55370cfb759bfeb8afb6e91e10adf05fb611f7fbbf597deb76fd3ad7c52234f0b9d1659b7f68eca9b5ecdc6ee6d7754abfca6461dade8edaf0ba219cb9b70dfba7aeda30eb8dcda6ddbd8a5e9efd26ae3416d6cd7effed6e5afd95ec748bee1da0daa47796ab4d7ae7a2dea4730eaa4d7a7780973f9e9eb6b97707a8fe0077ef0e50ff6df4de1de0f50fa2e707dc1bcc2f7fb1bb33ddbe6cd3b903547f9abb7f07a837eade01aa8dfa7780ea2f69f7ef00d546fd3b40b551ff0ef0f687b8f38dba77806a84f4ef0032700790813b800cdc0164e00e20837780cd76fd3af33b808cdc0164ec0e2063770019bc03bc6f476d18bb036c37ec9fbad13b406bd3ee5e87ef00327607b83d59fcbe2a59ef022ffff396a395d605b02d79fb999cd7a2d69a611a0545dfeb3c5db679e16651dd1cae9fb60fc4eda2e746d1b1038ef7968a9db75f396815f56dad27dfe6119a3da39b5a75f0345def619bae698cb1464b6f9cf7b564b9d83697d72afbfc6a417dc0debaa85ba7c93763426d9b036c95bddd21dfca2e6adb97599db2f15eafc8d8b9badf511b073d74b2ee77da4de1380d9dadfb1d78d3c163bd74bf316fca6edf3135cbdeeed7ef65e33274b6eeb7f1f7b23e369c7f7fcde6ad8b2fcbf63556bb706c0efa7af96ebf70d42c7c5b0ebc15d6d352aeff9f7750af14b6931d0fce7a05d198b2f094d52b8b46d9b163befd90c3e642de66eb3665ab9548a36e1c26ef2b946d79c321fab272699c703ef87a45f33ecefc2238cede7f0ae0ad78e33566bbf475e6d0f7af96fd7e769df65b0badd64eeeaba8b743b84de08d055855fc6d75b5b95844f8dcbfafba363bb85e46133bd88c1e5d4eade7b6fe0ede87cf6d073c02b6abb7c62eb813b6abbac62ef0c26facf61ad7211e456315d8d845f72864f0d5dad886f759ff5855d7c13458d56d0dd99d6286f6715b350db7abbb701cdac37dad34dab0eb22aa3b030dede3beba1aaecdcedd6b6d681f1a7afb7efa7875dd2b73681fb6f8327c2ebd7fd71eabecba7a1f6edb755975acdfccedba3c1d3e93b1fdc2d55c75e7939ec61b773a368bc4e924c3f3c86d697ce48a5b266792852bbb7d617f91f36ba99f5b73f4dfcc6bbf0f8df7afe7cfd6cd83a659b7cbcffd67959e95ebef7fdcbed33c51f9f546cdf3f550e5d7c9e6f68b63b775c05cdd9b79e7be9cda2c1deeb79fd6a78d77a1cbd27a19badc7e26a4f569343f3d373fbd343fbdfd046bebe3763b96764396764b5abf5072fbb8dd96a5dd98dbefa0b63e6e377269b752daad944e6fb55b29ede648bb39d26e8eb49b23ede648bb39da6e8eb69ba38de6c8bff788cdcf7bdb377a59fe3dd75f3fffaf66ac7172ee9f37cecefdf3c6e991db1dac7d4cf2a3f7766caec42ab6b95d57b1cdd455c536cf41556c73e3aa8f850e74fb5c50073793591da4766cd7e975707373a883740ab6cfee75904ec2f6c9fd1914e82d81de12e82d81de12e82da1de12ea2da1de12ea2da1de12ea2da1de12ea2da1de12ea2d85de52e82d85de52e82d85de52ea2da5de52ea2da5de52ea2da5de52ea2da5de52ea2da5de32e82d83de32e82d83de32e82da3de32ea2da3de32ea2da3de32ea2da3de32ea2da3de32ea2d87de72e82d87de72e82d87de72ea2da7de72ea2da7de72ea2da7de72ea2da7de72ea2da7de0ae8ad80de0ae8ad80de0aea91a01e09ea91a01e09ea91a01e09ea91a01e09ea9168f7c8fd31edfa4fd97efde3258a65b784f825da3abf6bb47582d768eb0cafd1d6295ea3ad73bc465b27798db6cef21ac573b585607574fb6af3258ae76a9b537d89d2b95a4edbef2bbf86e97c5cc37442ae616af372dabe327f0d53abf504434470e00a0e5cc1812b38700507aee0c0151cb882035770e00a0e5cc1812b38700507aee0c0151cb882035778e00a0f5ce1812b3c708507aef0c0151eb88a035771e02a0e5cc581ab38701507aee2c0551cb88a035771e02a0e5cc581ab38701507aee2c0551cb8ca035779e02a0f5ce581ab3c709507aef2c0351cb88603d770e01a0e5cc3816b38700d07aee1c0351cb88603d770e01a0e5cc3816b38700d07aee1c0351eb8c603d778e01a0f5ce3816b3c708d07aee3c0751cb88e03d771e03a0e5cc781eb38701d07aee3c0751cb88e03d771e03a0e5cc781eb38701d07aef3c0751eb8ce03d779e03a0f5ce7811b7ce4c1471e7ce4c1471e7ce4d13ff27fb9fdce35f588b66bfe17ed5c538f28d6dbb9a61ed1f6387944dbd7d423daee8a47b4dd138f68bb231e513c579d6bea5fb4734d3da278ae3ad7d423da3f57fdc7ab47b47fccfdc7ab47b47fccfdc7ab47148f19fab7ff78f588f6fbb7ff78f588e2b982feed3f5e3da278aea07ffb8f57f683798167b87d3e9ee1f6097986db6d7e843b33cf33dc6ef5f9a7f7a6f2116b9f8fdf58fb6cfcc6dae3e637d63e4dbfb1f639fa8db54fd06fac3d5e7e63ed3377fefd1f10ebb7bdfd4ef011ebb75da0eded77898f58bfeded77898f58bfededb7688f58bfeded376c8f58bfed0a6d57687bfbcddc23d66fbb42dbdbefa41eb17edbdbefab1eb17edb0ddade7ecff588f5dbde7ecff588f5dbde7ec3f388f5dbeed07687b63bb4bdfdd6e811ebb7bdfdd6e811ebb73da0ed016d6fbf4b79c4fa6d0f687bfb1dcc23d66f7b40db03da5ea0ed05da5ea0ed05da5ea0ed05da5ea0ed05da5ea0ed6768fb19da7e86b69fa1ed6768fb19da7e86b69fa1ed6768fb05da7e81b65fa0ed1768fb05da7e81b65fa0ed1768fba5d9f6fb4fc7fcb4d7368f58abed8f58abed8f58ab7d8f58ab0d8f58ab0d8f18b6a1b5b67b06a9855bf35207a98d5b5e55075bbdf80cd22958e81c2c7412b6fea60e523bb784b90e523b9b2bf66790da29d4cee652fe39f0a89dcd77e8cf20b5b3f90efd19a476365f933f83d4cee66bf247d0a89ddbdf6cab83d44ea3761ab573fb43887590dab9fd958a7ab2a0766e7ff7b20ee21c44ed746aa7533b9ddae9d4ceed37cfeb20b533a89d41eddcead53a48ed6ce6629e416a6733d7f20c523b9b99966790dad9cca43c83d4ce661ee519a47636f324cf20b5b399257906a99d676ae7196fadd4ceedafd1d4375ebab96e7fbcb70ed249d89afd3a482761fb5b357590d709b850d8fe46f44b14970a5b54ff12c5c5c29614be2c5fe89805cf94e20a469bdf0c5bef4d54af62c7db09ef235b90ff72f3a27a0deffe8d9fca7d89e2ad0fcf86e10ac0f846be55e52f513c66bee9e20dc770f6379ce10da778c7638e66d67b9de4e9a82edb9ffcaca33c51e1885d1abfd4f312c6e35a16bcad2d0bcecccb72c135bf6cdde1cb23012ee844707c89e29478fbb5740cf3f463f874750de37347e3f7b45ec3f8ec615b40f91ac68713c3c7b06b181f508c1fc56cfb63062f615cf35ec37cd670dd7b0de3592b78c790334e9272c695b39c71917b0de39137fe3e507dcb69bfe159c3b842d405bb4405172bdaf811bdd7303e202a3e525cc3f890a838cbab6e7ff7e2358c7779c59b842a2e64af078e87e6bc3a09bc88b4f1437a75b8fd92730de3b4a7679c72afcdc6233f37df64ae619c91af613ce767bce75fc3785acef874a1675cb869e307155fc3bc64c43585367e85fa358cebb3f6fbdf358c49063b6d7f41aa0e2f274ec5e0cde27aa7c1155ee3a76d5ec2bce2155c8a5d97cbbc6ec505d535cc6b44de79e12e2938af5dc3d8b0f61711aa308e9682cf9776763ce767bc41db19b30676e1c7900b265eae613c2d17bc49b67ee9fd358c69b113cec87ec225b4b7bfdf518531ebc6d7f7358c99375e1c78fbeb1f551893908d5f657a0df369c12555ebf7215fc27883f6056fb1ae9897704e10b872e25693ec2c27527961e28ad9c06b38298d751be6cabcf19381af611c8a8ecf25ee3cd67cfbab4f7538f8d0029fc7ae61de395ffec1e33c789c078ff3e0fe6e7f49af0a27a5f1d0dadfd37b86cf98bebb761897e6b70227ec9238f19b8105178321b894bc761896e6d440183ef484f10b0fc38c49f0151a8ddff47e0de33937cc145dc37ce4b8468ec64f4cbf86f1858de10afb1ae6b38679a66b98cf1a3e3285f370704c9f5fc378d61c6f54e13c90838fbce0cc740de369697f5f760df360e2a5645c30bf16177c74085e695ec3d8ee0bcec8d7308eb50bbef7be86f90d62725a7069710de368b9600aec1ae676f3bc76c1654d5cf059f01ae676f3747fc1c560e1375845f0fe5df8dd4ae1ebbbf09aa9387649717caa29673ca9e713eefccc2fe7ce8a0ff767c5c796b3e2947be614f7b9f15b782f617ea75bf081eb5cf035cd358c67ade0383ff3c3fd991feecffcf47e2e788bbd86f96d36be3738377e78f1258c53ee358cafbc4fd8eecb0907f275c6a5737ee11722d739135fb873b6e61ac6afdf357e8bfc258c77a26b185ff7732ef7c277e06b185fa09f164cd7dce2fca58105abbfc5932f0ee09c7f832df876f0c4ddbe9cce7c7c4be3ef07bec671bdbb2c174c9e2ca278b52e12f848bb48e12f4048e32f07bcc5f92b9efc78778bf3dbd936b67ac695a7c2db1f5ac6fa4d712db498e3c3edf51190db6f67bc3d2ece6bef251a3fe9ff126fd3bc2a8eaf2496ebc4c371becd5daf5e9c359773f0bbfb6b1ccfcf99bfb2708b73fdfc7c718be3f9bb9c787c5e1a3f01fd123fe357496f71bc7e2ffcfd835b1ccfdf358e2fea4f27fe76f289d3ced738de5cae715c2ec829795b7fe2b75e72bd8070ffc25f0eb9c6f109f216c7f3738df3f743164c1adce27cfcfcfe4a44f1fe29c2f952d1055fc65ce39829bec5f1ab1ccad7bf242f3dafb7375cd35de3f8f022c6f7f7dbd73db07ee7949178e3d7bceb78f0579b2484bf6713826bbb6b1cd388d7387fed2304d74fb778523fde3f6e71ecbfe02fbb5de33c7eae713e3ec7272909ce6dcb39707e96eb831c7e61e0c479dc6b9c5fdb9f1a7f19a68e2f27fefecac2d7af2ec9d70644f88b20d713dc3f3e01e0d406cc8f587f4cb591f223d6ef8b36447ec4fa6350083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c0490838757ec0fa19c4214bed845c70e737aa9f416a27ac6d3bbf51fd08c2aa54083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012044e82c049103809022741e024089c048193207012044e82c049103809022741e024089c048193207012044e82c049103809022741e024089c048193207012044e82c049103809022741e024089c048193207012044e82c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e02409709204385de3089c6e71024e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014eedbf52f88851b9fe986aff25c247acdf17edbf36f888f5c7a0127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093127052024e4ac049093829012725e0a4049c948093227052044e8ac049113829022745e0a4089c148193227052044e8ac049113829022745e0a4089c148193227052044e8ac049113829022745e0a4089c148193227052044e8ac049113829022745e0a4089c148193227052044ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c948193327052064ecac049193829032765e0a40c9c9481933270d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c04913e0a40970d2043869029c34014e9a00274d809326c0e91a47e0748b1370d2043869029c34014c9a00264d009326804913c0a40960d2043069029834014c9a00264d009326804913c0a40960d2043069029834014c9a00264d009326804913c06400980c0093016032004c0680c9003019002623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012623c06404988c0093116032024c4680c9083019012643c06408980c0193216032044c8680c9103019022643c06408980c0193216032044c8680c9103019022643c06408980c0193216032044c8680c9103019022643c06408980c0193216032044c8680c9103019022643c06408988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640c988c0193316032064cc680c9183019032663c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c9600264b00d3f5ff2260bac509305902982c014c9600264b00932580c912c0640960bac7f1118c01932580c912c0640960b204305902982c014c9600264b00932580c912c0640960b204305902982c014c0e80c9013039002607c0e400981c0093036072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072024c4e80c9093039012627c0e404989c0093136072044c8e80c9113039022647c0e408981c0193236072044c8e80c9113039022647c0e408981c0193236072044c8e80c9113039022647c0e408981c0193236072044c8e80c9113039022647c0e408981c0193236072044c8e80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064cce80c9193039032667c0e40c989c0193336072064c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204305de308986e71024c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f204307902983c014c9e00264f00932780c913c0e40960f2043079029802005300600a004c01802900300500a600c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014049882005310600a024c41802908300501a620c014089802015320600a044c81802910300502a640c014089802015320600a044c81802910300502a640c014089802015320600a044c81802910300502a640c014089802015320600a044c81802910300502a640c014089802015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9882015330600a064cc1802918300503a660c0140c9822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c01409608a043045029822014c9100a648005324802912c0140960bac61130dde2049822014c9100a648005324802912c01409608a04304502986e71c52757064e9100a748805324c02912e01409708a043845029c22014e9100a748805324c02912e01409708a043815004e05805301e054003815004e05805301e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054083815024e85805321e054103815044e05815341e054103815044e05815341e054103815044e05815341e054103815044e05815341e054103815044e05815341e054103815044e05815341e054103815044e05815341e054103815044e05815341e054103815044e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e054183815064e85815361e05418389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504389504385de3089c6e71024e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014e25014ea50b9cfcfa1ff77f2046e55a63ee116bb5e7116bf5c523d66ac723d61a83cf36b43af019a41636bbee19a43636278567b035a33c83740a9adfab7b06e924341fbc9f416a6773fdf00c523b9bb99f6790dad97c9a7e06a99dcd34dc33884396dad9cc053f83d4cee6f2f619a4763617b68f607355fa0c523b9bebd16790dad9fcbacb3348ed6cde039f416a67f3e9ee19a47636b3dccf20b5b399c27e06a99dcdb9fc19a47636b31ccf20b5b3b97e7806a99dcd7cf83348ed6cde739e416a677335f00c523b9bcff1cf20b5b3099c9e416a673377f10c523b9babb66790dad95caf3d83d4cee693d23388b7566a67f375f0f3c64b37d7666aec19a493d07c287b06e924341f379f415e27e042a1b90e5ea3b85468e688d6282e169acf7febf2858eb90d9cd65b25def19aef37d77b13d5db064ecff9be099cd628de489ad9d4358af5e2edbf0d9cd6289d8d36705aa378236f7edd798de231f34d176f386de0b446f18e8d537c1b38adf7155cffe3996c03a76794272a1cb11de0b486f1b83ac0690de3ccdc014eeb4348f37bc4eb23012ee83ac0695ddce394d8014e6b98a79f3670aac2f8dcd17efb5b85f1d9a30d9caa303e9cb4815315c6079436705ac3cd94e01ac6356f073855613e6bb8f2ed00a7f5b10c27c90e705ac3b8c8ed00a735dc4c143e6f39edef30af615c217680d3fadc888b950e70aac2f880d8feaa6f15c687c436705ac3cd77e65518eff26de0b4867121db014e6b985727edefd3ae615cb37680d31ac669af039cd630a63d3ac0690de38cdc014e5598130af8a8dd014e6b18176e9d5c7f15e62523ae293ac0a90ae3faac0d20d63026193ac0e9196e03a7358c378b0e707a86db2f88d630af78dbc0a95a2ef3ba1517541de0b4ae0279e7edafccac619cd73ac0690de303760738ad617cbeec00a72a8c75b781d333dcfedae91ac6c44b0738ad61bc4976805315c6b4581b38ad615c4277805315c6ac1b5fdf1de05485f9c8f11aeb00a72a8c69c8f60bf62acce71c1f3c3bc0e9196e03a767b80d9cd6302ec03bc0690d27d9594ea4f2c2a4039caa70521aeb6ef38967b8fd65dd2a8c43b10d9cd6308fb536707a86dbc0690de3f35807385561ecef3670aac29c72e771de064ecf70fb2570154e4ae3a1b5bf01f70cb781d31a6e7e5fbe0ae35b8136705ac3fc66a00d9c9ee136707a86dbc0e919e6d4400738ad617ee1d1064e55188fbc0d9caa309ef33670aac27ce4b846ee00a72a8c2f6cdac0a90af359c33c53073855613c6b6de05485f1acb5815315c6b3d6064ecf701b383dc36de05485f1b4b4bf5ebd867930f152b2039cd6303e3a74805315c676b7815315c6b1d6064e5598df2026a70597161de05485b9dd386177805315e676e3b360073855616e372e063bc0e9196e03a76798dfad74805315c6d7ac6de0b486f1a9a6039c1ee10e707a86f9e55c0738ad617c6ce900a7679853dc1de0b486f99d6efb9bdf6b185fd37480d31ac671de014e5518df9df3d37b073855617e9b8def0d3ac0690de394db014e8f700738ad611cc81de0f40cf30b910e707a86395bd3014e55181bd6064e55185ff7732eb7039caa30be40ef00a73ace5f1a6803a73a9e7c7100e7fc1e705ae3dced3de0f48c77805315c7f56e0f383de31de0b4c6dbc0698db7815315e7ef7776805315c7c7bb1e70aae3787c1de0f48c77805315c7b5500f38adf13670aae2787bec01a767bc039cd6781b3855717c25d1034e6b9c6f733de0f48c7780531dc7f3d3014e759cebe7e78b1e707ac63bc0698db781d31a6f03a73a8ed76f0738d5713c7f1de0f488f780531dc7d7c61de054c571b9d0034e6b9cdf7af580d333de014e551c9f207bc0a98ef3f743dac0a98ef3f1f3fbab1e705ae39c2fed01a72a8e99e21e705ae37cfdf780d31a6f03a72a8e0f2f3de0b4c679ddd6034e6bbc0d9c9ef10e705ae36de054c5314dd8034e551cd7473de054c793fde323580f38ad71feb25b0f38d5713efe36705ae39cdbee01a735de064e8f780f3855717e6ddf014ecf780738ad71be7e7bc0e919ef00a7354ec049003809002701e024009c048093007012004e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e42c049083809012721e024049c848093107012024e82c049103809022741e024089c048193207012044e82c049103809022741e024089c048193207012044e82c049103809022741e024089c048193207012044e82c049103809022741e024089c048193207012044e82c049103809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c049183809032761e0240c9c848193307012064ec2c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029c24014e9200a76b1c81d32d4ec04912e024097092043849029c24014e9200274980932480e9378ee307819324c04912e024097092043849029c24014e92002749809324c04912e024097092043849029ca40d9c74f979fe03312ab71973556cd39e2ab6b9d6aad8a69f9e3181e36c40ac2ad63fce06c4aa62fde36c20ad674ce138158e53e138158e53e138158ed3e0380d8ed3e0380d8ed3e0380d8ed3e1381d8ed3e1381d8ed3e1381d8e33e038038e33e038038e33e038038eb3c0711638ce02c759e0380b1c6781e33cc3719ee138cf709c6738ce331ce7198ef302c77981e3bcc0715ee0382f709c1738cee54413fd8966fa134df5279aeb4f34d99fe868173a5abc2fe18d09ef4c786ba27bd34237a785ee4e0bdd9e16ba3f2d74835ae80eb5d02d6aa17bd44237a985ee520bdda616ba4f2d740358e80eb0d02d60a17bc042378185ee020bdd0616ba0f2c742358e84eb0d0ad60a17bc14213fe4233fe4253fe4273fe4293fe42b3fe42d3fe42f3fe4213ff4233ff4253ff4273ff4293ff42b3ff42d3ff42f3ffd2bb01f8cfe601c77f1f0fda9f4be773ed7cfe5b667332aad8e65c54b14d83aad8a63dcf586316ab62fdfa1a335115ebd7d7583057b17e7d8d856f15ebd7d7b814aa58bfbec670ae62fdfa1a83b98af5eb6b0cc82ad6afafb520a983fd1a5bcb8a3ab8a9f37cfef9bd4036a3f75fa431deff451a23fe5fc4ba91c6d5768f48f708e4f752bd9f93db0deff69fa7cb8de4dd48ee8fc5cfe5f6bf967f91df4fef5b9ecacfd97e2ee5e772bebde86a19ddbd352c377777fddff1b51a6efffa63a75fabe57cdbedf7767e6fc2fd7f5f6f7be77fe14b8b257fa68ef3edbf6e2e8ebdfbbefc76f4e9f1f97596dbbebfdfb9f35be4b6c365b9876ef5dc0b5ed765721f57dfe891cd56ff5a75ff77735fad2ab1af5f7d5335ecbafaa66ad87df54dd5327bf54dee7cd7d577a08ef4ea9bdaf7ecd537b3f38f5d7d5395eebdfafceb57df540dbbaebea91a765f7d53b5cc5e7d933bdf75f51da823bdfaa6f63d7bf5cdecfc6357df54a57bafbef8fad53755c3aeab6faa86dd57df542db357dfe4ce775d7d07ea48afbea97dcf5e7d333bffd8d53755e9deabaf7cfdea9baa61d7d53755c3eeab6faa96d9ab6f72e7bbaebe0375a457dfd4be67afbe999d7fecea9baa74efd577fefad53755c3aeab6faa86dd57df542db357dfe4ce775d7d07ea48afbea97dcf5e7d333bffd8d53755e9deabeff2f5ab6faa865d57df540dbbafbea95a66afbec99defbafa0ed4915e7d53fb9ebdfa6676feb1ab6faad2bd57dfbdd0772fbfb92a765d7f7355ecbe00e7aa99bd0267f7beeb123c52497a0dceed7cf6229cdafbc7aec2b95a775f86cbf72fc3a92af65d865355ecbf0ca7aa99be0c27f7beef323c50497e194eed7cfa329cd9fbe72ec3a95a775f86f2fdcb70aa8a7d97e15415fb2fc3a96aa62fc3c9bdefbb0c0f54925f86533b9fbe0c67f6feb9cb70aad6dd97e1f7bf073357c5becbf06fbe093357cdf465f817df853952497e197ef5db30537bffdc65f827df8759beff8598b92af65d867ff39598b96aa62fc3bff852cc914af2cbf0ab5f8b99dafbe72ec33ff962ccfdaafaf2653855c5becb70aa8afd97e15435d397e1e4def75d86072ac92fc3a99d4f5f86337bffdc653855eb9ecbd06fb57cf52a9cae61fa229cae61d735385dcbcc25b863e7d357e0c13af0029cdef7ccf537bbf38f5c7ed395eebdfae4eb57df540dbbaebea91a765f7d53b5cc5e7d933bdf75f51da823bdfaa6f63d7bf5cdecfc6357df54a57bafbeefe663a66bd875f57d3f1b335dcbecd5f7ed5cccc13ad2abef6b9998d99d7feceafb7a1ee656c977d330d335ecbafabe9f8499ae65f6eafb760ae6601de9d5f7b504ccecce3f76f57d3dfd72abe4bbd997e91a765d7ddfcfbd4cd7327bf51d488a0c5f7d07ea48afbea97dcf5e7d333bffd8d53755e9deab6f865fecbbfaa66ad875f54dd5b0fbea9baa65f6ea9bdcf9aeabef401de9d537b5efd9ab6f66e71fbbfaa62add7bf5cdf08b7d57df540dbbaebea91a765f7d53b5cc5e7d933bdf75f51da823bdfaa6f63d7bf5cdecfc6357df54a5f357dff5b1f2df87176f56736b80773ae2adcfb7bfb1f3f92ada9dffd12a36bf96355885fc46e2f77cdf2f6efdf7ef6f3f94d3add79f97fddf54b3f7844d56f347276df3dbd8dfa966efb53252cdef00b4df8ffea89e6f0e82ba9e6f8e82ba9e6f0e83ba1e1e07c313f3f9566d44ef96930c838f55c3a360b89acbb39ae6eae253adc9aaf9506baefff1a8a7bfacfc549bc62afb7ccbfacbd92fb40c2afb78cb78c5f3b1c62dcfc6f1b2fdef2bfcd419f5e7199d5ab87eacc17beba7f6dbf757b51faae20f5a41b766aae283abda0f56b3f7847d7055fbc16a6839f3c16a683573b49ad155ed27ebf9e620185dd57eb29e6f0e83d155edc48bae23abda0f56c3a3e04f56b51face643ad39beaafd78659f6fd9ce55edc72bfb78cb0eac6aa75e547f6255fb950a3f7546bfb1aafd8bfaa9fdfefd55ed87aaf88356d0ad99aaf8e0aaf683d5ec3d611f5cd57eb01a5ace7cb01a5acd1cad667455fbc97abe39084657b59face79bc3607455ebe373f69155ed07abe151f027abda0f56f3a1d61c5fd57ebcb2cfb76ce7aaf6e3957dbc650756b533f57d6455fb950a3f7546bfb1aafd8bfadbedb7fb7f95fe9da0b1181cf8aec99eddc2d74bc67677f9bd61fd76fee0d272298f5bd85f557c7e6b787b25f0d98a5f5652db3f81fce91acfff2ec5fbb43dd24e786b7c64fccded361d7fd9eebe36fe3e5af1ccf8fb54c5e3e3ef23354e8f3fc8ef1e197f73bb4dc75fb6bbaf8dbf8f563c33fe3e55f1f8f8fb488dd3e30f9ec48e8cbfb9dda6e32fdbddd7c6df472b9e197f9faa787cfc7da4c6a9f1f7bb02fdf8f89bdf2d8ebf91dd7d65fc7dbce2d1f1f7c98ac7c6dfc76a9c1e7f5f78fe98df6d3afefe23cf1f1faf7866fcfdedf3c7c76a9c1e7f5f78fe98df6d3afefe23cf1f1faf7866fcfdedf3c7c76a1c1b7f17b9cfb78dbf14fc2fd2f85bc517f9f75f7a915e19fdb7c7726fcaef79907b872cff3ae5f667e93759fcaaaca665ffefff01e6191c3f


