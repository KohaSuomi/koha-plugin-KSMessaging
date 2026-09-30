package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;

## Module for loading and storing plugin configuration.

use Modern::Perl;
use utf8;

use C4::Context;
use File::Slurp;
use YAML::XS;
use JSON;
use Koha::Patrons;
use Koha::Libraries;
use Encode qw(decode encode);

our $VERSION = "1.0.0";

## Load the config. The config is stored in the plugin_data table (key
## 'ksmessaging_config') and the REST password separately (key
## 'suomifi_rest_password').  If there is no configuration stored in
## plugin_data, we fall back to the 'ksmessaging' section in koha-conf.xml.
sub new {
    my ($class, $params) = @_;

    my $self = {};
    bless $self, $class;

    $self->{interface} = $params->{interface} || 'suomifi';
    $self->{branch}    = $params->{branch}    || 'default';

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

## Returns the full (root) configuration hashref for this interface, either
## from plugin_data or as a fallback from koha-conf.xml.  If a branch
## specific configuration does not exist, use the 'default' branch config.
sub rootConfig {
    my ($self) = @_;

    my $config = $self->{_config} ||= $self->_load_config;
    my $branchconfig = $self->{branch};

    return $config->{$self->{interface}}->{'branches'}->{"$branchconfig"}
        || $config->{$self->{interface}}->{'branches'}->{'default'};
}

## Return the branch key to use ('default' if no branch specific config exists)
sub branchConfig {
    my ($self) = @_;

    my $config = $self->{_config} ||= $self->_load_config;
    if ( exists $config->{$self->{interface}}->{'branches'}->{$self->{branch}} ) {
        return $self->{branch};
    }
    return 'default';
}

sub stagingDir {
    my ($self) = @_;
    return $self->rootConfig()->{'stagingdir'};
}

sub contact {
    my ($self) = @_;
    return $self->rootConfig()->{'contact'};
}

sub cacheKey {
    my ($self) = @_;
    return $self->rootConfig()->{'cachekey'};
}

## Letters-level settings (skipletters / combineacrossbranches)
sub skipletters {
    my ($self) = @_;
    my $config = $self->{_config} ||= $self->_load_config;
    return $config->{'letters'}->{'skipletters'};
}

sub combineacrossbranches {
    my ($self) = @_;
    my $config = $self->{_config} ||= $self->_load_config;
    return $config->{'letters'}->{'combineacrossbranches'};
}

## RFAPI.
## Suosii is generic all-mail-config.
## We return the REST config for the current interface+branch.  The password
## is overlaid from plugin_data (suomifi_rest_password) when available, falling
## back to the 'rest' password from the config (plugin_data YAML or koha-conf).
sub getRESTConfig {
    my ($self) = @_;
    return {
        'baseUrl'  => $self->rootConfig()->{'rest'}->{'baseUrl'},
        'username' => $self->rootConfig()->{'rest'}->{'username'},
        'password' => $self->_load_plugin_password || $self->rootConfig()->{'rest'}->{'password'},
        'serviceid' => $self->rootConfig()->{'rest'}->{'serviceid'},
    };
}

sub getIPostConfig {
    my ($self) = @_;
    return {
        'customerid'    => $self->rootConfig()->{'ipostpdf'}->{'customerid'},
        'customerpass'  => $self->rootConfig()->{'ipostpdf'}->{'customerpass'},
        'ovtid'         => $self->rootConfig()->{'ipostpdf'}->{'ovtid'},
        'senderid'      => $self->rootConfig()->{'ipostpdf'}->{'senderid'},
        'printprovider' => $self->rootConfig()->{'ipostpdf'}->{'printprovider'},
        'fileprefix'    => $self->rootConfig()->{'ipostpdf'}->{'fileprefix'},
    };
}

sub getFileTransferConfig {
    my ($self) = @_;
    return {
        'host'      => $self->rootConfig()->{'filetransfer'}->{'host'},
        'port'      => $self->rootConfig()->{'filetransfer'}->{'port'},
        'remotedir' => $self->rootConfig()->{'filetransfer'}->{'remotedir'},
        'user'      => $self->rootConfig()->{'filetransfer'}->{'user'},
        'password'  => $self->rootConfig()->{'filetransfer'}->{'password'},
        'protocol'  => $self->rootConfig()->{'filetransfer'}->{'protocol'},
    };
}

############################################################
## Configuration page support
############################################################

## Load the stored config for display on the configure page.  If nothing is
## stored in plugin_data, load the fallback from koha-conf.xml so the admin
## can see and copy the current values.
sub load_for_configure {
    my ($self) = @_;
    $self->{config_for_display} = $self->_load_plugin_config;
    $self->{suomifi_alt_sender_for_display} = $self->_load_suomifi_alt_sender;
    $self->{suomifi_cost_pool_for_display} = $self->_load_suomifi_cost_pool;
    return $self;
}

sub loadedConfigForDisplay {
    my ($self) = @_;
    return $self->{config_for_display} || '';
}

sub loadedAltSenderForDisplay {
    my ($self) = @_;
    return $self->{suomifi_alt_sender_for_display} || '';
}

sub loadedCostPoolForDisplay {
    my ($self) = @_;
    return $self->{suomifi_cost_pool_for_display} || '';
}

## Save the configuration from the configure page into plugin_data.
## Accepts either a hashref (->save({...})) or a CGI object (->save($cgi)).
## Returns 1 on success and 0 on failure.  On failure last_save_error holds a
## reason code ('empty', 'invalid_yaml' or 'not_a_mapping') so the caller can
## show a specific message instead of one generic error.
sub save {
    my ($self, $args) = @_;

    my $config;
    my $suomifi_alt_sender;
    my $suomifi_cost_pool;

    if ( ref $args eq 'CGI' ) {
        $config = $args->param('config') || '';
        $suomifi_alt_sender = $args->param('suomifi_alt_sender') || '';
        $suomifi_cost_pool = $args->param('suomifi_cost_pool') || '';
    }
    else {
        $config = $args->{config} || '';
        $suomifi_alt_sender = $args->{suomifi_alt_sender} || '';
        $suomifi_cost_pool = $args->{suomifi_cost_pool} || '';
    }

    $self->{last_save_error} = undef;

    unless ($config) {
        $self->{last_save_error} = 'empty';
        return 0;
    }

    # Validate that the configurations are valid YAML and a hashref.  If not, return an error code.
    for my $yaml ($config, $suomifi_alt_sender, $suomifi_cost_pool) {
        if (!$yaml) {
            next; # Skip empty values, they are allowed
        }
        my $parsed = eval { YAML::XS::Load($yaml) };
        if ($@) {
            $self->{last_save_error} = 'invalid_yaml';
            return 0;
        }
        if ( ref($parsed) ne 'HASH' ) {
            $self->{last_save_error} = 'not_a_mapping';
            return 0;
        }
    }

    $self->_store_plugin_data( 'ksmessaging_config', $config );
    $self->_store_plugin_data( 'suomifi_alt_sender', $suomifi_alt_sender );
    $self->_store_plugin_data( 'suomifi_cost_pool', $suomifi_cost_pool );

    return 1;
}

## Reason why the last save() failed, or undef if it succeeded.
sub last_save_error {
    my ($self) = @_;
    return $self->{last_save_error};
}

############################################################
## Internal helpers
############################################################

sub _plugin_class {
    return 'Koha::Plugin::Fi::KohaSuomi::KSMessaging';
}

## Load the configuration: plugin_data first, then fall back to koha-conf.xml
sub _load_config {
    my ($self) = @_;

    my $raw = $self->_load_plugin_config;

    if ( $raw && $raw =~ /\S/ ) {
        my $config = eval { YAML::XS::Load($raw) };
        return $config if $config;
    }

    # Fallback to koha-conf.xml
    return C4::Context->config('ksmessaging') || {};
}

sub _load_plugin_config {
    my ($self) = @_;
    my $row = $self->_get_plugin_data('ksmessaging_config');
    return $row;
}

sub _load_suomifi_alt_sender {
    my ($self) = @_;
    my $row = $self->_get_plugin_data('suomifi_alt_sender');
    return $row;
}

sub _load_suomifi_cost_pool {
    my ($self) = @_;
    my $row = $self->_get_plugin_data('suomifi_cost_pool');
    return $row;
}

sub _load_plugin_password {
    my ($self) = @_;
    my $branch = $self->branch;
    my $row = $self->_get_plugin_data("suomifi_rest_password_$branch");
    return $row;
}

## Store the REST password into plugin_data (suomifi_rest_password) and return
## the count of changed rows, or 0 if the password was already empty/unchanged.
sub store_password {
    my ($self, $password) = @_;
    return 0 unless defined $password && length $password;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
        "INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value)"
    );
    my $branch = $self->branch;
    $sth->execute( $self->_plugin_class, "suomifi_rest_password_$branch", $password );
    return $dbh->rows;
}

