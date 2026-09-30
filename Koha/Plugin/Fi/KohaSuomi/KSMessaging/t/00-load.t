#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

BEGIN {
    $INC{'Koha/Plugin/Fi/KohaSuomi/SsnProvider/Modules/Database.pm'} = 'mocked';
    package Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database;
    sub new { bless {}, shift }
    sub getSSNByBorrowerNumber { return undef }
}

my @modules = qw(
    Koha::Plugin::Fi::KohaSuomi::KSMessaging
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Setup
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::SendMessages
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::CreateLetters
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::EPL
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::PDF
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::SuomiFi
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::File
    Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::DispatchXML
);

plan tests => scalar @modules;

use_ok($_) for @modules;

diag("Testing KSMessaging plugin modules, Perl $], $^X");