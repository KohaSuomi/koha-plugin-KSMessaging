#!/usr/bin/perl

use Modern::Perl;
use C4::Context;
use Getopt::Long;
use Try::Tiny;
use String::Random qw( random_string );
use Koha::Caches;
use POSIX qw(strftime);

my $pluginsdir = C4::Context->config("pluginsdir");
use lib $pluginsdir;

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST;

my $help;
my $verbose = 0;
my $branchcode = 'default';
my $old_password;
my $write_config = 0;
my $backup;
my $test_password = 0;

GetOptions(
    'help' => \$help,
    'verbose|v' => \$verbose,
    'branchcode=s' => \$branchcode,
    'old_password=s' => \$old_password,
    'write_config' => \$write_config,
    'backup=s' => \$backup,
    'test_password' => \$test_password
);

if ($help) {
    print "Usage: $0 [--branchcode=BRANCHCODE] [--old_password=OLD_PASSWORD] [--write_config] [--backup=BACKUP] [--test_password]\n";
    print "--branchcode: Specify the branch code (default: 'default')\n";
    print "--old_password: Provide the old password if you want to test it before changing\n";
    print "--write_config: If set, the new password will be written to the config file\n";
    print "--backup: Specify a file to back up the new password (default: /var/spool/koha/suomifi_password_backup.txt)\n";
    print "--test_password: If set, the script will only test the old password without changing it\n";
    exit 0;
}

my $config = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({
    interface => 'suomifi',
    branch => $branchcode,
});

my $start_time = strftime "%Y-%m-%d %H:%M:%S", localtime;
print "Script started at $start_time\n" if $verbose;
END {
    my $end_time = strftime "%Y-%m-%d %H:%M:%S", localtime;
    print "Script ended at $end_time\n" if $verbose;
}

# Generate and store the new password in a file for recovery if needed
my $new_password = generate_password();

unless ($test_password) {
    # Save the new password to a backup file before proceeding
    my $backup_file = $backup || "/var/spool/koha/suomifi_password_backup.txt";
    open my $fh, '>', $backup_file or die "Could not open $backup_file for writing: $!";
    print $fh "$new_password\n" if $fh;
    close $fh if $fh;
    print "New password backed up to $backup_file\n" if $verbose;
}

my $restConfig = $config->getRESTConfig();
my $password = $old_password || $restConfig->{password};
my $restClass = Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::REST->new({baseUrl => $restConfig->{baseUrl}});
my $cache = Koha::Caches->get_instance();
my $accessToken = $test_password ? undef : $cache->get_from_cache($config->cacheKey());
try {
    unless ($accessToken) {
        print "Fetching a access token\n" if $verbose;
        my $tokenResponse = $restClass->fetchAccessToken('/v1/token', 'application/json', {password => $password, username => $restConfig->{username}});
        $accessToken = $tokenResponse->{access_token};
        #Token should be valid for 5 seconds less than the expiry time
        $cache->set_in_cache($config->cacheKey(), $accessToken, { expiry => $tokenResponse->{expires_in} - 5 });
    }
    if ($test_password) {
        print "The provided old password is correct.\n";
        exit 0;
    }
    sleep 2; #Ensure token is valid
    my $response = $restClass->changePassword('/v1/change-password', 'application/json', {accessToken => $accessToken, currentPassword => $password, newPassword => $new_password});
    print "Password changed to $new_password\n" if $verbose;
    if ($write_config) {
        $config->store_password($new_password);
        print "Password stored in plugin_data (suomifi_rest_password).\n";
    } else {
        print "Not storing in plugin_data, use --write_config to enable this.\n";
        print "Add the new password via the plugin configuration page or --write_config.\n";
    }
    $cache->clear_from_cache($config->cacheKey());
} catch {
    print "$_\n";
};

sub generate_password {
    my $random = String::Random->new;
    my $password;
    do {
        $password = $random->randpattern("CCcc!n" x 8); # 8 sets of upper, lower, symbol, and number
    } while ($password =~ /[&<>'"\\\/]/); # Regenerate if it contains an ampersand, less than, or greater than symbol or a single quote or double quote or backslash or forward slash
    return $password;
}