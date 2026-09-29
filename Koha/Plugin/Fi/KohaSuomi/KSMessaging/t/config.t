#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::MockModule;
use File::Slurp;
use Template;
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

subtest 'save validation' => sub {
    my @stored;
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock(
        '_store_plugin_data',
        sub { my ( $self, $key, $value ) = @_; push @stored, { key => $key, value => $value } }
    );

    my $config = $ConfigClass->new( {} );

    is( $config->save( { config => "a: 1\nb: 2" } ), 1, 'flat mapping is accepted' );
    is( $config->save( { config => "suomifi:\n  branches:\n    default:\n      stagingdir: /tmp/x\n" } ),
        1, 'nested mapping is accepted' );

    is( $config->save( { config => "- a\n- b" } ),  0, 'valid YAML sequence is rejected' );
    is( $config->save( { config => 'just a string' } ), 0, 'valid YAML scalar is rejected' );
    is( $config->save( { config => "   \n" } ),         0, 'whitespace-only config is rejected' );
    is( $config->save( { config => "# comment only\n" } ), 0, 'comment-only config is rejected' );
    is( $config->save( { config => "foo: [broken" } ),  0, 'invalid YAML is rejected' );
    is( $config->save( { config => "\tfoo: bar" } ),     0, 'tab-indented YAML is rejected' );
    is( $config->save( { config => "a: 1\n b: 2" } ),    0, 'badly indented YAML is rejected' );

    @stored = ();
    $config->save( { config => "- a\n- b" } );
    is( scalar @stored, 0, 'nothing stored when the YAML is the wrong shape' );

    @stored = ();
    $config->save( { config => "a: 1" } );
    is( scalar @stored, 1, 'accepted mapping is still stored' );
};

subtest 'save error reasons' => sub {
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock( '_store_plugin_data', sub { return 1 } );

    my $config = $ConfigClass->new( {} );

    is( $config->save( { config => "a: 1" } ), 1, 'valid mapping is saved' );
    is( $config->last_save_error, undef, 'no error recorded after a successful save' );

    is( $config->save( { config => '' } ), 0, 'empty config is rejected' );
    is( $config->last_save_error, 'empty', 'empty config reports the empty reason' );

    is( $config->save( { config => "foo: [broken" } ), 0, 'unparseable YAML is rejected' );
    is( $config->last_save_error, 'invalid_yaml', 'unparseable YAML reports the invalid_yaml reason' );

    is( $config->save( { config => "- a\n- b" } ), 0, 'YAML sequence is rejected' );
    is( $config->last_save_error, 'not_a_mapping', 'YAML sequence reports the not_a_mapping reason' );

    is( $config->save( { config => 'plain scalar' } ), 0, 'YAML scalar is rejected' );
    is( $config->last_save_error, 'not_a_mapping', 'YAML scalar reports the not_a_mapping reason' );
};

subtest 'i18n keys used by the configure page exist in every language file' => sub {
    my $tt = read_file("$Bin/../config.tt");
    my $pm = read_file("$Bin/../../KSMessaging.pm");

    # Collect the keys the template and the plugin reference.  The template
    # looks most of them up dynamically via T.${message.key}, so scanning the
    # source is the only way to catch a key that no language file defines.
    my %keys;
    $keys{$1} = 1 while $tt =~ /T\.config_(\d+)/g;
    $keys{$1} = 1 while $pm =~ /'(config_\d+)'/g;

    ok( scalar keys %keys, 'the configure page references i18n keys' );

    for my $lang (qw(default.inc fi-FI.inc sv-SE.inc)) {
        my $inc = read_file("$Bin/../i18n/$lang");
        for my $key ( sort keys %keys ) {
            like( $inc, qr/\Q$key\E\s*=/, "$lang defines $key" );
        }
    }
};

subtest 'configure page renders translated messages' => sub {

    # The dynamic lookup T.${message.key} is easy to write as T.$message.key,
    # which Template parses as a single variable and renders as an EMPTY div.
    # That failure is silent, so render the real blocks and insist on text.
    my $tt = read_file("$Bin/../config.tt");
    my ($saved_block) = $tt =~ /(\[% IF saved %\].*?\[% END %\])/s;
    my ($msg_block)   = $tt =~ /(\[% FOREACH message IN messages %\].*?\[% END %\])/s;
    ok( $saved_block, 'config.tt has a success block' );
    ok( $msg_block,   'config.tt has a messages block' );

    my $block = $saved_block . "\n" . $msg_block;

    for my $lang (qw(default fi-FI sv-SE)) {
        my $snippet = read_file("$Bin/../i18n/$lang.inc") . "\n" . $block;

        for my $key (qw(config_12 config_13 config_14 config_15 config_16)) {
            my $out = '';
            my $tpl = Template->new;
            $tpl->process(
                \$snippet,
                {   saved   => 0,
                    messages => [ { type => 'error', alert_class => 'danger', key => $key } ],
                },
                \$out
            ) or die $tpl->error;

            my ($text) = $out =~ m{<div class="alert alert-danger[^"]*">(.*?)</div>}s;
            $text = '' unless defined $text;

            ok( length $text, "$lang renders text for $key" );
            isnt( $text, $key, "$lang does not fall back to the bare key $key" );
        }

        my $out = '';
        my $tpl = Template->new;
        $tpl->process( \$snippet, { saved => 1, messages => [] }, \$out ) or die $tpl->error;
        my ($text) = $out =~ m{<div class="alert alert-success[^"]*">(.*?)</div>}s;
        ok( length( $text // '' ), "$lang renders the success message" );
    }
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