sub _get_plugin_data {
    my ($self, $key) = @_;

    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
        "SELECT plugin_value FROM plugin_data WHERE plugin_key = ? AND plugin_class = ?"
    );
    $sth->execute( $key, $self->_plugin_class );
    my ($value) = $sth->fetchrow_array;
    $sth->finish;
    return $value;
}

sub _store_plugin_data {
    my ($self, $key, $value) = @_;

    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
        "INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value)"
    );
    $sth->execute( $self->_plugin_class, $key, $value );
    $sth->finish;
}

## Returns the alternative sender for the given branch, as defined in the
## SuomiFiAltSender system preference (YAML format). If no match is found,
## returns undef.
sub getSuomiFiAltSender {
    my ($self, $lang) = @_;

    my $library_id = $self->{branch};
    my $config = $self->_load_suomifi_alt_sender() || C4::Context->preference('SuomiFiAltSender');

    return unless $config;
    my $encoded_config = encode('UTF-8', $config);
    my $yaml = eval { YAML::XS::Load($encoded_config) };

    if ($@) {
        print "YAML load error: $@\n";
        return;
    }
    if (ref($yaml) ne 'HASH') {
        print "YAML is not a hash reference\n";
        return;
    }

    # First try to find matching language section
    foreach my $lang_key (keys %$yaml) {
        if (defined $lang && $lang ne "default" && $lang eq $lang_key) {
            my $lang_section = $yaml->{$lang_key};
            if (ref($lang_section) eq 'HASH') {
                foreach my $branch (keys %$lang_section) {
                    if ($library_id eq $branch || $library_id =~ /\Q$branch\E/) {
                        return $lang_section->{$branch};
                    }
                }
            } else {
                # If the lang section is not a hash, return it directly
                return $lang_section;
            }
        }
    }

    # Then try to find matching branch section without language
    foreach my $branch (keys %$yaml) {
        if ($library_id eq $branch || $library_id =~ /\Q$branch\E/) {
            return $yaml->{$branch};
        }
    }

    # Then try to find a default section
    if (exists $yaml->{default}) {
        return $yaml->{default};
    }

    return;
}

