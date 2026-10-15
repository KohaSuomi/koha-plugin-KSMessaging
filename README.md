**English** | [Suomi](README.fi.md)

# Koha-Suomi plugin KSMessaging

KSMessaging sends notices from the Koha message queue to library patrons through
Suomi.fi or iPost. Depending on how a branch is configured, a notice is either

- sent to the **Suomi.fi REST** interface, so the patron receives the message
  electronically and/or on paper, and the library can follow the delivery status
  through the API,
- sent to **iPost as a PDF**, which is transferred to the print provider over
  SFTP or FTP, or
- written as an **iPost EPL** file and transferred to the print provider over
  SFTP or FTP.

Letters that are queued for printing can also be re-routed through Suomi.fi
without changing the letter selection, which is useful when the delivery channel
changes for a period of time. The plugin is a Koha-Suomi port of Pate, and works
on local Koha databases.

Configuration is per branch: every library can have its own Suomi.fi account,
iPost customer ID, staging directory and file transfer settings, with a shared
`default` for the branches that do not need their own.

## Requirements

- Koha 25.05 or newer.
- The Koha-Suomi **SsnProvider** plugin. The patron SSN is looked up with it when
  a message is sent through Suomi.fi or iPost PDF. Without it, `pate.pl` does not
  start.
- Koha with the Koha-Suomi SFTP module (`C4::KohaSuomi::SFTP`). It is used for
  the `sftp` file transfer protocol, and the plugin loads it at startup, so
  `pate.pl` does not run without it.
- Memcached configured for Koha. Suomi.fi access tokens are cached under the
  `cachekey` value from the configuration.
- Perl modules: `Net::SFTP::Foreign`, `Net::FTP`, `PDF::API2`, `String::Random`,
  `Text::Unaccent`, `YAML::XS`, `XML::LibXML`, `File::Slurp`, `HTML::Template`,
  `Archive::Zip` and `LWP::UserAgent`. `XML::LibXML` is required by Koha
  itself, so it is normally already installed.
- A staging directory that the `koha` user can write to, and a writable
  `/var/spool/koha` for the Suomi.fi password backup.

## Downloading

From the release page you can download the latest `*.kpz` file. A KPZ file is a
zip file containing the Perl files, templates and other files the plugin needs.

## Installing

### 1. Enable the Koha plugin system

If the plugin system is not already in use on this server:

- set `<enable_plugins>1</enable_plugins>` in `koha-conf.xml`
- make sure the path in `<pluginsdir>` exists and is writable by the web server
- allow access to the plugin directory in Apache:

      <Directory <pluginsdir>>
          Options Indexes FollowSymLinks
          AllowOverride None
          Require all granted
      </Directory>

- restart the web server
- set the `UseKohaPlugins` system preference to `Yes`

The plugin system is documented in the plugin section of the Koha documentation.

### 2. Install the plugin

Upload the KPZ file in **Tools → Plugins → Upload plugin**.

### 3. Set up Suomi.fi messaging

Go to **Tools → Plugins → KSMessaging → Configure** and scroll to the
**Suomi.fi messaging** section. It has a description on the left and three
status readouts on the right:

| | |
| --- | --- |
| suomifi message transport | in use / not in use |
| Notices sent through Suomi.fi | how many notices are set up |
| Suomi.fi column in the message preferences | shown / hidden |

Below them are the two action buttons. Press **Set up Suomi.fi messaging**. The
button

- adds the `suomifi` message transport type, which is not part of a standard
  Koha installation,
- copies every `circulation` and `reserves` message transport to the new
  `suomifi` transport type, and reports how many notices were added and how
  many were already there.

The button can be pressed again at any time. A notice that is already set up
for Suomi.fi is never changed or removed, and the notices that are selected for
Suomi.fi for the first time are copied from the selections of the other
transport types.

The plugin's `install` and `upgrade` hooks do nothing, so this is the only
database setup there is.

### 4. Choose the notices that go to Suomi.fi

The same section has a second button, which shows or hides the **Suomi.fi**
column in **Administration → Message preferences**. Press
**Show the Suomi.fi column** first: without it the notices that are sent
through Suomi.fi cannot be reviewed or changed. The column is a user interface
only. Hiding it again does not stop the notices that are already set up for
Suomi.fi, and it is not what sends them.

