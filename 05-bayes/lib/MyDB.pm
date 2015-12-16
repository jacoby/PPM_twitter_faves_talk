package MyDB ;

=head1 NAME

MyDB - Module handling access to MySQL databases

=head2 DESCRIPTION

Mostly used within DB.pm, which handles the actual queries. This handles
connecting to the actual databases.

=cut

# 201303    DAJ     Adapted to GCore usage and added POD
# 201306    DAJ     Moved the YAML hit to the begin block so it isn't hit
#                   every time a DB routine is called

use strict ;
use warnings ;
use Carp ;
use DBI ;
use YAML::XS qw{ LoadFile } ;

use Exporter qw(import) ;
our @EXPORT      = qw{ db_connect } ;
our %EXPORT_TAGS = ( 'all' => [ qw( db_connect ) ], ) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{ 'all' } } ) ;
our $VERSION     = 0.0.1 ;

my $_db_params = '' ;    # String of current database parameters.
my $_dbh ;               # Save the handle.
my $config_obj ;

BEGIN {
    # moved to the begin block so the expensive repeated hits
    # to the config are reduced to one.
    my $config_file = '/group/gcore/apps/config/my.yaml' ;    

    $config_file = -f $config_file ? $config_file : '/home/ltl/.my.yaml' ;
    $config_file = -f $config_file ? $config_file : '/home/djacoby/.my.yaml' ;
    $config_file = -f $config_file ? $config_file : '/home/jacoby/.my.yaml' ;
    if ( defined $config_file && -f $config_file ) {
        my $z = LoadFile( $config_file ) ;
        $config_obj = $z->{ clients } ;
        }
    else {
        croak $! ;
        }
    }

=pod

=over 12

=item B<db_connect>

Connect to a database. Configuration aliases for different mysql servers
exist in /group/gcore/apps/config/my.yaml. Pass a correct alias, or nothing
to get the default database. Returns a DBI object.

=cut

sub db_connect {
    my ( $param_ptr, $attr_ptr ) = @_ ;
    my $port = '3306' ;

    # If database is already opened then check for a fast return.

    if ( defined $_dbh
        && ( !defined $param_ptr || $param_ptr eq '' ) ) {
        return $_dbh ;
        }

    # Check for a different set of parameters to use via a the name (string)
    #   of the parameter (e.g., 'test').

    my $which_db = 'default' ;

    if ( defined $param_ptr && ref( $param_ptr ) eq '' && $param_ptr ne '' ) {
        if ( defined $config_obj->{ $param_ptr } ) {
            $which_db = $param_ptr ;
            }
        else {
            croak "No connection parameters for '$param_ptr'" ;
            }
        }

    # Get the base parameters ... copy and flatten from global array

    my %params = () ;
    my %attr   = () ;

    foreach ( keys %{ $config_obj->{ $param_ptr || 'default' } } ) {
        $params{ $_ } = $config_obj->{ $param_ptr || 'default' }{ $_ } ;
        }
    $params{ port } = $port ;

    if ( defined $attr_ptr && ref( $attr_ptr ) eq 'HASH' ) {
        foreach ( keys %$attr_ptr ) { $attr{ $_ } = $attr_ptr->{ $_ } }
        }

    # Now make up an order string of the parameters so that we can compare
    #   them to the old ones.

    my $new_db_params = '' ;
    foreach ( sort keys %params ) { $new_db_params .= $params{ $_ } }

    # Can also do a quick return if params are same as old ones

    if ( defined $_dbh && $new_db_params eq $_db_params ) {
        return $_dbh ;
        }

    # At this point either the database has never been opened or
    #   new parameters are to be used. Close database and reopen.

    $_db_params = $new_db_params ;

    #if ( defined $_dbh ) { $_dbh->disconnect }    # no error check

    my $source = "dbi:mysql:$params{database}:$params{host}:$params{port}" ;

    # http://perltraining.com.au/talks/dbi-trick.pdf
    # consider move to Lab production
    $attr{ RaiseError } = 1 ;
    $attr{ ShowErrorStatement } = 1 ;
    $attr{ PrintError } = 0 ;
    $attr{ mysql_enable_utf8 } = 1 ;

    $_dbh = DBI->connect( 
        $source, 
        $params{ user }, 
        $params{ password }, \%attr )
        or croak $DBI::errstr ;

    if ( !defined $_dbh ) {

        #croak q{can't open DB} ;
        ## no critic -- can't use $dbh since there is none
        #$_error_message = 'db_connect: ' . $DBI::errstr;
        ## use critic
        }
    return $_dbh ;
    }    # End of db_connect

=pod

=back

=head2 AUTHOR

Dave Jacoby - L<jacoby@purdue.edu>

=cut

1 ;
