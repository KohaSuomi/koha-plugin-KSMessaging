package Koha::Plugin::Fi::KohaSuomi::KSMessaging;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
## We will also need to include any Koha libraries we want to access
use C4::Context;
use utf8;

## Configuration module (read/write the plugin_data config)
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;
## Sets up the 'suomifi' message transport type
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Setup;
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
## is stored in plugin_data via Modules::Config.  Nothing else is read at run
## time, so the page warns when koha-conf.xml still holds a 'ksmessaging'
## section, because those values are no longer used.
##
## The page also has the Suomi.fi messaging setup, which is the one time
## database setup the plugin needs: Modules::Setup adds the 'suomifi' message
## transport type and copies the selected circulation and reserves transports
## to it, and the SuomiFiMessaging system preference is toggled here because
## it decides whether the Suomi.fi column is shown in Administration ->
## Message preferences.
sub configure {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};
    my @messages;
    my $saved;
    my $setup_result;

    my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({});
    $config->load_for_configure;

    # Show the stored configuration until we know we are handling a submission
    my $config_for_display = $config->loadedConfigForDisplay;
    my $suomifi_alt_sender_for_display = $config->loadedAltSenderForDisplay;
    my $suomifi_cost_pool_for_display = $config->loadedCostPoolForDisplay;

    # Each of the three actions below is exclusive, so that a single click can
    # never run two of them.  They are all POSTs and all need a valid token.
    if ( $cgi->request_method eq 'POST' && $cgi->param('toggle_suomifi_messaging') ) {

        # Nothing is stored in plugin_data here, so a rejected token has not
        # thrown away anything the administrator typed in
        if ( !$self->_csrf_token_valid($cgi) ) {
            push @messages, $self->_configure_message( error => 'config_18' );
        }
        else {
            $self->_toggle_suomifi_messaging($config);
        }
    }
    elsif ( $cgi->request_method eq 'POST' && $cgi->param('setup_messages') ) {

        if ( !$self->_csrf_token_valid($cgi) ) {
            push @messages, $self->_configure_message( error => 'config_18' );
        }
        else {
            $setup_result = $self->_create_message_transports;
        }
    }
    # Save the configuration if the admin pressed "Save"
    elsif ( $cgi->request_method eq 'POST' && $cgi->param('save') ) {

        # Show what the admin actually submitted, so a failed save does not
        # throw away the configuration they just typed in
        $config_for_display = $cgi->param('config') || '';
        $suomifi_alt_sender_for_display = $cgi->param('suomifi_alt_sender') || '';
        $suomifi_cost_pool_for_display = $cgi->param('suomifi_cost_pool') || '';

        if ( !$self->_csrf_token_valid($cgi) ) {
            push @messages, $self->_configure_message( error => 'config_18' );
        }
        elsif ( $config->save($cgi) ) {
            $saved = 1;

            # The password left the textarea on its way to its own row, so say
            # so: a save that silently removed a secret looks like data loss.
            push @messages, $self->_configure_message( success => 'config_51' )
                if scalar @{ $config->moved_passwords };
        }
        else {
            push @messages, $self->_configure_message(
                error => $self->_save_error_key( $config->last_save_error ) );
        }
    }

    # Fill the textarea with the 'ksmessaging' section of koha-conf.xml.  This
    # one is posted by a form of its own, so it cannot carry the YAML typed into
    # the form above.  Nothing is stored here: the text is shown for review and
    # the administrator presses "Save configurations" to keep it, exactly as for
    # a typed edit.
    elsif ( $cgi->request_method eq 'POST' && $cgi->param('config_from_koha_conf') ) {

        if ( !$self->_csrf_token_valid($cgi) ) {
            push @messages, $self->_configure_message( error => 'config_18' );
        }
        else {
            my $from_conf = $config->config_from_koha_conf;

            if ( !defined $from_conf ) {
                push @messages, $self->_configure_message(
                    error => $self->_copy_error_key( $config->last_copy_error ) );
            }
            else {
                $config_for_display = $from_conf;
                push @messages, $self->_configure_message( success => 'config_47' );
            }
        }
    }

    return $self->_output_configure_page(
        config  => $config_for_display,
        suomifi_alt_sender => $suomifi_alt_sender_for_display,
        suomifi_cost_pool => $suomifi_cost_pool_for_display,
        messages => \@messages,
        saved   => $saved,
        setup_status => $self->_setup_status($config),
        setup_result => $setup_result,
        moved_passwords => $config->moved_passwords,
        koha_conf_section => $config->koha_conf_section_present,
    );
}

## The current state of the Suomi.fi message transport, for the setup section
## of the template.  The configuration object is passed in because it has
## already been loaded, and loading it again would not be cheaper.
sub _setup_status {
    my ( $self, $config ) = @_;

    my $setup = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Setup->new({});

    return {
        transport_type_exists => $setup->transport_type_exists,
        transport_count       => $setup->transport_count,
        suomifi_messaging     => $config->suomifiMessagingEnabled ? 1 : 0,
    };
}

## Flips the SuomiFiMessaging system preference, which is what shows or hides
## the Suomi.fi column in Administration -> Message preferences.  The column is
## only a user interface: the notices that are sent are the ones queued for the
## 'suomifi' message transport type, so hiding the column stops nothing.
sub _toggle_suomifi_messaging {
    my ( $self, $config ) = @_;

    return $config->setSuomiFiMessaging( $config->suomifiMessagingEnabled ? 0 : 1 );
}

## Adds the 'suomifi' message transport type and copies the selected
## circulation and reserves transports to it.  Returns the number of transports
## that were added and the number that were already there, or a hashref with an
## 'error' key if the setup failed.
sub _create_message_transports {
    my ($self) = @_;

    my $setup = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Setup->new({});

    my $result = eval { $setup->create_message_transports };
    if ($@) {
        warn "KSMessaging: setting up the suomifi message transports failed: $@";
        return { error => 1 };
    }

    return $result;
}

## Every exit path funnels through here so that 'messages' and 'saved' are
## always defined, and no code path can render a half-populated page.
sub _output_configure_page {
    my ( $self, %params ) = @_;

    my $template = $self->get_template( { file => 'config.tt' } );
    $template->param(
        config   => $params{config},
        suomifi_alt_sender => $params{suomifi_alt_sender},
        suomifi_cost_pool => $params{suomifi_cost_pool},
        messages => $params{messages},
        saved    => $params{saved},
        setup_status => $params{setup_status},
        setup_result => $params{setup_result},
        moved_passwords => $params{moved_passwords},
        koha_conf_section => $params{koha_conf_section},
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

    return 'config_15' if $reason eq 'empty';
    return 'config_16' if $reason eq 'invalid_yaml';
    return 'config_17' if $reason eq 'not_a_mapping';

    return 'config_14'; # Unknown reason, just show a generic error message
}

## Map a config_from_koha_conf() failure reason onto the i18n key that explains
## it.  'empty' is not really a failure: it means koha-conf.xml holds no
## ksmessaging section, so there is nothing to fill in and nothing changed.
sub _copy_error_key {
    my ( $self, $reason ) = @_;

    return 'config_48' if $reason eq 'empty';
    return 'config_49' if $reason eq 'invalid_yaml';

    return 'config_14'; # Unknown reason, just show a generic error message
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

