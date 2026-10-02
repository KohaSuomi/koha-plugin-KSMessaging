#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::MockModule;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";

use Koha::Plugin::Fi::KohaSuomi::KSMessaging;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Setup;

my $PluginClass = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging';
my $ConfigClass = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config';
my $SetupClass  = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Setup';

############################################################
## A fake database handle that records the statements it is
## given and answers the queries of Modules::Setup from canned
## results.  No database is needed.
############################################################

package TestSTH;

sub new {
    my ( $class, %args ) = @_;
    return bless {%args}, $class;
}

sub execute {
    my ( $self, @bind ) = @_;

    my $dbh  = $self->{dbh};
    my $type = $self->{type};

    push @{ $dbh->{binds} }, { type => $type, bind => [@bind] };

    if ( $type eq 'type_exists' ) {
        $self->{rows} = $dbh->{type_exists} ? [ (1) ] : [];
        return $#{$self->{rows}} + 1;
    }
    if ( $type eq 'count' ) {
        $self->{rows} = [ ( $dbh->{transport_count} ) ];
        return 1;
    }
    if ( $type eq 'source' ) {
        $self->{rows} = $dbh->{source} || [];
        return scalar @{ $self->{rows} };
    }

    # An insert: the caller wants to know whether a row was written, and DBI
    # answers with the number of affected rows, '0E0' when there was none
    my $affected;
    if ( $type eq 'create_type' ) {
        $affected = $dbh->{type_created};
    }
    elsif ( $type eq 'copy' ) {
        $affected = $dbh->{copy_results} ? shift @{ $dbh->{copy_results} } : $dbh->{copy_result};
        $affected = 0 unless defined $affected;
    }
    else {
        $affected = 1;
    }
    return $affected ? $affected : '0E0';
}

sub fetchrow_array {
    my ($self) = @_;
    return unless $self->{rows};
    return shift @{ $self->{rows} };
}

sub fetchall_arrayref {
    my ($self) = @_;
    return $self->{rows} || [];
}

sub finish { return 1 }

package TestDBH;

sub new {
    my ( $class, %args ) = @_;

    my $self = bless {
        type_exists     => 0,
        type_created    => 1,
        transport_count => 0,
        source          => [],
        copy_result     => 1,
        queries         => [],
        binds           => [],
    }, $class;

    return bless { %$self, %args }, $class;
}

sub quote {
    my ( $self, $value ) = @_;
    return "'$value'";
}

sub do {
    my ( $self, $sql ) = @_;
    push @{ $self->{queries} }, $sql;
    return 1;
}

sub prepare {
    my ( $self, $sql ) = @_;

    push @{ $self->{queries} }, $sql;

    my $type =
          $sql =~ /SELECT 1 FROM message_transport_types/ ? 'type_exists'
        : $sql =~ /SELECT COUNT/                            ? 'count'
        : $sql =~ /SELECT DISTINCT/                         ? 'source'
        : $sql =~ /INSERT IGNORE INTO message_transport_types/ ? 'create_type'
        : $sql =~ /INSERT IGNORE INTO message_transports/  ? 'copy'
        :                                                      'other';

    return TestSTH->new( type => $type, dbh => $self );
}

## --- helpers ---------------------------------------------------------------

sub statements {
    my ( $self, $pattern ) = @_;
    return grep { $_ =~ $pattern } @{ $self->{queries} };
}

sub binds_of {
    my ( $self, $type ) = @_;
    return [ map { $_->{bind} } grep { $_->{type} eq $type } @{ $self->{binds} } ];
}

package main;

sub mock_dbh {
    my ($dbh) = @_;
    my $mock = Test::MockModule->new('C4::Context');
    $mock->mock( 'dbh', sub { return $dbh } );
    return $mock;
}

############################################################

