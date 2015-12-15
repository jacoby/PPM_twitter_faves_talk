package DB ;

=head1 NAME

DB - Module handling access to MySQL databases

=head2 DESCRIPTION

This is the interface to the databases, abstracting all the complexity of
DBI into just a few functions.

=cut

# Tools dealing with database interaction for Second Generation
# sequencing jobs

# CHANGE LOG ========================================================
# 2009/12 DAJ - Finished initial development
# 2010/01 DAJ - Or so I thought
# 2010/03 DAJ - That's mojo. Using $Database to control what DB to use
# 2010/03 DAJ - placeholders added to db_arrayref, db_hashref and db_do
#               functions
# 2011/04 DAJ - removed requirement for 5.010 for use on RCAC systems

# This is the base class for all database connections. It is the plan and hope
# that you only need to (and get to) connect to the DBs via this module.
# 201303    DAJ     Adapted to GCore usage and added POD
# 201312    DAJ     Adding Logging to find answer to New Request ID issue
#                   Logging three events -- the query and args at the beginning,
#                   the errors if query fails, and the query, args and rows
#                   affected after the query executes
# 201404    DAJ     Commenting out the logging, which seems to not work
# 201404    DAJ     Adding "state" to $dbh, which should handle SOME
#                   overhead. Main issue is on DB side. Even if system perl,
#                   it should still work
#                   --- CANCELLED --- Coates still has 5.8.8.

# 201404    DAJ     adding db_one_arrayref and db_one_hashref to handle cases
#                   where we're asking for one value so, instead of returning
#                   $object and needing to run $object->{ key } , we just return
#                   $object->{ key }
#                   Also adding specific code to handle the new key_value_pair
#                   In addition, since we have genomics Perl, this not working
#                   is an indication that you're using system Perl. Using state.

# 201404    DAJ     added _execute_query(), made minor changes to db_hashref
#                   to make it work with 

# 201404    DAJ     Removed modules that were necessary for logging but 
#                   unnecessary once I removed logging. Plus I had CGI in
#                   there. Probably had CGI::Carp in there a while ago, too.
#                   Utterly unnecessary these days.

# 201405    DAJ     Copied from GCore, removed Genomics-Specific stuff

# 201407    DAJ     From Kevin Colby, gained knowledge of transactions, 
#                   put into subs 

# ISSUES ============================================================
# Warnings are trapped, not displayed. 

# Programmers waste enormous amounts of time thinking about, 
# or worrying about, the speed of noncritical parts of their 
# programs, and these attempts at efficiency actually have a 
# strong negative impact when debugging and maintenance are 
# considered. We should forget about small efficiencies, say 
# about 97% of the time: premature optimization is the root of 
# all evil. Yet we should not pass up our opportunities in 
# that critical 3%."  -- Donald Knuth

use feature 'state' ;
use strict ;
use warnings ;
use Carp ;
use DBI ;
use Exporter qw(import) ;

use MyDB ;

our $VERSION  = 0.0.3 ;
our $Database = 'itap' ;

#my %prepared ;
#my $dbh ;
our @EXPORT = qw{
    db_do
    db_arrayref
    db_one_arrayref
    db_hashref
    db_one_hashref
    db_start_transaction
    db_commit_transaction
    db_rollback_transaction
    db_array_as_json
    db_hash_as_json
    } ;

############################################################
# queries are prepared by the DB for later use. Takes a SQL
# query and returns the prepared object thing, which is
# cached. Not exported.
# sub _prepare_query {
#     my ( $sql ) = @_ ;
#     state $dbh = MyDB::db_connect( $Database ) ;
#     if ( !$prepared{ $sql } ) {
#         $prepared{ $sql } = $dbh->prepare( $sql ) ;
#         }
#     return $prepared{ $sql } ;
#     }

