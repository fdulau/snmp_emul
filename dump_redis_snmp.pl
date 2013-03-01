#!/usr/bin/perl

##########################################################
# snmp_emul
# Gnu GPL2 license
#
# $Id: dump_redis_snmp.pl  2010-12-18 14:32:07 fabrice $
#
# Fabrice Dulaunoy <fabrice@dulaunoy.com>
# copyright 2010,2011,2012,2013 Fabrice Dulaunoy
###########################################################

use strict;
use warnings;
use NetSNMP::OID;
use Data::Dumper;
use Getopt::Long;
use Redis;

my $VERSION = '0.14';

my $REDIS = '127.0.0.1:6379';

use subs qw(say);

my $oid;
my $type;
my $val;
my $do;
my $next;
my $access;
my $small = 50;
my $version;
my $help;

GetOptions(
    'l=s' => \$small,
    'h'   => \$help,
    'v'   => \$version,
    'r=s' => \$REDIS,
);

if ( $version ) { print "$0 $VERSION \n"; exit; }

if ( $help )
{
    print "Usage: $0 [options ...]\n\n";

    print "Where options include:\n";
    print "\t -h \t\t\t Print version and exit \n";
    print "\t -v \t\t\t This help \n";
    print "\t -l length \t\t max length of data tag. Truncate data. (default=$small) If set to 0 = no limit \n";
    print "\t -r server:port \t use that redis server (default=$REDIS)\n";

    exit;
}

my $redis = Redis->new(
    server => $REDIS,
    debug  => 0
);

$redis->select( 4 );    # use DB nbr 4 ( why not !!!)

my @enterprises = $redis->smembers( 'enterprise' );
{
    $Data::Dumper::Varname = 'enterprise';
    say \@enterprises;
}
my %all_next = $redis->hgetall( 'next' );
my %all_type = $redis->hgetall( 'type' );

## merge all_next and all_type to get all oid in all case( oops, a lot of all in that comment ) ##

my %all_oid = ( %all_next, %all_type );

if ( scalar keys %all_oid )
{
    my $l_oid = length( ( sort { length $a <=> length $b } keys %all_oid )[-1] );
#my $l_type = length( ( sort { length $a <=> length $b } values %all_type )[-1] );
    my $l_type = 4;

    my %all_val = $redis->hgetall( 'val' );
    my $l_val = length( ( sort { length $a <=> length $b } values %all_val )[-1] );
    if ( $small )
    {
        $l_val = $small;
    }
    my %all_access = $redis->hgetall( 'access' );
#  my $l_access = length( ( sort { length $a <=> length $b } values %all_access )[-1] );
    my $l_access = 6;
    my %all_do   = $redis->hgetall( 'do' );

    my $l_do = 0;
    if ( scalar keys %all_do )
    {
        $l_do = length( ( sort { length $a <=> length $b } values %all_do )[-1] );
    }
    say print_format_center( 'oid', 'next', 'type', 'val', 'access', 'do' );
    foreach $oid ( sort { sort_oid( $a, $b ) } keys %all_oid )
    {
        $type = $redis->hget( 'type', $oid ) // '';
        $val  = $redis->hget( 'val',  $oid ) // '';
        if ( $small )
        {
            $val = substr $val, 0, $small;
        }
        $next   = $redis->hget( 'next',   $oid ) // '';
        $access = $redis->hget( 'access', $oid ) // '';
        $access = '  ' . $access . '  ';
        $do     = $redis->hget( 'do',     $oid ) // '';
        say print_format( $oid, $next, $type, $val, $access, $do );
    }

    sub print_format
    {
        my $oid    = shift;
        my $next   = shift;
        my $type   = shift;
        my $val    = shift;
        my $access = shift;
        my $do     = shift;
        my $msg    = '[';

        $msg .= append( $oid, $l_oid ) . '] -> [' . append( $next, $l_oid ) . '] <' . append( $type, $l_type, 1 ) . '> <' . append( $val, $l_val, 1 ) . '> <' . append( $access, $l_access, 1 ) . '> <' . append( $do, $l_do, 1 ) . '>';
        return $msg;
    }

    sub print_format_center
    {
        my $oid    = shift;
        my $next   = shift;
        my $type   = shift;
        my $val    = shift;
        my $access = shift;
        my $do     = shift;
        my $msg    = '[';

        $msg .= append( $oid, $l_oid, 2 ) . '] -> [' . append( $next, $l_oid, 2 ) . '] <' . append( $type, $l_type, 2 ) . '> <' . append( $val, $l_val, 2 ) . '> <' . append( $access, $l_access, 2 ) . '> <' . append( $do, $l_do, 2 ) . '>';
        return $msg;
    }
}

sub append
{
    my $data   = shift;
    my $len    = shift;
    my $justif = shift // 0;
    my $blank  = ' ' x $len;
    my $l_data = length $data;
    if ( $justif == 1 )
    {
        substr $blank, $len - $l_data, $l_data, $data;
    }
    elsif ( $justif == 2 )
    {
        substr $blank, ( $len - $l_data ) / 2, $l_data, $data;
    }
    else
    {
        substr $blank, 0, $l_data, $data;
    }

    return $blank;

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

#sub sort_oid
#{
#    my $o1 = shift;
#    my $o2 = shift;
#    $o1 =~ s/^\.//;
#    $o2 =~ s/^\.//;
#    my @O1 = split /\./, $o1;
#    my @O2 = split /\./, $o2;
#    my @b = $#O1 < $#O2 ? @O2 : @O1;
#    foreach my $i ( 0 .. $#b )
#    {
#        no warnings;
#        my $res = ( $O1[$i] <=> $O2[$i] );
#        use warnings;
#        next if ( $res == 0 );
#        return $res;
#    }
#}

sub sort_oid
{
    my $oi1 = shift;
    my $oi2 = shift;
    return 1 if ( $oi1 !~ /^\.1/ || $oi2 !~ /^\.1/ );
    $oi1 =~ s/\.$//;
    $oi2 =~ s/\.$//;
    my $o1 = new NetSNMP::OID( $oi1 );
    my $o2 = new NetSNMP::OID( $oi2 );
    if ( $o1 > $o2 )
    {
        return 1;
    }
    elsif ( $o1 < $o2 )
    {
        return -1;
    }
    else
    {
        return 0;
    }
}
