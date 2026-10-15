#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::MockModule;
use Test::MockObject;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

use XML::LibXML;
use Koha::Patrons;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::DispatchXML qw(DispatchXML);

my $DispatchXML = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::DispatchXML';
my $ConfigClass = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config';
my $ipost_ns    = 'urn:itella.com:/schema/ipost/letterbundle/v1x0';

subtest '_escape_value' => sub {
    my $escape = \&{ $DispatchXML->can('_escape_value') };

    is( $escape->('Jane'),              'Jane',             'plain value is untouched' );
    is( $escape->(undef),               '',                 'undefined value becomes an empty string' );
    is( $escape->(''),                  '',                 'empty value stays empty' );
    is( $escape->('a & b'),             'a &amp; b',       'ampersand escaped' );
    is( $escape->('<x>'),               '&lt;x&gt;',        'angle brackets escaped' );
    is( $escape->('O"Brien'),           'O&quot;Brien',    'double quote escaped' );
    is( $escape->('a &amp; b'),         'a &amp;amp; b',   'ampersand of an entity is escaped as well' );

    is( $escape->("Bj\x{f6}rk"),        'Bj&#xF6;rk',      'latin 1 character as a character reference' );
    is( $escape->("20\x{20ac}"),       '20&#x20AC;',      'euro sign as a character reference' );
    is( $escape->("a\tb"),              'a&#9;b',          'tab as a character reference' );
    is( $escape->("a\nb"),              'a&#10;b',         'newline as a character reference' );
    is( $escape->("a\x{0}b\x{7}"),      'ab',              'characters XML 1.0 forbids are dropped' );
};

subtest 'DispatchXML' => sub {
    my $borrower = Test::MockObject->new;
    $borrower->mock( firstname => sub { 'Maija & "Malla" <3' } );
    $borrower->mock( surname   => sub { "O'Brien Bj\x{f6}rk" } );
    $borrower->mock( address   => sub { 'Katu 5 & 6 "B", 20€' } );
    $borrower->mock( zipcode   => sub { '00100' } );
    $borrower->mock( city      => sub { 'Helsinki' } );

    my $config = Test::MockObject->new;
    $config->mock( contact => sub { 'kirjasto@kissa.fi & co' } );
    $config->mock(
        getIPostConfig => sub {
            return {
                customerid   => 'CID&3',
                customerpass => 'p"a&ss',
                ovtid        => 'OVT/2',
                senderid     => 'SENDER-1',
            };
        }
    );

    my $patrons_mock = Test::MockModule->new('Koha::Patrons');
    $patrons_mock->mock( 'find', sub { return $borrower } );

    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( 'new', sub { return $config } );

    my $xml = DispatchXML(
        interface      => 'letters',
        branchconfig   => 'default',
        borrowernumber => 42,
        SSN            => '010180-123Y',
        filename       => 'letter-77.pdf',
        letterid       => 77,
        subject        => 'Maksuhuomautus: kirjanpito & laskutus <kautta>',
        totalpages     => 2,
    );

    # Every value lands in a double quoted attribute of an iso-8859-1 document,
    # so the whole file has to stay inside ASCII to survive the declaration.
    ok( $xml !~ /[^\x00-\x7F]/, 'dispatch XML is ASCII only' );

    my $document = eval { XML::LibXML->new->load_xml( string => $xml ) };
    ok( $document, 'dispatch XML parses' ) or diag($@);
    return unless $document;

    my $attribute = sub {
        my ($element_name) = @_;
        my ($element) = $document->getElementsByTagNameNS( $ipost_ns, $element_name );
        return $element;
    };

    my $sender = $attribute->('Sender');
    is( $sender->getAttribute('contact'),    'kirjasto@kissa.fi & co', 'sender contact round trips' );
    is( $sender->getAttribute('email'),      'kirjasto@kissa.fi & co', 'sender email round trips' );
    is( $sender->getAttribute('ovtID'),      'OVT/2',                  'sender ovtID round trips' );
    is( $sender->getAttribute('companyName'), 'SENDER-1',               'sender companyName round trips' );

    my $processing = $attribute->('StdBundleProcessing');
    is( $processing->getAttribute('customerId'), 'CID&3',  'customerId round trips' );
    is( $processing->getAttribute('password'),   'p"a&ss', 'customer password with a quote round trips' );

    my $external_file = $attribute->('ExternalFile');
    is( $external_file->getAttribute('senderFileId'), '77',              'senderFileId round trips' );
    is( $external_file->getAttribute('fileName'),     'letter-77.pdf',   'fileName round trips' );

    my $letter = $attribute->('Letter');
    is( $letter->getAttribute('senderLetterId'), '77', 'letter id round trips' );

    my $location = $attribute->('Location');
    is( $location->getAttribute('pages'), '2', 'page count round trips' );

    my $recipient = $attribute->('Recipient');
    is( $recipient->getAttribute('SSN'), '010180-123Y', 'SSN round trips' );

    my $address = $attribute->('Eu1');
    is( $address->getAttribute('name'), "Maija & \"Malla\" <3 O'Brien Bj\x{f6}rk",
        'recipient name round trips' );
    is( $address->getAttribute('address'),    "Katu 5 & 6 \"B\", 20\x{20ac} ", 'recipient address round trips' );
    is( $address->getAttribute('postalCode'), '00100',                'postal code round trips' );
    is( $address->getAttribute('city'),       'Helsinki',             'city round trips' );
    is( $address->getAttribute('countryCode'), 'FI',                  'country code unchanged' );

    my $subject = $attribute->('Subject');
    is( $subject->getAttribute('text'), 'Maksuhuomautus: kirjanpito & laskutus <kautta>',
        'subject with markup characters round trips' );
};

subtest 'DispatchXML with missing values' => sub {
    my $borrower = Test::MockObject->new;
    $borrower->mock( firstname => sub { 'Jane' } );
    $borrower->mock( surname   => sub { 'Doe' } );
    $borrower->mock( address   => sub { undef } );
    $borrower->mock( zipcode   => sub { undef } );
    $borrower->mock( city      => sub { undef } );

    my $config = Test::MockObject->new;
    $config->mock( contact => sub { undef } );
    $config->mock( getIPostConfig => sub { return {} } );

    my $patrons_mock = Test::MockModule->new('Koha::Patrons');
    $patrons_mock->mock( 'find', sub { return $borrower } );

    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( 'new', sub { return $config } );

    my $xml = DispatchXML(
        interface      => 'letters',
        branchconfig   => 'default',
        borrowernumber => 43,
        SSN            => undef,
        filename       => 'letter-78.pdf',
        letterid       => 78,
        subject        => undef,
        totalpages     => 1,
    );

    my $document = eval { XML::LibXML->new->load_xml( string => $xml ) };
    ok( $document, 'dispatch XML with empty values parses' ) or diag($@);
    return unless $document;

    my ($address) = $document->getElementsByTagNameNS( $ipost_ns, 'Eu1' );
    is( $address->getAttribute('address'),    ' ', 'missing address and address2 render as the space between them' );
    is( $address->getAttribute('postalCode'), '',    'missing zipcode renders empty' );
    is( $address->getAttribute('city'),       '',    'missing city renders empty' );

    my ($recipient) = $document->getElementsByTagNameNS( $ipost_ns, 'Recipient' );
    is( $recipient->getAttribute('SSN'), '', 'missing SSN renders empty' );

    my ($subject) = $document->getElementsByTagNameNS( $ipost_ns, 'Subject' );
    is( $subject->getAttribute('text'), '', 'missing subject renders empty' );
};

done_testing;