subtest 'create_message_transports' => sub {
    my $dbh = TestDBH->new(
        type_exists => 0,
        source      => [
            [ 12, 0, 'circulation', 'REMINDER' ],
            [ 13, 0, 'circulation', 'OVERDUE' ],
            [ 14, 0, 'reserves',     'HOLD' ],
        ],
    );
    my $mock = mock_dbh($dbh);

    my $result = $SetupClass->new->create_message_transports;

    is( $result->{type_created}, 1, 'the transport type was created' );
    is( $result->{added},        3, 'every source transport was added' );
    is( $result->{skipped},      0, 'nothing was skipped' );

    my ($create) = $dbh->statements(qr/INSERT IGNORE INTO message_transport_types/);
    like( $create, qr/VALUES \(\?\)/, 'the transport type is a bound INSERT IGNORE' );
    is_deeply( $dbh->binds_of('create_type'), [ ['suomifi'] ],
        'the suomifi transport type was inserted' );

    my ($select) = $dbh->statements(qr/SELECT DISTINCT/);
    like( $select, qr/letter_module IN \('circulation', 'reserves'\)/,
        'only circulation and reserves transports are copied' );
    like( $select, qr/message_transport_type <> \?/,
        'transports already set up for suomifi are not a source' );
    unlike( $select, qr/GROUP BY/i,
        'no GROUP BY, which would break under ONLY_FULL_GROUP_BY' );
    is_deeply( $dbh->binds_of('source'), [ ['suomifi'] ],
        'the source query is bound' );

    my ($copy) = $dbh->statements(qr/INSERT IGNORE INTO message_transports/);
    like( $copy, qr/INSERT IGNORE/, 'the copies are inserted with INSERT IGNORE' );
    is_deeply(
        $dbh->binds_of('copy'),
        [
            [ 12, 'suomifi', 0, 'circulation', 'REMINDER' ],
            [ 13, 'suomifi', 0, 'circulation', 'OVERDUE' ],
            [ 14, 'suomifi', 0, 'reserves',     'HOLD' ],
        ],
        'every transport is copied to the suomifi transport type'
    );
};

subtest 'create_message_transports is idempotent' => sub {
    # The second run: the transport type exists and every transport is already
    # there, so DBI reports '0E0' for every insert
    my $dbh = TestDBH->new(
        type_exists => 1,
        type_created => 0,
        source       => [ [ 12, 0, 'circulation', 'REMINDER' ] ],
        copy_result  => 0,
    );
    my $mock = mock_dbh($dbh);

    my $result = $SetupClass->new->create_message_transports;

    is( $result->{type_created}, 0, 'an existing transport type is not created again' );
    is( scalar $dbh->statements(qr/INSERT IGNORE INTO message_transport_types/),
        0, 'no insert into message_transport_types when the type already exists' );
    is( $result->{added},   0, 'nothing was added' );
    is( $result->{skipped}, 1, 'the transport that was already there was skipped' );
};

subtest 'create_message_transports counts a partly existing setup' => sub {
    # A notice that was set up for Suomi.fi by hand, and a new one
    my $dbh = TestDBH->new(
        type_exists => 1,
        type_created => 0,
        source       => [
            [ 12, 0, 'circulation', 'REMINDER' ],
            [ 13, 0, 'circulation', 'OVERDUE' ],
        ],
        copy_results => [ 0, 1 ],
    );
    my $mock = mock_dbh($dbh);

    my $result = $SetupClass->new->create_message_transports;

    is( $result->{added},   1, 'the new transport was added' );
    is( $result->{skipped}, 1, 'the existing transport was left alone' );
};

subtest 'create_message_transports does not write system preferences' => sub {
    my $dbh = TestDBH->new(
        type_exists => 0,
        source      => [ [ 12, 0, 'circulation', 'REMINDER' ] ],
    );
    my $mock = mock_dbh($dbh);

    $SetupClass->new->create_message_transports;

    is( scalar $dbh->statements(qr/systempreferences/), 0,
        'the message transport setup writes no system preference' );
    is( scalar $dbh->statements(qr/plugin_data/), 0,
        'the message transport setup writes no plugin_data' );
};

subtest 'status' => sub {
    my $dbh = TestDBH->new( type_exists => 1, transport_count => 7 );
    my $mock = mock_dbh($dbh);

    my $setup = $SetupClass->new;
    is( $setup->transport_type_exists, 1, 'the transport type is in use' );
    is( $setup->transport_count,       7, 'seven transports are set up' );
};

subtest 'status without a transport type' => sub {
    my $dbh = TestDBH->new( type_exists => 0, transport_count => 0 );
    my $mock = mock_dbh($dbh);

    my $setup = $SetupClass->new;
    is( $setup->transport_type_exists, 0, 'the transport type is not in use' );
    is( $setup->transport_count,       0, 'no transports are set up' );
};

