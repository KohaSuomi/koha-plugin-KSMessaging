#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Integration test for cronjobs/change-suomifi-password.pl.  Runs against a
# live Koha database inside a single transaction that is rolled back at the
# end, so no fixture rows or password changes persist.  Only the physical
# outside world is mocked:
#   * Deliver::REST HTTP calls (fetchAccessToken / changePassword)
#   * Koha::Caches (memcached) instance
#
# Run from the plugin repo root:
#
#     KOHA_CONF=/path/to/koha-conf.xml \
#     PERL5LIB=/path/to/koha:/path/to/koha/t \
#       prove -v Koha/Plugin/Fi/KohaSuomi/KSMessaging/t/change-suomifi-password.t

use Test::More;
use Test::MockModule;

use FindBin qw($Bin);
use Cwd qw(abs_path);
use File::Temp qw(tempdir tempfile);
use File::Slurp qw(read_file);

use lib abs_path("$Bin/../../../../../..");   # plugin repo root

BEGIN {
    my @dirs;
    my @lists = ( $ENV{KOHA_PATH}, $ENV{KOHA_HOME} );
    for my $list (@lists) {
        next unless defined $list && length $list;
        push @dirs, grep { length } split( /:/, $list );
    }
    push @dirs, '/home/koha/Koha' unless @dirs;
    for my $d (@dirs) {
        push @INC, $d   if -d $d;
        push @INC, "$d/t" if -d "$d/t";
    }
}

use Koha::Database;
use C4::Context;
use Koha::Caches;

my $PLUGIN_CLASS = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging';
my $CONFIG_CLASS = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config';
my $REST_CLASS   = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST';

my $SCRIPT = abs_path("$Bin/../cronjobs/change-suomifi-password.pl");
die "change-suomifi-password.pl not found at $SCRIPT" unless -e $SCRIPT;

# --- database wrapper ------------------------------------------------------

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;
my $dbh = C4::Context->dbh;
my $connected = eval { $dbh->do("SELECT 1"); 1 };
die "Cannot connect to the Koha database (is the dev instance running?): $@" unless $connected;

END {
    $schema->storage->txn_rollback
        if defined $schema && eval { $schema->storage->in_txn; 1 };
}

# --- mocks for the physical outside world ---------------------------------

my @fetch_calls;
my @change_calls;
our @cache_get;
our @cache_set;
our @cache_clear;
our $cached_token;

my $rest_mock = Test::MockModule->new($REST_CLASS);
$rest_mock->mock(
    'fetchAccessToken',
    sub { push @fetch_calls, [@_]; return { access_token => 'fake-token', expires_in => 3600 } }
);
$rest_mock->mock(
    'changePassword',
    sub { push @change_calls, [@_]; return {} }
);

{
    package MockCache;
    sub new { bless {}, shift }
    sub get_from_cache { push @::cache_get, $_[1]; return $::cached_token }
    sub set_in_cache   { push @::cache_set,   [@_] }
    sub clear_from_cache { push @::cache_clear, $_[1] }
}
my $cache_mock = Test::MockModule->new('Koha::Caches');
$cache_mock->mock( 'get_instance', sub { MockCache->new } );

# --- script runner ---------------------------------------------------------

my $exit_code;

{
    no warnings 'once';
    *CORE::GLOBAL::exit = sub {
        my $code = shift;
        $exit_code = defined $code ? $code : 0;
        die 'KSMessaging exit requested';
    };
    *CORE::GLOBAL::sleep = sub { 0 };
}

sub run_script {
    my (@args) = @_;
    local @ARGV = @args;

    my ( undef, $errfile ) = tempfile( UNLINK => 1 );
    my ( undef, $outfile ) = tempfile( UNLINK => 1 );
    open my $saved_err, '>&', *main::STDERR or die "cannot dup STDERR: $!";
    open my $saved_out, '>&', *main::STDOUT or die "cannot dup STDOUT: $!";
    open main::STDERR, '>', $errfile or die "cannot redirect STDERR: $!";
    open main::STDOUT, '>', $outfile or die "cannot redirect STDOUT: $!";
    binmode main::STDERR, ':encoding(utf8)';
    binmode main::STDOUT, ':encoding(utf8)';

    $exit_code = undef;
    my $fatal;
    my $ran = eval {
        no warnings 'redefine';
        local $SIG{__WARN__} = sub { my $m = shift; warn $m unless $m =~ /redefined at/ };
        do "$SCRIPT";
        1;
    };
    my $eval_err = $@;

    close main::STDERR;
    close main::STDOUT;

    my $stderr = '';
    my $stdout = '';
    for my $pair ( [ $errfile, \$stderr ], [ $outfile, \$stdout ] ) {
        my ( $file, $target ) = @$pair;
        open my $rh, '<', $file or die "cannot reopen output: $!";
        local $/;
        $$target = <$rh>;
        close $rh;
    }
    open main::STDERR, '>&', $saved_err or die "cannot restore STDERR: $!";
    open main::STDOUT, '>&', $saved_out or die "cannot restore STDOUT: $!";

    if ( !$ran && defined $eval_err && $eval_err !~ /KSMessaging exit requested/ ) {
        $fatal = $eval_err;
    }

    return ( $exit_code, $stderr, $stdout, $fatal );
}