Then review the notices in **Administration → Message preferences**: the setup
copied the selections of the other transport types, so they are the ones to
check first.

Those selections are what put notices into the message queue with the `suomifi`
transport type, and `pate.pl --suomifi` picks up exactly those pending notices.

The `SuomiFiMessaging` system preference behind the column is not declared in
any `.pref` file and the plugin does not send messages based on it, so it is not
shown in **Administration → System preferences** and it does not stop the
notices. That is why it is toggled from the plugin configuration page.

The `SuomiFiAltSender` and `SuomiFiCostPool` system preferences are not created
any more. The sender addresses and the cost pool are configured on the plugin
configuration page and stored in `plugin_data`; a library that still has values
in the old system preferences keeps using them.

## Configuring

The configuration is edited in **Tools → Plugins → KSMessaging → Configure**. The
page has two groups of YAML fields: **Message service** holds the main settings,
and **Message details** holds the alternative sender addresses and the cost
pool. Each field must contain a YAML mapping; an empty field, invalid YAML or
YAML that is not a mapping is rejected with a message and nothing is saved.
Every field has a **Show example** link that opens a documented example of its
format.

The values are stored in the `plugin_data` table of the database:

| Plugin key | Configure page field | Contents |
| --- | --- | --- |
| `ksmessaging_config` | Configuration (YAML) | the main configuration |
| `suomifi_alt_sender` | Suomifi alternative sender addresses (YAML) | sender block on the generated letter |
| `suomifi_cost_pool` | Suomifi cost pool (YAML) | cost pool sent to Suomi.fi REST |

The configuration in the YAML fields includes service credentials and is stored
in plain text in the database. Restrict access to the database accordingly.

### Main configuration

The main configuration has two interfaces, `suomifi` and `letters`, each with its
own `branches`. A message is always handled with the configuration of the
patron's branch; if the branch has no section of its own, the `default` section
is used.

    suomifi:
      branches:
        default:
          stagingdir: /tmp/ksmessaging
          contact: kirjasto@example.fi
          cachekey: ksmessaging_token
          rest:
            baseUrl: https://example.com/api
            username: user
            # The REST password is handled internally (change-suomifi-password.pl cronjob)
            # and stored separately in plugin_data.
            serviceid: service
          ipostpdf:
            customerid: customer
            customerpass: secret
            ovtid: OVT
            senderid: sender
            printprovider: provider
            fileprefix: prefix

    letters:
      branches:
        default:
          stagingdir: /tmp/ksmessaging
          contact: kirjasto@example.fi
          ipostepl:
            encoding: latin1
            fileprefix: EPL
            code: 123
            header: Header
            layout:
              firstpage: 40
              otherpages: 60
              templatecode: 1
              contpagecode: 2
          ipostpdf:
            customerid: customer
            customerpass: secret
            ovtid: OVT
            senderid: sender
            printprovider: provider
            fileprefix: prefix
          filetransfer:
            host: ftp.example.com
            port: 22
            remotedir: /incoming
            user: transfer
            password: secret
            protocol: sftp
      skipletters: RETURN,OVERDUE
      combineacrossbranches: no

Common to all branch sections:

| Key | Description |
| --- | --- |
| `stagingdir` | Directory where the letters are written before they are transferred. Created if it does not exist. |
| `contact` | Contact address sent to Suomi.fi as the print service contact. |
| `cachekey` | Memcached key used for the Suomi.fi access token. Give each branch its own key if the branches have different Suomi.fi accounts. |

`suomifi` interface, used by `--suomifi`, `--letters-as-suomifi-ipost` and
`--letters-as-suomifi-rest`:

