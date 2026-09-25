#!/usr/bin/perl

use strict;
use warnings;
use C4::Context;
use Try::Tiny;

# This script is used to set up the SuomiFi messaging system in Koha.
# It inserts a new message transport type 'suomifi' into the database
# and updates the system preferences to enable SuomiFi messaging.
# It also copies existing message transports for circulation and reserves
# from the database and associates them with the new 'suomifi' transport type.
# This is a one-time setup script and should be run only once after


my $dbh = C4::Context->dbh;
$dbh->do("INSERT IGNORE INTO message_transport_types (message_transport_type) VALUES ('suomifi');");
$dbh->do("INSERT IGNORE INTO systempreferences (variable, value) VALUES ('SuomiFiMessaging', '0');");
$dbh->do("INSERT IGNORE INTO systempreferences (variable, value, explanation, type) VALUES ('SuomiFiAltSender', '', 'Enable SuomiFi alternative sender, yaml format. Maximum 4 rows are shown per sender', 'Textarea');");
$dbh->do("INSERT IGNORE INTO systempreferences (variable, value, explanation, type) VALUES ('SuomiFiCostPool', '', 'Add costPool to SuomiFi REST, yaml format. Branch/part of branch: costPool value (1-15 only capital letters or numbers)', 'Textarea');");

my $message_transports = $dbh->selectall_arrayref("SELECT message_attribute_id, message_transport_type, is_digest, letter_module, letter_code FROM message_transports WHERE letter_module in ('circulation', 'reserves') GROUP BY message_attribute_id, letter_code");

foreach my $row (@$message_transports) {
    my ($message_attribute_id, $message_transport_type, $is_digest, $letter_module, $letter_code) = @$row;
    print "Inserting: $message_attribute_id, suomifi, $is_digest, $letter_module, $letter_code\n";
    my $sth = $dbh->prepare("INSERT INTO message_transports (message_attribute_id, message_transport_type, is_digest, letter_module, letter_code) VALUES (?, ?, ?, ?, ?)");
    try {
        $sth->execute($message_attribute_id, 'suomifi', $is_digest, $letter_module, $letter_code);
    } catch {
        warn "Failed to insert message transport: $_";
    };
    $sth->finish();
}