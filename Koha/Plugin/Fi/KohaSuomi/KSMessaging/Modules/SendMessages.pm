package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::SendMessages;

use Modern::Perl;
use Koha::Caches;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::CreateLetters;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::File qw(FileTransfer);
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::SuomiFi qw(RESTMessage);

# Constructor
sub new {
    my ($class, $params) = @_;
    my $self = {};
    $self->{interface} = $params->{interface};
    $self->{branch} = $params->{branch};
    $self->{method} = $params->{method};
    $self->{testID} = $params->{testID};
    $self->{methods} = ['suomifi_rest', 'ipost_pdf'];
    bless $self, $class;
    return $self;
}

sub interface {
    my ($self) = @_;
    return $self->{interface};
}

sub branch {
    my ($self) = @_;
    return $self->{branch};
}

sub method {
    my ($self) = @_;
    return $self->{method};
}

sub methods {
    my ($self) = @_;
    return @{$self->{methods}};
}

sub testID {
    my ($self) = @_;
    return $self->{testID};
}

sub config {
    my ($self) = @_;
    return Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({
        interface => $self->interface,
        branch => $self->branch,
    });
}

# Public method to send messages
sub send_message {
    my ($self, $message) = @_;

    die "Method not supported" unless grep { $_ eq $self->method } $self->methods;
    return $self->send_suomifi_rest($message) if $self->method eq 'suomifi_rest';
    return $self->send_ipost_pdf($message) if $self->method eq 'ipost_pdf';
}

sub send_suomifi_rest {
    my ($self, $message) = @_;
    
    my $config = $self->config;
    my $restConfig = $config->getRESTConfig;
    my $restClass = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST->new({baseUrl => $restConfig->{baseUrl}});
    my $cache = Koha::Caches->get_instance();
    my $accessToken = $cache->get_from_cache($config->cacheKey);
    
    unless ($accessToken) {
        my $tokenResponse = $restClass->fetchAccessToken('/v1/token', 'application/json', {password => $restConfig->{password}, username => $restConfig->{username}});
        $accessToken = $tokenResponse->{access_token};
        $cache->set_in_cache($config->cacheKey, $accessToken, { expiry => $tokenResponse->{expires_in} - 5 });
    }
    my $createLetters = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::CreateLetters->new({interface => $self->interface, branch => $self->branch, testID => $self->testID, type => 'pdf'});
    my $filename = $createLetters->create_ipost_letter($message);
    $filename = $config->stagingDir() . '/' . $filename;
    print "Sending the file: $filename\n";
    my $fileResponse = $restClass->send('/v2/attachments', 'form-data', $accessToken, $filename);
    print "File uploaded with response: " . Data::Dumper::Dumper($fileResponse) . "\n" if $ENV{'DEBUG'};
    print "Creating the RESTMessage for @$message{'message_id'}\n" if $ENV{'DEBUG'};
    my $messageData = RESTMessage(%{$message}, 'branchconfig' => $config->branchConfig, 'file_id' => $fileResponse->{attachmentId}, id => $self->testID);
    my $response;
    if ($messageData->{recipient}->{id}) {
        print "Sending the message @$message{'message_id'} with recipient ID\n" if $ENV{'DEBUG'};
        $response = $restClass->send('/v2/messages', 'application/json', $accessToken, $messageData);
    } else {
        print "No recipient ID found for message @$message{'message_id'}, sending without recipient\n" if $ENV{'DEBUG'};
        $response = $restClass->send('/v2/paper-mail-without-id', 'application/json', $accessToken, $messageData);
    }
    print "Message sent with response: " . Data::Dumper::Dumper($response) . "\n" if $ENV{'DEBUG'};
    return 1;
}

sub send_ipost_pdf {
    my ($self, $message) = @_;
    
    my $createLetters = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::CreateLetters->new({interface => $self->interface, branch => $self->branch, testID => $self->testID, type => 'ipost_pdf'});
    my $filename = $createLetters->create_ipost_letter($message);

    my $transfer = FileTransfer ( 'interface' => $self->interface, 'branchconfig' => $self->config->branchConfig(), 'filename' => "$filename" );
    if ($transfer) {
        return 1;
    } else {
        die "Failed to send iPost PDF";
    }
}

1;  # End of module