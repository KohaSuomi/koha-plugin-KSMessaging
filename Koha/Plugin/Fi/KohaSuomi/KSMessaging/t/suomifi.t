#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::MockModule;
use Test::MockObject;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

BEGIN {
    $INC{'Koha/Plugin/Fi/KohaSuomi/SsnProvider/Modules/Database.pm'} = 'mocked';
    package Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database;
    our $mocked_ssn;
    sub new { bless {}, shift }
    sub getSSNByBorrowerNumber { return $mocked_ssn }
}

use Koha::Patrons;
use Koha::Libraries;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::SuomiFi qw(RESTMessage);

my $SuomiFiClass  = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::SuomiFi';
my $ConfigClass   = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config';
my $SsnProviderDb = 'Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database';

subtest 'FormatDescription' => sub {
    is( &{ $SuomiFiClass->can('FormatDescription') }("a\r\nb"), "a\nb", 'CRLF converted to LF' );
    is( &{ $SuomiFiClass->can('FormatDescription') }("a<b>c"),   'a&lt;b&gt;c', 'angle brackets escaped' );
    is( &{ $SuomiFiClass->can('FormatDescription') }("ok\r\n<b>"), "ok\n&lt;b&gt;", 'mixed conversion' );
};

subtest 'RESTMessage' => sub {
    my $borrower = Test::MockObject->new;
    $borrower->mock( firstname => sub { 'Jane' } );
    $borrower->mock( surname   => sub { 'Doe' } );
    $borrower->mock( address   => sub { 'Main 1' } );
    $borrower->mock( zipcode   => sub { '00100' } );
    $borrower->mock( city      => sub { 'Helsinki' } );
    $borrower->mock( country   => sub { 'Finland' } );

    my $branch = Test::MockObject->new;
    $branch->mock( branchname     => sub { 'Kirjasto' } );
    $branch->mock( branchaddress1 => sub { 'Katu 1' } );
    $branch->mock( branchzip      => sub { '00100' } );
    $branch->mock( branchcity     => sub { 'Helsinki' } );
    $branch->mock( branchcountry  => sub { 'Finland' } );

    my $patrons_mock  = Test::MockModule->new('Koha::Patrons');
    my $libraries_mock = Test::MockModule->new('Koha::Libraries');
    $patrons_mock->mock( 'find',   sub { return $borrower } );
    $libraries_mock->mock( 'find', sub { return $branch } );

    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( contact           => sub { return 'mail@x.fi' } );
    $config_mock->mock( getIPostConfig    => sub { return { customerid => 'CID', customerpass => 'CPASS' } } );
    $config_mock->mock( getRESTConfig     => sub { return { serviceid => 'svc' } } );
    $config_mock->mock( getSuomiFiCostPool => sub { return 'KL001' } );

    my %message = (
        borrowernumber => 42,
        branchcode     => 'CPL',
        branchconfig   => 'default',
        subject        => 'Hei',
        content        => 'Viesti sisalto',
        message_id     => 77,
        file_id        => 'ATT1',
    );

    $Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database::mocked_ssn = '010180-123Y';

    my $msg = RESTMessage(%message);
    is( $msg->{sender}->{serviceId}, 'svc', 'sender.serviceId from REST config' );
    is( $msg->{externalId}, '77',   'externalId is the message_id' );
    is( $msg->{recipient}->{id}, '010180-123Y', 'recipient.id from SSN lookup' );
    ok( $msg->{electronic}, 'electronic present when recipient id found' );
    is( $msg->{electronic}->{title},     'Hei',          'electronic title' );
    is( $msg->{electronic}->{body},      'Viesti sisalto', 'electronic body' );
    is( $msg->{electronic}->{bodyFormat}, 'Text',         'electronic bodyFormat' );
    is( $msg->{electronic}->{attachments}->[0]->{attachmentId}, 'ATT1', 'electronic attachment id' );

    is( $msg->{paperMail}->{sender}->{address}->{name},        'Kirjasto', 'paperMail sender name from branch' );
    is( $msg->{paperMail}->{sender}->{address}->{countryCode}, 'FI',       'paperMail sender country defaults to FI' );
    is( $msg->{paperMail}->{recipient}->{address}->{name},     'Jane Doe', 'paperMail recipient name' );
    is( $msg->{paperMail}->{recipient}->{address}->{countryCode}, 'FI', 'paperMail recipient country' );
    is( $msg->{paperMail}->{printingAndEnvelopingService}->{postiMessaging}->{username}, 'CID',   'postiMessaging username' );
    is( $msg->{paperMail}->{printingAndEnvelopingService}->{postiMessaging}->{password}, 'CPASS', 'postiMessaging password' );
    is( $msg->{paperMail}->{printingAndEnvelopingService}->{postiMessaging}->{contactDetails}->{email}, 'mail@x.fi',
        'postiMessaging contact email' );
    is( $msg->{paperMail}->{printingAndEnvelopingService}->{costPool}, 'KL001', 'costPool included when configured' );
    is( $msg->{paperMail}->{attachments}->[0]->{attachmentId}, 'ATT1', 'paperMail attachment id' );

    $config_mock->mock( getSuomiFiCostPool => sub { return undef } );
    my $msg_no_cost = RESTMessage(%message);
    ok( !exists $msg_no_cost->{paperMail}->{printingAndEnvelopingService}->{costPool},
        'costPool omitted when not configured' );
};

