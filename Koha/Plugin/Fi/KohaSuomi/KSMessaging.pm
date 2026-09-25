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

    return $self;
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

    my $cgi     = $self->{'cgi'};
    my $template = $self->get_template( { file => 'config.tt' } );

    # Save the configuration if the admin pressed "Save"
    if ( $cgi->param('save') ) {
        my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({});
        if ( $config->save( $cgi ) ) {
            $template->param( saved => 1 );
        }
        else {
            $template->param( error => 'Failed to save configuration. Check that the YAML is valid.' );
        }
    }

    # Load the configuration for display (plugin_data first, koha-conf.xml fallback)
    my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({});
    $config->load_for_configure;

    $template->param(
        config => $config->loadedConfigForDisplay,
    );

    print $cgi->header( -charset => 'utf-8' );
    print $template->output();
}

1;

