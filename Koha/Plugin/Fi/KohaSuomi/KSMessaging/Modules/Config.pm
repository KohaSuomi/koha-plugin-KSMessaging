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
## 'suomifi_rest_password_<BRANCHCODE>').  Without a stored configuration there
## is nothing to read: koha-conf.xml is only a source the configuration page
## copies from (config_from_koha_conf()), never one that is read at run time.
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

## Returns the full (root) configuration hashref for this interface, from
## plugin_data.  If a branch specific configuration does not exist, use the
## 'default' branch config.
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
## is overlaid from plugin_data (suomifi_rest_password_<BRANCHCODE>) when
## available, falling back to the 'rest' password from the stored
## configuration.
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

## Load the stored config for display on the configure page.  Only plugin_data
## is read, so what the page shows is what the cronjobs will read.  A
## koha-conf.xml section is not shown here either: it reaches the page through
## config_from_koha_conf(), as text the administrator can review before saving.
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
## Any REST password in the YAML is moved into a plugin_data row of its own and
## left out of the stored YAML; see _config_without_passwords().
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

    $self->_store_plugin_data( 'ksmessaging_config', $self->_config_without_passwords($config) );
    $self->_store_plugin_data( 'suomifi_alt_sender', $suomifi_alt_sender );
    $self->_store_plugin_data( 'suomifi_cost_pool', $suomifi_cost_pool );

    return 1;
}

## Move the REST passwords out of the configuration and into their own
## plugin_data rows.  getRESTConfig() already prefers suomifi_rest_password_<B>
## over the YAML, so a password left in the stored configuration is both a
## plaintext secret echoed back into the configuration page and one keystroke of
## editing away from being overwritten with a different secret.
##
## Only the Suomi.fi REST password is moved, because that is the one with a row
## of its own and a cronjob that writes it.  The iPost customerpass and the file
## transfer password stay where they are: nothing reads them from anywhere else,
## so stripping them would break those transfers.
##
## Returns the configuration to store.  When it holds no REST password the
## administrator's text is stored unchanged, so comments and formatting survive
## a normal save; only a configuration that really carries a password is
## re-serialised, and then without it.
sub _config_without_passwords {
    my ($self, $yaml) = @_;

    $self->{last_moved_passwords} = [];

    my $parsed = eval { YAML::XS::Load($yaml) };
    return $yaml unless ref $parsed eq 'HASH';

    my $branches = $parsed->{'suomifi'}->{'branches'};
    return $yaml unless ref $branches eq 'HASH';

    my @moved;
    for my $branch ( keys %$branches ) {
        my $branch_config = $branches->{$branch};
        next unless ref $branch_config eq 'HASH';

        my $rest = $branch_config->{'rest'};
        next unless ref $rest eq 'HASH';

        my $password = $rest->{'password'};

        # Only a non-empty scalar can be stored.  Anything else is left in the
        # YAML for the administrator to see rather than silently dropped, and an
        # absent password never clears a row that is already stored.
        next unless defined $password && !ref $password && length $password;

        $self->store_password( $password, $branch );

        delete $rest->{'password'};
        push @moved, $branch;
    }

    return $yaml unless @moved;

    $self->{last_moved_passwords} = [ sort @moved ];

    my $stripped = eval { YAML::XS::Dump($parsed) };
    return $yaml unless defined $stripped && $stripped =~ /\S/;

    return $stripped;
}

## Branchcodes whose REST password the last save() moved out of the YAML and
## into a plugin_data row of its own.  Empty when there was nothing to move.
sub moved_passwords {
    my ($self) = @_;
    return $self->{last_moved_passwords} || [];
}

## Reason why the last save() failed, or undef if it succeeded.
sub last_save_error {
    my ($self) = @_;
    return $self->{last_save_error};
}

## Whether koha-conf.xml still holds a 'ksmessaging' section.  The plugin does
## not read it, so this is only used by the configuration page to tell an
## administrator that there are settings in koha-conf.xml that nothing is
## reading any more.
##
## Kept apart from config_from_koha_conf() on purpose: asking this question
## must not overwrite last_copy_error, which belongs to the copy operation.
sub koha_conf_section_present {
    my ($self) = @_;

    my $config = C4::Context->config('ksmessaging');

    return ( ref $config eq 'HASH' && scalar keys %$config ) ? 1 : 0;
}

## Return the 'ksmessaging' section of koha-conf.xml as the YAML that save()
## stores, so that the configuration page can offer it as a starting point for
## the configuration text.  Nothing is written: the text ends up in the
## textarea and the administrator saves it like any other edit, which is
## what keeps the button safe to offer while a configuration is already stored.
##
## The section is serialised as it is, so a rest.password that is part of it
## comes along and lands in the textarea.  That is fine: save() moves any REST
## password into a plugin_data row of its own and stores the YAML without it,
## so the password is only ever visible on this page, and only until it is
## saved.
##
## Returns the YAML, or undef when there is nothing to offer, in which case
## last_copy_error holds a reason code ('empty' or 'invalid_yaml').
sub config_from_koha_conf {
    my ($self) = @_;

    $self->{last_copy_error} = undef;

    my $config = C4::Context->config('ksmessaging');

    unless ( ref $config eq 'HASH' && scalar keys %$config ) {
        $self->{last_copy_error} = 'empty';
        return;
    }

    my $yaml = eval { YAML::XS::Dump($config) };
    if ( $@ || !defined $yaml || $yaml !~ /\S/ ) {
        $self->{last_copy_error} = 'invalid_yaml';
        return;
    }

    return $yaml;
}

## Reason why the last config_from_koha_conf() returned nothing, or undef if it
## returned the YAML.
sub last_copy_error {
    my ($self) = @_;
    return $self->{last_copy_error};
}

############################################################
## Internal helpers
############################################################

sub _plugin_class {
    return 'Koha::Plugin::Fi::KohaSuomi::KSMessaging';
}

## Load the configuration from plugin_data.  Nothing else is read here: a
## <ksmessaging> section in koha-conf.xml is a starting point that the
## administrator copies onto the configuration page and saves, not a
## configuration the cronjobs pick up on their own.
sub _load_config {
    my ($self) = @_;

    my $raw = $self->_load_plugin_config;

    if ( $raw && $raw =~ /\S/ ) {
        my $config = eval { YAML::XS::Load($raw) };
        return $config if $config;
    }

    return {};
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

## Store the REST password into plugin_data (suomifi_rest_password_<BRANCHCODE>)
## and return the count of changed rows, or 0 if the password was already
## empty/unchanged.  The branchcode defaults to the one this object was built
## for; save() passes the one it found in the YAML, because the configuration
## page holds the settings of every branch at once.
sub store_password {
    my ($self, $password, $branch) = @_;
    return 0 unless defined $password && length $password;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
        "INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE plugin_value = VALUES(plugin_value)"
    );
    $branch = $self->branch unless defined $branch && length $branch;
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

## The SuomiFiMessaging system preference decides whether the Suomi.fi column is
## shown in Administration -> Message preferences.  The preference is read by
## the messaging preference form itself, not by the plugin, and it is not
## declared in any .pref file, so the system preferences page does not show it
## and this module is the only place that can read or change it.
sub suomifiMessagingEnabled {
    my ($self) = @_;

    return C4::Context->preference('SuomiFiMessaging');
}

## Enables or disables the Suomi.fi column in the message preferences form by
## writing the SuomiFiMessaging system preference.  Returns true on success.
sub setSuomiFiMessaging {
    my ($self, $enabled) = @_;

    return C4::Context->set_preference( 'SuomiFiMessaging', $enabled ? 1 : 0 );
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
