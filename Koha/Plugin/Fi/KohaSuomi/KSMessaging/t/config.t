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
    is( scalar @stored, 3, 'one store call per configuration' );
    is( $stored[0]->{key}, 'ksmessaging_config', 'stores under ksmessaging_config' );
    is( $stored[0]->{value}, "a: 1\nb: 2", 'stores the config text' );
    is( $stored[1]->{key}, 'suomifi_alt_sender', 'alt sender stored under its own key' );
    is( $stored[2]->{key}, 'suomifi_cost_pool',  'cost pool stored under its own key' );
    is( $stored[1]->{value}, '', 'a blank alt sender is stored as an empty string' );
    is( $stored[2]->{value}, '', 'a blank cost pool is stored as an empty string' );

    @stored = ();
    ok( $config->save( { config => "a: 1", password => 'secret' } ), 'config with an extra password argument saves' );

    # save() deliberately ignores a password.  It is owned by the
    # change-suomifi-password cronjob through store_password(), and keeping it
    # out of the stored config stops it being echoed back in the plaintext
    # textarea that the configure form renders.
    is( scalar @stored, 3, 'the three configurations are stored and the password is not among them' );
    is( $stored[0]->{key},   'ksmessaging_config', 'still stored under ksmessaging_config' );
    is( $stored[0]->{value}, "a: 1",               'stored config text is unaffected by the password' );

    @stored = ();
    ok( $config->save( { config => "a: 1", suomifi_alt_sender => "fi-FI:\n  KOHAPK:\n    - Kirjasto\n", suomifi_cost_pool => "KOHAPK: KL001\n" } ),
        'alt sender and cost pool save ok' );
    is( scalar @stored, 3, 'all three configurations stored' );
    is( $stored[1]->{value}, "fi-FI:\n  KOHAPK:\n    - Kirjasto\n", 'alt sender text stored verbatim' );
    is( $stored[2]->{value}, "KOHAPK: KL001\n", 'cost pool text stored verbatim' );
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
    is( $stored[0]->{key},   'ksmessaging_config', 'CGI branch stores config' );
    is( $stored[0]->{value}, "a: 1",               'CGI branch config value' );
    is( scalar @stored, 3, 'CGI branch also stores the two SuomiFi configurations' );
    is( $stored[1]->{key}, 'suomifi_alt_sender', 'CGI branch stores the alt sender' );
    is( $stored[2]->{key}, 'suomifi_cost_pool',  'CGI branch stores the cost pool' );
    is( $stored[1]->{value}, '', 'an absent alt sender parameter stores an empty string' );
    is( $stored[2]->{value}, '', 'an absent cost pool parameter stores an empty string' );

    @stored = ();
    my $full_cgi = bless { config => "a: 1", suomifi_alt_sender => "fi-FI:\n  KOHAPK:\n    - Kirjasto\n", suomifi_cost_pool => "KOHAPK: KL001\n" }, 'CGI';
    ok( $config->save($full_cgi), 'CGI object carrying the SuomiFi fields saved' );
    is( scalar @stored, 3, 'all three configurations stored from CGI' );
    is( $stored[1]->{value}, "fi-FI:\n  KOHAPK:\n    - Kirjasto\n", 'CGI alt sender value' );
    is( $stored[2]->{value}, "KOHAPK: KL001\n", 'CGI cost pool value' );
};

