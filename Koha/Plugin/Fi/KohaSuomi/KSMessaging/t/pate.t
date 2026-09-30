#!/usr/bin/perl
use strict;
use warnings;
use utf8;

# Integration test for cronjobs/pate.pl against a live Koha database.
#
# Everything runs inside a single transaction that is rolled back at the end,
# so no fixture rows or status changes persist.  Output goes to a File::Temp
# staging directory.  Only the physical outside world is mocked:
#   * Deliver::REST HTTP calls             (fetchAccessToken / send)
#   * Deliver::File::FileTransfer network  (recorded, canned result)
# The SSN database is never touched: positive SSN paths use --test-id and the
# negative path relies on the borrower having no 'SSN' attribute (the real
# SsnProvider module then returns undef from the main Koha database).
#
# Run from the plugin repo root.  The plugin modules resolve via $Bin; the Koha
# source is taken from $KOHA_PATH (single dir, also exported on the server),
# $KOHA_HOME (colon-separated search list) or $KOHA_SRC, falling back to the
# local dev checkout and otherwise the runner's PERL5LIB.
#
#     # normal run (nothing persists)
#     KOHA_CONF=/path/to/koha-conf.xml \
#     PERL5LIB=/path/to/koha:/path/to/koha/t \
#       prove -v Koha/Plugin/Fi/KohaSuomi/KSMessaging/t/pate.t
#
#     # inspect created messages + keep the staged files in /tmp/ks_report
#     KOHA_PATH=/path/to/koha KS_REPORT=1 KS_STAGING=/tmp/ks_report \
#       prove -v Koha/Plugin/Fi/KohaSuomi/KSMessaging/t/pate.t
#
# With KS_REPORT=1 the test prints (to STDERR, right before the transaction is
# rolled back) every created fixture message with its final status plus the
# files written into the staging dir, so created messages can be inspected
# without anything persisting in the live Koha database.  With KS_STAGING=
# /path the staging files (EPL/PDF/ZIP) are left on disk in that directory
# instead of a temporary, auto-cleaned directory.

use Test::More;
use Test::MockModule;

use FindBin qw($Bin);
use Cwd qw(abs_path);

use lib abs_path("$Bin/../../../../../..");              # plugin repo root

# Koha classes + TestBuilder.  Not derivable from $Bin (the Koha source lives
# outside this repo), so resolve from the environment:
#   * KOHA_PATH  - single Koha source directory
#   * KOHA_HOME  - colon-separated search list (like PERL5LIB)
# For each entry, <dir>/t is added as well (t::lib::TestBuilder lives there).
# Falls back to the local dev checkout if none of the above is set, and
# otherwise relies on the runner's PERL5LIB.
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
use C4::Letters;
use Koha::Patrons;
use Koha::Libraries;
use Koha::Patron::Categories;
use Koha::Notice::Messages;

use File::Temp qw(tempdir tempfile);
use t::lib::TestBuilder;

my $PLUGIN_CLASS = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging';
my $CONFIG_CLASS = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config';
my $REST_CLASS   = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST';
my $FILE_CLASS   = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::File';

my $SCRIPT = abs_path("$Bin/../cronjobs/pate.pl");abs_path
die "pate.pl not found at $SCRIPT" unless -e $SCRIPT;

# --- database wrapper ------------------------------------------------------

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;
my $dbh = C4::Context->dbh;
my $connected = eval { $dbh->do("SELECT 1"); 1 };
die "Cannot connect to the Koha database (is the dev instance running?): $@" unless $connected;

my @report;    # created fixture messages, for KS_REPORT=1 inspection
my $staging;   # assigned below; needed by the KS_REPORT END block

END {
    if ( $ENV{KS_REPORT} && @report ) {
        print STDERR "\nKS_REPORT: fixture messages created during this run\n";
        for my $r (@report) {
            printf STDERR "  message_id=%-12d borrowernumber=%-10d %-4s %-6s %-14s status=%s\n",
                $r->{message_id}, $r->{borrowernumber}, $r->{branchcode},
                $r->{transport}, $r->{letter_code}, message_status( $r->{message_id} );
            print STDERR "    subject: $r->{subject}\n";
        }
        print STDERR "KS_REPORT: files in staging dir $staging\n";
        for my $f ( sort glob( "$staging/*" ) ) {
            print STDERR "  " . substr( $f, length($staging) + 1 ) . "\n";
        }
        print STDERR "KS_REPORT: end\n";
    }

    $schema->storage->txn_rollback
        if defined $schema && eval { $schema->storage->in_txn; 1 };
}

