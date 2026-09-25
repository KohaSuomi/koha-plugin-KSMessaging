#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::MockModule;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;

my $ConfigClass = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config';

subtest 'new / accessors' => sub {
    my $config = $ConfigClass->new( {} );
    is( $config->interface, 'suomifi', 'default interface is suomifi' );
    is( $config->branch,    'default', 'default branch is default' );

    my $cfg = $ConfigClass->new( { interface => 'letters', branch => 'lib1' } );
    is( $cfg->interface, 'letters', 'interface set from params' );
    is( $cfg->branch,    'lib1',    'branch set from params' );
};

subtest 'countryCode' => sub {
    my $config = $ConfigClass->new( {} );
    foreach my $t ( [ 'Sverige', 'SE' ], [ 'ruotsi', 'SE' ], [ 'SWEDEN', 'SE' ],
        [ 'Norge', 'NO' ], [ 'norja', 'NO' ], [ 'norway', 'NO' ],
        [ 'Danmark', 'DK' ], [ 'tanska', 'DK' ], [ 'denmark', 'DK' ] ) {
        is( $config->countryCode( $t->[0] ), $t->[1], "countryCode($t->[0]) -> $t->[1]" );
    }
    is( $config->countryCode('Finland'), 'FI', 'unknown country defaults to FI' );
    is( $config->countryCode(undef),    'FI', 'undef country defaults to FI' );
    is( $config->countryCode('  Sweden '), 'SE', 'leading/trailing whitespace is trimmed' );
};

subtest 'rootConfig / branchConfig fallback' => sub {
    my $fixture = {
        suomifi => {
            branches => {
                default => { stagingdir => '/tmp/default', contact => 'c@x.fi', cachekey => 'tok' },
                lib1    => { stagingdir => '/tmp/lib1' },
            },
        },
    };

    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock( '_load_config', sub { return $fixture } );

    my $cfg = $ConfigClass->new( { interface => 'suomifi', branch => 'lib1' } );
    is( $cfg->rootConfig->{stagingdir}, '/tmp/lib1', 'branch-specific config returned' );
    is( $cfg->branchConfig, 'lib1', 'branchConfig returns real branch' );
    is( $cfg->stagingDir,   '/tmp/lib1', 'stagingDir from branch config' );

    my $fallback = $ConfigClass->new( { interface => 'suomifi', branch => 'nope' } );
    is( $fallback->rootConfig->{stagingdir}, '/tmp/default', 'unknown branch falls back to default' );
    is( $fallback->branchConfig, 'default', 'branchConfig returns default' );
    is( $fallback->contact,      'c@x.fi',  'contact from default branch' );
    is( $fallback->cacheKey,     'tok',     'cacheKey from default branch' );
};

subtest 'skipletters / combineacrossbranches' => sub {
    my $fixture = {
        letters => { skipletters => 1, combineacrossbranches => 0 },
    };
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock( '_load_config', sub { return $fixture } );

    my $cfg = $ConfigClass->new( {} );
    is( $cfg->skipletters,          1, 'skipletters read from letters section' );
    is( $cfg->combineacrossbranches, 0, 'combineacrossbranches read from letters section' );
};

subtest 'getRESTConfig / getIPostConfig / getFileTransferConfig' => sub {
    my $fixture = {
        suomifi => {
            branches => {
                default => {
                    'rest'         => { baseUrl => 'https://api.example/', username => 'u', password => 'p', serviceid => 'svc' },
                    'ipostpdf'     => { customerid => 'cid', customerpass => 'cpass', ovtid => 'ovt', senderid => 'sid', printprovider => 'pp', fileprefix => 'fp' },
                    'filetransfer' => { host => 'h', port => 22, remotedir => 'r', user => 'fuser', password => 'fpass', protocol => 'sftp' },
                },
            },
        },
    };
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock( '_load_config',          sub { return $fixture } );
    $mock->mock( '_load_plugin_password', sub { return undef } );

    my $cfg = $ConfigClass->new( {} );
    my $rest = $cfg->getRESTConfig;
    is( $rest->{baseUrl},   'https://api.example/', 'rest baseUrl' );
    is( $rest->{username},  'u',    'rest username' );
    is( $rest->{password},  'p',    'rest password falls back to config' );
    is( $rest->{serviceid}, 'svc',  'rest serviceid' );

    $mock->mock( '_load_plugin_password', sub { return 'stored' } );
    is( $cfg->getRESTConfig->{password}, 'stored', 'rest password overlaid from plugin_data' );

    my $ipost = $cfg->getIPostConfig;
    is( $ipost->{customerid},    'cid',   'ipost customerid' );
    is( $ipost->{customerpass},  'cpass', 'ipost customerpass' );
    is( $ipost->{ovtid},         'ovt',   'ipost ovtid' );
    is( $ipost->{senderid},      'sid',   'ipost senderid' );
    is( $ipost->{printprovider}, 'pp',    'ipost printprovider' );
    is( $ipost->{fileprefix},    'fp',    'ipost fileprefix' );

    my $transfer = $cfg->getFileTransferConfig;
    is( $transfer->{host},      'h',     'filetransfer host' );
    is( $transfer->{port},      22,      'filetransfer port' );
    is( $transfer->{remotedir}, 'r',     'filetransfer remotedir' );
    is( $transfer->{user},      'fuser', 'filetransfer user' );
    is( $transfer->{password},  'fpass', 'filetransfer password' );
    is( $transfer->{protocol},  'sftp',  'filetransfer protocol' );
};

