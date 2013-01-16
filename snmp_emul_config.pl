#!/usr/bin/perl
##########################################################
# snmp_emul
# Gnu GPL2 license
#
# $Id: snmp_emul_config.pl 2 2011-07-12 09:32:07 fabrice $
#
# Fabrice Dulaunoy <fabrice@dulaunoy.com>
# copyright 2011, 2012, 2013 Fabrice Dulaunoy
###########################################################

use Mojolicious::Lite;
use IO::All;
use File::Spec;
use Data::Dumper;
use Redis;
use NetSNMP::OID;

use subs qw( debug  list_dir);

my $VERSION = '0.08';

####################### config section #######################
my $PARSE            = 1;
my $LISTEN           = 'http://*:8080';
my $LOG              = '/tmp/mojo.log';
my $BASE             = '/opt/snmp_emul/conf';
my $AVAILABLE_FOLDER = 'available';
my $ENABLED_FOLDER   = 'enabled';
my $CMD              = '/opt/snmp_emul/bin/parse_snmp_emul.pl';
my $REDIS            = '127.0.0.1:6379';
my $DEFAULT_OID      = '.1.3.6.1.4.1.';
my $enterprise_oid   = '.1.3.6.1.(2|4).1.';
##############################################################
my $redis = Redis->new(
    server => $REDIS,
    debug  => 0
);

$redis->select( 4 );    # use DB nbr 4 ( why not !!!)

my $enterprise_option = fetch_enterprise();
my $oids_option       = fetch_oids();

my %ASN_TYPE = (

    1  => 'BOOLEAN',
    2  => 'INTEGER',
    3  => 'BIT_STR',
    4  => 'OCTET_STR',
    5  => 'NULL',
    6  => 'OBJECT_ID',
    16 => 'SEQUENCE',
    17 => 'SET',
    64 => 'APPLICATION/IPADDRESS',
    65 => 'COUNTER',
    66 => 'UNSIGNED/GAUGE',
    67 => 'TIMETICKS',
    68 => 'OPAQUE',
    70 => 'COUNTER64',
    72 => 'FLOAT',
    73 => 'DOUBLE',
    74 => 'INTEGER64',
    75 => 'UNSIGNED64',
);

my $AVAILABLE_PATH = File::Spec->catfile( $BASE, $AVAILABLE_FOLDER );
my $ENABLED_PATH   = File::Spec->catfile( $BASE, $ENABLED_FOLDER );
my $oid            = $DEFAULT_OID;
my $val;
my $type;
my $oids_option_ent;
my $selected_ent;

sub debug
{
    my $msg = shift;
    if ( $LOG )
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
        open LOG, '>>', $LOG;
        print LOG "$msg\n";
        close LOG;
    }
}

sub list_dir
{
    my $some_dir = shift;
    my $dis      = shift;
    my $tag      = 'en_';
    if ( $dis )
    {
        $tag = 'dis_';
    }
    my $res;
    opendir( my $dh, $some_dir ) || die "can't opendir $some_dir: $!";
    my @dots = sort grep { -f "$some_dir/$_" } readdir( $dh );
    closedir $dh;
    foreach my $file_name ( @dots )
    {
        my $file = "$some_dir/$file_name";
        $res .= '<option name="opt" id="' . $tag . $file_name . '" value="' . $file . '" >' . $file_name . "</option>\n";
    }
    $res .= '<option name="opt" id="' . $tag . 'empty" value="" >' . "</option>\n";
    return $res;
}

my $available = list_dir( $AVAILABLE_PATH );
my $enabled = list_dir( $ENABLED_PATH, 1 );

sub fetch_enterprise
{
  
    my @enterprises = $redis->smembers( 'enterprise' );
    my $res         = '<option name="opt" id="empty" value="" >' . "</option>\n";

    foreach my $ent ( @enterprises )
    {
    if ( $selected_ent eq $ent )
    {
      $res .= '<option selected name="opt" id="' . $ent . '" value="' . $ent . '" >' . $ent . "</option>\n";
    
    }else{
        $res .= '<option name="opt" id="' . $ent . '" value="' . $ent . '" >' . $ent . "</option>\n";
	}

    }
    return $res;
}

sub fetch_oids
{

    my %enterprises = map { $_ => [] } $redis->smembers( 'enterprise' );

    my %enterprises_option;

  #  my %all_next = $redis->hgetall( 'next' );
    my %all_type = $redis->hgetall( 'type' );
    my %all_oid;
foreach my $t ( keys  %all_type )
{
next if ( $all_type{$t} == 0 );
$all_oid{$t}=$all_type{$t};

}
## merge all_next and all_type to get all oid in all case( oops, a lot of all in that comment ) ##

   # my %all_oid = ( %all_next, %all_type );
# my %all_oid =  grep { $_[1] != 0 } each $redis->hgetall( 'type' );

    my @all_oids = sort { sort_oid( $a, $b ) } keys %all_oid;

    foreach my $oid ( @all_oids )
    {
        my $tmp = $enterprise_oid;
        $tmp =~ s/\./\\./g;
        my $res = ( $oid =~ /^($tmp\d+)/ );
        my $ent = $1;
        push $enterprises{ $ent }, $oid;
    }
    foreach my $ent ( keys %enterprises )
    {
        my $res;
        foreach my $oid ( @{ $enterprises{ $ent } } )
        {
            $res .= '<option name="oids" id="' . $oid . '" value="' . $oid . '" >' . $oid . "</option>\n";

        }
        $enterprises_option{ $ent } = $res;
    }

    return ( \%enterprises_option );
}

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

app->config(
    hypnotoad => {
        listen             => [$LISTEN],
        pid_file           => '/var/run/snmp_emul_config.pid',
        inactivity_timeout => 60
    }
);

app->secret( 'Fab pass' );

# Upload form in DATA section
get '/' => sub {
    my $self = shift;
    $available         = list_dir( $AVAILABLE_PATH );
    $enabled           = list_dir( $ENABLED_PATH, 1 );
    $enterprise_option = fetch_enterprise();
    $self->stash( list_available => $available );
    $self->stash( list_enable    => $enabled );
    $self->stash( version        => $VERSION );
    $self->stash( oid            => $oid );
    $self->stash( val            => $val );
    $self->stash( type           => $type );
    $self->stash( type_str       => $ASN_TYPE{ $type } );
    $self->stash( enterprise     => $enterprise_option );
    $self->stash( oids           => $oids_option_ent );

} => 'form';

get '/css/min.css' => {
    template => 'css/min',
    format   => 'css'
} => 'min-css';

get '/redir' => 'redir';

post '/enterprise' => sub {
    my $self = shift;
    debug( $self->tx->req->params );
    while ( my $line = shift @{ $self->tx->req->params->params } )
    {
        my $param = shift @{ $self->tx->req->params->params };
        debug "in ENTERPRISE <$line>";
        if ( $line eq 'sel_enterprise' && $param )
        {
            debug "in ENT =" .$param;
          $selected_ent =$param ;

            $oids_option     = fetch_oids();
            $oids_option_ent = $oids_option->{ $selected_ent };

        }
	if ( $line eq 'sel_enterprise_oid' && $param )
        {
            debug "in ENT oid =" .$param;
           $oid = $param;
            if ( $redis->hexists( 'type', $oid ) )
            {
                $type = $redis->hget( 'type', $oid ) // '';
                $val  = $redis->hget( 'val',  $oid ) // '';
            }
debug "<$oid> <$type> <$val>";
        }
    }
} => 'enterprise';

post '/change' => sub {
    my $self = shift;

    while ( my $line = shift @{ $self->tx->req->params->params } )
    {
        debug "in change <$line>";
        if ( $line eq 'oid' && $self->tx->req->params->params->[0] )
        {
            debug "in oid =" . $self->tx->req->params->params->[0];
            $oid = shift @{ $self->tx->req->params->params };
            if ( $redis->hexists( 'type', $oid ) )
            {
                $type = $redis->hget( 'type', $oid ) // '';
                $val  = $redis->hget( 'val',  $oid ) // '';
            }
        }
        if ( $line eq 'oid_val' && $self->tx->req->params->params->[0] )
        {
            debug "in oid_val =" . $self->tx->req->params->params->[0];
            $val = shift @{ $self->tx->req->params->params };
            $redis->hset( 'val', $oid, $val );
            $val  = '';
            $type = '';
            $oid  = $DEFAULT_OID;
        }
    }
} => 'change';

