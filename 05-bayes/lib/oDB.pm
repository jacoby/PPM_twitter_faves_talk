package oDB ;

=head1 NAME

oDB - Module handling access to MySQL databases

=head2 DESCRIPTION

This is the interface to the databases, abstracting all the complexity of
DBI into just a few functions, hanging off an interface object.

=head1 SYNOPSIS

    use oDB ;

    my $genomics = oDB->new( 'genomics' ) ;

    my $tables = $genomics->arrayref( 'show tables' ) ;

    my $recent_request = $genomics->arrayref(
        'SELECT request_id , lab_director , request_name , pi_id
    FROM requests
    WHERE lab_director = ?
    ORDER BY request_id DESC LIMIT 10',
        {
            placeholders => [ qw{ woeste } ],
            controls     => {},
            }
        ) ;

    $engines = $genomics->hashref(
        'SELECT * FROM sequence_engines where is_valid = 1' ,
        { controls => 'sequence_engine' }
        ) ;

=head1 DESCRIPTION

This module uses the oldest-of-schools methods for object orientation, 
wrapping Perl's DBI module like DB.pm had before, but this has two great
features that were not fully implemented in DB.pm

=over

=item * The ability to have two MySQL databases open at once, which 
    is useful when comparing the test and production databases, for
    example.

=item * The separation of controls and placeholders, which allows 
    you to turn a hashref into an array of hashrefs, and similarly 
    turn hashrefs into hashrefs of hashrefs

=back

=head1 METHODS

=head2 new

    my $itap = oDB->new() ;
    my $oz   = oDB->new( 'oz' ) ;

Returns a new oDB object.

=head2 database 

    say $itap->database ;

Returns the identifier for the database. This program uses a .my.yaml file
which holds the connection information. This program does not and will not
export any of that connection information.

=head2 arrayref

    my $out1 = $itap->arrayref( 'SELECT * FROM table' ) ; 
        # array of arrays

    my $out2 = $itap->arrayref( 'SELECT * FROM table WHERE class = ? ' , 
        { placeholders => [ 'test' ] } ) ; 
        # limited on query

    my $out3 = $itap->arrayref( 'SELECT * FROM table' , { controls => {} } ) ; 
        # array of hashes

The arrayref method wraps DBI's fetchall_arrayref(), giving the ability 
to use placeholders to scrub input going into the query and controls to
change the way output is generated.

=head2 one_arrayref

    my $out1 = $itap->one_arrayref( 'SELECT * FROM table' ) ;

    my $out2 = $itap->one_arrayref( 'SELECT * FROM table WHERE class = ?' , 
        { placeholders => [ 'test' ] } ) ;

The one_arrayref method wraps DBI's fetchrow_arrayref(), giving the ability 
to use placeholders to scrub input going into the query.

The main difference between arrayref and one_arrayref is that one_arrayref
just returns one arrayref, removing the need to remove it from that array.
This is very useful in cases where you're only expecting one response, 
such as "SELECT * FROM requests WHERE request_id = ?".

=head2 hashref

    my $out1 = $itap->hashref( 'SELECT * FROM table' , { controls => 'id' } ) ; 
        # id is the index key for the hashref, controls are required
    my $out2 = $itap->hashref( 'SELECT * FROM table WHERE class = ? ' , { 
        controls -> 'id' , 
        placeholders => [ 'test' ] ,
        } ) ; 
        # using a placeholder in the query
    my $out3 = $itap->hashref( 'SELECT * FROM table WHERE class = ?' , { 
        controls -> [qw{ id intensity }] , 
        placeholders => [ 'test' ] ,
        } ) ; 
        # using a placeholder in the query and adding a second level of hashes

The hashref method wraps DBI's fetchall_hashref(), giving the same 
abilities as that function. placeholders and controls are separated, 
as with arrayref, so that they have no chance of interacting with 
each other.

=head2 one_hashref

    my $out1 = $itap->one_hashref(
        'SELECT * FROM table WHERE class = ? ' , 
        { placeholders => [ 'test' ] } ) ; 

The one_hashref method wraps DBI's fetchrow_hashref(), giving the same 
abilities as that function. 

Since it returns one row, it's best used where you would expect one response
( "SELECT * FROM requests WHERE request_id = ?" ). The id field is not 
required, therefore.

=head2 do

my $bool = $itap->do( 'INSERT INTO table ( key , value ) VALUES ( ? , ? ) ' ,
    { placeholders => [ 'key' , 'value' ] }    
    )

Handles query without returning rows, for queries such as INSERT , REPLACE, 
DELETE and UPDATE, where you don't expect output beyond the number of rows 
affected, which is exactly the output it returns.

=head2 start_transaction

=head2 commit_transaction

=head2 rollback_transaction

Transactions are used to turn a series of database actions into an 
atomic action, succeeding or failing as one. Transactions only work
if the table uses the InnoDB engine.

=head1 UNIMPLEMENTED METHODS

These are methods available in B<DB> but not in B<oDB>.

=head2 array_as_json

=head2 hash_as_json

These functions work the same as arrayref() and hashref(), but
return JSON-encoded text instead of objects. 

=head2 insert_only

=head2 update_only

=head2 insert_or_update