subtest 'the SuomiFiMessaging system preference' => sub {
    my $pref;
    my @set;

    my $context_mock = Test::MockModule->new('C4::Context');
    $context_mock->mock( 'preference', sub { return $pref } );
    $context_mock->mock(
        'set_preference',
        sub {
            my ( $context, $variable, $value ) = @_;
            push @set, [ $variable, $value ];
            return 1;
        }
    );

    my $config = $ConfigClass->new( {} );

    $pref = 0;
    is( $config->suomifiMessagingEnabled, 0, 'a false preference is not enabled' );
    $pref = 1;
    is( $config->suomifiMessagingEnabled, 1, 'the preference is read as it is' );
    $pref = undef;
    is( $config->suomifiMessagingEnabled, undef,
        'a preference that does not exist reads as undef' );

    $config->setSuomiFiMessaging(1);
    $config->setSuomiFiMessaging(0);
    is_deeply(
        \@set,
        [ [ 'SuomiFiMessaging', 1 ], [ 'SuomiFiMessaging', 0 ] ],
        'the preference is written to the systempreferences table'
    );
};

############################################################
## The configure page decides which of the three actions runs
############################################################

{
    package TestCGI;

    sub new {
        my ( $class, %args ) = @_;
        return bless { %args }, $class;
    }

    sub request_method { return $_[0]->{method} }
    sub param           { my ( $self, $name ) = @_; return $self->{params}->{$name} }
    sub cookie          { return 'CGISESSID' }
}

{
    package TestToken;

    our $VALID = 1;
    sub new          { return bless {}, shift }
    sub check_csrf   { return $VALID }
}

{
    package TestTemplate;

    sub new  { return bless { params => {} }, shift }
    sub param {
        my $self = shift;
        $self->{params} = @_ == 1 ? $_[0] : {@_};
        return 1;
    }
    sub output { return '' }
}

## Runs configure() with mocked collaborators and returns the template
## parameters it was called with, plus the calls that were made.
sub run_configure {
    my (%args) = @_;

    my @calls;
    my %prefs = %{ $args{prefs} || {} };

    my $config_mock = Test::MockModule->new($ConfigClass);
    $config_mock->mock( 'new', sub { return bless { prefs => \%prefs }, $ConfigClass } );
    $config_mock->mock( 'load_for_configure', sub { return 1 } );
    $config_mock->mock( 'loadedConfigForDisplay',     sub { return 'a: 1' } );
    $config_mock->mock( 'loadedAltSenderForDisplay',  sub { return '' } );
    $config_mock->mock( 'loadedCostPoolForDisplay',   sub { return '' } );
    $config_mock->mock( 'suomifiMessagingEnabled',     sub { return $prefs{SuomiFiMessaging} } );
    $config_mock->mock(
        'koha_conf_section_present',
        sub { return $args{koha_conf_section} ? 1 : 0 }
    );
    $config_mock->mock(
        'setSuomiFiMessaging',
        sub {
            my ( $config, $enabled ) = @_;
            push @calls, 'setSuomiFiMessaging';
            $prefs{SuomiFiMessaging} = $enabled ? 1 : 0;
            return 1;
        }
    );
    $config_mock->mock(
        'save',
        sub {
            push @calls, 'save';
            return 1;
        }
    );

    my $setup_mock = Test::MockModule->new($SetupClass);
    $setup_mock->mock( 'new', sub { return bless {}, $SetupClass } );

    # The state of the transport, so that the status the page renders is the
    # state after the action, not the state before it
    my %transport = (
        exists => $args{transport_type_exists} ? 1 : 0,
        count  => $args{transport_count} || 0,
    );
    $setup_mock->mock( 'transport_type_exists', sub { return $transport{exists} } );
    $setup_mock->mock( 'transport_count',       sub { return $transport{count} } );
    $setup_mock->mock(
        'create_message_transports',
        sub {
            push @calls, 'create_message_transports';
            die "no transport type\n" if $args{setup_fails};
            $transport{exists} = 1;
            $transport{count} += 2;
            return {
                type_created => 1,
                added        => 2,
                skipped      => 1,
            };
        }
    );

    $TestToken::VALID = exists $args{token_valid} ? $args{token_valid} : 1;
    my $token_mock = Test::MockModule->new('Koha::Token');
    $token_mock->mock( 'new', sub { return TestToken->new } );

    my $template = TestTemplate->new;
    my $plugin_mock = Test::MockModule->new($PluginClass);
    $plugin_mock->mock( 'get_template', sub { return $template } );
    $plugin_mock->mock( 'output_html',  sub { return '' } );

    my $cgi = TestCGI->new(
        method => $args{method} || 'GET',
        params => $args{params} || {},
    );
    my $plugin = bless { cgi => $cgi }, $PluginClass;
    $plugin->configure( {} );

    return { calls => \@calls, template => $template->{params} };
}