my $builder = t::lib::TestBuilder->new;

# --- script runner: execute the real pate.pl in-process --------------------

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

sub run_pate {
    my (@args) = @_;
    local @ARGV = @args;

    my ( undef, $errfile )  = tempfile( UNLINK => 1 );
    my ( undef, $outfile )  = tempfile( UNLINK => 1 );
    open my $saved_err,  '>&', *main::STDERR or die "cannot dup STDERR: $!";
    open my $saved_out,  '>&', *main::STDOUT or die "cannot dup STDOUT: $!";
    open main::STDERR,   '>',  $errfile      or die "cannot redirect STDERR: $!";
    open main::STDOUT,   '>',  $outfile      or die "cannot redirect STDOUT: $!";
    binmode main::STDERR, ':encoding(utf8)';
    binmode main::STDOUT, ':encoding(utf8)';

    $exit_code = undef;
    my $ran = eval {
        no warnings 'redefine';
        local $SIG{__WARN__} = sub { my $m = shift; warn $m unless $m =~ /redefined at/ };
        do "$SCRIPT";
        1;
    };

    close main::STDERR;    # flush buffered progress output
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

    my $eval_err = $@;
    die "pate.pl died unexpectedly: $eval_err" unless defined $exit_code;
    return ( $exit_code, $stderr, $stdout );
}

# --- mocks for the physical outside world ----------------------------------

my @ft_calls;
my $ft_result = 1;

my $ft_mock = Test::MockModule->new($FILE_CLASS);
$ft_mock->mock(
    'FileTransfer',
    sub {
        my %param = @_;
        push @ft_calls, { %param };
        return $ft_result;
    }
);

my @rest_calls;
my $rest_mock = Test::MockModule->new($REST_CLASS);
$rest_mock->mock(
    'fetchAccessToken',
    sub { return { access_token => 'fake-token', expires_in => 3600 } }
);
$rest_mock->mock(
    'send',
    sub {
        my ( $self, $endpoint ) = @_;
        push @rest_calls, $endpoint;
        return { attachmentId => 'ATT-' . scalar @rest_calls };
    }
);

# --- fixture helpers --------------------------------------------------------

sub create_library {
    my ($code) = @_;
    return $builder->build_object( { class => 'Koha::Libraries', value => { branchcode => $code } } );
}

sub create_patron {
    my ($branchcode) = @_;
    return $builder->build_object(
        { class => 'Koha::Patrons', value => { branchcode => $branchcode, categorycode => 'PT' } }
    );
}

sub queue_message {
    my ( $borrowernumber, $transport, $letter_code, $subject ) = @_;
    $dbh->do( 'INSERT IGNORE INTO message_transport_types (message_transport_type) VALUES (?)',
        undef, $transport );
    my $sth = $dbh->prepare(
        'INSERT INTO message_queue
         (borrowernumber, letter_code, message_transport_type, status, subject, content,
          to_address, from_address, time_queued)
         VALUES (?,?,?,?,?,?,?,?,NOW())'
    );
    $sth->execute( $borrowernumber, $letter_code, $transport, 'pending', $subject,
        "This is the content of the letter for test purposes.", 'patron@example.com', 'library@example.com' );
    my $id = $dbh->{mysql_insertid};
    push @report,
        {
        message_id     => $id,
        borrowernumber => $borrowernumber,
        branchcode     => Koha::Patrons->find($borrowernumber)->branchcode,
        transport      => $transport,
        letter_code    => $letter_code,
        subject        => $subject,
        };
    return $id;
}

sub message_status {
    my ($id) = @_;
    my $m = Koha::Notice::Messages->find($id);
    return $m ? $m->status : 'not found';
}

if ( $ENV{KS_STAGING} ) {
    $staging = $ENV{KS_STAGING};
    mkdir $staging unless -d $staging;
}
else {
    $staging = tempdir( CLEANUP => 1 );
}

