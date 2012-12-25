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

use Redis;

my $VERSION = '0.05';

my $REDIS = '127.0.0.1:6379';
my $redis = Redis->new(
    server => $REDIS,
    debug  => 0
);

$redis->select( 4 );    # use DB nbr 4 ( why not !!!)
use subs qw(say);

my @enterprises = $redis->smembers( 'enterprise' );
{
    $Data::Dumper::Varname = 'enterprise';
    say \@enterprises;
}

my $oid;
my $type;
my $val;
my $do;
my $next;

my %all_oid = $redis->hgetall( 'next' );
if ( scalar keys %all_oid )
{
    my $l_oid  = length( ( sort { length $a <=> length $b } keys %all_oid )[-1] );
    my $l_type = length( ( sort { length $a <=> length $b } values %all_oid )[-1] );

    my %all_val = $redis->hgetall( 'val' );
    my $l_val = length( ( sort { length $a <=> length $b } values %all_val )[-1] );

    my %all_do = $redis->hgetall( 'do' );

    my $l_do = 0;
    if ( scalar keys %all_do )
    {
        $l_do = length( ( sort { length $a <=> length $b } values %all_do )[-1] );
    }
    say print_format_center( 'oid', 'next', 'type', 'val', 'do' );
    foreach $oid ( sort { sort_oid( $a, $b ) } keys %all_oid )
    {
        $type = $all_oid{ $oid };
        $val  = $redis->hget( 'val', $oid ) // '';
        $next = $redis->hget( 'next', $oid ) // '';
        $do   = $redis->hget( 'do', $oid ) // '';
        say print_format( $oid, $next, $type, $val, $do );
    }

    sub print_format
    {
        my $oid  = shift;
        my $next = shift;
        my $type = shift;
        my $val  = shift;
        my $do   = shift;
        my $msg  = '[';

        $msg .= append( $oid, $l_oid ) . '] -> [' . append( $next, $l_oid ) . '] <' . append( $type, $l_type, 1 ) . '> <' . append( $val, $l_val, 1 ) . '> <' . append( $do, $l_do, 1 ) . '>';
        return $msg;
    }

    sub print_format_center
    {
        my $oid  = shift;
        my $next = shift;
        my $type = shift;
        my $val  = shift;
        my $do   = shift;
        my $msg  = '[';

        $msg .= append( $oid, $l_oid, 2 ) . '] -> [' . append( $next, $l_oid, 2 ) . '] <' . append( $type, $l_type, 2 ) . '> <' . append( $val, $l_val, 2 ) . '> <' . append( $do, $l_do, 2 ) . '>';
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