subtest 'configure: the setup button only sets up the message transports' => sub {
    my $result = run_configure(
        method                => 'POST',
        params                => { setup_messages => 1 },
        transport_type_exists => 0,
    );

    is_deeply( $result->{calls}, ['create_message_transports'],
        'the message transports are set up and nothing else' );
    is( $result->{template}->{setup_result}->{added},   2, 'the added count is shown' );
    is( $result->{template}->{setup_result}->{skipped}, 1, 'the skipped count is shown' );
    ok( !$result->{template}->{saved}, 'the configuration was not saved' );
    is( $result->{template}->{setup_status}->{transport_type_exists}, 1,
        'the status shows the transport type that was just created' );
};

subtest 'configure: the toggle button only toggles the preference' => sub {
    my $result = run_configure(
        method => 'POST',
        params => { toggle_suomifi_messaging => 'Hide the Suomi.fi column' },
        prefs  => { SuomiFiMessaging => 0 },
    );

    is_deeply( $result->{calls}, ['setSuomiFiMessaging'],
        'the preference is written and nothing else' );
    is( $result->{template}->{setup_status}->{suomifi_messaging}, 1,
        'the status shows the preference that was just enabled' );
    ok( !$result->{template}->{setup_result}, 'no message transports were set up' );
    ok( !$result->{template}->{saved},        'the configuration was not saved' );
};

subtest 'configure: the toggle turns the preference off again' => sub {
    my $result = run_configure(
        method => 'POST',
        params => { toggle_suomifi_messaging => 1 },
        prefs  => { SuomiFiMessaging => 1 },
    );

    is_deeply( $result->{calls}, ['setSuomiFiMessaging'], 'the preference is written' );
    is( $result->{template}->{setup_status}->{suomifi_messaging}, 0,
        'the status shows the preference that was just disabled' );
};

subtest 'configure: the save button only saves the configuration' => sub {
    my $result = run_configure(
        method => 'POST',
        params => { save => 1, config => "a: 1\n" },
        prefs  => { SuomiFiMessaging => 0 },
    );

    is_deeply( $result->{calls}, ['save'], 'only the configuration is saved' );
    is( $result->{template}->{saved}, 1, 'the save is reported' );
    ok( !$result->{template}->{setup_result}, 'no message transports were set up' );
};

subtest 'configure: an invalid token changes nothing' => sub {
    for my $action (qw(setup_messages toggle_suomifi_messaging save)) {
        my $result = run_configure(
            method     => 'POST',
            params     => { $action => 1 },
            token_valid => 0,
        );

        is_deeply( $result->{calls}, [], "$action does nothing without a valid token" );
        is_deeply(
            [ map { $_->{key} } @{ $result->{template}->{messages} } ],
            ['config_18'],
            "$action reports the invalid token"
        );
        ok( !$result->{template}->{saved}, "$action did not save the configuration" );
        ok( !$result->{template}->{setup_result}, "$action set up no message transports" );
    }
};

subtest 'configure: a failing setup is reported' => sub {
    # the failure is warned about by the plugin, which is the point of it
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $result = run_configure(
        method      => 'POST',
        params      => { setup_messages => 1 },
        setup_fails => 1,
    );

    is( $result->{template}->{setup_result}->{error}, 1, 'the failure is reported' );
    ok( !$result->{template}->{setup_result}->{added},
        'no transports are claimed to have been added' );
    is( scalar( grep { /setting up the suomifi message transports failed/ } @warnings ),
        1, 'the failure is written to the error log' );
};

subtest 'configure: the page renders the status without a submission' => sub {
    my $result = run_configure( transport_type_exists => 1, transport_count => 5 );

    is_deeply( $result->{calls}, [], 'a GET changes nothing' );
    is( $result->{template}->{setup_status}->{transport_type_exists}, 1,
        'the transport type status is shown' );
    is( $result->{template}->{setup_status}->{transport_count}, 5,
        'the transport count is shown' );
    is( $result->{template}->{setup_status}->{suomifi_messaging}, 0,
        'the preference status is shown' );
    ok( !$result->{template}->{setup_result}, 'no result is reported' );
    ok( !$result->{template}->{saved},        'nothing was saved' );
};

subtest 'configure: the page says that koha-conf.xml is not read' => sub {
    my $without = run_configure();
    is( $without->{template}->{koha_conf_section}, 0,
        'no section in koha-conf.xml is reported as none' );

    my $with = run_configure( koha_conf_section => 1 );
    is( $with->{template}->{koha_conf_section}, 1,
        'a section in koha-conf.xml is reported, so the page can warn about it' );
    is_deeply( $with->{calls}, [], 'reporting it changes nothing' );
};

done_testing();
