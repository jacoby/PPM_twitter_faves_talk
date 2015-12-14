#!/home/jacoby/perl-5.18.0/bin/perl

use feature qw' say ' ;
use strict ;
use warnings ;
use Data::Dumper ;
use IO::Interactive qw{ interactive } ;
use Net::Twitter ;
use WWW::Shorten 'TinyURL' ;
use YAML qw{ DumpFile LoadFile } ;

use lib '/home/jacoby/lib' ;
use DB ;

use utf8 ;
binmode STDOUT, ':utf8' ;

my $config_file = $ENV{ HOME } . '/.twitter.cnf' ;
my $config      = LoadFile( $config_file ) ;

my $sql =<<SQL;
    SELECT user_screen_name screenname
        , count(*) count
    FROM twitter_favorites
    WHERE consumer like 'jacobydave'
    AND user_screen_name not like 'jacobydave'
    AND DATEDIFF( NOW() , created ) < 8
    GROUP BY screenname
    ORDER BY count
    DESC
    ;
SQL

my $output = db_arrayref( $sql ) ;

my $user = 'jacobydave' ;
# my $ff = join ' ' , '#ff' , map { qq{\@$_->[ 0 ]} } @$output[0..8] ;

my $ff = '#ff' ;
my $flag = 0 ;
for my $f ( map { qq{\@$_->[ 0 ]} }  @$output ) {
    my $g = join ' ' , $ff , $f ;
    if ( $flag ) { next }
    if ( length $g > 140 ) { $flag ++ ; }
    else { $ff = $g }
    }

# GET key and secret from http://twitter.com/apps
my $twit = Net::Twitter->new(
    traits          => [qw/API::RESTv1_1/],
    consumer_key    => $config->{ consumer_key },
    consumer_secret => $config->{ consumer_secret },
    ssl => 1 ,
    ) ;

# You'll save the token and secret in cookie, config file or session database
my ( $access_token, $access_token_secret ) ;
( $access_token, $access_token_secret ) = restore_tokens( $user ) ;

if ( $access_token && $access_token_secret ) {
    $twit->access_token( $access_token ) ;
    $twit->access_token_secret( $access_token_secret ) ;
    }

unless ( $twit->authorized ) {

    # You have no auth token
    # go to the auth website.
    # they'll ask you if you wanna do this, then give you a PIN
    # input it here and it'll register you.
    # then save your token vals.

    say "Authorize this app at ", $twit->get_authorization_url,
        ' and enter the PIN#' ;
    my $pin = <STDIN> ;    # wait for input
    chomp $pin ;
    my ( $access_token, $access_token_secret, $user_id, $screen_name ) =
        $twit->request_access_token( verifier => $pin ) ;
    save_tokens( $user, $access_token, $access_token_secret ) ;
    }

if ( $twit->update( $ff ) ) {
    say { interactive } $ff ;
    }
else {
    say { interactive } 'FAIL' ;
    }

#========= ========= ========= ========= ========= ========= =========

sub restore_tokens {
    my ( $user ) = @_ ;
    my ( $access_token, $access_token_secret ) ;
    if ( $config->{ tokens }{ $user } ) {
        $access_token = $config->{ tokens }{ $user }{ access_token } ;
        $access_token_secret =
            $config->{ tokens }{ $user }{ access_token_secret } ;
        }
    return $access_token, $access_token_secret ;
    }

sub save_tokens {
    my ( $user, $access_token, $access_token_secret ) = @_ ;
    $config->{ tokens }{ $user }{ access_token }        = $access_token ;
    $config->{ tokens }{ $user }{ access_token_secret } = $access_token_secret ;
    DumpFile( $config_file, $config ) ;
    return 1 ;
    }