sub seed_config {
    my ( $combine, $skipletters, $default_ft_protocol ) = @_;
    $combine              ||= 'no';
    $skipletters          ||= '';
    $default_ft_protocol  ||= '';

    my $default_filetransfer = $default_ft_protocol ? qq{
      filetransfer:
        host: "h"
        port: 22
        remotedir: "in"
        user: "u"
        password: "p"
        protocol: "$default_ft_protocol"} : '';

    my $yaml = qq{
letters:
  skipletters: "$skipletters"
  combineacrossbranches: "$combine"
  branches:
    default:
      contact: "kirjasto\@test.fi"
      stagingdir: "$staging"$default_filetransfer
      ipostepl:
        code: "1000"
        encoding: "latin1"
        fileprefix: ""
        header: "TESTREC"
        layout:
          templatecode: "TESTPL"
          contpagecode: ""
          firstpage: 20
          otherpages: 20
      ipostpdf:
        customerid: "123"
        customerpass: "pw"
        ovtid: "OVT1"
        senderid: "SND1"
    ZT2:
      contact: "kirjasto-cpl\@test.fi"
      stagingdir: "$staging"
      filetransfer:
        host: "testhost"
        port: 22
        remotedir: "in"
        user: "testuser"
        password: "testpw"
        protocol: "sftp"
      ipostepl:
        code: "2000"
        encoding: "latin1"
        fileprefix: "C"
        header: "TESTREC2"
        layout:
          templatecode: "TESTPL2"
          contpagecode: ""
          firstpage: 20
          otherpages: 20
    ZT3:
      contact: "kirjasto-mtk\@test.fi"
      stagingdir: "$staging"
      ipostpdf:
        customerid: "124"
        customerpass: "pw"
        ovtid: "OVT2"
        senderid: "SND2"
suomifi:
  branches:
    default:
      contact: "suomifi\@test.fi"
      cachekey: "kscache"
      stagingdir: "$staging"
      rest:
        baseUrl: "https://rest.test.invalid/"
        username: "tester"
        serviceid: "svc1"
      ipostpdf:
        customerid: "777"
        customerpass: "pw2"
        ovtid: "OVT9"
        senderid: "SND9"
        printprovider: "PP1"
        fileprefix: "SP"
    ZT2:
      contact: "suomifi-cpl\@test.fi"
      cachekey: "kscache"
      stagingdir: "$staging"
      rest:
        baseUrl: "https://rest.test.invalid/"
        username: "tester"
        password: "secret"
        serviceid: "svc-cpl"
      ipostpdf:
        customerid: "778"
        customerpass: "pw3"
        ovtid: "OVT8"
        senderid: "SND8"
        printprovider: "PP2"
        fileprefix: "SPC"
    ZT3:
      contact: "suomifi-mtk\@test.fi"
      cachekey: "kscache"
      stagingdir: "$staging"
      ipostpdf:
        customerid: "779"
        customerpass: "pw4"
        ovtid: "OVT7"
        senderid: "SND7"
        printprovider: "PP3"
        fileprefix: "MP"
};

    my $sth = $dbh->prepare(
        'INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
         VALUES (?,?,?) ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value)'
    );
    $sth->execute( $PLUGIN_CLASS, 'ksmessaging_config', $yaml );
    $sth = $dbh->prepare(
        'INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
         VALUES (?,?,?) ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value)'
    );
    $sth->execute( $PLUGIN_CLASS, 'suomifi_rest_password_default', 'verysecret' ); 
}

# --- fixtures used by most subtests ----------------------------------------

$builder->build_object(
    {   class => 'Koha::Patron::Categories',
        value => {
            categorycode  => 'PT',
            category_type => 'A',
            description   => 'Adults (test)',
        }
    }
);

create_library('ZT1');
create_library('ZT2');
create_library('ZT3');

my $patron_dpl = create_patron('ZT1');
my $patron_cpl = create_patron('ZT2');
my $patron_mtk = create_patron('ZT3');

my $processed = sub {
    my ($stderr) = @_;
    return unless $stderr =~ /(\d+) messages processed, (\d+) undelivered\./;
    return ( $1, $2 );
};

# ===========================================================================

subtest 'help and mode guards' => sub {
    seed_config();
    my ( $code, $err, $out ) = run_pate('--help');
    is( $code, 0, '--help exits 0' );
    like( $out, qr/Usage:/, '--help prints usage' );

    ( $code, $err ) = run_pate();
    is( $code, 1, 'no mode exits 1' );
    like( $err, qr/Select exactly one mode/, 'no mode prints an error' );

    ( $code, $err ) = run_pate( '--letters', '--suomifi' );
    is( $code, 1, 'two modes exits 1' );

    # Guard: no configuration at all
    my $guard_mock = Test::MockModule->new($CONFIG_CLASS);
    $guard_mock->mock( 'rootConfig', sub { return undef } );
    ( $code, $err ) = run_pate('--letters');
    is( $code, 1, 'missing configuration exits 1' );
    like( $err, qr/No configuration found for ksmessaging/, 'guard message on stderr' );
    $guard_mock->unmock('rootConfig');
};

