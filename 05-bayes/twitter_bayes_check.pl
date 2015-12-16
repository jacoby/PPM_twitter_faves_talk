#!/home/jacoby/perl-5.18.0/bin/perl

# usage twitter_bayes_check.pl -u username

use feature qw{ say state } ;
use strict ;
use warnings ;
use utf8 ;
binmode STDOUT, ':utf8' ;

use Algorithm::NaiveBayes ;
use Carp ;
use Data::Dumper ;
use DateTime ;
use Getopt::Long ;
use IO::Interactive qw{ interactive } ;
use Net::Twitter ;
use String::Tokenizer ;
use YAML qw{ DumpFile LoadFile } ;

# oDB is an object-oriented DB interface, used so I don't put DB keys
# into source code

use lib '/home/jacoby/lib' ;
use oDB ;

my $config = config() ;
my $nb     = train() ;
my @top    = read_timeline( $config, $nb ) ;

for my $tweet (sort {
    $a->{analysis}->{favorites} <=> $b->{analysis}->{favorites}
    } @top) {
    my $fav = int $tweet->{analysis}->{favorites} * 100 ;
    say $tweet->{text} ;
    say $tweet->{user}->{screen_name} ;
    say $tweet->{gen_url} ;
    say $fav ;
    say '' ;
    }

exit ;

#========= ========= ========= ========= ========= ========= =========
# gets the first page of your Twitter timeline.
#
# avoids checking a tweet if it's 1) from you (you like yourself;
#   we get it) and 2) if it doesn't give enough tokens to make a
#   prediction.
sub read_timeline {
    my $config = shift ;
    my $nb     = shift ;
    my $twit   = Net::Twitter->new(
        consumer_key    => $config->{consumer_key},
        consumer_secret => $config->{consumer_secret},
        ssl             => 1,
        traits          => [qw/API::RESTv1_1/],
        ) ;
    if ( $config->{access_token} && $config->{access_token_secret} ) {
        $twit->access_token( $config->{access_token} ) ;
        $twit->access_token_secret( $config->{access_token_secret} ) ;
        }
    unless ( $twit->authorized ) {
        croak("Not Authorized") ;
        }
    my @favorites ;
    my $start = 1 ;
    my $end   = 10 ;

    # maybe put the API call in a try-catch so 

    # for ( my $page = $start; $page <= $end; ++$page ) {
    #     say { interactive } join ' - ' , $start , $page , $end ;
        my $timeline = $twit->home_timeline( { count => 40 } ) ;
        say scalar @$timeline ;
        sleep 1 ;
        for my $tweet (@$timeline) {
            my $id      = $tweet->{id} ;                          # twitter_id
            my $text    = $tweet->{text} ;                        # text
            my $created = handle_date( $tweet->{created_at} ) ;   # created
            my $screen_name = $tweet->{user}->{screen_name} ;     # user id
            my $check       = toke( lc $text ) ;
            next if lc $screen_name eq lc $config->{user} ;
            next if !scalar keys %{ $check->{attributes} } ;
            my $r   = $nb->predict( attributes => $check->{attributes} ) ;
            my $fav = int $r->{favorites} * 100 ;
            next if $fav < 90 ;
            my $url = join '/', 'http:', '', 'twitter.com', $screen_name,
                'status', $id ;
            $tweet->{analysis} = $r ;
            $tweet->{gen_url}  = $url ;
            push @favorites, $tweet ;
            }
        # sleep 60 * 3 ;    # five minutes
        # }
    return @favorites ;
    }

#========= ========= ========= ========= ========= ========= =========
# trains the NB thing by pulling text of tweets, returning an NB object.
# I found that A::NB does not like to have just one label, so I give
# labels for year, year-month, and 'favorites'. Showed me that what I
# like about Twitter changes over time.
#
# If you don't keep track of your favorites, dunno how you're going to
# train your ML algorithm. Sorry.
sub train {
    my $nb = Algorithm::NaiveBayes->new( purge => 1 ) ;
    my $db = oDB->new('default') ;
    my $q  = '   SELECT  text 
                    ,   MONTH(created)
                    ,   YEAR(created) 
                FROM twitter_favorites' ;
    my $text = $db->arrayref($q) ;
    for my $entry (@$text) {
        my ( $tweet, $month, $year ) = (@$entry) ;
        my $label = join '', $year, ( sprintf '%02d', $month ) ;
        my $ham = toke($tweet) ;
        next unless scalar keys %$ham ;
        $nb->add_instance(
            attributes => $ham->{attributes},
            label      => [ $year, $label, 'favorites' ],
            ) ;
        }
    $nb->train() ;
    return $nb ;
    }

#========= ========= ========= ========= ========= ========= =========
# tokenizes a tweet by breaking it into characters, removing URLs
# and short words
sub toke {
    my $tweet = shift ;
    my $ham ;
    my $tokenizer = String::Tokenizer->new() ;
    $tweet =~ s{https?://\S+}{}g ;
    $tokenizer->tokenize($tweet) ;
    for my $t ( $tokenizer->getTokens() ) {
        $t =~ s{\W}{}g ;
        next if length $t < 5 ;
        next if $t !~ /\D/ ;
        my @x = $tweet =~ m{($t)}gmix ;
        $ham->{attributes}{$t} = scalar @x ;
        }
    return $ham ;
    }

#========= ========= ========= ========= ========= ========= =========
# converts twitter dates to DateTime dates, gives ymd
sub handle_date {
    my $twitter_date = shift ;
    my $months       = {
        Jan => 1,
        Feb => 2,
        Mar => 3,
        Apr => 4,
        May => 5,
        Jun => 6,
        Jul => 7,
        Aug => 8,
        Sep => 9,
        Oct => 10,
        Nov => 11,
        Dec => 12,
        } ;
    my @twitter_date = split m{\s+}, $twitter_date ;
    my $year         = $twitter_date[5] ;
    my $month        = $months->{ $twitter_date[1] } ;
    my $day          = $twitter_date[2] ;
    my $t_day        = DateTime->new(
        year      => $year,
        month     => $month,
        day       => $day,
        time_zone => 'floating'
        ) ;
    return $t_day->ymd() ;
    }

#========= ========= ========= ========= ========= ========= =========
# handles the user configuration. you'll need to get your own
# developer keys, etc
sub config {
    my $config_file = $ENV{HOME} . '/.twitter_fave.cnf' ;
    my $data        = LoadFile($config_file) ;

    my $config ;
    GetOptions(
        'user=s' => \$config->{user},
        'help'   => \$config->{help},
        ) ;
    if (   $config->{help}
        || !$config->{user}
        || !$data->{tokens}->{ $config->{user} } ) {
        say $config->{user} || 'no user' ;
        croak qq(nothing) ;
        }

    for my $k (qw{ consumer_key consumer_secret }) {
        $config->{$k} = $data->{$k} ;
        }

    my $tokens = $data->{tokens}->{ $config->{user} } ;
    for my $k (qw{ access_token access_token_secret }) {
        $config->{$k} = $tokens->{$k} ;
        }
    return $config ;
    }

=pod

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015 by Dave Jacoby - L<jacoby.david@gmail.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
