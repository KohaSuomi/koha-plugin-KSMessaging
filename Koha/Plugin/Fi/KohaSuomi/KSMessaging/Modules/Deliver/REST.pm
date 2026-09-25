package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST;
use warnings;
use strict;
use utf8;

use LWP::UserAgent;
use HTTP::Request::Common qw( POST );
use JSON;

sub new {
    my ($class, $params) = @_;
    my $self = {};
    $self->{baseUrl} = $params->{baseUrl};
    bless($self, $class);
    return $self;

}

sub baseUrl {
    my ($self) = @_;
    return $self->{baseUrl};
}

sub ua {
    my ($self) = @_;
    my $ua = LWP::UserAgent->new;
    ## Set up proxy if needed, this is for testing purposes. Install LWP::Protocol::socks and set up a SOCKS proxy
    if ($ENV{HTTPS_PROXY}) {
        $ua->proxy(['http', 'https'], $ENV{HTTPS_PROXY});
    }
    return $ua;
}

=head2 fetchAccessToken

Fetch an access token from the REST API

=cut

sub fetchAccessToken {
    my ($self, $endpoint, $contentType, $content) = @_;
    my $ua = $self->ua;
    my $baseUrl = $self->baseUrl;
    my $req = POST(
        $baseUrl.$endpoint, 
        Content_Type => $contentType,
        Content => encode_json($content) 
    );
    my $res = $ua->request($req);
    if ($res->is_success) {
        return decode_json($res->content);
    } else {
        print "Error: ". $res->content . "\n";
        die $res->status_line;
    }
}

=head2 changePassword

Change the password for the REST API

=cut

sub changePassword {
    my ($self, $endpoint, $contentType, $content) = @_;
    my $ua = $self->ua;
    my $baseUrl = $self->baseUrl;
    my $req = POST(
        $baseUrl.$endpoint, 
        Content_Type => $contentType,
        Content => encode_json($content) 
    );
    my $res = $ua->request($req);
    if ($res->is_success) {
        return decode_json($res->content);
    } else {
        print "Error: ". $res->content . "\n";
        die $res->status_line;
    }
}

=head2 send

Send a request to the REST API

=cut

sub send {
    my ($self, $endpoint, $contentType, $accessToken, $content) = @_;
    my $ua = $self->ua;
    my $baseUrl = $self->baseUrl;

    if ($contentType eq 'application/json') {
        $content = encode_json($content);
    }
    if ($contentType eq 'form-data') {
        $content = [ file => [$content] ];
    }
    my $req = POST(
        $baseUrl.$endpoint, 
        Authorization => 'Bearer '.$accessToken, 
        Content_Type => $contentType, 
        Content => $content
    );

    my $res = $ua->request($req);
    if ($res->is_success) {
        my $json = decode_json($res->content);
        return $json;
    } else {
        print "Error: ". $res->content . "\n";
        die $res->status_line;
    }
}

sub get {
    my ($self, $endpoint, $contentType, $accessToken, $content) = @_;
    my $ua = $self->ua;
    my $baseUrl = $self->baseUrl;
    my $req = HTTP::Request->new(GET => $baseUrl.$endpoint);
    $req->header('Authorization' => 'Bearer '.$accessToken);
    $req->header('Content-Type' => $contentType);
    $req->content(encode_json($content)) if $content;
    my $res = $ua->request($req);
    if ($res->is_success) {
        return decode_json($res->content);
    } else {
        print "Error: ". $res->content . "\n";
        die $res->status_line;
    }
}

1;