# --- helpers ---------------------------------------------------------------

sub reset_mocks {
    @fetch_calls   = ();
    @change_calls  = ();
    @cache_get     = ();
    @cache_set     = ();
    @cache_clear   = ();
    $cached_token  = undef;
    $rest_mock->mock(
        'fetchAccessToken',
        sub { push @fetch_calls, [@_]; return { access_token => 'fake-token', expires_in => 3600 } }
    );
    $rest_mock->mock(
        'changePassword',
        sub { push @change_calls, [@_]; return {} }
    );
}

sub seed_config {
    my $yaml = <<'YAML';
suomifi:
  branches:
    default:
      contact: "suomifi@test.fi"
      cachekey: "kscache"
      stagingdir: "/tmp/ks"
      rest:
        baseUrl: "https://rest.test.invalid/"
        username: "tester"
        serviceid: "svc1"
    ZT2:
      contact: "suomifi-cpl@test.fi"
      cachekey: "kscache"
      stagingdir: "/tmp/ks"
      rest:
        baseUrl: "https://rest.test.invalid/"
        username: "tester"
        serviceid: "svc-cpl"
YAML
    my $sth = $dbh->prepare(
        'INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
         VALUES (?,?,?) ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value)'
    );
    $sth->execute( $PLUGIN_CLASS, 'ksmessaging_config', $yaml );
    $sth->execute( $PLUGIN_CLASS, 'suomifi_rest_password_default', 'old-secret' );
    $sth->execute( $PLUGIN_CLASS, 'suomifi_rest_password_ZT2', 'zt2-old' );
    $sth->finish;
}

sub stored_password {
    my ($branch) = @_;
    my $sth = $dbh->prepare(
        'SELECT plugin_value FROM plugin_data WHERE plugin_class = ? AND plugin_key = ?'
    );
    $sth->execute( $PLUGIN_CLASS, "suomifi_rest_password_$branch" );
    my ($v) = $sth->fetchrow_array;
    $sth->finish;
    return $v;
}

# --- tests -----------------------------------------------------------------

subtest 'help' => sub {
    reset_mocks();
    seed_config();
    my ( $code, $err, $out, $fatal ) = run_script('--help');
    is( $code, 0, '--help exits 0' );
    like( $out, qr/Usage:/, '--help prints usage' );
    like( $out, qr/--store/, '--help documents --store' );
    like( $out, qr/suomifi_password_backup\.txt/, 'default backup name for default branch shown' );
};

subtest 'test_password (correct) does not change or store' => sub {
    reset_mocks();
    seed_config();
    my $backup_dir  = tempdir( CLEANUP => 1 );
    my $backup_file = "$backup_dir/backup.txt";
    my ( $code, $err, $out, $fatal ) = run_script( '--branchcode=default', '--test_password' );
    is( $code, 0, 'test_password exits 0' );
    like( $out, qr/The provided old password is correct\./, 'reports correct password' );
    is( scalar @change_calls, 0, 'changePassword not called' );
    is( scalar @fetch_calls, 1, 'fetchAccessToken called once' );
    ok( !-e $backup_file, 'no backup file written' );
    is( stored_password('default'), 'old-secret', 'DB row unchanged' );
    is( scalar @cache_clear, 0, 'cache not cleared' );
};