subtest 'REST password is stored separately from the config' => sub {
    my $config = $ConfigClass->new( {branch => 'default'} );

    # store_password is reached only from the change-suomifi-password cronjob.
    # It refuses empty input before ever touching the database.
    is( $config->store_password(undef), 0, 'undef password is not stored' );
    is( $config->store_password(''),    0, 'empty password is not stored' );

    my $stored_password = 'secret';
    my @requested;
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock(
        '_get_plugin_data',
        sub { my ( $self, $key ) = @_; push @requested, $key; return $stored_password }
    );

    is( $config->_load_plugin_password, 'secret', 'the stored password is read back' );
    is( $requested[0], 'suomifi_rest_password_default', 'read from the suomifi_rest_password_default key' );

    # getRESTConfig prefers the separately stored password, and falls back to
    # the password held in the YAML / koha-conf config when none is stored.
    $mock->mock( 'rootConfig', sub { return { rest => { password => 'from-config' } } } );

    $stored_password = 'secret';
    is( $config->getRESTConfig->{'password'}, 'secret', 'stored password takes precedence' );

    $stored_password = '';
    is( $config->getRESTConfig->{'password'}, 'from-config', 'empty stored password falls back to the config' );

    $stored_password = undef;
    is( $config->getRESTConfig->{'password'}, 'from-config', 'missing stored password falls back to the config' );
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
    is( scalar @stored, 3, 'accepted mapping is still stored' );
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

    is( $config->save( { config => "a: 1", suomifi_alt_sender => "foo: [broken" } ), 0,
        'unparseable alt sender YAML is rejected' );
    is( $config->last_save_error, 'invalid_yaml', 'unparseable alt sender reports the invalid_yaml reason' );

    is( $config->save( { config => "a: 1", suomifi_cost_pool => "- a\n- b" } ), 0,
        'a YAML sequence as a cost pool is rejected' );
    is( $config->last_save_error, 'not_a_mapping', 'cost pool sequence reports the not_a_mapping reason' );

    is( $config->save( { config => "a: 1", suomifi_alt_sender => '', suomifi_cost_pool => '' } ), 1,
        'blank SuomiFi fields are accepted alongside a valid config' );
    is( $config->last_save_error, undef, 'no error recorded when the SuomiFi fields are blank' );
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

        for my $key (qw(config_14 config_15 config_16 config_17 config_18 config_48 config_49)) {
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

subtest 'configure page warns about a koha-conf.xml section that is still there' => sub {

    # The warning is the whole indication that a section in koha-conf.xml is
    # being ignored, so render it: an empty div or a bare i18n key reads as
    # nothing being wrong, when what is wrong is that the settings are ignored.
    my $tt = read_file("$Bin/../config.tt");

    my ($warn_block) = $tt =~ /(\[% IF koha_conf_section %\].*?\[% END %\])/s;
    ok( $warn_block, 'config.tt has the notice about a section that is still there' );
    like( $warn_block, qr/T\.config_53/,   'the notice uses config_53' );
    like( $warn_block, qr/alert-warning/, 'the notice is a warning' );
    unlike( $tt, qr/T\.config_52/,       'no always-on notice is shown' );

    for my $lang (qw(default fi-FI sv-SE)) {
        my $snippet = read_file("$Bin/../i18n/$lang.inc") . "\n" . $warn_block;

        my $out = '';
        my $tpl = Template->new;
        $tpl->process( \$snippet, { koha_conf_section => 1 }, \$out ) or die $tpl->error;

        my ($warn) = $out =~ m{<div class="alert alert-warning[^"]*">(.*?)</div>}s;
        ok( length( $warn // '' ), "$lang renders text for config_53" );
        isnt( $warn, 'config_53', "$lang does not fall back to the bare key config_53" );

        # A site with no section in koha-conf.xml has nothing to migrate, so
        # there is nothing to warn about
        my $out_without = '';
        $tpl->process( \$snippet, { koha_conf_section => 0 }, \$out_without ) or die $tpl->error;
        unlike( $out_without, qr/alert-warning/, "$lang is not warned about a section that is not there" );
    }
};

subtest 'save moves the REST password out of the YAML' => sub {
    my %stored;
    my $mock = Test::MockModule->new($ConfigClass);
    $mock->mock(
        '_store_plugin_data',
        sub { my ( $self, $key, $value ) = @_; $stored{$key} = $value; return 1 }
    );

    # Store the passwords where they land, so the row they are read back from
    # can be checked.
    my @passwords;
    $mock->mock(
        'store_password',
        sub { my ( $self, $password, $branch ) = @_; push @passwords, { branch => $branch, password => $password }; return 1 }
    );

    my $config = $ConfigClass->new( {} );

    # The bootstrap case: the password is in the YAML, as it is when it has been
    # copied from koha-conf.xml.
    ok( $config->save( { config => "suomifi:\n  branches:\n    default:\n      rest:\n        baseUrl: https://api.example/\n        username: u\n        password: s3cret\n" } ),
        'a configuration carrying a REST password saves' );
    is_deeply( [ map { $_->{branch} } @passwords ], ['default'], 'the password is stored for its own branch' );
    is( $passwords[0]->{password}, 's3cret', 'the password value is stored' );
    unlike( $stored{ksmessaging_config}, qr/s3cret/, 'the password is not left in the stored YAML' );
    like( $stored{ksmessaging_config}, qr/baseUrl/, 'the rest of the configuration is kept' );
    is_deeply( $config->moved_passwords, ['default'], 'the moved branch is reported' );

    # Every branch gets its own row, which is what _load_plugin_password reads.
    # The branch list is sorted rather than compared in place: keys %$branches
    # does not iterate in a stable order.
    @passwords = ();
    $config->save( { config => "suomifi:\n  branches:\n    default:\n      rest:\n        password: d\n    lib1:\n      rest:\n        password: one\n" } );
    is_deeply( [ sort map { $_->{branch} } @passwords ], [ 'default', 'lib1' ],
        'each branch password is stored under its own branchcode' );
    is_deeply( $config->moved_passwords, ['default','lib1'], 'moved branches are sorted' );

    # The iPost and file transfer passwords have no row of their own and are read
    # from the YAML, so they must survive.
    @passwords = ();
    ok( $config->save( { config => "suomifi:\n  branches:\n    default:\n      ipostpdf:\n        customerid: c\n        customerpass: ipostsecret\n      filetransfer:\n        host: h\n        password: ftsecret\n" } ),
        'a configuration with only iPost and file transfer passwords saves' );
    is( scalar @passwords, 0, 'no REST password row is written for them' );
    is_deeply( $config->moved_passwords, [], 'nothing is reported as moved' );
    like( $stored{ksmessaging_config}, qr/ipostsecret/, 'the iPost customerpass stays in the YAML' );
    like( $stored{ksmessaging_config}, qr/ftsecret/, 'the file transfer password stays in the YAML' );

    # A configuration without a password is stored byte for byte, so comments and
    # formatting survive an ordinary save.
    @passwords = ();
    my $commented = "# my settings\nsuomifi:\n  branches:\n    default:\n      rest:\n        baseUrl: https://api.example/   # keep this\n";
    ok( $config->save( { config => $commented } ), 'a configuration without a password saves' );
    is( scalar @passwords, 0, 'no password row is written' );
    is( $stored{ksmessaging_config}, $commented, 'the text is stored unchanged, comments included' );
    is_deeply( $config->moved_passwords, [], 'nothing is reported as moved' );

    # An absent password must not clear a row that is already stored.
    @passwords = ();
    $config->save( { config => "suomifi:\n  branches:\n    default:\n      rest:\n        username: u\n" } );
    is( scalar @passwords, 0, 'saving without a password writes no row, so the stored one survives' );

    # An empty password is not a password and does not strip the stored one.
    @passwords = ();
    $config->save( { config => "suomifi:\n  branches:\n    default:\n      rest:\n        password: ''\n" } );
    is( scalar @passwords, 0, 'an empty password is not stored' );
    like( $stored{ksmessaging_config}, qr/password/, 'an empty password is left in place rather than hidden' );

    # Values that are not plain scalars are left alone rather than dropped.
    @passwords = ();
    my $structured = "suomifi:\n  branches:\n    default:\n      rest:\n        password:\n          key: value\n";
    ok( $config->save( { config => $structured } ), 'a configuration with a structured password saves' );
    is( scalar @passwords, 0, 'a structured password is not stored' );
    like( $stored{ksmessaging_config}, qr/key: value/, 'a structured password is left in place' );

    # The stored YAML is still a valid mapping that _load_config can read, and a
    # rest section emptied of its password still parses.
    @passwords = ();
    $config->save( { config => "suomifi:\n  branches:\n    default:\n      rest:\n        password: only\n" } );
    my $roundtrip = YAML::XS::Load( $stored{ksmessaging_config} );
    is( ref $roundtrip, 'HASH', 'the stripped YAML is still a mapping' );
    ok( exists $roundtrip->{suomifi}{branches}{default}{rest}, 'the rest section is kept' );
    ok( !exists $roundtrip->{suomifi}{branches}{default}{rest}{password}, 'the password is gone from it' );
};

subtest 'koha_conf_section_present' => sub {
    my $context_mock = Test::MockModule->new('C4::Context');
    my $config = $ConfigClass->new( {} );

    $context_mock->mock( 'config', sub { return { suomifi => { branches => { default => {} } } } } );
    is( $config->koha_conf_section_present, 1, 'a ksmessaging section is reported' );

    $context_mock->mock( 'config', sub { return undef } );
    is( $config->koha_conf_section_present, 0, 'a missing section is not reported' );

    $context_mock->mock( 'config', sub { return {} } );
    is( $config->koha_conf_section_present, 0, 'an empty section is not reported' );

    $context_mock->mock( 'config', sub { return 'not a mapping' } );
    is( $config->koha_conf_section_present, 0, 'a section that is not a mapping is not reported' );

    # Asking the question must not disturb the copy operation's own error
    is( $config->last_copy_error, undef, 'asking leaves last_copy_error alone' );
};

subtest 'config_from_koha_conf' => sub {
    my @stored;
    my $context_mock = Test::MockModule->new('C4::Context');
    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock(
        '_store_plugin_data',
        sub { my ( $self, $key, $value ) = @_; push @stored, { key => $key, value => $value } }
    );

    my $config = $ConfigClass->new( {} );

    my $section = {
        suomifi => { branches => { default => { stagingdir => '/tmp/x', rest => { serviceid => 'svc' } } } },
        letters => { skipletters => 'RETURN,OVERDUE' },
    };

    $context_mock->mock( 'config', sub { return $section } );
    my $yaml = $config->config_from_koha_conf;
    ok( $yaml, 'a ksmessaging section is returned' );
    is( $config->last_copy_error, undef, 'no error recorded when the YAML is returned' );

    # Nothing is written.  The text goes into the textarea and the administrator
    # saves it, so a stored configuration can never be overwritten by pressing
    # this button.
    is( scalar @stored, 0, 'the section is not written to plugin_data' );

    # The section is serialised back to the YAML that save() stores, so what
    # lands in the textarea is what save() can store and _load_config() can
    # read back.
    is_deeply( YAML::XS::Load($yaml), $section, 'the returned YAML round-trips the section' );
    ok( $yaml =~ /^suomifi:/m, 'the returned text is the YAML that the textarea expects' );

    # A rest.password in the section is offered along on purpose: the section is
    # the only place it can come from, and leaving it behind would stop it from
    # being used.
    $context_mock->mock( 'config', sub { return { suomifi => { branches => { default => { rest => { password => 'p' } } } } } } );
    my $with_password = $config->config_from_koha_conf;
    is( $with_password =~ /password: p/, 1, 'the REST password comes along in the returned YAML' );
    is( scalar @stored, 0, 'still nothing stored' );

    # Nothing to offer is reported rather than returned.
    $context_mock->mock( 'config', sub { return undef } );
    is( $config->config_from_koha_conf, undef, 'a missing section returns undef' );
    is( $config->last_copy_error, 'empty', 'a missing section reports the empty reason' );
    is( scalar @stored, 0, 'nothing stored when there is nothing to offer' );

    $context_mock->mock( 'config', sub { return {} } );
    is( $config->config_from_koha_conf, undef, 'an empty section returns undef' );
    is( $config->last_copy_error, 'empty', 'an empty section reports the empty reason' );
    is( scalar @stored, 0, 'nothing stored for an empty section' );

    $context_mock->mock( 'config', sub { return 'not a mapping' } );
    is( $config->config_from_koha_conf, undef, 'a section that is not a mapping returns undef' );
    is( $config->last_copy_error, 'empty', 'a section that is not a mapping reports the empty reason' );
    is( scalar @stored, 0, 'nothing stored for a section that is not a mapping' );
};

subtest 'getSuomiFiAltSender' => sub {
    my $pref;
    my $stored;
    my $context_mock = Test::MockModule->new('C4::Context');
    $context_mock->mock( 'preference', sub { return $pref } );
    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( '_load_suomifi_alt_sender', sub { return $stored } );

    my $config = $ConfigClass->new( { branch => 'lib1' } );

    $pref   = undef;
    $stored = undef;
    is( $config->getSuomiFiAltSender('fi-FI'), undef, 'undef preference returns undef' );

    $stored = "fi-FI:\n  lib1:\n    - Kirjasto A\nen:\n  lib1:\n    - Library E\n";
    is_deeply( $config->getSuomiFiAltSender('fi-FI'), ['Kirjasto A'], 'language section + branch match' );
    is_deeply( $config->getSuomiFiAltSender('en'),     ['Library E'], 'a second language section is matched' );

    $stored = "fi-FI:\n  lib1:\n    - Kirjasto A\n";
    is_deeply( $config->getSuomiFiAltSender('fi-FI'), ['Kirjasto A'], 'a one row alt sender is returned as stored' );

    $stored = "lib1:\n  - Direct\ndefault:\n  - Def\n";
    is_deeply( $config->getSuomiFiAltSender(undef), ['Direct'], 'direct branch section match without lang' );

    $stored = "default:\n  - Def\n";
    is_deeply( $config->getSuomiFiAltSender('fi-FI'), ['Def'], 'default section fallback' );

    # The stored configuration is preferred over the system preference, and an
    # empty stored value falls back to it, which is what save() writes when the
    # admin leaves the field blank.
    $stored = "fi-FI:\n  lib1:\n    - From plugin_data\n";
    $pref   = "fi-FI:\n  lib1:\n    - From preference\n";
    is_deeply( $config->getSuomiFiAltSender('fi-FI'), ['From plugin_data'],
        'the stored alt sender takes precedence over the system preference' );

    $stored = '';
    is_deeply( $config->getSuomiFiAltSender('fi-FI'), ['From preference'],
        'an empty stored alt sender falls back to the system preference' );

    $stored = undef;
    is_deeply( $config->getSuomiFiAltSender('fi-FI'), ['From preference'],
        'a missing stored alt sender falls back to the system preference' );

    $stored = undef;
    $pref   = undef;
    local *STDOUT;
    open STDOUT, '>', '/dev/null' or die $!;
    $stored = "foo: [broken";
    is( $config->getSuomiFiAltSender('fi-FI'), undef, 'invalid YAML returns undef' );

    $stored = "- just\n- a\n- list\n";
    is( $config->getSuomiFiAltSender('fi-FI'), undef, 'non-hash YAML returns undef' );

    $stored = "other:\n  - Nope\n";
    is( $config->getSuomiFiAltSender('fi-FI'), undef, 'no matching branch returns undef' );
};

subtest 'getSuomiFiCostPool' => sub {
    my $pref;
    my $stored;
    my $context_mock = Test::MockModule->new('C4::Context');
    $context_mock->mock( 'preference', sub { return $pref } );
    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( '_load_suomifi_cost_pool', sub { return $stored } );

    my $config = $ConfigClass->new( { branch => 'lib1' } );

    $pref   = undef;
    $stored = undef;
    is( $config->getSuomiFiCostPool, undef, 'undef preference returns undef' );

    $stored = "lib1: KL001\n";
    is( $config->getSuomiFiCostPool, 'KL001', 'valid cost pool returned' );

    $stored = "lib1: bad value\n";
    is( $config->getSuomiFiCostPool, undef, 'invalid cost pool value returns undef' );

    $stored = "lib1: 123ABC\n";
    is( $config->getSuomiFiCostPool, '123ABC', 'numeric cost pool returned' );

    $stored = "other: KL099\n";
    is( $config->getSuomiFiCostPool, undef, 'no matching branch returns undef' );

    # The stored cost pool is preferred over the system preference, and an empty
    # stored value falls back to it.
    $stored = "lib1: KLSTORED\n";
    $pref   = "lib1: KLPREF\n";
    is( $config->getSuomiFiCostPool, 'KLSTORED', 'the stored cost pool takes precedence over the system preference' );

    $stored = '';
    is( $config->getSuomiFiCostPool, 'KLPREF', 'an empty stored cost pool falls back to the system preference' );

    $stored = undef;
    is( $config->getSuomiFiCostPool, 'KLPREF', 'a missing stored cost pool falls back to the system preference' );

    $stored = undef;
    $pref   = undef;
    local *STDOUT;
    open STDOUT, '>', '/dev/null' or die $!;
    $stored = "foo: [broken";
    is( $config->getSuomiFiCostPool, undef, 'invalid YAML returns undef' );
};

subtest '_load_config' => sub {
    my $config_mock = Test::MockModule->new($ConfigClass);
    my $context_mock = Test::MockModule->new('C4::Context');

    # koha-conf.xml is a source to copy from, not one that is read: with nothing
    # stored there is no configuration at all, even when the file has a
    # <ksmessaging> section, and pate.pl's guard message is the way that is
    # reported.
    $context_mock->mock( 'config', sub { return { suomifi => { branches => { default => { stagingdir => '/tmp/x' } } } } } );

    $config_mock->mock( '_load_plugin_config', sub { return undef } );
    my $config = $ConfigClass->new( {} );
    is_deeply( $config->_load_config, {}, 'nothing stored means no configuration' );
    is( $config->rootConfig, undef, 'no branch configuration without a stored one' );

    $config_mock->mock( '_load_plugin_config', sub { return "  \n" } );
    is_deeply( $ConfigClass->new( {} )->_load_config, {}, 'blank stored text means no configuration' );

    $config_mock->mock( '_load_plugin_config', sub { return "suomifi: [broken\n" } );
    is_deeply( $ConfigClass->new( {} )->_load_config, {}, 'unparsable stored text means no configuration' );

    # A stored configuration is read from plugin_data, and C4::Context->config is
    # not consulted for it.
    $config_mock->mock( '_load_plugin_config', sub { return "suomifi:\n  branches:\n    default:\n      stagingdir: /tmp/stored\n" } );
    is( $ConfigClass->new( {} )->stagingDir, '/tmp/stored', 'the stored configuration is used' );
};

subtest 'load_for_configure' => sub {
    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( '_load_plugin_config',       sub { return "config:\n  a: 1\n" } );
    $config_mock->mock( '_load_suomifi_alt_sender',  sub { return "fi-FI:\n  KOHAPK:\n    - Kirjasto\n" } );
    $config_mock->mock( '_load_suomifi_cost_pool',   sub { return "KOHAPK: KL001\n" } );

    my $config = $ConfigClass->new( {} );
    $config->load_for_configure;
    is( $config->loadedConfigForDisplay,  "config:\n  a: 1\n", 'config exposed for display' );
    is( $config->loadedAltSenderForDisplay, "fi-FI:\n  KOHAPK:\n    - Kirjasto\n", 'alt sender exposed for display' );
    is( $config->loadedCostPoolForDisplay,  "KOHAPK: KL001\n", 'cost pool exposed for display' );

    $config_mock->mock( '_load_suomifi_alt_sender', sub { return undef } );
    $config_mock->mock( '_load_suomifi_cost_pool',  sub { return undef } );

    my $empty = $ConfigClass->new( {} );
    $empty->load_for_configure;
    is( $empty->loadedAltSenderForDisplay, '', 'a missing alt sender is exposed as an empty string' );
    is( $empty->loadedCostPoolForDisplay,  '', 'a missing cost pool is exposed as an empty string' );
};

done_testing;