subtest 'RESTMessage without SSN' => sub {
    my $borrower = Test::MockObject->new;
    $borrower->mock( firstname => sub { 'Jane' } );
    $borrower->mock( surname   => sub { 'Doe' } );
    $borrower->mock( address   => sub { 'Main 1' } );
    $borrower->mock( zipcode   => sub { '00100' } );
    $borrower->mock( city      => sub { 'Helsinki' } );
    $borrower->mock( country   => sub { 'Finland' } );

    my $branch = Test::MockObject->new;
    $branch->mock( branchname     => sub { 'Kirjasto' } );
    $branch->mock( branchaddress1 => sub { 'Katu 1' } );
    $branch->mock( branchzip      => sub { '00100' } );
    $branch->mock( branchcity     => sub { 'Helsinki' } );
    $branch->mock( branchcountry  => sub { 'Finland' } );

    my $patrons_mock  = Test::MockModule->new('Koha::Patrons');
    my $libraries_mock = Test::MockModule->new('Koha::Libraries');
    $patrons_mock->mock( 'find',   sub { return $borrower } );
    $libraries_mock->mock( 'find', sub { return $branch } );

    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( contact           => sub { return 'mail@x.fi' } );
    $config_mock->mock( getIPostConfig    => sub { return { customerid => 'CID', customerpass => 'CPASS' } } );
    $config_mock->mock( getRESTConfig     => sub { return { serviceid => 'svc' } } );
    $config_mock->mock( getSuomiFiCostPool => sub { return undef } );

    $Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database::mocked_ssn = undef;

    my %message = (
        borrowernumber => 42,
        branchcode     => 'CPL',
        branchconfig   => 'default',
        subject        => 'Hei',
        content        => 'Viesti sisalto',
        message_id     => 88,
        file_id        => 'ATT2',
    );

    my $msg = RESTMessage(%message);
    ok( !exists $msg->{recipient},       'no recipient when no SSN' );
    ok( !exists $msg->{electronic},      'no electronic when no SSN' );
    ok( $msg->{paperMail},               'paperMail still present' );

    my $msg_with_id = RESTMessage( %message, id => 'ABC123' );
    is( $msg_with_id->{recipient}->{id}, 'ABC123', 'fallback id used when SSN lookup empty' );
    ok( $msg_with_id->{electronic}, 'electronic present with fallback id' );
};

done_testing;