subtest 'save' => sub {
    my @stored;
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock(
        '_store_plugin_data',
        sub { my ( $self, $key, $value ) = @_; push @stored, { key => $key, value => $value } }
    );

    my $config = $ConfigClass->new( {} );

    is( $config->save( {} ), 0, 'empty config returns 0' );
    is( $config->save( { config => "foo: [broken" } ), 0, 'invalid YAML returns 0 (unterminated sequence)' );
    is( $config->save( { config => "\tfoo: bar" } ), 0, 'invalid YAML returns 0 (tab indent)' );
    is( scalar @stored, 0, 'nothing stored on failure' );

    ok( $config->save( { config => "a: 1\nb: 2" } ), 'valid YAML saves ok' );
    is( scalar @stored, 1, 'one store call for config' );
    is( $stored[0]->{key}, 'ksmessaging_config', 'stores under ksmessaging_config' );
    is( $stored[0]->{value}, "a: 1\nb: 2", 'stores the config text' );

    @stored = ();
    ok( $config->save( { config => "a: 1", password => 'secret' } ), 'valid YAML with password saves' );
    is( scalar @stored, 2, 'two store calls with password' );
    is( $stored[1]->{key}, 'suomifi_rest_password', 'password stored under suomifi_rest_password' );
    is( $stored[1]->{value}, 'secret', 'password value stored' );
};

subtest 'save via CGI object' => sub {
    {
        package CGI;
        sub param { my ( $self, $key ) = @_; return $self->{$key}; }
    }

    my @stored;
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock(
        '_store_plugin_data',
        sub { my ( $self, $key, $value ) = @_; push @stored, { key => $key, value => $value } }
    );

    my $config  = $ConfigClass->new( {} );
    my $fake_cgi = bless { config => "a: 1", password => 'pw' }, 'CGI';
    ok( $config->save($fake_cgi), 'CGI object saved' );
    is( $stored[0]->{key},   'ksmessaging_config',    'CGI branch stores config' );
    is( $stored[1]->{key},   'suomifi_rest_password', 'CGI branch stores password' );
    is( $stored[0]->{value}, "a: 1",                  'CGI branch config value' );
};

subtest 'getSuomiFiAltSender' => sub {
    my $pref;
    my $context_mock = Test::MockModule->new('C4::Context');
    $context_mock->mock( 'preference', sub { return $pref } );

    my $config = $ConfigClass->new( { branch => 'lib1' } );

    $pref = undef;
    is( $config->getSuomiFiAltSender('fi'), undef, 'undef preference returns undef' );

    $pref = "fi:\n  lib1: \"Kirjasto A\"\n  default: \"Kirjasto D\"\nen:\n  lib1: \"Library E\"\n";
    is( $config->getSuomiFiAltSender('fi'), 'Kirjasto A', 'language section + branch match' );

    $pref = "lib1: \"Direct\"\ndefault: \"Def\"\n";
    is( $config->getSuomiFiAltSender(undef), 'Direct', 'direct branch section match without lang' );

    $pref = "default: \"Def\"\n";
    is( $config->getSuomiFiAltSender('fi'), 'Def', 'default section fallback' );

    local *STDOUT;
    open STDOUT, '>', '/dev/null' or die $!;
    $pref = "foo: [broken";
    is( $config->getSuomiFiAltSender('fi'), undef, 'invalid YAML returns undef' );

    $pref = "- just\n- a\n- list\n";
    is( $config->getSuomiFiAltSender('fi'), undef, 'non-hash YAML returns undef' );

    $pref = "other: 1\n";
    is( $config->getSuomiFiAltSender('fi'), undef, 'no matching branch returns undef' );
};

subtest 'getSuomiFiCostPool' => sub {
    my $pref;
    my $context_mock = Test::MockModule->new('C4::Context');
    $context_mock->mock( 'preference', sub { return $pref } );

    my $config = $ConfigClass->new( { branch => 'lib1' } );

    $pref = undef;
    is( $config->getSuomiFiCostPool, undef, 'undef preference returns undef' );

    $pref = "lib1: KL001\n";
    is( $config->getSuomiFiCostPool, 'KL001', 'valid cost pool returned' );

    $pref = "lib1: bad value\n";
    is( $config->getSuomiFiCostPool, undef, 'invalid cost pool value returns undef' );

    $pref = "lib1: 123ABC\n";
    is( $config->getSuomiFiCostPool, '123ABC', 'numeric cost pool returned' );

    $pref = "other: KL099\n";
    is( $config->getSuomiFiCostPool, undef, 'no matching branch returns undef' );

    local *STDOUT;
    open STDOUT, '>', '/dev/null' or die $!;
    $pref = "foo: [broken";
    is( $config->getSuomiFiCostPool, undef, 'invalid YAML returns undef' );
};

subtest 'load_for_configure' => sub {
    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( '_load_plugin_config',   sub { return "config:\n  a: 1\n" } );
    $config_mock->mock( '_load_plugin_password', sub { return 'displaypw' } );

    my $config = $ConfigClass->new( {} );
    $config->load_for_configure;
    is( $config->loadedConfigForDisplay,   "config:\n  a: 1\n", 'config exposed for display' );
    is( $config->loadedPasswordForDisplay, 'displaypw',         'password exposed for display' );
};

done_testing;