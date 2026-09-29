package Koha::Plugin::Fi::KohaSuomi::KSMessaging;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
## We will also need to include any Koha libraries we want to access
use C4::Context;
use utf8;

## Configuration module (read/write plugin_data config, fallback to koha-conf.xml)
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;
## Used to verify the CSRF token submitted with the configuration form
use Koha::Token;

## Here we set our plugin version
our $VERSION = "1.0.0";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'KSMessaging',
    author          => 'Johanna Räisä',
    date_authored   => '2026-09-23',
    date_updated    => '2026-09-23',
    minimum_version => '25.05',
    maximum_version => '',
    version         => $VERSION,
    description     => 'Messaging plugin',
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual 
    my $self = $class->SUPER::new($args);

    my ($name, $description) = $self->get_localized_metadata();
    $self->{metadata}->{name} = $name;
    $self->{metadata}->{description} = $description;

    return $self;
}

sub get_localized_metadata {
    my ($self) = @_;
    my $lang = C4::Languages::getlanguage() || 'en';
    my ($name, $description);

    if ( $lang eq 'sv-SE' ) {
        $name = "KSMessaging: Pate";
        $description = "Använder meddelanden via Suomi.fi eller iPost (Lokala databaser)";
    } elsif ( $lang eq 'fi-FI' ) {
        $name = "KSMessaging: Pate";
        $description = "Lähettää viestejä kirjastoasiakkaille Suomi.fi- tai iPost-viestintärajapinnan kautta (Paikalliskannat)";
    } else {
        $name = "KSMessaging: Pate";
        $description = "Sends messages to patrons via the Suomi.fi or iPost messaging (Local databases)";
    }
    return ($name, $description);
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

## This is the 'upgrade' method. It will be triggered when a newer version of a
## plugin is installed over an existing older version of a plugin
sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

## This is the configure page.  It lets the administrator view and edit the
## REST configuration (and optionally the REST password).  The configuration
## is stored in plugin_data via Modules::Config, falling back to the
## 'ksmessaging' section in koha-conf.xml when no plugin_data exists yet.
sub configure {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};
    my @messages;
    my $saved;

    my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({});
    $config->load_for_configure;

    # Show the stored configuration until we know we are handling a submission
    my $config_for_display = $config->loadedConfigForDisplay;

    # Save the configuration if the admin pressed "Save"
    if ( $cgi->request_method eq 'POST' && $cgi->param('save') ) {

        # Show what the admin actually submitted, so a failed save does not
        # throw away the configuration they just typed in
        $config_for_display = $cgi->param('config') || '';

        if ( !$self->_csrf_token_valid($cgi) ) {
            push @messages, $self->_configure_message( error => 'config_16' );
        }
        elsif ( $config->save($cgi) ) {
            $saved = 1;
        }
        else {
            push @messages, $self->_configure_message(
                error => $self->_save_error_key( $config->last_save_error ) );
        }
    }

    return $self->_output_configure_page(
        config  => $config_for_display,
        messages => \@messages,
        saved   => $saved,
    );
}

## Every exit path funnels through here so that 'messages' and 'saved' are
## always defined, and no code path can render a half-populated page.
sub _output_configure_page {
    my ( $self, %params ) = @_;

    my $template = $self->get_template( { file => 'config.tt' } );
    $template->param(
        config   => $params{config},
        messages => $params{messages},
        saved    => $params{saved},
    );

    return $self->output_html( $template->output() );
}

## Build a message for the template.  'key' is an i18n key, so the text is
## translated by the template rather than hardcoded here.
sub _configure_message {
    my ( $self, $type, $key ) = @_;

    return {
        type        => $type,
        alert_class => $type eq 'error' ? 'danger' : $type,
        key         => $key,
    };
}

## Map a save() failure reason onto the i18n key that explains it.
sub _save_error_key {
    my ( $self, $reason ) = @_;

    return 'config_13' if $reason eq 'empty';
    return 'config_14' if $reason eq 'invalid_yaml';
    return 'config_15' if $reason eq 'not_a_mapping';

    return 'config_12';
}

sub _csrf_token_valid {
    my ( $self, $cgi ) = @_;

    return unless $cgi;

    return Koha::Token->new->check_csrf(
        {
            session_id => scalar $cgi->cookie('CGISESSID'),
            token      => scalar $cgi->param('csrf_token'),
        }
    );
}

1;

