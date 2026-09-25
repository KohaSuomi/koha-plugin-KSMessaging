#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::MockModule;
use Test::MockObject;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";
use File::Temp qw(tempdir);
use Archive::Zip qw(:ERROR_CODES);

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::File
    qw(WriteiPostEPL WriteiPostPDF WriteiPostArchive GetTransferConfig FileTransfer);

my $FileClass = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::File';
my $deliver_config;

my $file_mock = Test::MockModule->new($FileClass);
$file_mock->mock( '_deliver_config', sub { return $deliver_config } );

sub make_fake_config {
    my (%args) = @_;
    my $fc = Test::MockObject->new;
    $fc->mock( 'stagingDir',           sub { $args{stagingdir} } );
    $fc->mock( 'getFileTransferConfig', sub { return $args{transfer} || {} } );
    return $fc;
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<:encoding(latin1)', $path or die "Can't read $path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    return $content;
}

subtest 'WriteiPostEPL latin1' => sub {
    my $tempdir = tempdir( CLEANUP => 1 );
    $deliver_config = make_fake_config( stagingdir => "$tempdir" );
    WriteiPostEPL( epl => "hel\x{f6}\r\n", filename => 'a.epl', branchconfig => 'default' );
    ok( -e "$tempdir/a.epl", 'EPL file written to staging dir' );
    is( read_file("$tempdir/a.epl"), "hel\x{f6}\r\n", 'latin1 content preserved round-trip' );
};

subtest 'WriteiPostEPL unconvertible chars' => sub {
    my $tempdir = tempdir( CLEANUP => 1 );
    $deliver_config = make_fake_config( stagingdir => "$tempdir" );
    local $SIG{__WARN__} = sub {};
    WriteiPostEPL( epl => "euro=\x{20ac}\r\n", filename => 'b.epl', branchconfig => 'default' );
    is( read_file("$tempdir/b.epl"), "euro=?\r\n", 'unconvertible char replaced with ?' );
};

subtest 'WriteiPostPDF creates missing staging dir' => sub {
    my $base   = tempdir( CLEANUP => 1 );
    my $newdir = "$base/missingdir";
    $deliver_config = make_fake_config( stagingdir => $newdir );
    WriteiPostPDF( pdf => '%PDF-x', filename => 'a.pdf', interface => 'letters', branchconfig => 'default' );
    ok( -d $newdir, 'staging dir auto-created' );
    ok( -e "$newdir/a.pdf", 'PDF file written' );
    is( read_file("$newdir/a.pdf"), '%PDF-x', 'PDF content preserved' );
};

subtest 'WriteiPostArchive' => sub {
    my $tempdir = tempdir( CLEANUP => 1 );
    $deliver_config = make_fake_config( stagingdir => "$tempdir" );
    WriteiPostArchive(
        pdf         => '%PDF-1',
        xml         => '<x/>',
        pdfname     => '1.pdf',
        xmlname     => '1.xml',
        filename    => 'a.zip',
        interface   => 'letters',
        branchconfig => 'default',
    );
    ok( -e "$tempdir/a.zip", 'archive written' );
    my $zip = Archive::Zip->new;
    is( $zip->read("$tempdir/a.zip"), AZ_OK, 'archive is a readable zip' );
    my @names = sort map { $_->fileName } $zip->members;
    is_deeply( \@names, [ '1.pdf', '1.xml' ], 'archive contains pdf and xml' );

    my @warns;
    local $SIG{__WARN__} = sub { push @warns, $_[0] };
    WriteiPostArchive(
        pdf         => 'NEW',
        xml         => '<y/>',
        pdfname     => '1.pdf',
        xmlname     => '1.xml',
        filename    => 'a.zip',
        interface   => 'letters',
        branchconfig => 'default',
    );
    ok( @warns >= 1, 'overwriting an existing archive warns' );
    my $zip2 = Archive::Zip->new;
    is( $zip2->read("$tempdir/a.zip"), AZ_OK, 'overwritten archive still readable' );
    my ($pdf) = grep { $_->fileName eq '1.pdf' } $zip2->members;
    like( $pdf->contents, qr/NEW/, 'archive replaced with new pdf content' );
};

subtest 'GetTransferConfig' => sub {
    $deliver_config = make_fake_config(
        transfer => { host => 'h', port => 22, remotedir => 'r', user => 'u', password => 'p', protocol => 'sftp' } );
    my %cfg = GetTransferConfig( interface => 'letters', branchconfig => 'default' );
    is_deeply(
        \%cfg,
        { host => 'h', port => 22, remotedir => 'r', user => 'u', password => 'p', protocol => 'sftp' },
        'transfer config keys extracted'
    );
};

subtest 'FileTransfer sftp' => sub {
    my $tempdir = tempdir( CLEANUP => 1 );
    $deliver_config = make_fake_config(
        stagingdir => "$tempdir",
        transfer   => { host => 'h', port => 22, remotedir => 'r', user => 'u', password => 'p', protocol => 'sftp' } );
    my $sftp_mock = Test::MockModule->new('C4::KohaSuomi::SFTP');
    my @sftp_args;
    $sftp_mock->mock( 'sftp_transfer', sub { my ( $files, $cfg, $dir ) = @_; @sftp_args = ( $files, $cfg, $dir ); return 1 } );
    local *STDERR;
    open STDERR, '>', '/dev/null' or die $!;
    my $res = FileTransfer( interface => 'letters', branchconfig => 'default', filename => 'out.zip' );
    is( $res, 1, 'sftp transfer returns success' );
    is_deeply( $sftp_args[0], ['out.zip'], 'sftp receives the filename as a list' );
    is( $sftp_args[1]->{host}, 'h',        'sftp receives the transfer config' );
    is( $sftp_args[2], "$tempdir",         'sftp receives the staging dir' );
};

subtest 'FileTransfer not configured' => sub {
    my $tempdir = tempdir( CLEANUP => 1 );
    $deliver_config = make_fake_config( stagingdir => "$tempdir", transfer => {} );
    local *STDERR;
    open STDERR, '>', '/dev/null' or die $!;
    my $res = FileTransfer( interface => 'letters', branchconfig => 'default', filename => 'out.zip' );
    is( $res, 1, 'transfer skipped when not configured returns 1' );
};

subtest 'FileTransfer unknown protocol' => sub {
    my $tempdir = tempdir( CLEANUP => 1 );
    $deliver_config = make_fake_config(
        stagingdir => "$tempdir",
        transfer   => { host => 'h', user => 'u', password => 'p', protocol => 'carrier-pigeon' } );
    local *STDERR;
    open STDERR, '>', '/dev/null' or die $!;
    my $res = FileTransfer( interface => 'letters', branchconfig => 'default', filename => 'out.zip' );
    is( $res, 0, 'unknown protocol returns 0' );
};

done_testing;