## Returns the cost pool value for the given branch, as defined in the
## SuomiFiCostPool system preference (YAML format). If no match is found,
## returns undef.
sub getSuomiFiCostPool {
    my ($self) = @_;

    my $library_id = $self->{branch};
    my $config = $self->_load_suomifi_cost_pool() || C4::Context->preference('SuomiFiCostPool');

    return unless $config;

    my $yaml = eval { YAML::XS::Load($config) };
    if ($@) {
        print "YAML load error: $@\n";
        return;
    }
    if (ref($yaml) ne 'HASH') {
        print "YAML is not a hash reference\n";
        return;
    }

    foreach my $branch (keys %$yaml) {
        if ($library_id eq $branch || $library_id =~ /\Q$branch\E/) {
            my $value = $yaml->{$branch};
            if (defined $value && $value =~ /^[A-Z0-9]+$/) {
                return $value;
            } else {
                return;
            }
        }
    }
    return;
}

## Maps a free-form country string to an ISO 3166-1 alpha-2 code (default FI)
sub countryCode {
    my ($self, $country) = @_;

    my %countryCodes = (
        'sverige' => 'SE',
        'ruotsi' => 'SE',
        'sweden' => 'SE',
        'norge' => 'NO',
        'norja' => 'NO',
        'norway' => 'NO',
        'danmark' => 'DK',
        'tanska' => 'DK',
        'denmark' => 'DK'
    );
    $country = defined($country) ? lc($country) : '';
    $country =~ s/^\s+|\s+$//g;
    return $countryCodes{$country} // 'FI';
}

1;
