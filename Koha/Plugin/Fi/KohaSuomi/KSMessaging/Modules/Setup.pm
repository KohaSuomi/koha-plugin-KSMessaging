package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Setup;

## Module for setting up the 'suomifi' message transport type.
##
## The 'suomifi' message transport type is what makes Koha queue notices for
## Suomi.fi, and it is not part of the standard Koha installation.  This module
## adds the transport type and copies the currently selected circulation and
## reserves message transports to it, so that an administrator only has to
## review the result in Administration -> Message preferences.
##
## Everything here is idempotent and can be run as often as needed: the
## transport type is inserted with INSERT IGNORE, and the copies are inserted
## with INSERT IGNORE too, which the primary key of the message_transports
## table turns into a no-op for a transport that is already there.  Transports
## that already exist for 'suomifi' are never updated or deleted, so the
## selections an administrator has made are kept.

use Modern::Perl;
use utf8;

use C4::Context;

our $VERSION = "1.0.0";

## The message transport type this module sets up.
our $TRANSPORT_TYPE = 'suomifi';

## The letter modules whose transports are copied to the new transport type.
our @LETTER_MODULES = qw(circulation reserves);

sub new {
    my ($class, $params) = @_;

    my $self = {};
    bless $self, $class;

    return $self;
}

############################################################
## Setup
############################################################

## Adds the 'suomifi' message transport type and copies every circulation and
## reserves message transport to it.  Returns a hashref with the number of
## transports that were added and the number that were already there:
##
##     { type_created => 0|1, added => N, skipped => N }
sub create_message_transports {
    my ($self) = @_;

    my $type_created = $self->create_transport_type;
    my $source       = $self->_source_transports;

    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
        "INSERT IGNORE INTO message_transports
            (message_attribute_id, message_transport_type, is_digest, letter_module, letter_code)
         VALUES (?, ?, ?, ?, ?)"
    );

    my ( $added, $skipped ) = ( 0, 0 );

    for my $row (@$source) {
        my ( $message_attribute_id, $is_digest, $letter_module, $letter_code ) = @$row;

        my $inserted = eval {
            # '0E0' is a false string but a true value in Perl, so the number
            # of affected rows has to be compared numerically
            $sth->execute( $message_attribute_id, $TRANSPORT_TYPE, $is_digest,
                $letter_module, $letter_code ) == 0 ? 0 : 1;
        };
        if ($@) {
            warn "KSMessaging: failed to insert message transport "
                . "$message_attribute_id/$TRANSPORT_TYPE/$is_digest/$letter_module/"
                . "$letter_code: $@";
            next;
        }

        $inserted ? $added++ : $skipped++;
    }

    $sth->finish;

    return {
        type_created => $type_created,
        added        => $added,
        skipped      => $skipped,
    };
}

## Returns 1 if the 'suomifi' message transport type was created, 0 if it
## already existed or could not be created.
sub create_transport_type {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;

    return 0 if $self->transport_type_exists;

    my $created = eval {
        my $sth = $dbh->prepare(
            "INSERT IGNORE INTO message_transport_types (message_transport_type) VALUES (?)"
        );
        my $inserted = $sth->execute($TRANSPORT_TYPE) == 0 ? 0 : 1;
        $sth->finish;
        $inserted;
    };
    if ($@) {
        warn "KSMessaging: failed to create the '$TRANSPORT_TYPE' message transport type: $@";
        return 0;
    }

    return $created;
}

############################################################
## Status
############################################################

## Returns 1 if the 'suomifi' message transport type exists, 0 otherwise.
sub transport_type_exists {
    my ($self) = @_;

    my $dbh  = C4::Context->dbh;
    my $sth  = $dbh->prepare("SELECT 1 FROM message_transport_types WHERE message_transport_type = ?");
    my $rows = eval { $sth->execute($TRANSPORT_TYPE) };
    warn "KSMessaging: failed to read the message transport types: $@" if $@;
    my ($found) = $rows ? $sth->fetchrow_array : ();
    $sth->finish;

    return $found ? 1 : 0;
}

## Returns the number of message transports that are set up for the 'suomifi'
## message transport type.
sub transport_count {
    my ($self) = @_;

    my $dbh  = C4::Context->dbh;
    my $sth  = $dbh->prepare("SELECT COUNT(*) FROM message_transports WHERE message_transport_type = ?");
    my $rows = eval { $sth->execute($TRANSPORT_TYPE) };
    warn "KSMessaging: failed to count the message transports: $@" if $@;
    my ($count) = $rows ? $sth->fetchrow_array : ();
    $sth->finish;

    return $count || 0;
}

############################################################
## Internal helpers
############################################################

## Returns the circulation and reserves message transports that are to be
## copied to the 'suomifi' message transport type.  Transports that are
## already set up for 'suomifi' are left out, and DISTINCT collapses the
## remaining transport types of the same notice into a single row, so that a
## notice selected for several transport types is copied only once.
sub _source_transports {
    my ($self) = @_;

    my $dbh     = C4::Context->dbh;
    my $modules = join( ', ', map { $dbh->quote($_) } @LETTER_MODULES );

    my $sth = $dbh->prepare(
        "SELECT DISTINCT message_attribute_id, is_digest, letter_module, letter_code
           FROM message_transports
          WHERE letter_module IN ($modules)
            AND message_transport_type <> ?"
    );
    my $rows = eval { $sth->execute($TRANSPORT_TYPE) };
    warn "KSMessaging: failed to read the message transports: $@" if $@;

    my $transports = $rows ? $sth->fetchall_arrayref : [];
    $sth->finish;

    return $transports || [];
}

1;
