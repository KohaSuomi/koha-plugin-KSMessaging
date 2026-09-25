package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::SuomiFi;
use warnings;
use strict;
use utf8;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(RESTMessage);

use JSON;

use Koha::Patrons;
use Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database;

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;

sub FormatDescription {
    my $description =  shift;
       $description =~ s/\r\n/\n/g;
       $description =~ s/</&lt;/g;
       $description =~ s/>/&gt;/g;

    return $description;
}

sub RESTMessage {
    my %param = @_;

    my $borrower = Koha::Patrons->find( $param{'borrowernumber'} );
    my $branch = Koha::Libraries->find( $param{'branchcode'} );
    my $ssndb = Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database->new();
    my $id = $ssndb->getSSNByBorrowerNumber ( $param{'borrowernumber'} ) || $param{'id'};
    my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({ interface => 'suomifi', branch => $param{'branchconfig'} });
    my $costPool = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({branch => $param{'branchcode'}})->getSuomiFiCostPool();

    my $paperMail = {
        'createAddressPage' => JSON::false,
        'messageServiceType' => 'Normal',
        'colorPrinting' => JSON::false,
        'rotateLandscapePages' => JSON::false,
        'twoSidedPrinting' => JSON::true,
        sender => {
            address => {
                name => $branch->branchname,
                streetAddress => $branch->branchaddress1,
                zipCode => $branch->branchzip,
                city => $branch->branchcity,
                countryCode => Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->countryCode( $branch->branchcountry )
            }
        },
        recipient => {
            address => {
                name => $borrower->firstname . ' ' . $borrower->surname,
                streetAddress => $borrower->address,
                zipCode => $borrower->zipcode,
                city => $borrower->city,
                countryCode => Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->countryCode( $borrower->country )
            }
        },
        printingAndEnvelopingService => {
            postiMessaging => {
                contactDetails => {
                    email => $config->contact
                },
                username => $config->getIPostConfig->{customerid},
                password => $config->getIPostConfig->{customerpass},
            }
        },
        attachments => [
            {
                attachmentId => $param{'file_id'}
            }
        ]
    };

    $paperMail->{'printingAndEnvelopingService'}->{'costPool'} = $costPool if $costPool;

    my $electronic = {
        title => $param{'subject'},
        body => $param{'content'},
        bodyFormat => 'Text',
        visibility => 'Normal',
        'replyAllowedBy' => "No one", # No reply allowed
        'messageServiceType' => 'Normal',
        'notifications' => {
            'customisedNewMessageNotification' => {
                'title' => {
                    'fi' => 'Uusi viesti kirjastosta',
                    'sv' => 'Ett nytt meddelande från biblioteket',
                    'en' => 'New message from the library'
                },
                'content' => {
                    'fi' => $param{'subject'},
                    'sv' => $param{'subject'},
                    'en' => $param{'subject'}
                },
            },
            'unreadMessageNotification' => {
                'reminder' => 'No reminders'
            },
            'senderDetailsInNotifications' => 'Organisation and service name'
        },
        'attachments' => [{
            attachmentId => $param{'file_id'}
        }]
    };

    my $format_message;

    if ($id) {
        $format_message->{recipient}->{id} = $id;
        $format_message->{electronic} = $electronic;
    } 
    
    $format_message->{'paperMail'} = $paperMail;
    $format_message->{sender}->{serviceId} = $config->getRESTConfig->{serviceid};
    $format_message->{externalId} = "$param{'message_id'}";
    return $format_message;
}