post '/select' => sub {

    my $self = shift;
    my $name;

    foreach my $line ( @{ $self->tx->req->params->params } )
    {
        debug( $line );
        if ( $line =~ /^$BASE/ )
        {
            if ( $line =~ /^$ENABLED_PATH\/*(.*)/ )
            {
                $name = $1;
                my $source_file = File::Spec->catfile( $AVAILABLE_PATH, $name );
                debug "UNLINK=$line <$name> <$source_file>";
                if ( -l $line )
                {
                    debug "unlink result:" . unlink $line;
                    if ( $PARSE )
                    {
                        my $cmd = "$CMD -D -f $source_file";
                        my $res_do;
                        eval {
                            my $pid = open( my $README, "-|", $cmd )
                              or debug "Couldn't fork: $! <$cmd>";
                            while ( <$README> )
                            {
                                $res_do .= $_;
                            }
                            debug $res_do;
                        };
                    }
                }
            }
            if ( $line =~ /^$AVAILABLE_PATH\/*(.*)/ )
            {
                $name = $1;
                my $dest_file = File::Spec->catfile( $ENABLED_PATH, $name );
                debug "symlink result:" . symlink( $line, $dest_file );
                if ( $PARSE )
                {
                    my $cmd = "$CMD -f $dest_file";
                    my $res_do;
                    eval {
                        my $pid = open( my $README, "-|", $cmd )
                          or debug "Couldn't fork: $! <$cmd>";
                        while ( <$README> )
                        {
                            $res_do .= $_;
                        }
                        debug $res_do;
                    };
                }
            }
        }
        if ( $line =~ /flushing/ )
        {
            debug "doing flush";

            opendir( my $dh, $ENABLED_PATH ) || die "can't opendir $ENABLED_PATH $!";
            my @dots = sort grep { -f "$ENABLED_PATH/$_" } readdir( $dh );
            closedir $dh;
            foreach my $file_name ( @dots )
            {
                my $dest_file = File::Spec->catfile( $ENABLED_PATH, $file_name );
                debug "remove $dest_file";
                debug "unlink result:" . unlink $dest_file;
            }

            my $cmd = "$CMD -F";
            my $res_do;
            eval {
                my $pid = open( my $README, "-|", $cmd )
                  or debug "Couldn't fork: $! <$cmd>";
                while ( <$README> )
                {
                    $res_do .= $_;
                }
                debug $res_do;
            };
        }
        if ( $line =~ /reloading/ )
        {
            debug "doing reload";
            opendir( my $dh, $ENABLED_PATH ) || die "can't opendir $ENABLED_PATH $!";
            my @dots = sort grep { -f "$ENABLED_PATH/$_" } readdir( $dh );
            closedir $dh;
            foreach my $file_name ( @dots )
            {
                my $dest_file = File::Spec->catfile( $AVAILABLE_PATH, $file_name );
                debug "reload $dest_file";
                if ( $PARSE )
                {
                    my $cmd = "$CMD -f $dest_file";
                    my $res_do;
                    eval {
                        my $pid = open( my $README, "-|", $cmd )
                          or debug "Couldn't fork: $! <$cmd>";

                        while ( <$README> )
                        {
                            $res_do .= $_;
                        }
                        debug $res_do;
                    };
                }
            }
        }
    }
} => 'select';

# Multipart upload handler
post '/upload' => sub {

    my $self = shift;

# Check file size
    return $self->render(
        text   => 'File is too big.',
        status => 200
    ) if $self->req->is_limit_exceeded;

# Process uploaded file

    if ( $self->param( 'file' ) )
    {
        my $example = $self->param( 'file' );
        my $size    = $example->size;
        my $name    = $example->filename;

        $example->move_to( File::Spec->catfile( $AVAILABLE_PATH, $example->filename ) );

        $self->render(
            'redir',
            size => $size,
            name => $name
        );
    }
    if ( $self->param( 'bt_enable' ) )
    {
        debug( "enable with" . Dumper( $self->param( 'bt_enable' ) ) );
    }

    $available = list_dir( $AVAILABLE_PATH );
    $enabled = list_dir( $ENABLED_PATH, 1 );
    return $self->redirect_to( 'form' );
};

app->start;

__DATA__
 
@@ form.html.ep 
  % layout 'mylayout', title => 'SNMP Emul ' , version => <%= $version %>;  
<script language="javascript">
function basename(path) 
{
    return path.replace(/.*\/|\.[^.]*$/g, '');
}
 
function check_available()
{
	var elem_enable = document.getElementById("sel_enable").getElementsByTagName("option");
        var elem_avail = document.getElementById("sel_available").getElementsByTagName("option");
        for(var j = 0; j < elem_enable.length; j++)
        {
		var  dropdownIndex_enable = elem_enable[j].selected;	   
		if ( !dropdownIndex_enable ) 
		{
			continue;
		}
	      
        	for(var i = 0; i < elem_avail.length; i++)
        	{
        		var dropdownIndex_avail = elem_avail[i].selected;
			if ( !dropdownIndex_avail ) 
			{
				continue;
			}
			var avail_name = basename( elem_avail[i].value );
			var enable__name = basename( elem_enable[j].value );
			if ( avail_name == enable__name )
			{
				elem_avail[i].selected = false;
        		} 
		}
	}
}

function check_enable()
{
	var elem_enable = document.getElementById("sel_enable").getElementsByTagName("option");
        var elem_avail = document.getElementById("sel_available").getElementsByTagName("option");
        for(var j = 0; j < elem_avail.length; j++)
        {
		var  dropdownIndex_avail= elem_avail[j].selected;	   
		if ( !dropdownIndex_avail ) 
		{
			continue;
		}
	      
        	for(var i = 0; i < elem_enable.length; i++)
        	{
        		var dropdownIndex_enable = elem_enable[i].selected;
			if ( !dropdownIndex_enable ) 
			{
				continue;
			}
			var enable_name = basename( elem_enable[i].value );
			var avail_name = basename( elem_avail[j].value );
			if ( avail_name == enable_name )
			{
				elem_enable[i].selected = false;
        		} 
		}
	}
}

function reload()
{
   document.getElementById("status").value = 'reloading';
   document.getElementById("able").submit()
}
  
function flush()
{
   document.getElementById("status").value = 'flushing';
   document.getElementById("able").submit()
} 
</script>

	
   <div class="navbar navbar-fixed-top">
    <div class="navbar-inner">
      <div class="container">
        <a class="btn btn-navbar" data-toggle="collapse"
        data-target=".nav-collapse"></a> <a class="brand" href=
        "http://www.menolly.be/snmp_emul/" target="_blank">SNMP
        emulator configurator (version:<%== $version %>)</a>

        <div class="nav-collapse" id="main-menu">
          <div style="margin-left: 2em" class="nav" id=
          "main-menu-left">
            <ul class="btn btn-navbar"></ul>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="container">
    <section id="upload"></section>

    <div class="container">
      <section id="upload"><br></section>

      <div class="span12">
        <section id="upload"></section>

        <div class="span1">
          <section id="upload"></section>
        </div>

        <div class="span9">
          <section id="upload"></section>

          <h3 style="margin-left:150px"><section id="upload">Upload
          a new configuration file</section></h3>

          <h4 style="margin-left:150px"><section id="upload">(
          "MIB" or "snmpwalk -On" result or specific "agentx" file
          )</section></h4>

          <div style="margin-left:20px;">
            %= form_for upload => ( enctype => 'multipart/form-data'  ) => begin
            %= file_field 'file'  => (size => '55'  )
            %= submit_button 'Upload'
            % end
          </div>
        </div>
      </div>
    </div>
  </div>
  <hr>

  <div class="container">
    <section id="enterprise_form"></section>

    <form action="/enterprise" method="post" name="enterprise" id=
    "enterprise">
      <section id="enterprise_form"></section>

      <div class="span12">
        <section id="enterprise_form"></section>

        <div class="span_frame5 pagination-centered">
          <section id="enterprise_form"></section>

          <div>
            <section id="enterprise_form">Enterprise</section>
          </div><section id="enterprise_form"><select id=
          "sel_enterprise" name="sel_enterprise" onchange=
          "this.form.submit();" style="width:363px;">
            <%== $enterprise %>
          </select></section>
        </div><section id="enterprise_form"></section>

        <div class="span_frame5 pagination-centered">
          <section id="enterprise_form"></section>

          <div>
            <section id="enterprise_form">Get OID</section>
          </div><section id="enterprise_form"><select id=
          "sel_enterprise_oid" name="sel_enterprise_oid" onchange=
          "this.form.submit();" style="width:363px;">
            <%== $oids %>
          </select></section>
        </div><section id="enterprise_form"></section>
      </div>
    </form>
  </div>
  <hr>

  <div class="container">
    <section id="change_val"></section>

    <form action="/change" method="post" name="change" id="change">
      <section id="change_val"></section>

      <div class="span12">
        <section id="change_val"></section>

        <div class="span3 pagination-centered">
          <section id="change_val"><%== $oid %></section>
        </div><section id="change_val"></section>

        <div class="span3">
          <section id="change_val"></section>

          <center>
            <section id="change_val">Type <%== $type %>
            (<%== $type_str %>)</section>
          </center><section id="change_val"></section>
        </div>

        <div class="span4 pagination-centered">
          <section id="change_val"><input type="text" name=
          "oid_val" id="oid_val" value="<%== $val %>" style=
          "width:263px;"></section>
        </div><section id="change_val"></section>

        <div>
          <section id="change_val"><button type="button" name=
          "bt_oid_val" id="bt_oid_val" onclick=
          "this.form.submit();"><section id="change_val">Set
          value</section></button></section>
        </div>
      </div>
    </form>
  </div>
  <hr>

  <div class="container">
    <section id="abelizer"></section>

    <div class="container">
      <section id="abelizer"></section>

      <form action="/select" method="post" name="able" id="able">
        <section id="abelizer"><input type="hidden" id="status"
        name="status" value="undef"></section>

        <div class="span12">
          <section id="abelizer"></section>

          <div class="span_frame5 pagination-centered">
            <section id="abelizer"></section>

            <div>
              <section id="abelizer">Available</section>
            </div><section id="abelizer"><select multiple name=
            "sel_available" id="sel_available" size="20" style=
            "width:365px;" onchange="check_enable();">
              <%== $list_available %>
            </select></section>
          </div><section id="abelizer"></section>

          <div class="span1 pagination-centered">
            <section id="abelizer"></section>

            <div>
              <section id="abelizer">&nbsp; &nbsp;</section>
            </div><section id="abelizer"><button style=
            "margin-top:50px" type="button" name="bt_able" id=
            "bt_able" onclick="this.form.submit();"><section id=
            "abelizer"><img src="/double_arrow.png"></section>

            <div>
              &nbsp; &nbsp;
            </div><button style="margin-top:30px" type="button"
            name="bt_refresh" id="bt_refresh" onclick=
            "reload();"><img src="/refresh.png"></button>

            <div>
              &nbsp; &nbsp;
            </div><button style="margin-top:30px" type="button"
            name="bt_flush" id="bt_flush" onclick=
            "flush();"><img src=
            "/flush.png"></button></button></section>
          </div>

          <div class="span_frame5 pagination-centered">
            <div>
              Enabled
            </div><select multiple name="sel_enable" id=
            "sel_enable" size="20" style="width:365px;" onchange=
            "check_available();">
              <%== $list_enable %>
            </select>
          </div>
        </div>
      </form>
    </div>
  </div> 	
	
@@ select.html.ep
  <!DOCTYPE html>
  <html>
    <head>
      <title>Select</title> 
      <meta HTTP-EQUIV="REFRESH" content="0; url=/">
    </head>
    <body>
      in select
      <a href="/" >return</a>
    </body>
  </html>
	
@@ enterprise.html.ep
  <!DOCTYPE html>
  <html>
    <head>
      <title>Enterprise</title> 
      <meta HTTP-EQUIV="REFRESH" content="0; url=/">
    </head>
    <body>
      in select
      <a href="/" >return</a>
    </body>
  </html>  
  				
@@ redir.html.ep
  <!DOCTYPE html>
  <html>
   <head>
   <title>Redir</title>
   <meta HTTP-EQUIV="REFRESH" content="2; url=/">
   </head>
    <body>
	The file <%= $name %> (size: <%= $size %> byte) is uploaded.
    </body>
  </html>
    
@@ change.html.ep
  <!DOCTYPE html>
  <html>
   <head>
   <title>Change</title>
   <meta HTTP-EQUIV="REFRESH" content="0; url=/">
   </head>
    <body>
	 in change
      <a href="/" >return</a>
    </body>
  </html>  
    
@@ layouts/mylayout.html.ep
  <!DOCTYPE html>
  <html>
    <head><title><%= $title %> <%= $version %></title>
    <link href="/css/min.css" rel="stylesheet" type="text/css">
    </head>
    <body><%= content %></body>
  </html>
  
  
@@ css/min.css.ep
article,aside,details,figcaption,figure,footer,header,hgroup,nav,section{display:block;}
audio,canvas,video{display:inline-block;*display:inline;*zoom:1;}
audio:not([controls]){display:none;}
html{font-size:100%;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}
a:focus{outline:thin dotted #333;outline:5px auto -webkit-focus-ring-color;outline-offset:-2px;}
a:hover,a:active{outline:0;}
sub,sup{position:relative;font-size:75%;line-height:0;vertical-align:baseline;}
sup{top:-0.5em;}
sub{bottom:-0.25em;}
img{max-width:100%;width:auto\9;height:auto;vertical-align:middle;border:0;-ms-interpolation-mode:bicubic;}
#map_canvas img,.google-maps img{max-width:none;}
button,input,select,textarea{margin:0;font-size:100%;vertical-align:middle;}
button,input{*overflow:visible;line-height:normal;}
button::-moz-focus-inner,input::-moz-focus-inner{padding:0;border:0;}
button,html input[type="button"],input[type="reset"],input[type="submit"]{-webkit-appearance:button;cursor:pointer;}
label,select,button,input[type="button"],input[type="reset"],input[type="submit"],input[type="radio"],input[type="checkbox"]{cursor:pointer;}
input[type="search"]{-webkit-box-sizing:content-box;-moz-box-sizing:content-box;box-sizing:content-box;-webkit-appearance:textfield;}
input[type="search"]::-webkit-search-decoration,input[type="search"]::-webkit-search-cancel-button{-webkit-appearance:none;}
textarea{overflow:auto;vertical-align:top;}
@media print{*{text-shadow:none !important;color:#000 !important;background:transparent !important;box-shadow:none !important;} a,a:visited{text-decoration:underline;} a[href]:after{content:" (" attr(href) ")";} abbr[title]:after{content:" (" attr(title) ")";} .ir a:after,a[href^="javascript:"]:after,a[href^="#"]:after{content:"";} pre,blockquote{border:1px solid #999;page-break-inside:avoid;} thead{display:table-header-group;} tr,img{page-break-inside:avoid;} img{max-width:100% !important;} @page {margin:0.5cm;}p,h2,h3{orphans:3;widows:3;} h2,h3{page-break-after:avoid;}}.clearfix{*zoom:1;}.clearfix:before,.clearfix:after{display:table;content:"";line-height:0;}
.clearfix:after{clear:both;}
.hide-text{font:0/0 a;color:transparent;text-shadow:none;background-color:transparent;border:0;}
.input-block-level{display:block;width:100%;min-height:30px;-webkit-box-sizing:border-box;-moz-box-sizing:border-box;box-sizing:border-box;}
body{margin:0;font-family:"Open Sans",Calibri,Candara,Arial,sans-serif;font-size:14px;line-height:20px;color:#555555;background-color:#ffffff;}
a{color:#007fff;text-decoration:none;}
a:hover{color:#0066cc;text-decoration:underline;}
.img-rounded{-webkit-border-radius:6px;-moz-border-radius:6px;border-radius:6px;}
.img-polaroid{padding:4px;background-color:#fff;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.2);-webkit-box-shadow:0 1px 3px rgba(0, 0, 0, 0.1);-moz-box-shadow:0 1px 3px rgba(0, 0, 0, 0.1);box-shadow:0 1px 3px rgba(0, 0, 0, 0.1);}
.img-circle{-webkit-border-radius:500px;-moz-border-radius:500px;border-radius:500px;}
.row{margin-left:-20px;*zoom:1;}.row:before,.row:after{display:table;content:"";line-height:0;}
.row:after{clear:both;}
[class*="span"]{float:left;min-height:1px;margin-left:20px;}
.container,.navbar-static-top .container,.navbar-fixed-top .container,.navbar-fixed-bottom .container{width:940px;}
.span12{width:940px;}
.span11{width:860px;}
.span10{width:780px;}
.span9{width:700px;}
.span8{width:620px;}
.span7{width:540px;}
.span6{width:460px;}
.span5{width:380px;}
.span4{width:300px;}
.span3{width:220px;}
.span2{width:140px;}
.span1{width:60px;}
.span_frame12{width:938px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame11{width:858px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame10{width:778px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame9{width:698px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame8{width:618px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame7{width:538px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame6{width:458px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame5{width:378px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame4{width:298px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame3{width:218px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame2{width:138px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame1{width:58px;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.span_frame_offset{margin-top:-10px;margin-left:2px;}
.offset12{margin-left:980px;}
.offset11{margin-left:900px;}
.offset10{margin-left:820px;}
.offset9{margin-left:740px;}
.offset8{margin-left:660px;}
.offset7{margin-left:580px;}
.offset6{margin-left:500px;}
.offset5{margin-left:420px;}
.offset4{margin-left:340px;}
.offset3{margin-left:260px;}
.offset2{margin-left:180px;}
.offset1{margin-left:100px;}
[class*="span"].hide,.row-fluid [class*="span"].hide{display:none;}
[class*="span"].pull-right,.row-fluid [class*="span"].pull-right{float:right;}
.container{margin-right:auto;margin-left:auto;*zoom:1;}.container:before,.container:after{display:table;content:"";line-height:0;}
.container:after{clear:both;}
.container-fluid{padding-right:20px;padding-left:20px;*zoom:1;}.container-fluid:before,.container-fluid:after{display:table;content:"";line-height:0;}
.container-fluid:after{clear:both;}
p{margin:0 0 10px;}
.lead{margin-bottom:20px;font-size:21px;font-weight:200;line-height:30px;}
small{font-size:85%;}
strong{font-weight:bold;}
em{font-style:italic;}
cite{font-style:normal;}
.muted{color:#dfdfdf;}
h1,h2,h3,h4,h5,h6{margin:10px 0;font-family:inherit;font-weight:300;line-height:20px;color:#080808;text-rendering:optimizelegibility;}h1 small,h2 small,h3 small,h4 small,h5 small,h6 small{font-weight:normal;line-height:1;color:#dfdfdf;}
h1,h2,h3{line-height:40px;}
h1{font-size:38.5px;}
h2{font-size:31.5px;}
h3{font-size:24.5px;}
h4{font-size:17.5px;}
h5{font-size:14px;}
h6{font-size:11.9px;}
h1 small{font-size:24.5px;}
h2 small{font-size:17.5px;}
h3 small{font-size:14px;}
h4 small{font-size:14px;}
.page-header{padding-bottom:9px;margin:20px 0 30px;border-bottom:1px solid #eeeeee;}
ul,ol{padding:0;margin:0 0 10px 25px;}
ul ul,ul ol,ol ol,ol ul{margin-bottom:0;}
li{line-height:20px;}
ul.unstyled,ol.unstyled{margin-left:0;list-style:none;}
ul.inline,ol.inline{margin-left:0;list-style:none;}ul.inline >li,ol.inline >li{display:inline-block;padding-left:5px;padding-right:5px;}
dl{margin-bottom:20px;}
dt,dd{line-height:20px;}
dt{font-weight:bold;}
dd{margin-left:10px;}
hr{margin:20px 0;border:0;border-top:1px solid #eeeeee;border-bottom:1px solid #ffffff;}
abbr[title],abbr[data-original-title]{cursor:help;border-bottom:1px dotted #dfdfdf;}
abbr.initialism{font-size:90%;text-transform:uppercase;}
q:before,q:after,blockquote:before,blockquote:after{content:"";}
address{display:block;margin-bottom:20px;font-style:normal;line-height:20px;}
code,pre{padding:0 3px 2px;font-family:Monaco,Menlo,Consolas,"Courier New",monospace;font-size:12px;color:#999999;-webkit-border-radius:3px;-moz-border-radius:3px;border-radius:3px;}
code{padding:2px 4px;color:#d14;background-color:#f7f7f9;border:1px solid #e1e1e8;white-space:nowrap;}
pre{display:block;padding:9.5px;margin:0 0 10px;font-size:13px;line-height:20px;word-break:break-all;word-wrap:break-word;white-space:pre;white-space:pre-wrap;background-color:#f5f5f5;border:1px solid #ccc;border:1px solid rgba(0, 0, 0, 0.15);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}pre.prettyprint{margin-bottom:20px;}
pre code{padding:0;color:inherit;white-space:pre;white-space:pre-wrap;background-color:transparent;border:0;}
.pre-scrollable{max-height:340px;overflow-y:scroll;}
form{margin:0 0 20px;}
fieldset{padding:0;margin:0;border:0;}
legend{display:block;width:100%;padding:0;margin-bottom:20px;font-size:21px;line-height:40px;color:#999999;border:0;border-bottom:1px solid #e5e5e5;}legend small{font-size:15px;color:#dfdfdf;}
label,input,button,select,textarea{font-size:14px;font-weight:normal;line-height:20px;}
input,button,select,textarea{font-family:"Open Sans",Calibri,Candara,Arial,sans-serif;}
label{display:block;margin-bottom:5px;}
select,textarea,input[type="text"],input[type="password"],input[type="datetime"],input[type="datetime-local"],input[type="date"],input[type="month"],input[type="time"],input[type="week"],input[type="number"],input[type="email"],input[type="url"],input[type="search"],input[type="tel"],input[type="color"],.uneditable-input{display:inline-block;height:20px;padding:4px 6px;margin-bottom:10px;font-size:14px;line-height:20px;color:#bbbbbb;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;vertical-align:middle;}
input,textarea,.uneditable-input{width:206px;}
textarea{height:auto;}
textarea,input[type="text"],input[type="password"],input[type="datetime"],input[type="datetime-local"],input[type="date"],input[type="month"],input[type="time"],input[type="week"],input[type="number"],input[type="email"],input[type="url"],input[type="search"],input[type="tel"],input[type="color"],.uneditable-input{background-color:#ffffff;border:1px solid #bbbbbb;-webkit-box-shadow:inset 0 1px 1px rgba(0, 0, 0, 0.075);-moz-box-shadow:inset 0 1px 1px rgba(0, 0, 0, 0.075);box-shadow:inset 0 1px 1px rgba(0, 0, 0, 0.075);-webkit-transition:border linear .2s, box-shadow linear .2s;-moz-transition:border linear .2s, box-shadow linear .2s;-o-transition:border linear .2s, box-shadow linear .2s;transition:border linear .2s, box-shadow linear .2s;}textarea:focus,input[type="text"]:focus,input[type="password"]:focus,input[type="datetime"]:focus,input[type="datetime-local"]:focus,input[type="date"]:focus,input[type="month"]:focus,input[type="time"]:focus,input[type="week"]:focus,input[type="number"]:focus,input[type="email"]:focus,input[type="url"]:focus,input[type="search"]:focus,input[type="tel"]:focus,input[type="color"]:focus,.uneditable-input:focus{border-color:rgba(82, 168, 236, 0.8);outline:0;outline:thin dotted \9;-webkit-box-shadow:inset 0 1px 1px rgba(0,0,0,.075), 0 0 8px rgba(82,168,236,.6);-moz-box-shadow:inset 0 1px 1px rgba(0,0,0,.075), 0 0 8px rgba(82,168,236,.6);box-shadow:inset 0 1px 1px rgba(0,0,0,.075), 0 0 8px rgba(82,168,236,.6);}
input[type="radio"],input[type="checkbox"]{margin:4px 0 0;*margin-top:0;margin-top:1px \9;line-height:normal;}
input[type="file"],input[type="image"],input[type="submit"],input[type="reset"],input[type="button"],input[type="radio"],input[type="checkbox"]{width:auto;}
select,input[type="file"]{height:30px;*margin-top:4px;line-height:30px;}
select{width:220px;border:1px solid #bbbbbb;background-color:#ffffff;}
select[multiple],select[size]{height:auto;}
select:focus,input[type="file"]:focus,input[type="radio"]:focus,input[type="checkbox"]:focus{outline:thin dotted #333;outline:5px auto -webkit-focus-ring-color;outline-offset:-2px;}
.uneditable-input,.uneditable-textarea{color:#dfdfdf;background-color:#fcfcfc;border-color:#bbbbbb;-webkit-box-shadow:inset 0 1px 2px rgba(0, 0, 0, 0.025);-moz-box-shadow:inset 0 1px 2px rgba(0, 0, 0, 0.025);box-shadow:inset 0 1px 2px rgba(0, 0, 0, 0.025);cursor:not-allowed;}
.uneditable-input{overflow:hidden;white-space:nowrap;}
.uneditable-textarea{width:auto;height:auto;}
input:-moz-placeholder,textarea:-moz-placeholder{color:#bbbbbb;}
input:-ms-input-placeholder,textarea:-ms-input-placeholder{color:#bbbbbb;}
input::-webkit-input-placeholder,textarea::-webkit-input-placeholder{color:#bbbbbb;}
.radio,.checkbox{min-height:20px;padding-left:20px;}
.radio input[type="radio"],.checkbox input[type="checkbox"]{float:left;margin-left:-20px;}
.controls>.radio:first-child,.controls>.checkbox:first-child{padding-top:5px;}
.radio.inline,.checkbox.inline{display:inline-block;padding-top:5px;margin-bottom:0;vertical-align:middle;}
.radio.inline+.radio.inline,.checkbox.inline+.checkbox.inline{margin-left:10px;}
input[class*="span"],select[class*="span"],textarea[class*="span"],.uneditable-input[class*="span"],.row-fluid input[class*="span"],.row-fluid select[class*="span"],.row-fluid textarea[class*="span"],.row-fluid .uneditable-input[class*="span"]{float:none;margin-left:0;}
.input-append input[class*="span"],.input-append .uneditable-input[class*="span"],.input-prepend input[class*="span"],.input-prepend .uneditable-input[class*="span"],.row-fluid input[class*="span"],.row-fluid select[class*="span"],.row-fluid textarea[class*="span"],.row-fluid .uneditable-input[class*="span"],.row-fluid .input-prepend [class*="span"],.row-fluid .input-append [class*="span"]{display:inline-block;}
input,textarea,.uneditable-input{margin-left:0;}
.controls-row [class*="span"]+[class*="span"]{margin-left:20px;}
input.span12, textarea.span12, .uneditable-input.span12{width:926px;}
input.span11, textarea.span11, .uneditable-input.span11{width:846px;}
input.span10, textarea.span10, .uneditable-input.span10{width:766px;}
input.span9, textarea.span9, .uneditable-input.span9{width:686px;}
input.span8, textarea.span8, .uneditable-input.span8{width:606px;}
input.span7, textarea.span7, .uneditable-input.span7{width:526px;}
input.span6, textarea.span6, .uneditable-input.span6{width:446px;}
input.span5, textarea.span5, .uneditable-input.span5{width:366px;}
input.span4, textarea.span4, .uneditable-input.span4{width:286px;}
input.span3, textarea.span3, .uneditable-input.span3{width:206px;}
input.span2, textarea.span2, .uneditable-input.span2{width:126px;}
input.span1, textarea.span1, .uneditable-input.span1{width:46px;}
input[disabled],select[disabled],textarea[disabled],input[readonly],select[readonly],textarea[readonly]{cursor:not-allowed;background-color:#eeeeee;}
input[type="radio"][disabled],input[type="checkbox"][disabled],input[type="radio"][readonly],input[type="checkbox"][readonly]{background-color:transparent;}
input:focus:invalid,textarea:focus:invalid,select:focus:invalid{color:#b94a48;border-color:#ee5f5b;}input:focus:invalid:focus,textarea:focus:invalid:focus,select:focus:invalid:focus{border-color:#e9322d;-webkit-box-shadow:0 0 6px #f8b9b7;-moz-box-shadow:0 0 6px #f8b9b7;box-shadow:0 0 6px #f8b9b7;}
.form-actions{padding:19px 20px 20px;margin-top:20px;margin-bottom:20px;background-color:#f5f5f5;border-top:1px solid #e5e5e5;*zoom:1;}.form-actions:before,.form-actions:after{display:table;content:"";line-height:0;}
.form-actions:after{clear:both;}
.help-block,.help-inline{color:#7b7b7b;}
.help-block{display:block;margin-bottom:10px;}
.help-inline{display:inline-block;*display:inline;*zoom:1;vertical-align:middle;padding-left:5px;}
input.search-query{padding-right:14px;padding-right:4px \9;padding-left:14px;padding-left:4px \9;margin-bottom:0;-webkit-border-radius:15px;-moz-border-radius:15px;border-radius:15px;}
legend+.control-group{margin-top:20px;-webkit-margin-top-collapse:separate;}
[class^="icon-"],[class*=" icon-"]{display:inline-block;width:14px;height:14px;*margin-right:.3em;line-height:14px;vertical-align:text-top;background-image:url("../img/glyphicons-halflings.png");background-position:14px 14px;background-repeat:no-repeat;margin-top:1px;}
.dropup,.dropdown{position:relative;}
.dropdown-toggle{*margin-bottom:-3px;}
.dropdown-toggle:active,.open .dropdown-toggle{outline:0;}
.caret{display:inline-block;width:0;height:0;vertical-align:top;border-top:4px solid #000000;border-right:4px solid transparent;border-left:4px solid transparent;content:"";}
.open{*z-index:1000;}.open >.dropdown-menu{display:block;}
.pull-right>.dropdown-menu{right:0;left:auto;}
.typeahead{z-index:1051;margin-top:2px;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
button.close{padding:0;cursor:pointer;background:transparent;border:0;-webkit-appearance:none;}
.btn{display:inline-block;*display:inline;*zoom:1;padding:4px 12px;margin-bottom:0;font-size:14px;line-height:20px;text-align:center;vertical-align:middle;cursor:pointer;color:#999999;text-shadow:0 1px 1px rgba(255, 255, 255, 0.75);background-color:#dfdfdf;background-image:-moz-linear-gradient(top, #eeeeee, #c8c8c8);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#eeeeee), to(#c8c8c8));background-image:-webkit-linear-gradient(top, #eeeeee, #c8c8c8);background-image:-o-linear-gradient(top, #eeeeee, #c8c8c8);background-image:linear-gradient(to bottom, #eeeeee, #c8c8c8);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ffeeeeee', endColorstr='#ffc8c8c8', GradientType=0);border-color:#c8c8c8 #c8c8c8 #a2a2a2;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#c8c8c8;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);border:1px solid #bbbbbb;*border:0;border-bottom-color:#a2a2a2;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;*margin-left:.3em;-webkit-box-shadow:inset 0 1px 0 rgba(255,255,255,.2), 0 1px 2px rgba(0,0,0,.05);-moz-box-shadow:inset 0 1px 0 rgba(255,255,255,.2), 0 1px 2px rgba(0,0,0,.05);box-shadow:inset 0 1px 0 rgba(255,255,255,.2), 0 1px 2px rgba(0,0,0,.05);}.btn:hover,.btn:active,.btn.active,.btn.disabled,.btn[disabled]{color:#999999;background-color:#c8c8c8;*background-color:#bbbbbb;}
.btn:active,.btn.active{background-color:#aeaeae \9;}
.btn:first-child{*margin-left:0;}
.btn:hover{color:#999999;text-decoration:none;background-position:0 -15px;-webkit-transition:background-position 0.1s linear;-moz-transition:background-position 0.1s linear;-o-transition:background-position 0.1s linear;transition:background-position 0.1s linear;}
.btn:focus{outline:thin dotted #333;outline:5px auto -webkit-focus-ring-color;outline-offset:-2px;}
.btn.active,.btn:active{background-image:none;outline:0;-webkit-box-shadow:inset 0 2px 4px rgba(0,0,0,.15), 0 1px 2px rgba(0,0,0,.05);-moz-box-shadow:inset 0 2px 4px rgba(0,0,0,.15), 0 1px 2px rgba(0,0,0,.05);box-shadow:inset 0 2px 4px rgba(0,0,0,.15), 0 1px 2px rgba(0,0,0,.05);}
.btn.disabled,.btn[disabled]{cursor:default;background-image:none;opacity:0.65;filter:alpha(opacity=65);-webkit-box-shadow:none;-moz-box-shadow:none;box-shadow:none;}
.btn-large{padding:22px 30px;font-size:17.5px;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.btn-large [class^="icon-"],.btn-large [class*=" icon-"]{margin-top:4px;}
.btn-medium{padding:14px 16px;font-size:16px;-webkit-border-radius:4px;-moz-border-radius:4px;border-radius:4px;}
.btn-medium [class^="icon-"],.btn-medium [class*=" icon-"]{margin-top:4px;}
.btn-small{padding:2px 10px;font-size:11.9px;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.btn-small [class^="icon-"],.btn-small [class*=" icon-"]{margin-top:0;}
.btn-mini [class^="icon-"],.btn-mini [class*=" icon-"]{margin-top:-1px;}
.btn-mini{padding:2px 6px;font-size:10.5px;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.btn-block{display:block;width:100%;padding-left:0;padding-right:0;-webkit-box-sizing:border-box;-moz-box-sizing:border-box;box-sizing:border-box;}
.btn-block+.btn-block{margin-top:5px;}
input[type="submit"].btn-block,input[type="reset"].btn-block,input[type="button"].btn-block{width:100%;}
.btn-primary.active,.btn-warning.active,.btn-danger.active,.btn-success.active,.btn-info.active,.btn-inverse.active{color:rgba(255, 255, 255, 0.75);}
.btn{border-color:#c5c5c5;border-color:rgba(0, 0, 0, 0.15) rgba(0, 0, 0, 0.15) rgba(0, 0, 0, 0.25);}
.btn-primary{color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.25);background-color:#0f82f5;background-image:-moz-linear-gradient(top, #1a8cff, #0072e6);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#1a8cff), to(#0072e6));background-image:-webkit-linear-gradient(top, #1a8cff, #0072e6);background-image:-o-linear-gradient(top, #1a8cff, #0072e6);background-image:linear-gradient(to bottom, #1a8cff, #0072e6);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ff1a8cff', endColorstr='#ff0072e6', GradientType=0);border-color:#0072e6 #0072e6 #004c99;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#0072e6;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);}.btn-primary:hover,.btn-primary:active,.btn-primary.active,.btn-primary.disabled,.btn-primary[disabled]{color:#ffffff;background-color:#0072e6;*background-color:#0066cc;}
.btn-primary:active,.btn-primary.active{background-color:#0059b3 \9;}
.btn-warning{color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.25);background-color:#fe781e;background-image:-moz-linear-gradient(top, #ff8432, #fe6600);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#ff8432), to(#fe6600));background-image:-webkit-linear-gradient(top, #ff8432, #fe6600);background-image:-o-linear-gradient(top, #ff8432, #fe6600);background-image:linear-gradient(to bottom, #ff8432, #fe6600);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ffff8432', endColorstr='#fffe6600', GradientType=0);border-color:#fe6600 #fe6600 #b14700;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#fe6600;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);}.btn-warning:hover,.btn-warning:active,.btn-warning.active,.btn-warning.disabled,.btn-warning[disabled]{color:#ffffff;background-color:#fe6600;*background-color:#e45c00;}
.btn-warning:active,.btn-warning.active{background-color:#cb5200 \9;}
.btn-danger{color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.25);background-color:#f50f43;background-image:-moz-linear-gradient(top, #ff1a4d, #e60033);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#ff1a4d), to(#e60033));background-image:-webkit-linear-gradient(top, #ff1a4d, #e60033);background-image:-o-linear-gradient(top, #ff1a4d, #e60033);background-image:linear-gradient(to bottom, #ff1a4d, #e60033);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ffff1a4d', endColorstr='#ffe60033', GradientType=0);border-color:#e60033 #e60033 #990022;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#e60033;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);}.btn-danger:hover,.btn-danger:active,.btn-danger.active,.btn-danger.disabled,.btn-danger[disabled]{color:#ffffff;background-color:#e60033;*background-color:#cc002e;}
.btn-danger:active,.btn-danger.active{background-color:#b30028 \9;}
.btn-success{color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.25);background-color:#41bb19;background-image:-moz-linear-gradient(top, #47cd1b, #379f15);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#47cd1b), to(#379f15));background-image:-webkit-linear-gradient(top, #47cd1b, #379f15);background-image:-o-linear-gradient(top, #47cd1b, #379f15);background-image:linear-gradient(to bottom, #47cd1b, #379f15);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ff47cd1b', endColorstr='#ff379f15', GradientType=0);border-color:#379f15 #379f15 #205c0c;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#379f15;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);}.btn-success:hover,.btn-success:active,.btn-success.active,.btn-success.disabled,.btn-success[disabled]{color:#ffffff;background-color:#379f15;*background-color:#2f8912;}
.btn-success:active,.btn-success.active{background-color:#28720f \9;}
.btn-info{color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.25);background-color:#9b59bb;background-image:-moz-linear-gradient(top, #a466c2, #8d46b0);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#a466c2), to(#8d46b0));background-image:-webkit-linear-gradient(top, #a466c2, #8d46b0);background-image:-o-linear-gradient(top, #a466c2, #8d46b0);background-image:linear-gradient(to bottom, #a466c2, #8d46b0);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ffa466c2', endColorstr='#ff8d46b0', GradientType=0);border-color:#8d46b0 #8d46b0 #613079;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#8d46b0;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);}.btn-info:hover,.btn-info:active,.btn-info.active,.btn-info.disabled,.btn-info[disabled]{color:#ffffff;background-color:#8d46b0;*background-color:#7e3f9d;}
.btn-info:active,.btn-info.active{background-color:#6f378b \9;}
.btn-inverse{color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.25);background-color:#080808;background-image:-moz-linear-gradient(top, #0d0d0d, #000000);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#0d0d0d), to(#000000));background-image:-webkit-linear-gradient(top, #0d0d0d, #000000);background-image:-o-linear-gradient(top, #0d0d0d, #000000);background-image:linear-gradient(to bottom, #0d0d0d, #000000);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ff0d0d0d', endColorstr='#ff000000', GradientType=0);border-color:#000000 #000000 #000000;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#000000;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);}.btn-inverse:hover,.btn-inverse:active,.btn-inverse.active,.btn-inverse.disabled,.btn-inverse[disabled]{color:#ffffff;background-color:#000000;*background-color:#000000;}
.btn-inverse:active,.btn-inverse.active{background-color:#000000 \9;}
button.btn,input[type="submit"].btn{*padding-top:3px;*padding-bottom:3px;}button.btn::-moz-focus-inner,input[type="submit"].btn::-moz-focus-inner{padding:0;border:0;}
button.btn.btn-large,input[type="submit"].btn.btn-large{*padding-top:7px;*padding-bottom:7px;}
button.btn.btn-small,input[type="submit"].btn.btn-small{*padding-top:3px;*padding-bottom:3px;}.btn.disabled,
button.btn.btn-mini,input[type="submit"].btn.btn-mini{*padding-top:1px;*padding-bottom:1px;}
.btn-link,.btn-link:active,.btn-link[disabled]{background-color:transparent;background-image:none;-webkit-box-shadow:none;-moz-box-shadow:none;box-shadow:none;}
.btn-link{border-color:transparent;cursor:pointer;color:#007fff;-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;}
.btn-link:hover{color:#0066cc;text-decoration:underline;background-color:transparent;}
.btn-link[disabled]:hover{color:#999999;text-decoration:none;}
.btn-group{position:relative;display:inline-block;*display:inline;*zoom:1;font-size:0;vertical-align:middle;white-space:nowrap;*margin-left:.3em;}.btn-group:first-child{*margin-left:0;}
.btn-group+.btn-group{margin-left:5px;}
.btn-toolbar{font-size:0;margin-top:10px;margin-bottom:10px;}.btn-toolbar>.btn+.btn,.btn-toolbar>.btn-group+.btn,.btn-toolbar>.btn+.btn-group{margin-left:5px;}
.btn .caret{margin-top:8px;margin-left:0;}
.btn-mini .caret,.btn-small .caret,.btn-large .caret{margin-top:6px;}
.btn-large .caret{border-left-width:5px;border-right-width:5px;border-top-width:5px;}
.dropup .btn-large .caret{border-bottom-width:5px;}
.btn-primary .caret,.btn-warning .caret,.btn-danger .caret,.btn-info .caret,.btn-success .caret,.btn-inverse .caret{border-top-color:#ffffff;border-bottom-color:#ffffff;}
.btn-group-vertical{display:inline-block;*display:inline;*zoom:1;}
.btn-group-vertical>.btn{display:block;float:none;max-width:100%;-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;}
.btn-group-vertical>.btn+.btn{margin-left:0;margin-top:-1px;}
.btn-group-vertical>.btn:first-child{-webkit-border-radius:0px 0px 0 0;-moz-border-radius:0px 0px 0 0;border-radius:0px 0px 0 0;}
.btn-group-vertical>.btn:last-child{-webkit-border-radius:0 0 0px 0px;-moz-border-radius:0 0 0px 0px;border-radius:0 0 0px 0px;}
.btn-group-vertical>.btn-large:first-child{-webkit-border-radius:0px 0px 0 0;-moz-border-radius:0px 0px 0 0;border-radius:0px 0px 0 0;}
.btn-group-vertical>.btn-large:last-child{-webkit-border-radius:0 0 0px 0px;-moz-border-radius:0 0 0px 0px;border-radius:0 0 0px 0px;}
.alert{padding:8px 35px 8px 14px;margin-bottom:20px;text-shadow:0 1px 0 rgba(255, 255, 255, 0.5);background-color:#ff7518;border:1px solid transparent;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.alert,.alert h4{color:#ffffff;}
.alert h4{margin:0;}
.alert .close{position:relative;top:-2px;right:-21px;line-height:20px;}
.alert-success{background-color:#3fb618;border-color:transparent;color:#ffffff;}
.alert-success h4{color:#ffffff;}
.alert-danger,.alert-error{background-color:#ff0039;border-color:transparent;color:#ffffff;}
.alert-danger h4,.alert-error h4{color:#ffffff;}
.alert-info{background-color:#9954bb;border-color:transparent;color:#ffffff;}
.alert-info h4{color:#ffffff;}
.alert-block{padding-top:14px;padding-bottom:14px;}
.alert-block>p,.alert-block>ul{margin-bottom:0;}
.alert-block p+p{margin-top:5px;}
.nav{margin-left:0;margin-bottom:20px;list-style:none;}
.nav>li>a{display:block;}
.nav>li>a:hover{text-decoration:none;background-color:#eeeeee;}
.nav>li>a>img{max-width:none;}
.nav>.pull-right{float:right;}
.nav-header{display:block;padding:3px 15px;font-size:11px;font-weight:bold;line-height:20px;color:#dfdfdf;text-shadow:0 1px 0 rgba(255, 255, 255, 0.5);text-transform:uppercase;}
.nav li+.nav-header{margin-top:9px;}
.nav-list{padding-left:15px;padding-right:15px;margin-bottom:0;}
.nav-list>li>a,.nav-list .nav-header{margin-left:-15px;margin-right:-15px;text-shadow:0 1px 0 rgba(255, 255, 255, 0.5);}
.nav-list>li>a{padding:3px 15px;}
.nav-list>.active>a,.nav-list>.active>a:hover{color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.2);background-color:#007fff;}
.nav-list [class^="icon-"],.nav-list [class*=" icon-"]{margin-right:2px;}
.nav-list .divider{*width:100%;height:1px;margin:9px 1px;*margin:-5px 0 5px;overflow:hidden;background-color:#e5e5e5;border-bottom:1px solid #ffffff;}
.nav-tabs,.nav-pills{*zoom:1;}.nav-tabs:before,.nav-pills:before,.nav-tabs:after,.nav-pills:after{display:table;content:"";line-height:0;}
.nav-tabs:after,.nav-pills:after{clear:both;}
.nav-tabs>li,.nav-pills>li{float:left;}
.nav-tabs>li>a,.nav-pills>li>a{padding-right:12px;padding-left:12px;margin-right:2px;line-height:14px;}
.nav-tabs{border-bottom:1px solid #ddd;}
.nav-tabs>li{margin-bottom:-1px;}
.nav-tabs>li>a{padding-top:8px;padding-bottom:8px;line-height:20px;border:1px solid transparent;-webkit-border-radius:4px 4px 0 0;-moz-border-radius:4px 4px 0 0;border-radius:4px 4px 0 0;}.nav-tabs>li>a:hover{border-color:#eeeeee #eeeeee #dddddd;}
.nav-tabs>.active>a,.nav-tabs>.active>a:hover{color:#bbbbbb;background-color:#ffffff;border:1px solid #ddd;border-bottom-color:transparent;cursor:default;}
.nav-pills>li>a{padding-top:8px;padding-bottom:8px;margin-top:2px;margin-bottom:2px;-webkit-border-radius:5px;-moz-border-radius:5px;border-radius:5px;}
.nav-pills>.active>a,.nav-pills>.active>a:hover{color:#ffffff;background-color:#007fff;}
.nav-stacked>li{float:none;}
.nav-stacked>li>a{margin-right:0;}
.nav-tabs.nav-stacked{border-bottom:0;}
.nav-tabs.nav-stacked>li>a{border:1px solid #ddd;-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;}
.nav-tabs.nav-stacked>li:first-child>a{-webkit-border-top-right-radius:4px;-moz-border-radius-topright:4px;border-top-right-radius:4px;-webkit-border-top-left-radius:4px;-moz-border-radius-topleft:4px;border-top-left-radius:4px;}
.nav-tabs.nav-stacked>li:last-child>a{-webkit-border-bottom-right-radius:4px;-moz-border-radius-bottomright:4px;border-bottom-right-radius:4px;-webkit-border-bottom-left-radius:4px;-moz-border-radius-bottomleft:4px;border-bottom-left-radius:4px;}
.nav-tabs.nav-stacked>li>a:hover{border-color:#ddd;z-index:2;}
.nav-pills.nav-stacked>li>a{margin-bottom:3px;}
.nav-pills.nav-stacked>li:last-child>a{margin-bottom:1px;}
.nav-tabs .dropdown-menu{-webkit-border-radius:0 0 6px 6px;-moz-border-radius:0 0 6px 6px;border-radius:0 0 6px 6px;}
.nav-pills .dropdown-menu{-webkit-border-radius:6px;-moz-border-radius:6px;border-radius:6px;}
.nav .dropdown-toggle .caret{border-top-color:#007fff;border-bottom-color:#007fff;margin-top:6px;}
.nav .dropdown-toggle:hover .caret{border-top-color:#0066cc;border-bottom-color:#0066cc;}
.nav-tabs .dropdown-toggle .caret{margin-top:8px;}
.nav .active .dropdown-toggle .caret{border-top-color:#fff;border-bottom-color:#fff;}
.nav-tabs .active .dropdown-toggle .caret{border-top-color:#bbbbbb;border-bottom-color:#bbbbbb;}
.nav>.dropdown.active>a:hover{cursor:pointer;}
.nav-tabs .open .dropdown-toggle,.nav-pills .open .dropdown-toggle,.nav>li.dropdown.open.active>a:hover{color:#ffffff;background-color:#dfdfdf;border-color:#dfdfdf;}
.nav li.dropdown.open .caret,.nav li.dropdown.open.active .caret,.nav li.dropdown.open a:hover .caret{border-top-color:#ffffff;border-bottom-color:#ffffff;opacity:1;filter:alpha(opacity=100);}
.nav>.disabled>a{color:#dfdfdf;}
.nav>.disabled>a:hover{text-decoration:none;background-color:transparent;cursor:default;}
.navbar{overflow:visible;margin-bottom:20px;*position:relative;*z-index:2;}
.navbar-inner{min-height:50px;padding-left:20px;padding-right:20px;background-color:#080808;background-image:-moz-linear-gradient(top, #080808, #080808);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#080808), to(#080808));background-image:-webkit-linear-gradient(top, #080808, #080808);background-image:-o-linear-gradient(top, #080808, #080808);background-image:linear-gradient(to bottom, #080808, #080808);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ff080808', endColorstr='#ff080808', GradientType=0);border:1px solid transparent;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;-webkit-box-shadow:0 1px 4px rgba(0, 0, 0, 0.065);-moz-box-shadow:0 1px 4px rgba(0, 0, 0, 0.065);box-shadow:0 1px 4px rgba(0, 0, 0, 0.065);*zoom:1;}.navbar-inner:before,.navbar-inner:after{display:table;content:"";line-height:0;}
.navbar-inner:after{clear:both;}
.navbar .container{width:auto;}
.nav-collapse.collapse{height:auto;overflow:visible;}
.navbar .brand{float:left;display:block;padding:15px 20px 15px;margin-left:-20px;font-size:20px;font-weight:200;color:#ffffff;text-shadow:0 1px 0 #080808;}.navbar .brand:hover{text-decoration:none;}
.navbar-text{margin-bottom:0;line-height:50px;color:#ffffff;}
.navbar-link{color:#ffffff;}.navbar-link:hover{color:#bbbbbb;}
.navbar .divider-vertical{height:50px;margin:0 9px;border-left:1px solid #080808;border-right:1px solid #080808;}
.navbar .btn,.navbar .btn-group{margin-top:10px;}
.navbar .btn-group .btn,.navbar .input-prepend .btn,.navbar .input-append .btn{margin-top:0;}
.navbar-form{margin-bottom:0;*zoom:1;}.navbar-form:before,.navbar-form:after{display:table;content:"";line-height:0;}
.navbar-form:after{clear:both;}
.navbar-form input,.navbar-form select,.navbar-form .radio,.navbar-form .checkbox{margin-top:10px;}
.navbar-form input,.navbar-form select,.navbar-form .btn{display:inline-block;margin-bottom:0;}
.navbar-form input[type="image"],.navbar-form input[type="checkbox"],.navbar-form input[type="radio"]{margin-top:3px;}
.navbar-form .input-append,.navbar-form .input-prepend{margin-top:5px;white-space:nowrap;}.navbar-form .input-append input,.navbar-form .input-prepend input{margin-top:0;}
.navbar-search{position:relative;float:left;margin-top:10px;margin-bottom:0;}.navbar-search .search-query{margin-bottom:0;padding:4px 14px;font-family:"Open Sans",Calibri,Candara,Arial,sans-serif;font-size:13px;font-weight:normal;line-height:1;-webkit-border-radius:15px;-moz-border-radius:15px;border-radius:15px;}
.navbar-static-top{position:static;margin-bottom:0;}.navbar-static-top .navbar-inner{-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;}
.navbar-fixed-top,.navbar-fixed-bottom{position:fixed;right:0;left:0;z-index:1030;margin-bottom:0;}
.navbar-fixed-top .navbar-inner,.navbar-static-top .navbar-inner{border-width:0 0 1px;}
.navbar-fixed-bottom .navbar-inner{border-width:1px 0 0;}
.navbar-fixed-top .navbar-inner,.navbar-fixed-bottom .navbar-inner{padding-left:0;padding-right:0;-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;}
.navbar-static-top .container,.navbar-fixed-top .container,.navbar-fixed-bottom .container{width:940px;}
.navbar-fixed-top{top:0;}
.navbar-fixed-top .navbar-inner,.navbar-static-top .navbar-inner{-webkit-box-shadow:0 1px 10px rgba(0,0,0,.1);-moz-box-shadow:0 1px 10px rgba(0,0,0,.1);box-shadow:0 1px 10px rgba(0,0,0,.1);}
.navbar-fixed-bottom{bottom:0;}.navbar-fixed-bottom .navbar-inner{-webkit-box-shadow:0 -1px 10px rgba(0,0,0,.1);-moz-box-shadow:0 -1px 10px rgba(0,0,0,.1);box-shadow:0 -1px 10px rgba(0,0,0,.1);}
.navbar .nav{position:relative;left:0;display:block;float:left;margin:0 10px 0 0;}
.navbar .nav.pull-right{float:right;margin-right:0;}
.navbar .nav>li{float:left;}
.navbar .nav>li>a{float:none;padding:15px 15px 15px;color:#ffffff;text-decoration:none;text-shadow:0 1px 0 #080808;}
.navbar .nav .dropdown-toggle .caret{margin-top:8px;}
.navbar .nav>li>a:focus,.navbar .nav>li>a:hover{background-color:rgba(0, 0, 0, 0.05);color:#bbbbbb;text-decoration:none;}
.navbar .nav>.active>a,.navbar .nav>.active>a:hover,.navbar .nav>.active>a:focus{color:#ffffff;text-decoration:none;background-color:transparent;-webkit-box-shadow:inset 0 3px 8px rgba(0, 0, 0, 0.125);-moz-box-shadow:inset 0 3px 8px rgba(0, 0, 0, 0.125);box-shadow:inset 0 3px 8px rgba(0, 0, 0, 0.125);}
.navbar .btn-navbar{display:none;float:right;padding:7px 10px;margin-left:5px;margin-right:5px;color:#ffffff;text-shadow:0 -1px 0 rgba(0, 0, 0, 0.25);background-color:#000000;background-image:-moz-linear-gradient(top, #000000, #000000);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#000000), to(#000000));background-image:-webkit-linear-gradient(top, #000000, #000000);background-image:-o-linear-gradient(top, #000000, #000000);background-image:linear-gradient(to bottom, #000000, #000000);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#ff000000', endColorstr='#ff000000', GradientType=0);border-color:#000000 #000000 #000000;border-color:rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);*background-color:#000000;filter:progid:DXImageTransform.Microsoft.gradient(enabled = false);-webkit-box-shadow:inset 0 1px 0 rgba(255,255,255,.1), 0 1px 0 rgba(255,255,255,.075);-moz-box-shadow:inset 0 1px 0 rgba(255,255,255,.1), 0 1px 0 rgba(255,255,255,.075);box-shadow:inset 0 1px 0 rgba(255,255,255,.1), 0 1px 0 rgba(255,255,255,.075);}.navbar .btn-navbar:hover,.navbar .btn-navbar:active,.navbar .btn-navbar.active,.navbar .btn-navbar.disabled,.navbar .btn-navbar[disabled]{color:#ffffff;background-color:#000000;*background-color:#000000;}
.navbar .btn-navbar:active,.navbar .btn-navbar.active{background-color:#000000 \9;}
.navbar .btn-navbar .icon-bar{display:block;width:18px;height:2px;background-color:#f5f5f5;-webkit-border-radius:1px;-moz-border-radius:1px;border-radius:1px;-webkit-box-shadow:0 1px 0 rgba(0, 0, 0, 0.25);-moz-box-shadow:0 1px 0 rgba(0, 0, 0, 0.25);box-shadow:0 1px 0 rgba(0, 0, 0, 0.25);}
.btn-navbar .icon-bar+.icon-bar{margin-top:3px;}
.navbar .nav>li>.dropdown-menu:before{content:'';display:inline-block;border-left:7px solid transparent;border-right:7px solid transparent;border-bottom:7px solid #ccc;border-bottom-color:rgba(0, 0, 0, 0.2);position:absolute;top:-7px;left:9px;}
.navbar .nav>li>.dropdown-menu:after{content:'';display:inline-block;border-left:6px solid transparent;border-right:6px solid transparent;border-bottom:6px solid #ffffff;position:absolute;top:-6px;left:10px;}
.navbar-fixed-bottom .nav>li>.dropdown-menu:before{border-top:7px solid #ccc;border-top-color:rgba(0, 0, 0, 0.2);border-bottom:0;bottom:-7px;top:auto;}
.navbar-fixed-bottom .nav>li>.dropdown-menu:after{border-top:6px solid #ffffff;border-bottom:0;bottom:-6px;top:auto;}
.navbar .nav li.dropdown>a:hover .caret{border-top-color:#ffffff;border-bottom-color:#ffffff;}
.navbar .nav li.dropdown.open>.dropdown-toggle,.navbar .nav li.dropdown.active>.dropdown-toggle,.navbar .nav li.dropdown.open.active>.dropdown-toggle{background-color:transparent;color:#ffffff;}
.navbar .nav li.dropdown>.dropdown-toggle .caret{border-top-color:#ffffff;border-bottom-color:#ffffff;}
.navbar .nav li.dropdown.open>.dropdown-toggle .caret,.navbar .nav li.dropdown.active>.dropdown-toggle .caret,.navbar .nav li.dropdown.open.active>.dropdown-toggle .caret{border-top-color:#ffffff;border-bottom-color:#ffffff;}
.navbar .pull-right>li>.dropdown-menu,.navbar .nav>li>.dropdown-menu.pull-right{left:auto;right:0;}.navbar .pull-right>li>.dropdown-menu:before,.navbar .nav>li>.dropdown-menu.pull-right:before{left:auto;right:12px;}
.navbar .pull-right>li>.dropdown-menu:after,.navbar .nav>li>.dropdown-menu.pull-right:after{left:auto;right:13px;}
.navbar .pull-right>li>.dropdown-menu .dropdown-menu,.navbar .nav>li>.dropdown-menu.pull-right .dropdown-menu{left:auto;right:100%;margin-left:0;margin-right:-1px;-webkit-border-radius:6px 0 6px 6px;-moz-border-radius:6px 0 6px 6px;border-radius:6px 0 6px 6px;}
.breadcrumb{padding:8px 15px;margin:0 0 20px;list-style:none;background-color:#f5f5f5;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}.breadcrumb>li{display:inline-block;*display:inline;*zoom:1;text-shadow:0 1px 0 #ffffff;}.breadcrumb>li>.divider{padding:0 5px;color:#ccc;}
.breadcrumb>.active{color:#dfdfdf;}
.pagination{margin:20px 0;}
.pagination ul{display:inline-block;*display:inline;*zoom:1;margin-left:0;margin-bottom:0;-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;-webkit-box-shadow:0 1px 2px rgba(0, 0, 0, 0.05);-moz-box-shadow:0 1px 2px rgba(0, 0, 0, 0.05);box-shadow:0 1px 2px rgba(0, 0, 0, 0.05);}
.pagination ul>li{display:inline;}
.pagination ul>li>a,.pagination ul>li>span{float:left;padding:4px 12px;line-height:20px;text-decoration:none;background-color:#dfdfdf;border:1px solid transparent;border-left-width:0;}
.pagination ul>li>a:hover,.pagination ul>.active>a,.pagination ul>.active>span{background-color:#007fff;}
.pagination ul>.active>a,.pagination ul>.active>span{color:#dfdfdf;cursor:default;}
.pagination ul>.disabled>span,.pagination ul>.disabled>a,.pagination ul>.disabled>a:hover{color:#dfdfdf;background-color:transparent;cursor:default;}
.pagination ul>li:first-child>a,.pagination ul>li:first-child>span{border-left-width:1px;-webkit-border-top-left-radius:0px;-moz-border-radius-topleft:0px;border-top-left-radius:0px;-webkit-border-bottom-left-radius:0px;-moz-border-radius-bottomleft:0px;border-bottom-left-radius:0px;}
.pagination ul>li:last-child>a,.pagination ul>li:last-child>span{-webkit-border-top-right-radius:0px;-moz-border-radius-topright:0px;border-top-right-radius:0px;-webkit-border-bottom-right-radius:0px;-moz-border-radius-bottomright:0px;border-bottom-right-radius:0px;}
.pagination-centered{text-align:center;}
.pagination-right{text-align:right;}
.pagination-large ul>li>a,.pagination-large ul>li>span{padding:22px 30px;font-size:17.5px;}
.pagination-large ul>li:first-child>a,.pagination-large ul>li:first-child>span{-webkit-border-top-left-radius:0px;-moz-border-radius-topleft:0px;border-top-left-radius:0px;-webkit-border-bottom-left-radius:0px;-moz-border-radius-bottomleft:0px;border-bottom-left-radius:0px;}
.pagination-large ul>li:last-child>a,.pagination-large ul>li:last-child>span{-webkit-border-top-right-radius:0px;-moz-border-radius-topright:0px;border-top-right-radius:0px;-webkit-border-bottom-right-radius:0px;-moz-border-radius-bottomright:0px;border-bottom-right-radius:0px;}
.pagination-mini ul>li:first-child>a,.pagination-small ul>li:first-child>a,.pagination-mini ul>li:first-child>span,.pagination-small ul>li:first-child>span{-webkit-border-top-left-radius:0px;-moz-border-radius-topleft:0px;border-top-left-radius:0px;-webkit-border-bottom-left-radius:0px;-moz-border-radius-bottomleft:0px;border-bottom-left-radius:0px;}
.pagination-mini ul>li:last-child>a,.pagination-small ul>li:last-child>a,.pagination-mini ul>li:last-child>span,.pagination-small ul>li:last-child>span{-webkit-border-top-right-radius:0px;-moz-border-radius-topright:0px;border-top-right-radius:0px;-webkit-border-bottom-right-radius:0px;-moz-border-radius-bottomright:0px;border-bottom-right-radius:0px;}
.pagination-small ul>li>a,.pagination-small ul>li>span{padding:2px 10px;font-size:11.9px;}
.pagination-mini ul>li>a,.pagination-mini ul>li>span{padding:2px 6px;font-size:10.5px;}
@-webkit-keyframes progress-bar-stripes{from{background-position:40px 0;} to{background-position:0 0;}}@-moz-keyframes progress-bar-stripes{from{background-position:40px 0;} to{background-position:0 0;}}@-ms-keyframes progress-bar-stripes{from{background-position:40px 0;} to{background-position:0 0;}}@-o-keyframes progress-bar-stripes{from{background-position:0 0;} to{background-position:40px 0;}}@keyframes progress-bar-stripes{from{background-position:40px 0;} to{background-position:0 0;}}.progress{overflow:hidden;height:20px;margin-bottom:20px;background-color:#f7f7f7;background-image:-moz-linear-gradient(top, #f5f5f5, #f9f9f9);background-image:-webkit-gradient(linear, 0 0, 0 100%, from(#f5f5f5), to(#f9f9f9));background-image:-webkit-linear-gradient(top, #f5f5f5, #f9f9f9);background-image:-o-linear-gradient(top, #f5f5f5, #f9f9f9);background-image:linear-gradient(to bottom, #f5f5f5, #f9f9f9);background-repeat:repeat-x;filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#fff5f5f5', endColorstr='#fff9f9f9', GradientType=0);-webkit-box-shadow:inset 0 1px 2px rgba(0, 0, 0, 0.1);-moz-box-shadow:inset 0 1px 2px rgba(0, 0, 0, 0.1);box-shadow:inset 0 1px 2px rgba(0, 0, 0, 0.1);-webkit-border-radius:0px;-moz-border-radius:0px;border-radius:0px;}
.pull-right{float:right;}
.pull-left{float:left;}
.hide{display:none;}
.show{display:block;}
.invisible{visibility:hidden;}
.affix{position:fixed;}
body{font-weight:300;}
h1{font-size:50px;}
h2,h3{font-size:26px;}
h4{font-size:14px;}
h5,h6{font-size:11px;}
blockquote{padding:10px 15px;background-color:#eeeeee;border-left-color:#bbbbbb;}blockquote.pull-right{padding:10px 15px;border-right-color:#bbbbbb;}
blockquote small{color:#bbbbbb;}
.muted{color:#bbbbbb;}
.navbar .navbar-inner{background-image:none;-webkit-box-shadow:none;-moz-box-shadow:none;box-shadow:none;-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;}
.navbar .brand:hover{color:#bbbbbb;}
.navbar .nav>.active>a,.navbar .nav>.active>a:hover,.navbar .nav>.active>a:focus{-webkit-box-shadow:none;-moz-box-shadow:none;box-shadow:none;background-color:rgba(0, 0, 0, 0.05);}
.navbar .nav li.dropdown.open>.dropdown-toggle,.navbar .nav li.dropdown.active>.dropdown-toggle,.navbar .nav li.dropdown.open.active>.dropdown-toggle{color:#ffffff;}.navbar .nav li.dropdown.open>.dropdown-toggle:hover,.navbar .nav li.dropdown.active>.dropdown-toggle:hover,.navbar .nav li.dropdown.open.active>.dropdown-toggle:hover{color:#eeeeee;}
.navbar .navbar-search .search-query{line-height:normal;}
.navbar-inverse .brand,.navbar-inverse .nav>li>a{text-shadow:none;}
.navbar-inverse .brand:hover,.navbar-inverse .nav>.active>a,.navbar-inverse .nav>.active>a:hover,.navbar-inverse .nav>.active>a:focus{background-color:rgba(0, 0, 0, 0.05);-webkit-box-shadow:none;-moz-box-shadow:none;box-shadow:none;color:#ffffff;}
.navbar-inverse .navbar-search .search-query{color:#080808;}
.pager li>a,.pager li>span{background-color:#dfdfdf;border:none;-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;color:#080808;}.pager li>a:hover,.pager li>span:hover{background-color:#080808;color:#ffffff;}
.pager .disabled>a,.pager .disabled>a:hover,.pager .disabled>span{background-color:#eeeeee;color:#999999;}
.breadcrumb{background-color:#dfdfdf;}.breadcrumb li{text-shadow:none;}
.breadcrumb .divider,.breadcrumb .active{color:#080808;text-shadow:none;}
.btn{background-image:none;-webkit-box-shadow:none;-moz-box-shadow:none;box-shadow:none;border:none;-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;text-shadow:none;}.btn.disabled{box-shadow:inset 0 2px 4px rgba(0, 0, 0, 0.15), 0 1px 2px rgba(0, 0, 0, 0.05);}
.btn-group >.btn:first-child,.btn-group >.btn:last-child,.btn-group >.dropdown-toggle{-webkit-border-radius:0;-moz-border-radius:0;border-radius:0;}
.btn-group >.btn+.dropdown-toggle{-webkit-box-shadow:none;-moz-box-shadow:none;box-shadow:none;}
select,textarea,input[type="text"],input[type="password"],input[type="datetime"],input[type="datetime-local"],input[type="date"],input[type="month"],input[type="time"],input[type="week"],input[type="number"],input[type="email"],input[type="url"],input[type="search"],input[type="tel"],input[type="color"]{color:#080808;}
.control-group.warning .control-label,.control-group.warning .help-block,.control-group.warning .help-inline{color:#ff7518;}
.control-group.warning input,.control-group.warning select,.control-group.warning textarea{border-color:#ff7518;color:#080808;}
.control-group.error .control-label,.control-group.error .help-block,.control-group.error .help-inline{color:#ff0039;}
.control-group.error input,.control-group.error select,.control-group.error textarea{border-color:#ff0039;color:#080808;}
.control-group.success .control-label,.control-group.success .help-block,.control-group.success .help-inline{color:#3fb618;}
.control-group.success input,.control-group.success select,.control-group.success textarea{border-color:#3fb618;color:#080808;}
[class^="icon-"],[class*=" icon-"]{margin:0 2px;vertical-align:-2px;}
.pull-right{float:right;}
.pull-left{float:left;}
.hide{display:none;}
.show{display:block;}
.invisible{visibility:hidden;}
.affix{position:fixed;}


@@ css/min1.css.ep
.upload_file_container{
   width:400px;
   height:40px;
   position:relative;
   background(your img);
}

.upload_file_container input{
   width:400px;
   height:40px;
   position:absolute;
   left:0;
   top:0;
   cursor:pointer;
}

@@ double_arrow.png (base64)
iVBORw0KGgoAAAANSUhEUgAAACAAAAArCAYAAAAZvYo3AAAABHNCSVQICAgIfAhkiAAAAAlwSFlz
AAABHAAAARwB37PomgAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAASmSURB
VFiFxZdNbBtFGIZfe+M4jvdnkk0UW8SkShwndtxIUSLcSI0VuNCKazmklBap6pVDQEWowBGu7QEh
4MAJKnHkRwKpPVSqUAulGAkhpEaq1m12Y+9mduva3rXX8XKgtvLjOrGdmPc283277zOjndnvA/YR
y7IzhJDkfnm7RQhJsiwb2y/PfYAXXfF4PIFWATweT4AQcqVTAEEUxZOtmtc0NDR0EoDQNkAwGHxv
bGws1C5AKBR6MRgMXm4XwC0Iwqnjx4+3649oNApBEE4183luQBTF84lEYnZycrJtgFgshvn5+VlC
yBstAwiCcDaZTDK2bbcNUKlUkEwmewYHB8+1BEAImZuYmFiMRqPoBMC2bczMzODYsWMJQsjcgQF4
nl9NJpNspVJBuVxuG6BUKqFarWJpaUngeX71oACiKIrLU1NTKBaLHe9AsVjE9PQ0RFFcBkB25/Ts
nhgZGVldXFwc9Xg8ME0Ttm0jn8+/3tvbu++ttl35fH7Gtm2Ypom+vj4kEolRWZbfyWQyHzYDcA8M
DJwOh8MoFov1VSwsLJxxHOdMKwAul6u+AwAQDocxMDDwWiaT+QiA0xBgeHj4Qjwen+U4DqZpAgAY
hkE0Gm3Fuy6GYervEQQBsVhsNpvNvkUp/aohAMdxK+FwmKk9BAA8zyMej7cFAKC+AwAQDoeZVCq1
0hCA5/mXxsbGTgiCgO0AhylCCEKh0AlK6ZxhGH/sACCEvD05OclZlnUk5jVFIhHu4cOHq4ZhvLkd
QBRFcdnv9x/Z6mtiWRaDg4PL6XRaBLDZAwCBQOByJBJ5wbbtjs79QTU1NTWayWTeVRTl/R4AjCAI
r3q93iNffU1erxc8z59WFOWDnuHh4Qvj4+Pxbq2+pvHx8Til9HwPz/MrPp+PKZVKXTMHAJ/Px3Ac
t+Lu7+8f7arzNvn9/pCbUnrn/zB3HAebm5t3GMdxHrAsu8KyrK+bANlsVnv06NFFdz6f/1tRlLvd
NAcARVF+ffr06T9uAKCUXi8UCpVumRcKhYqu69eBZwWJYRhfS5L0Z7cAJElK6br+TR0AQJVSenNr
a+vIzbe2tqDr+k0AVQBgaoFCofC73+9fIYQ07WQ6VTqdTq+trZ0DYAE7a0JdVdVfjtIcAJ55GLXx
jqJU07RrmqbljtA8p2na1e1zOyoi0zTvyLJ8b2ho6JXt87Isw3EctCK3241gMLhjTpbl30zT3HHk
91TFhmF8XyqVXvZ6vS7gvxsrlUp9aVnWvVYA+vr6FgKBwCWXywUAKJVKTi6X+2533h4ATdM+lSTp
YiQSqReCHMfdsCzr21YAOI4zAFyqjSVJ+ktV1c925zVqTGxN025Vq9VW/JqqWq1C07RbAPb87xu2
Zk+ePPlkfX09c1gAjx8/ljc2Nj5uFGsIYJrmejabPbQjqarqXQDKgQEAQNf1L3Rd77hGo5Sauq5/
/rz4cwFyudxPsizf7xRAUZT7uVzu55YBAIBS+mMn7Xm5XAal9IdmOU0BVFW9KknSWrsAkiStqap6
rW0AAKau67fbBaCU3gbQ9DtimgUBwHGcBwCqlmVJrZj39vaKpmneKJfLarO8fwE+OfcEu9v11AAA
AABJRU5ErkJggg==


@@ refresh.png (base64)
iVBORw0KGgoAAAANSUhEUgAAACAAAAAsCAYAAAAEuLqPAAAABHNCSVQICAgIfAhkiAAAAAlwSFlz
AAABHAAAARwB37PomgAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAMXSURB
VFiFxdjbi1VVHAfwzxwMIeiioiKFIESTFzAbxhgjMNRi0CYEi3rwtQejFMKHeu8PmKAowS6vPfQW
0auKRQbVgzJdyNvUOFDeb0em2T6svXGfPXuvfc6cM54vrIe91nf9vt+9ztq/31qHzrEBo/OY1zMM
oYmxfhpIUhMv99NAZmJnPw0kuIlt/TSQ4AZeWEjRBnbgQ5wuMZDgCt7AOHZhUS+EF2N/RLTYruMt
XMNZvNmNkTX4oU3hfLuId4QNmuAIHu9UfAyX5yGetX+FlWvmnl9qV/xVzHQhnrVLeBu30uc72vhk
twifVbfiWTuCL3PP1zBcJb4Ekz0UP4kPSvrPp1pzcKiNoP/jRBu8v/A+ZivGDxXF16bBY0F/xdPK
E1G+ncW+mnizeCpv4POaoEfxUMqNGZjEE3gEx2tifpaJLxN2aBXxPJbnzFYZmMJgjrcMFyJxb+FR
2FPjdLdWlBmYxjpz8Xo7sT+NEH4uCVo08A+eLOFlmIjE/6SBjZHJX0fGCMlmJ36PcL6KjG1sYEWE
cDwydgUvKl+lPH6KjK1sYGWEMFXRfxFbC8GfFz7nIiYj8Zc3IoPwQEnfDbyCX3J9I/gGD5bwm5H4
Aw1hB1dhdUnfBI7lnofxrXt5oojHIvGn6ww8ExmDTfhOSDxVGIkZIByzqj6TMxiomDxs7plhqMAZ
wJ+R+OOEZBBLFq+ViK9L3Re5RQN1SW6MkA5vR0hTWJoLOpj2lXHzBlaIl/ebeDgjx7JhglNYJRSa
vyO8zMBSfF8T8+P8Uq1XXbsTobTuw7maoEPC3vijhjeTvkwLDleQZ/Ge9o7mJ9SfKxJ8VBQnJJHf
St78YBtv3kmbUJ6wwGbhcpGRvxAOI70Sv45nq8QzbHXvKD2Dd4WS2634VfGk1IJR/JdObOKAUIDm
Kz6dvlhHWC3k/ETIE/vN77Z0VLwe1GK7UPPvCCuRrUxd+zGd2xMsEq7c49irdaPm22mhtmwTrvQL
hhFhUxUNFGvBguI54a7XNwOEY1j+57jvBgh/3WR5oy8GCH8+3O6nAULy2tDppLs73VJAJ/Uw4QAA
AABJRU5ErkJggg==

@@ flush.png (base64)
iVBORw0KGgoAAAANSUhEUgAAACIAAAAsCAYAAAAATWqyAAAABHNCSVQICAgIfAhkiAAAAAlwSFlz
AAAB0gAAAdIBoShtngAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAU9SURB
VFiFvdh5iFVVHAfwz0yTpZlNtmlWtliW0ooWtlBUZEErLWR/+Ef/RBsYFRESUf2RRhQR9UcbFLRR
gdlOZbYJkYljlmla6kxWZpbTjNuMTX/8zuXdue++eU9Dv3B5555zzznfc873t5zXZOfhAlyPA/Eb
nsXHO3G+UtyFdejLPetwx64kcRzWFEhkTwfG7CoiD9cgkT0PlnVq3glE9qjTPmRXEfkavTXaejBv
J8xZiia8r/xY3t5VJDIMw8v4RezOaryIvWt1aKoz4AQhrr12kNBu2BObsS3VdeNq/L29g43HDCxE
uzjngayi3vMv3tmhZeVwFKZjPn4Wq9sRMn/i4v9LJsNw4cI/xSp0bieZxepLoy6KZj8Ik/E6VmBT
A0Q2CK00hJtwBQbn6o7GbCHkMuyO5Q0Q6cN32aIGcmgn4RJMxFfCFDuEGb6FaZiKAwr9evBBmqge
DsZ59T56FZNy70fiKtyHx/Cm8BFXlvQ9RO3AV3zmDETidjxZZyVf4MIBvvm2QSLtiXg/7Ien8AJa
akywP77EiQOQgKcbJLIN9xc734ZZBjarV3BOHRIwBVsbJLOguOrHxK58jDZsEccwRoT3zDPObYBI
m3DjPamPVO7NPdl7e62VD8PxwmzX4kfhG7YHo4V19Ymd6UFXKneJ+NMlvPOKFnE+k4SD2SA8ZGeu
vC8OKmnrrkPkdIwTga8elrUIX3FSquhOTJuFU9qQVnSYyDE6MRRj8ZzwK+cKD3lpes8wqUES0rha
xPZnpjgBS3MfTcCS3Ptl+Cj3/g1uKRn8E43HnbnNQiwLcUIaYJXYgUw/m0VOkWGw/noZKeJLEfuV
1NVCR2Y1i3CtSkxpxkNCTMOF77g3tZ2MI9J7s9DPr4WBmwyQjZVgVRZr2oR3a01PFw5N5SEikGVt
w9JErWI3mkuIjFI/m89jWVY4QZhXdgTvih0idiN/FHequP+TU79i8Dw/LaYRfXTj3GyAJcLpjEvv
K4UfIDSyh4pmhmBjKo8UQs8cVoZTlOe5f5XUdeO3TCM9IvX7MDUME6Z3c2pvEpl4H/ZJddekyfIm
m2FiSd2/wtMO1l/8W/NEiDy0DzNxkfALN6a2hWnif3A3/sAzuEEIt4jDS+o6hIuYIzSUoRfr82e7
QAh2MT4X1rI4PRvFcRXLzSJhKqJoMT14Q4hyQ6FtE/1D/SKR9DwldHBMKhNW84jYkXOEZx2HM/Ba
YeChqu+3a3BPKi9X0SKhwX5qb0uDrE1lYrXL0sftuXJHKg9SbbpHF4hswhMqsWmW/nfjzUqwRuW+
sVQlQV4mTJWIOVl6uFJoKY+pItnJzHOp/jt/WCKftc+mOgtrw+WJ5T9pktb03VnCbR8sjmYURqje
kdNUdrpTRPf8DqxOY4/ILaYKM8TRzBeW0Z7KXWll88UWLxXRt091vjk3t9o25ZiT+2Za2QdTVCLv
dDyeyp8JkybuIqeKO/E2IeQ8FqUJ/sDZNYjcKfzKVpGGVLnmNpEWDlXtXTMnlHnWkeIO25Pr36xi
uj+K62gZ3hN/7nWpPlqEFraIq8C34hjmYb0Q7Ly0igVpou8L/UcLwf8q/tSrhSb8lL4dla0gj178
IJKamanu/kTqbRXhPSyOq+jMxgpHOF//ZKqIPpUY9XsZESLjasFL6fcrcUzLhekOEv9vdKqOMxOE
bm4dgESGT0Ws6qU8pzwC1wkNjBXbPUZYxyk4M/WbLI4o/2/ybWkhzzdAZKNIOx+tReQXHCvykNVC
pF2JeavQRauwiifEFmcYjwc0dvVYK5zbe/Afac3j8hWR5tYAAAAASUVORK5CYII=