subtest 'letters EPL delivery' => sub {
    seed_config();
    my $id = queue_message( $patron_dpl->borrowernumber, 'print', 'NOTICE', 'My letter' );

    @ft_calls = ();
    $ft_result = 1;

    my ( $code, $err ) = run_pate( '--letters', "--messages=$id" );
    is( $code, 0, 'letters EPL run exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'one message processed, none undelivered' );
    ok( -e "$staging/ZT1-$id.epl", 'EPL file written to staging dir' );
    is( message_status($id), 'sent', 'message marked sent' );
    is( scalar @ft_calls, 1, 'FileTransfer called once' );
    is( $ft_calls[0]{branchconfig}, 'default', 'FileTransfer uses default branch config' );
};

subtest 'letters ipostpdf delivery' => sub {
    seed_config();
    my $id = queue_message( $patron_mtk->borrowernumber, 'print', 'IPOST', 'A PDF letter' );

    @ft_calls = ();
    $ft_result = 1;

    my ( $code, $err ) = run_pate( '--letters', "--messages=$id" );
    is( $code, 0, 'letters ipostpdf run exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'one message processed, none undelivered' );
    ok( -e "$staging/ZT3-$id.zip", 'iPostPDF archive written to staging dir' );
    is( message_status($id), 'sent', 'message marked sent' );
    is( $ft_calls[0]{branchconfig}, 'default', 'FileTransfer uses default branch config' );
};

subtest 'letters skipletters' => sub {
    seed_config( 'no', 'SKIP1' );
    my $skip = queue_message( $patron_dpl->borrowernumber, 'print', 'SKIP1', 'Skipped letter' );
    my $keep = queue_message( $patron_dpl->borrowernumber, 'print', 'NOTICE', 'Kept letter' );

    @ft_calls = ();
    $ft_result = 1;

    my ( $code, $err ) = run_pate( '--letters', "--messages=$skip,$keep" );
    is( $code, 0, 'run with a skipped letter exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'only the non-skipped letter is processed' );
    is( message_status($keep), 'sent', 'non-skipped letter sent' );
    is( message_status($skip), 'pending', 'skipped letter left pending' );
    ok( !-e "$staging/ZT1-$skip.epl", 'no file written for the skipped letter' );
};

subtest 'letters combineacrossbranches' => sub {
    seed_config( 'no', '' );
    my $id = queue_message( $patron_cpl->borrowernumber, 'print', 'NOTICE', 'Combine no' );

    @ft_calls = ();
    $ft_result = 1;

    my ( $code, $err ) = run_pate( '--letters', "--messages=$id" );
    is( $code, 0, 'combine=no run exits 0' );
    is( $ft_calls[0]{branchconfig}, 'ZT2', 'branch-specific filetransfer used when combine is no' );

    seed_config( 'yes', '' );
    my $id2 = queue_message( $patron_cpl->borrowernumber, 'print', 'NOTICE', 'Combine yes' );

    @ft_calls = ();
    ( $code, $err ) = run_pate( '--letters', "--messages=$id2" );
    is( $code, 0, 'combine=yes run exits 0' );
    is( $ft_calls[0]{branchconfig}, 'default', 'default filetransfer used when combine is yes' );
};

subtest 'letters file transfer failure (real FileTransfer)' => sub {
    # Configure the default branch with an unknown protocol so the real
    # FileTransfer returns 0 without touching any network.
    seed_config( 'no', '', 'tftp' );
    $ft_mock->unmock('FileTransfer');
    my $id = queue_message( $patron_dpl->borrowernumber, 'print', 'NOTICE', 'Failing letter' );

    my ( $code, $err ) = run_pate( '--letters', "--messages=$id" );
    is( $code, 1, 'failed transfer exits 1' );
    like( $err, qr/Unknown protocol tftp/, 'real FileTransfer reports the unknown protocol' );
    like( $err, qr/File transfer failed\./, 'pate reports the transfer failure' );
    is_deeply( [ $processed->($err) ], [ 1, 1 ], 'one message processed, one undelivered' );
    is( message_status($id), 'failed', 'message marked failed' );

    $ft_mock->redefine( 'FileTransfer', sub { my %param = @_; push @ft_calls, {%param}; return $ft_result } );
};

subtest 'suomifi REST delivery' => sub {
    seed_config();
    my $id = queue_message( $patron_cpl->borrowernumber, 'suomifi', 'SUOMI', 'REST message' );

    @rest_calls = ();
    my ( $code, $err ) = run_pate( '--suomifi', "--messages=$id", '--test-id=TESTREST' );
    is( $code, 0, 'suomifi REST run exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'one message processed, none undelivered' );
    is( message_status($id), 'sent', 'message marked sent' );
    is( $rest_calls[0], '/v2/attachments', 'attachment uploaded first' );
    ok( grep { $_ eq '/v2/messages' || $_ eq '/v2/paper-mail-without-id' } @rest_calls,
        'message posted to the REST API' );
    my @pdfs = glob "$staging/SPC_*.pdf";
    ok( scalar @pdfs, 'a PDF letter written to staging dir' );
};

subtest 'suomifi ipost delivery via test-id (no ssn db)' => sub {
    seed_config();
    my $id = queue_message( $patron_mtk->borrowernumber, 'suomifi', 'SUOMI', 'iPost message' );

    @ft_calls = ();
    $ft_result = 1;

    my ( $code, $err ) = run_pate( '--suomifi', "--messages=$id", '--test-id=TESTIPOST' );
    is( $code, 0, 'suomifi ipost run exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'one message processed, none undelivered' );
    is( message_status($id), 'sent', 'message marked sent' );
    is( $ft_calls[0]{interface}, 'suomifi', 'FileTransfer called with the suomifi interface' );
    my @zips = glob "$staging/MP_*.zip";
    ok( scalar @zips, 'iPost archive written to staging dir' );
};

subtest 'suomifi ipost without SSN' => sub {
    seed_config();
    my $id = queue_message( $patron_mtk->borrowernumber, 'suomifi', 'SUOMI', 'No SSN message' );

    my ( $code, $err ) = run_pate( '--suomifi', "--messages=$id" );
    is( $code, 1, 'no-SSN run exits 1' );
    like( $err, qr/No SSN available/, 'missing SSN reported' );
    is_deeply( [ $processed->($err) ], [ 1, 1 ], 'one message processed, one undelivered' );
    is( message_status($id), 'failed', 'message marked failed' );
};

subtest 'letters routed as suomifi ipost' => sub {
    seed_config();
    my $id = queue_message( $patron_cpl->borrowernumber, 'print', 'NOTICE', 'Letter to suomifi' );

    @ft_calls = ();
    $ft_result = 1;

    my ( $code, $err ) = run_pate( '--letters-as-suomifi-ipost', "--messages=$id" );
    is( $code, 0, 'letters-as-suomifi-ipost run exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'one message processed, none undelivered' );
    is( message_status($id), 'sent', 'message marked sent' );
};

subtest 'letters routed as suomifi rest' => sub {
    seed_config();
    my $id = queue_message( $patron_cpl->borrowernumber, 'print', 'NOTICE', 'Letter via REST' );

    @rest_calls = ();
    my ( $code, $err ) = run_pate( '--letters-as-suomifi-rest', "--messages=$id" );
    is( $code, 0, 'letters-as-suomifi-rest run exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'one message processed, none undelivered' );
    is( message_status($id), 'sent', 'message marked sent' );
    ok( grep { $_ eq '/v2/messages' || $_ eq '/v2/paper-mail-without-id' } @rest_calls,
        'message posted to the REST API' );
};

subtest '--messages filters processing' => sub {
    seed_config();
    my $in  = queue_message( $patron_cpl->borrowernumber, 'suomifi', 'SUOMI', 'Selected message' );
    my $out = queue_message( $patron_cpl->borrowernumber, 'suomifi', 'SUOMI', 'Unselected message' );

    @rest_calls = ();
    my ( $code, $err ) = run_pate( '--suomifi', "--messages=$in", '--test-id=TESTFILTER' );
    is( $code, 0, 'filtered run exits 0' );
    is_deeply( [ $processed->($err) ], [ 1, 0 ], 'only the selected message is processed' );
    is( message_status($in), 'sent', 'selected message processed' );
    is( message_status($out), 'pending', 'unselected message left pending' );
};

done_testing;