############################################################
# Takes an sql query and related arguments (which could 
# contain a hashref's index variable), executes the query 
# (or dies), and returns a Statement Handle Object. Not exported.
sub _execute_query {
    my ( $sql, @args ) = @_ ;
    croak 'no SQL statement' if ! defined $sql || $sql eq '' ;
    state $dbh = MyDB::db_connect( $Database ) ;
    state %prepared ;
    if ( !$prepared{ $sql } ) {
        $prepared{ $sql } =  $dbh->prepare( $sql )
            or croak $dbh->errstr ;
        }
    $prepared{ $sql }->execute( @args ) or croak $dbh->errstr ;
    return $prepared{ $sql } ;
    }

=pod

=over 12

=item B<db_arrayref>

Takes a query and an array, containing the values required
by the query. Returns a reference to an array containing
the data requested by the query.

=cut

sub db_arrayref {    
    my $sql = shift ;
    my $sth = _execute_query( $sql , @_ ) ;
    my $ptr = $sth->fetchall_arrayref( @_ ) ;
    return $ptr ;
    }

=pod

=item B<db_one_arrayref>

Takes a query and an array, containing the values required
by the query expecting a single response. Returns a reference 
to an array containing the data requested by the query.

=cut

sub db_one_arrayref {
    my $sql = shift ;
    my $sth = _execute_query( $sql ) ;
    my $ptr = $sth->fetchrow_arrayref() ;
    return $ptr ;
    }

=pod

=item B<db_hashref>

Takes a query and an array, containing the values required
by the query. Returns a reference to an array containing
the data requested by the query.

=cut

############################################################
# $id has nothing to do with the query but is only used in 
# fetchall_hashref, so it's separated before the query

sub db_hashref {
    my $sql = shift ;
    my $id = shift ;
    my $sth = _execute_query( $sql , @_ ) ;
    my $ptr = $sth->fetchall_hashref( $id ) ;
    return $ptr ;
    }

=pod

=item B<db_one_hashref>

Takes a query and an array, containing the values required
by the query expecting a single response. Returns a reference 
to hash containing the data requested by the query.

=cut

sub db_one_hashref {
    my $sth = _execute_query( @_ ) ;
    my $ptr = $sth->fetchrow_hashref( ) ;
    return $ptr ;
    }

=pod

=item B<db_db>

Takes a query and an array, containing the values required
by the query. Returns the number of rows affected, or '0E0'
if no content.

This one is used for create, update or delete, not read.

=cut

sub db_do {
    my $sth = _execute_query( @_ ) ;
    my $rows = $sth->rows ;
    return ( $rows == 0 ) ? "0E0" : $rows ;
    # always return true if no error
    }

=pod

=item B<db_start_transaction>

Used in transactions, which is a means to make atomic a series of 
database calls. This marks the beginning of transaction, and the 
following calls (usually additions) only get committed if a commit
is set.

Transactions only work if the database table is run with the InnoDB engine.

=cut

sub db_start_transaction{
    return db_do( 'START TRANSACTION' )
    }

=pod

=item B<db_commit_transaction>

Used in transactions, which is a means to make atomic a series of 
database calls. This marks the successful end of the transaction, 
telling MySQL to commit all the calls in the transaction.

=cut

sub db_commit_transaction{
    return db_do( 'COMMIT' )
    }

=pod

=item B<db_rollback_transaction>

Used in transactions, which is a means to make atomic a series of 
database calls. This marks the unsuccessful end of the transaction, 
telling MySQL to drop all the calls in the transaction. Those 
transactions will also be dropped if the program closes before 
the commit.

=cut

sub db_rollback_transaction{
    return db_do( 'ROLLBACK' )
    }

sub db_array_as_json {
    require JSON;
    return JSON::encode_json( db_arrayref(@_) ) ;
    }

sub db_hash_as_json {
    require JSON;
    return JSON::encode_json( db_hashref(@_) ) ;
    }

=pod

=back

=head2 AUTHOR

Dave Jacoby - L<jacoby.david@gmail.com>

=cut

1 ;
