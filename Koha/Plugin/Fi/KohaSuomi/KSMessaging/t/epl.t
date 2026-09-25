#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::MockModule;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::EPL;

my $EPLClass = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::EPL';
my $epl_cfg;

my $epl_mock = Test::MockModule->new($EPLClass);
$epl_mock->mock( '_epl_config', sub { return $epl_cfg } );

sub _epl {
    my ( $name, @args ) = @_;
    return $EPLClass->can($name)->(@args);
}

subtest 'hdiacritic' => sub {
    local $SIG{__WARN__} = sub {};
    is( _epl('hdiacritic', 'Ʒʒßʻ€'), 'ZzB\'e', 'explicit character mappings applied' );
    is( _epl('hdiacritic', 'ÅåÄäÖöÉéÜüÁá abc XYZ 0123'), 'ÅåÄäÖöÉéÜüÁá abc XYZ 0123',
        'allowlisted characters preserved' );
    is( _epl('hdiacritic', 'ñàøi'), 'naoi', 'accented characters unaccented' );
    is( _epl('hdiacritic', 'a.b, c!?'), 'a.b, c!?', 'punctuation preserved' );
};

subtest 'fixZip' => sub {
    is( _epl('fixZip', '00100'),     'FI00100',    'Finnish zip prefixed with FI' );
    is( _epl('fixZip', '00100-123'), 'FI00100123', 'dash stripped from Finnish zip' );
    is( _epl('fixZip', 'FI00100'),   'FI00100',    'already prefixed zip unchanged' );
    is( _epl('fixZip', 'SE-123'),    'SE123',      'non-digit zip has dash stripped, no FI prefix' );
    is( _epl('fixZip', ''),          '',           'empty zip returns empty' );
};

subtest 'letterHeader' => sub {
    $epl_cfg = { code => 'SOME', layout => { templatecode => 'TPL9' } };
    my $expected = "EPLKFI00100   100                       SOME\r\n"
                 . "10                                            Reminder\r\n"
                 . " 0                                            23.09.2026\r\n"
                 . "TPL9\r\n";
    is(
        _epl( 'letterHeader', zipcode => '00100', subject => 'Reminder', date => '23.09.2026' ),
        $expected,
        'letterHeader format is exactly as expected'
    );
};

subtest 'letterRecipient' => sub {
    my $expected = "20John Doe\r\n"
                 . " 0Main 1\r\n"
                 . " 000100 Helsinki\r\n"
                 . " 0Finland\r\n";
    is(
        _epl( 'letterRecipient', firstname => 'John', surname => 'Doe', address => 'Main 1',
            zipcode => '00100', city => 'Helsinki', country => 'Finland' ),
        $expected,
        'letterRecipient format is exactly as expected'
    );
};

subtest 'letterBody without continuation code' => sub {
    $epl_cfg = { layout => { contpagecode => '', firstpage => 3, otherpages => 2 } };
    is( _epl( 'letterBody', content => "L1\r\nL2\nL3" ),
        "30L1\r\n 0L2\r\n 0L3\r\n",
        'first line prefixed with 30, rest with 0' );
};

subtest 'letterBody with continuation code' => sub {
    $epl_cfg = { layout => { contpagecode => 'CONT', firstpage => 3, otherpages => 2 } };
    my $expected = "30L1\r\n 0L2\r\n10\r\nCONT\r\n"
                 . " 0L3\r\n10\r\nCONT\r\n"
                 . " 0L4\r\n10\r\nCONT\r\n"
                 . " 0L5\r\n10\r\nCONT\r\n";
    is( _epl( 'letterBody', content => "L1\nL2\nL3\nL4\nL5" ), $expected,
        'page breaks inserted at firstpage/otherpages thresholds' );
};

done_testing;