#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::MockObject;
use FindBin qw($Bin);
use lib "$Bin/../../../../../..";
use HTTP::Response;
use File::Temp qw(tempfile);
use JSON qw(decode_json);

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST;

my $RESTClass = 'Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST';

my $ua_mock = Test::MockModule->new($RESTClass);
my @requests;
my $response;
my $fake_ua = Test::MockObject->new;
$fake_ua->mock( 'request', sub { push @requests, $_[1]; return $response } );
$ua_mock->mock( 'ua',      sub { return $fake_ua } );

my $rest = $RESTClass->new( { baseUrl => 'https://suomi.example/' } );

subtest 'baseUrl' => sub {
    is( $rest->baseUrl, 'https://suomi.example/', 'baseUrl accessor' );
};

subtest 'fetchAccessToken success' => sub {
    @requests = ();
    $response = HTTP::Response->new( 200, 'OK', ['Content-Type' => 'application/json'],
        '{"access_token":"tok1","expires_in":3600}' );
    my $token = $rest->fetchAccessToken( '/v1/token', 'application/json', { username => 'u', password => 'p' } );
    is( $token->{access_token}, 'tok1', 'access_token decoded' );
    is( $token->{expires_in},   3600,   'expires_in decoded' );
    my $req = $requests[0];
    is( $req->method, 'POST', 'token request is POST' );
    is( $req->uri,    'https://suomi.example//v1/token', 'token request URI (baseUrl+endpoint concatenation)' );
    is( $req->header('Content-Type'), 'application/json', 'token content type' );
    is_deeply( decode_json( $req->content ), { password => 'p', username => 'u' }, 'token body is JSON' );
};

subtest 'fetchAccessToken failure' => sub {
    @requests = ();
    $response = HTTP::Response->new( 401, 'Unauthorized' );
    my $ok = eval {
        local *STDOUT;
        open STDOUT, '>', '/dev/null' or die $!;
        $rest->fetchAccessToken( '/v1/token', 'application/json', {} );
        1;
    };
    ok( !$ok, 'fetchAccessToken died on failure' );
    like( $@, qr/Unauthorized/, 'dies with status line' );
};

subtest 'changePassword' => sub {
    @requests = ();
    $response = HTTP::Response->new( 200, 'OK', ['Content-Type' => 'application/json'], '{"ok":1}' );
    my $res = $rest->changePassword( '/v1/change-password', 'application/json', { old => 'a', new => 'b' } );
    is( $res->{ok}, 1, 'changePassword returns decoded response' );
    is( $requests[0]->method, 'POST', 'changePassword is POST' );

    @requests = ();
    $response = HTTP::Response->new( 500, 'Internal Server Error' );
    my $ok = eval {
        local *STDOUT;
        open STDOUT, '>', '/dev/null' or die $!;
        $rest->changePassword( '/v1/change-password', 'application/json', {} );
        1;
    };
    ok( !$ok, 'changePassword died on failure' );
    like( $@, qr/Internal Server Error/, 'dies with status line' );
};

subtest 'send JSON' => sub {
    @requests = ();
    $response = HTTP::Response->new( 200, 'OK', ['Content-Type' => 'application/json'], '{"ok":1}' );
    my $res = $rest->send( '/v2/messages', 'application/json', 'tok1', { externalId => '7' } );
    is( $res->{ok}, 1, 'send returns decoded JSON' );
    my $req = $requests[0];
    is( $req->method, 'POST', 'send is POST' );
    is( $req->header('Authorization'), 'Bearer tok1', 'send includes bearer token' );
    is( $req->header('Content-Type'),  'application/json', 'send JSON content type' );
    is_deeply( decode_json( $req->content ), { externalId => '7' }, 'send JSON body' );
};

subtest 'send form-data' => sub {
    @requests = ();
    my ( $fh, $fname ) = tempfile( SUFFIX => '.pdf' );
    print {$fh} '%PDF-1.4';
    close $fh;
    $response = HTTP::Response->new( 200, 'OK', ['Content-Type' => 'application/json'], '{"id":"fid"}' );
    my $res = $rest->send( '/v2/attachments', 'form-data', 'tok1', $fname );
    is( $res->{id}, 'fid', 'form-data upload returns decoded response' );
    my $req = $requests[0];
    is( $req->method, 'POST', 'upload is POST' );
    like( $req->header('Content-Type'), qr/multipart\/form-data/, 'form-data content type is multipart' );
    unlink $fname;
};

subtest 'send failure' => sub {
    @requests = ();
    $response = HTTP::Response->new( 403, 'Forbidden' );
    my $ok = eval {
        local *STDOUT;
        open STDOUT, '>', '/dev/null' or die $!;
        $rest->send( '/v2/messages', 'application/json', 'tok1', {} );
        1;
    };
    ok( !$ok, 'send died on failure' );
    like( $@, qr/Forbidden/, 'dies with status line' );
};

subtest 'get' => sub {
    @requests = ();
    $response = HTTP::Response->new( 200, 'OK', ['Content-Type' => 'application/json'], '{"state":"sent"}' );
    my $res = $rest->get( '/v1/messages/1', 'application/json', 'tok1', {} );
    is( $res->{state}, 'sent', 'get returns decoded response' );
    my $req = $requests[0];
    is( $req->method, 'GET', 'get is GET' );
    is( $req->header('Authorization'), 'Bearer tok1', 'get includes bearer token' );
    is( $req->uri, 'https://suomi.example//v1/messages/1', 'get URI (baseUrl+endpoint concatenation)' );
};

done_testing;