subtest 'test_password (wrong) reports an error' => sub {
    reset_mocks();
    seed_config();
    $rest_mock->mock( 'fetchAccessToken', sub { die "401 Unauthorized\n" } );
    my ( $code, $err, $out, $fatal ) = run_script( '--branchcode=default', '--test_password' );
    unlike( $out // '', qr/The provided old password is correct\./, 'not reported correct' );
    like( ( $fatal // '' ) . ( $err // '' ) . ( $out // '' ), qr/401 Unauthorized/, 'error surfaced' );
    # restore
    $rest_mock->mock(
        'fetchAccessToken',
        sub { push @fetch_calls, [@_]; return { access_token => 'fake-token', expires_in => 3600 } }
    );
};

subtest 'change without --store does not persist' => sub {
    reset_mocks();
    seed_config();
    my $backup_dir  = tempdir( CLEANUP => 1 );
    my $backup_file = "$backup_dir/backup.txt";
    my ( $code, $err, $out, $fatal ) = run_script( '--branchcode=default', "--backup=$backup_file" );
    ok( !defined $fatal, 'script completed without a fatal error' );
    ok( -e $backup_file, 'backup file written' );
    my $backed = read_file($backup_file);
    chomp $backed;
    is( scalar @change_calls, 1, 'changePassword called once' );
    my $change = $change_calls[0];
    is( $change->[1], '/v1/change-password', 'changePassword endpoint' );
    is( $change->[3]{currentPassword}, 'old-secret', 'current password sent' );
    is( $change->[3]{accessToken}, 'fake-token', 'access token sent' );
    is( $backed, $change->[3]{newPassword}, 'backup holds the new password' );
    like( $out, qr/Not storing in plugin_data/, 'not-stored message printed' );
    is( stored_password('default'), 'old-secret', 'DB row unchanged' );
    is( scalar @cache_clear, 1, 'cache cleared once' );
    is( $cache_clear[0], 'kscache', 'correct cache key cleared' );
};

subtest 'change with --store persists to DB' => sub {
    reset_mocks();
    seed_config();
    my $backup_dir  = tempdir( CLEANUP => 1 );
    my $backup_file = "$backup_dir/backup.txt";
    my ( $code, $err, $out, $fatal ) = run_script( '--branchcode=default', '--store', "--backup=$backup_file" );
    ok( !defined $fatal, 'script completed without a fatal error' );
    ok( -e $backup_file, 'backup file written' );
    is( scalar @change_calls, 1, 'changePassword called once' );
    my $new_pw = $change_calls[0][3]{newPassword};
    is( stored_password('default'), $new_pw, 'DB row updated to the new password' );
    like( $out, qr/Password stored in plugin_data/, 'stored message printed' );
};

subtest 'cached access token is reused' => sub {
    reset_mocks();
    seed_config();
    $cached_token = 'cached-token';
    my $backup_dir  = tempdir( CLEANUP => 1 );
    my $backup_file = "$backup_dir/backup.txt";
    my ( $code, $err, $out, $fatal ) = run_script( '--branchcode=default', "--backup=$backup_file" );
    ok( !defined $fatal, 'script completed without a fatal error' );
    is( scalar @fetch_calls, 0, 'fetchAccessToken not called' );
    is( scalar @change_calls, 1, 'changePassword called' );
    is( $change_calls[0][3]{accessToken}, 'cached-token', 'cached token used' );
    $cached_token = undef;
};

subtest 'backup is written even if changePassword fails' => sub {
    reset_mocks();
    seed_config();
    $rest_mock->mock( 'changePassword', sub { die "change failed\n" } );
    my $backup_dir  = tempdir( CLEANUP => 1 );
    my $backup_file = "$backup_dir/backup.txt";
    my ( $code, $err, $out, $fatal ) = run_script( '--branchcode=default', "--backup=$backup_file" );
    ok( -e $backup_file, 'backup file written before failure' );
    my $backed = read_file($backup_file);
    chomp $backed;
    ok( $backed =~ /\S/, 'backup contains a password' );
    like( ( $fatal // '' ) . ( $err // '' ) . ( $out // '' ), qr/change failed/, 'failure surfaced' );
    # restore
    $rest_mock->mock(
        'changePassword',
        sub { push @change_calls, [@_]; return {} }
    );
};

subtest 'per-branch password and isolation' => sub {
    reset_mocks();
    seed_config();
    my $backup_dir  = tempdir( CLEANUP => 1 );
    my $backup_file = "$backup_dir/backup.txt";
    my ( $code, $err, $out, $fatal ) = run_script( '--branchcode=ZT2', '--store', "--backup=$backup_file" );
    ok( !defined $fatal, 'script completed without a fatal error' );
    is( scalar @change_calls, 1, 'changePassword called once' );
    my $change = $change_calls[0];
    is( $change->[3]{currentPassword}, 'zt2-old', 'uses the branch password' );
    my $new_pw = $change->[3]{newPassword};
    is( stored_password('ZT2'), $new_pw, 'ZT2 DB row updated' );
    is( stored_password('default'), 'old-secret', 'default DB row untouched' );
};

subtest 'old_password overrides the stored password' => sub {
    reset_mocks();
    seed_config();
    my $backup_dir  = tempdir( CLEANUP => 1 );
    my $backup_file = "$backup_dir/backup.txt";
    my ( $code, $err, $out, $fatal ) = run_script(
        '--branchcode=default', '--old_password=provided-old', "--backup=$backup_file"
    );
    ok( !defined $fatal, 'script completed without a fatal error' );
    is( scalar @change_calls, 1, 'changePassword called once' );
    is( $change_calls[0][3]{currentPassword}, 'provided-old', 'provided old password is used' );
    is( stored_password('default'), 'old-secret', 'DB row unchanged without --store' );
};

done_testing;