| Key | Description |
| --- | --- |
| `rest` | Suomi.fi REST account. `baseUrl` is the API base URL, `username` and `serviceid` identify the service. The password is not configured here, see [The Suomi.fi REST password](#the-suomifi-rest-password). |
| `ipostpdf` | iPost customer. `customerid` and `customerpass` are the iPost credentials, `ovtid` the organisation, `senderid` the sender, `printprovider` the print provider added to the file name, and `fileprefix` the file name prefix. `senderid` is mandatory for iPost messages; the file name prefix defaults to it. |

`letters` interface, used by `--letters`:

| Key | Description |
| --- | --- |
| `ipostepl` | EPL output. `encoding` is `latin1` or `utf8`, `fileprefix` is prepended to the file name, and `code`, `header` and the `layout` values are written into the EPL template code (`templatecode`, `contpagecode`, `firstpage`, `otherpages`). |
| `ipostpdf` | iPost customer, same keys as above. The letter is rendered as a PDF and zipped together with the iPost dispatch XML. |
| `filetransfer` | Where the files are sent. `protocol` is `sftp` or `ftp`, `port` defaults to 22 or 21, and `remotedir` defaults to `~`. If `filetransfer` is missing, the letter is only written to `stagingdir` and the message is still marked as sent. A transfer to the Suomi.fi SFTP endpoint has a deadline, see [The Suomi.fi SFTP interface closes on 1.1.2027](#the-suomifi-sftp-interface-closes-on-112027). |

At the `letters` level, next to `branches`:

| Key | Description |
| --- | --- |
| `skipletters` | Comma-separated letter codes that are not processed, for example `RETURN,OVERDUE`. |
| `combineacrossbranches` | `yes` transfers every file with the `default` file transfer configuration. Otherwise a branch with its own `filetransfer` section transfers with its own settings. |

### The Suomi.fi REST password

The REST password is not part of the stored YAML configuration and there is no
password field on the configuration page. It is stored in `plugin_data` under
`suomifi_rest_password_<BRANCHCODE>`, once per branch, and
`change-suomifi-password.pl --write_config` writes it.

A `rest.password` written in the YAML on the configuration page is not stored
there. Saving the configuration moves it into the `plugin_data` row for that
branch and stores the YAML without it, and the page reports which branches this
happened for. That makes the YAML a place where the current password can be typed
in without becoming part of the stored configuration. Nothing is removed unless a
password was actually there, so saving a configuration that has no `rest.password`
leaves an already stored password alone.

This is the other bootstrap path: put the current password in the YAML, save the
configuration page, and the stored password takes over from that point on. Before
any password has been stored, the `rest.password` value in the YAML is used as a
fallback. The password can also be kept in a `<ksmessaging>` section of
`koha-conf.xml` until the configuration has been copied over and saved.

Only the Suomi.fi REST password is moved this way. The iPost `customerpass` and
the file transfer `password` have no row of their own and are read straight from
the YAML, so they are always stored with it and are visible on the page.

### Alternative sender addresses

By default the generated letter shows the branch name, address, zip code, city
and phone number as the sender. Up to four lines can be shown instead:

    fi-FI:
      BRANCH:
        - Erikoiskirjasto
    en:
      - Library
    sv-SE:
      - Biblioteken
    default:
      - Kirjasto
      - Katu 1
      - 0000 Kaupunki
      - Puh. 0501111111

The first match wins: the patron's language and the branch, the patron's
language with a partial branch code, the branch without a language, and finally
the `default` section. A language section may also be a list without branches, as
in `en:` above, in which case it is used for that language in every branch.

### Cost pool

The cost pool is added to the paper mail part of the Suomi.fi REST message:

    KOHAPK: KOHA1234
    TU: TU23456

The branch code is matched exactly or as a part of the patron's branch code, and
the value must consist of 1 to 15 uppercase letters or digits. There is no
`default` fallback: a branch without a matching entry is sent without a cost
pool.

### Starting from koha-conf.xml

A site that keeps its settings in `koha-conf.xml` can hold the same YAML
structure in a `<ksmessaging>` section:

    <ksmessaging><![CDATA[
    suomifi:
      branches:
        default:
          ...
    ]]></ksmessaging>

The plugin does not read that section. It is a source to copy from, and the
configuration page is where the settings live from then on, since it validates
the YAML and keeps all three settings in one place.

The configuration page warns when the section is still in `koha-conf.xml`,
because those values are then ignored. Copy them into the configuration field
and press **Save configurations**; nothing reads them before that. A
`rest.password` in the section comes along, and it is
worth removing it from the YAML and storing it with
`change-suomifi-password.pl --write_config` instead, since the
configuration page shows the YAML in the clear. The two Suomi.fi settings have no
`koha-conf.xml` counterpart and are left untouched.

## Sending messages

The plugin does not register a Koha cron job. The scripts in
`KSMessaging/cronjobs/` are run by the administrator, as the `koha` user, in an
environment where `KOHA_CONF` points to the site configuration and Koha's Perl
libraries are on `PERL5LIB`. `pate.pl` adds the plugin directory to `@INC` itself;
`change-suomifi-password.pl` and `suomifi-status.pl` do not, so `<pluginsdir>`
has to be on `PERL5LIB` for those two. All three take `--help`.

The scripts are normally installed under `<pluginsdir>`, for example:

    sudo -u koha env KOHA_CONF=/etc/koha/sites/<site>/koha-conf.xml \
        PERL5LIB=<koha perl library directory>:<pluginsdir> \
        perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/pate.pl --suomifi

Run each mode on its own schedule, since one run handles one interface only.

### pate.pl

Exactly one mode must be given per run:

| Option | Messages handled | What it does |
| --- | --- | --- |
| `--suomifi` | pending notices with the `suomifi` transport type | Sends to Suomi.fi REST if the branch has a `rest` section, otherwise sends as iPost PDF if the branch has an `ipostpdf` section. The patron SSN is required for iPost PDF; without it the notice is marked failed and the run continues. |
| `--letters-as-suomifi-ipost` | pending print notices | Renders the notice as a PDF, packages it with the iPost dispatch XML and transfers it to the print provider. |
| `--letters-as-suomifi-rest` | pending print notices | Renders the notice as a PDF, uploads it to Suomi.fi and sends the electronic and paper mail message through the REST API. |
| `--letters` | pending print notices | Writes the notice as an EPL file if the branch has an `ipostepl` section, or as a zip of the PDF and the iPost dispatch XML if it has an `ipostpdf` section, and then transfers the file to the print provider. |

`--letters-as-suomifi-ipost` and `--letters-as-suomifi-rest` use the Suomi.fi
section of the branch, so the Suomi.fi or iPost account belongs under
`suomifi`, not under `letters`.

The three modes that transfer a file to the print provider (`--suomifi` with an
`ipostpdf` section, `--letters-as-suomifi-ipost` and `--letters`) work as long
as the `filetransfer` endpoint is one that stays available. See
[The Suomi.fi SFTP interface closes on 1.1.2027](#the-suomifi-sftp-interface-closes-on-112027).

The files are written to the `stagingdir` of the branch:
`<branchcode>-<message_id>.epl` or `<branchcode>-<message_id>.zip` with
`--letters`, and `<fileprefix>_<timestamp>.pdf` or
`<fileprefix>_<timestamp>.zip` in the Suomi.fi modes. The file name prefix
defaults to the iPost `senderid`, a zip archive gets `_suoratulostus` appended
when the patron has no SSN, and `_printprovider` when a print provider is
configured.

Other options:

| Option | Description |
| --- | --- |
| `--messages=234,2345` | Process only the given message IDs, whatever their transport type or status. Useful for testing. |
| `--test-id=TESTIHETU` | Use this SSN instead of looking up the patron's, for testing. |
| `--help`, `-h` | Usage. |

The script marks each processed notice as `sent` or `failed`, counts the
undelivered ones, waits a second between messages and prints
`N messages processed, M undelivered.` on standard error. It exits with 1 if any
message was undelivered and 0 otherwise, so a cron job can use the exit status
for monitoring.

Set `DEBUG=1` in the environment to get the resolved branch configuration and the
generated letters or dispatch XML on standard error.

### change-suomifi-password.pl

Rotates the Suomi.fi REST password of one branch and stores the new password in
`plugin_data`.

| Option | Description |
| --- | --- |
| `--branchcode=BRANCHCODE` | Branch whose REST account and stored password are used. Defaults to `default`. |
| `--old_password=OLD_PASSWORD` | Use this password instead of the stored one. |
| `--write_config` | Store the new password in `plugin_data` under `suomifi_rest_password_<BRANCHCODE>`. Without it the password is changed in Suomi.fi but not stored, and the plugin keeps using the old one. |
| `--backup=BACKUP` | File to write the new password to before the change. Defaults to `/var/spool/koha/suomifi_password_backup.txt`, or `/var/spool/koha/suomifi_password_backup_<BRANCHCODE>.txt` for any other branch. |
| `--test_password` | Only check that the current password is accepted, then exit without changing anything. |
| `--verbose`, `-v` | Print timestamps and progress. |

The new password is always written to the backup file before the change is
attempted, unless `--test_password` is given, so the password can be recovered if
the change fails.

Run the script once per branch with `--write_config` after the initial
configuration, so that the password in `plugin_data` is in use.

### suomifi-status.pl

Reads the delivery status of already sent messages from the Suomi.fi REST API and
prints the electronic and paper mail status lines with their timestamps. It makes
no changes.

    perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/suomifi-status.pl \
        --date=2026-01-31 --message_id=1234

| Option | Description |
| --- | --- |
| `--date=YYYY-MM-DD` | Look at messages updated on or after this date. Defaults to today. |
| `--message_id=MESSAGE_ID` | Look at one message instead. |

The file is not executable in the repository, so run it with `perl`. Only notices
with the `print` transport type and the status `sent` are inspected.

## The Suomi.fi SFTP interface closes on 1.1.2027

The old Suomi.fi viestit interfaces (WS, SFTP and SMTP) are closed on
**1 January 2027**, after which every message to Suomi.fi has to be sent through
the REST interface. The schedule is in the DVV notice [Use of Suomi.fi Messages
will be transferred to the REST interface](https://kehittajille.suomi.fi/topical/use-of-suomi-fi-messages-will-be-transferred-to-the-rest-interface-see-the-transition-periods).

That concerns the SFTP service Suomi.fi itself offered for the iPost material of
the messages it printed. The `letters` interface is not that service: `--letters`
delivers EPL files, or a PDF with the iPost dispatch XML, straight to a print
provider over the provider's own iPost SFTP endpoint. A direct iPost agreement is
made with the print provider, not with Suomi.fi, so it is not affected by the
Suomi.fi shutdown.

The transfer is the same SFTP transfer in both cases, so check which endpoint the
configuration points at:

| | Suomi.fi, closes on 1.1.2027 | Print provider, not affected |
| --- | --- | --- |
| `filetransfer.host` | the Suomi.fi/VIA service, `*.integraatiopalvelu.fi` or `*.integraatiopalvelu.vyv.fi` | the print provider's own iPost SFTP host |
| `filetransfer.remotedir` | `/to_viestit/ipost/` | the directory the print provider gave out |

When a transfer is configured, the plugin cannot tell the two endpoints apart
from the configuration, so check this by hand rather than by reading a run log.

Only a deployment that really delivers to the Suomi.fi endpoint has to change
something, and then it moves from the file transfer to the REST interface of the
`suomifi` section: `--letters-as-suomifi-rest` for the pending print notices and
`--suomifi` for the notices queued for Suomi.fi. Both send the letter as a PDF,
so a branch on such a deployment that produces EPL (`ipostepl`) would have to
produce PDF instead. Every branch that delivers to a print provider keeps
working as it is, over the same SFTP transfer as before.

Before the REST interface is in use, DVV asks for two things: the source IP
addresses of the server have to be authorised for the service, and TLS 1.3 is
recommended over TLS 1.2.

## Troubleshooting

- `No configuration found for ksmessaging.` — nothing is stored in
  `plugin_data`. A `<ksmessaging>` section in `koha-conf.xml` is not read, so it
  has to be copied into the field on the plugin configuration page and saved
  there.
- `The format for the branch is not configured.` — the branch has neither a
  `rest` nor an `ipostpdf` section under `suomifi`.
- `No suomi.fi message created ... No SSN available.` — SsnProvider has no SSN
  for the patron. A notice sent through iPost PDF needs one.
- Notices stay `pending` — the mode that handles their transport type is not
  being run, or the run failed before it reached them.
- `Can't create directory` or `Can't write to` — `stagingdir` does not exist and
  cannot be created by the `koha` user, or is not writable.
- `Unknown protocol` — `filetransfer.protocol` is neither `sftp` nor `ftp`.
- Repeated token requests or token errors — check that memcached is running for
  Koha and that `cachekey` is set and unique per Suomi.fi account.
- The plugin may be listed as **KSMessaging: Pate**. That is the plugin's
  display name, it is the same plugin.
- The recipient and sender country is sent as an ISO 3166-1 alpha-2 code. Only
  the country names Sweden, Norway and Denmark (in Finnish, Swedish and English)
  are recognised, so a country field holding an ISO code such as `SE` is sent as
  `FI`, as is any unrecognised value.