xxx

=head2 get_config

=head2 quote

quote() is a wrapper for the B<DBI> quote function, which prepares a variable for
use in an SQL query. We instead use placeholders to escape our inputs, so this 
will not be added to oDB.

=head1 AUTHOR

Dave Jacoby - L<jacoby.david@gmail.com>

=cut

# CHANGE LOG ========================================================
# 2015/3 DAJ - Initial Development

use feature qw{ state say } ;
use strict ;
use warnings ;
use Carp ;
use DBI ;
use Data::Dumper ;

use lib '/home/jacoby/lib' ;
use MyDB ;

sub new {
    my ( $class, $database ) = @_ ;
    $database = $database ? $database : 'itap' ;
    my $self = {} ;
    bless $self, $class ;
    $self->{ database } = $database ;
    $self->{ dbh }      = MyDB::db_connect( $database ) ;
    $self->{ prepared } = {} ;
    return $self ;
    }

sub database {
    my $self = shift ;
    return $self->{ database } ;
    }

sub arrayref {
    my ( $self, $query, $object ) = @_ ;
    my $placeholders = $object->{ placeholders } || [] ;
    my $controls     = $object->{ controls } ;

    my $sth = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;

    if ( $placeholders && scalar @$placeholders ) {
        $sth->execute( @$placeholders )
            or croak $self->{ dbh }->errstr ;
        }
    else {
        $sth->execute()
            or croak $self->{ dbh }->errstr ;
        }

    my $ptr ;
    if ( $controls ) {
        $ptr = $sth->fetchall_arrayref( $controls ) ;
        }
    else {
        $ptr = $sth->fetchall_arrayref() ;
        }

    return $ptr ;
    }

sub one_arrayref {
    my ( $self, $query, $object ) = @_ ;
    my $placeholders = $object->{ placeholders } || [] ;

    my $sth = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;
    if ( $placeholders && scalar @$placeholders ) {
        $sth->execute( @$placeholders )
            or croak $self->{ dbh }->errstr ;
        }
    else {
        $sth->execute()
            or croak $self->{ dbh }->errstr ;
        }

    my $ptr ;
    $ptr = $sth->fetchrow_arrayref() ;

    return $ptr ;
    }

sub hashref {
    my ( $self, $query, $object ) = @_ ;
    my $placeholders = $object->{ placeholders } || [] ;
    my $controls     = $object->{ controls } ;
    my $id           = $object->{ id } ;

    my $sth = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;

    if ( $placeholders && scalar @$placeholders ) {
        $sth->execute( @$placeholders )
            or croak $self->{ dbh }->errstr ;
        }
    else {
        $sth->execute()
            or croak $self->{ dbh }->errstr ;
        }

    my $ptr ;
    $ptr = $sth->fetchall_hashref( $controls ) ;

    return $ptr ;
    }

sub one_hashref {
    my ( $self, $query, $object ) = @_ ;
    my $placeholders = $object->{ placeholders } || [] ;

    my $sth = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;

    if ( $placeholders && scalar @$placeholders ) {
        $sth->execute( @$placeholders )
            or croak $self->{ dbh }->errstr ;
        }
    else {
        $sth->execute()
            or croak $self->{ dbh }->errstr ;
        }

    my $ptr ;
    $ptr = $sth->fetchrow_hashref( ) ;

    return $ptr ;
    }

sub do {
    my ( $self, $query, $object ) = @_ ;
    my $placeholders = $object->{ placeholders } ;

    my $sth = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;

    if ( $placeholders && scalar @$placeholders ) {
        $sth->execute( @$placeholders )
            or croak $self->{ dbh }->errstr ;
        }
    else {
        $sth->execute()
            or croak $self->{ dbh }->errstr ;
        }
    my $rows = $sth->rows ;
    return $rows ;
    }

sub last_insert_id {
    my ( $self ) = @_ ;
    return $self->{ dbh }->last_insert_id( 0..3 ) ;
    # DBI requires four fields. MySQL couldn't care less.
    }

# transaction methods get no explicit tests, because you cannot test
# their function without making persistent changes in the database
# which is not what testing is for

sub start_transaction {
    my ( $self ) = @_ ;
    my $query = 'BEGIN' ;
    my $sth = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;
    $sth->execute()
        or croak $self->{ dbh }->errstr ;
    my $rows = $sth->rows ;
    return $rows ;
    }

sub commit_transaction {
    my ( $self ) = @_ ;
    my $query    = 'COMMIT' ;
    my $sth      = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;
    $sth->execute()
        or croak $self->{ dbh }->errstr ;
    my $rows = $sth->rows ;
    return $rows ;
    }

sub rollback_transaction {
    my ( $self ) = @_ ;
    my $query    = 'ROLLBACK' ;
    my $sth      = $self->{ dbh }->prepare( $query )
        or croak $self->{ dbh }->errstr ;
    $sth->execute()
        or croak $self->{ dbh }->errstr ;
    my $rows = $sth->rows ;
    return $rows ;
    }

sub array_as_json {}
sub hash_as_json {}

sub insert_only {}
sub update_only {}
sub insert_or_update {}

sub get_config {}
sub quote {
    # this one is never coming    
    }

1 ;
