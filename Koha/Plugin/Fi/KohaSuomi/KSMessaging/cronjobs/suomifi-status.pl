#!/usr/bin/perl

use Modern::Perl;
use C4::Context;
use Getopt::Long;
use Try::Tiny;
use POSIX qw(strftime);
use Koha::Notice::Messages;
use Koha::Patrons;

my $pluginsdir = C4::Context->config("pluginsdir");
use lib $pluginsdir;

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST;

my $help;
my $date = strftime "%Y-%m-%d", localtime;
my $message_id;

GetOptions(
    'help' => \$help,
    'date=s' => \$date,
    'message_id=s' => \$message_id,
);

if ($help) {
    print "Usage: $0 --date=YYYY-MM-DD --message_id=MESSAGE_ID\n";
    exit;
}

my $where = {
    status => { '=', 'sent' },
    message_transport_type => { '=', 'print' },
};

if ($message_id) {
    $where->{message_id} = { '=', $message_id };
} else {
    $where->{updated_on} = { '>=', $date };
}

my $notices = Koha::Notice::Messages->search($where);
print "Found " . $notices->count . " notices\n";
foreach my $notice (@{$notices->unblessed}) {
    my $patron = Koha::Patrons->find($notice->{borrowernumber});
    my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({
        interface => 'suomifi',
        branch => $patron->branchcode,
    });
    my $restConfig = $config->getRESTConfig();
    try {
        my $restClass = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST->new({baseUrl => $restConfig->{baseUrl}});
        my $cache = Koha::Caches->get_instance();
        my $accessToken = $cache->get_from_cache($config->cacheKey());

        unless ($accessToken) {
            print "Fetching a access token\n" if $ENV{'DEBUG'};
            my $tokenResponse = $restClass->fetchAccessToken('/v1/token', 'application/json', {password => $restConfig->{password}, username => $restConfig->{username}});
            $accessToken = $tokenResponse->{access_token};
            #Token should be valid for 5 seconds less than the expiry time
            $cache->set_in_cache($config->cacheKey(), $accessToken, { expiry => $tokenResponse->{expires_in} - 5 });
        }
        my $idResponse = $restClass->get('/v1/messages/id?externalId='.$notice->{message_id}, 'application/json', $accessToken);
        my $statusResponse = $restClass->get('/v1/messages/'.$idResponse->{messageId}.'/state', 'application/json', $accessToken);
        print "Electronic message status\n";
        for my $status (@{$statusResponse->{electronic}->{statuses}}) {
            print "Time: $status->{createdAt}, Status: $status->{status}\n";
        }
        print "Paper mail message status\n";
        for my $status (@{$statusResponse->{paperMail}->{statuses}}) {
            print "Time: $status->{createdAt}, Status: $status->{status}\n";
        }
    } catch {
        my $error = $_;
        print "Error: $error\n";
    };
}

