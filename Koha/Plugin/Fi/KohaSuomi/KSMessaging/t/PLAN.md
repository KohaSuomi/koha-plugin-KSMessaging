# KSMessaging test plan

Core unit tests for `koha-plugin-KSMessaging`, following the sibling
Koha-Suomi plugin convention (tests live inside the plugin tree, run with
`prove -lrv <plugin>/t`).

No CI, no DB access: every `C4::Context->dbh` / preference read / Config
load is mocked. Koha core libs come from `PERL5LIB` (local: `/home/jraisa/Koha`).
All test files use `use utf8;` (formatting funcs depend on decoded input).

## Files

```
Koha/Plugin/Fi/KohaSuomi/KSMessaging/t/
├── PLAN.md
├── 00-load.t
├── config.t
├── epl.t
├── suomifi.t
├── rest.t
└── file.t
```

All tests `use lib "$Bin/../../../../../.."` (repo root, so the plugin
modules resolve) and use `Test::More` + `Test::MockModule`/`Test::MockObject`
+ `Test::Exception`.

## SsnProvider dependency

`CreateLetters.pm:13` and `Format/SuomiFi.pm:12` `use`
`Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database` at compile time;
the plugin is not on the local `@INC`. No stub file is shipped. Instead,
`00-load.t` and `suomifi.t` define a minimal **inline mock** in a `BEGIN`
block and pre-seed `%INC` so `require` skips loading (verified working):

```perl
BEGIN {
    $INC{'Koha/Plugin/Fi/KohaSuomi/SsnProvider/Modules/Database.pm'} = 'mocked';
    package Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database;
    sub new { bless {}, shift }
    sub getSSNByBorrowerNumber { my ($self) = @_; return $self->{ssn}; }
}
```

`suomifi.t` toggles the SSN value returned by the mock (or re-mocks it with
`Test::MockModule`) to exercise both RESTMessage branches.

## Coverage per file (expected values empirically verified)

- **00-load.t** — `use_ok` for all 10 packages: main plugin, Config,
  SendMessages, CreateLetters, Format::{EPL,PDF,SuomiFi},
  Deliver::{REST,File,DispatchXML}.

- **config.t** — `new/interface/branch` defaults (`suomifi`, `default`);
  `countryCode` (`sverige/ruotsi/sweden`->`SE`, `norge/norja/norway`->`NO`,
  `danmark/tanska/denmark`->`DK`, anything else/undef ->`FI`, case match is
  `lc` + trim). `save()`: returns 0 for empty config and for invalid YAML
  (`"foo: [broken"`, `"\tfoo: bar"`), 1 + stores via mocked
  `_store_plugin_data` for valid YAML (`"a: 1\nb: 2"`); hashref branch and
  `ref($args) eq 'CGI'` branch (fake `CGI` blessed object with `param`).
  `rootConfig`/`branchConfig` branch->`default` fallback (mock `_load_config`
  fixture); `stagingDir/contact/cacheKey`; `getRESTConfig` password overlay
  from mocked `_load_plugin_password`; `getIPostConfig`,
  `getFileTransferConfig`; `getSuomiFiAltSender`/`getSuomiFiCostPool` against
  mocked `C4::Context->preference` (lang section, branch section, `default`,
  invalid YAML, non-hash, `costPool` code regex `/^[A-Z0-9]+$/`);
  `load_for_configure` + display getters.

- **epl.t** — mock `_epl_config` to a fixture
  `{ code=>'SOME', layout=>{ templatecode=>'TPL9', contpagecode=>'CONT',
  firstpage=>3, otherpages=>2 } }`.
  - `hdiacritic` (needs decoded input): `Ʒ→Z`, `ʒ→z`, `ß→B`, `ʻ→'`, `€→e`;
    allowlisted `ÅåÄäÖöÉéÜüÁá` + ASCII preserved; unac fallback `ñàø → nao`;
    punctuation `a.b, c!?` preserved.
  - `fixZip`: `00100→FI00100`, `00100-123→FI00100123`, `FI00100→FI00100`,
    `SE-123→SE123` (dash always stripped), `''→''`.
  - `letterHeader` exactly:
    `EPLKFI00100   100                       SOME\r\n10                                            Reminder\r\n 0                                            23.09.2026\r\nTPL9\r\n`
  - `letterRecipient` exactly:
    `20John Doe\r\n 0Main 1\r\n 000100 Helsinki\r\n 0Finland\r\n` (zip raw).
  - `letterBody` no-contpage `L1\r\nL2\nL3` -> `30L1\r\n 0L2\r\n 0L3\r\n`.
  - `letterBody` with contpage `L1..L5` (firstpage 3, otherpages 2) ->
    `30L1\r\n 0L2\r\n10\r\nCONT\r\n 0L3\r\n10\r\nCONT\r\n 0L4\r\n10\r\nCONT\r\n 0L5\r\n10\r\nCONT\r\n`.

- **suomifi.t** — `FormatDescription`: `\r\n`->`\n`, `<`->`&lt;`, `>`->`&gt;`.
  `RESTMessage` with mocked `Koha::Patrons->find`/`Koha::Libraries->find`
  (Test::MockObject with accessor mocks) + SsnProvider mock + mocked Config
  methods (`contact`, `getIPostConfig`, `getRESTConfig`, `getSuomiFiCostPool`):
  SSN present -> `recipient.id`, `electronic` set; SSN absent -> no
  `recipient`/`electronic`, `paperMail` only; costPool included only when
  returned; `sender.serviceId` + `externalId`("42") wiring;
  `paperMail.sender.address.countryCode` from `countryCode`.

- **rest.t** — `Deliver::REST` with `ua` mocked (Test::MockModule) to a fake
  returning prepared `HTTP::Response` and capturing `HTTP::Request`s:
  `fetchAccessToken`/`changePassword` success (JSON decoded) + failure
  (`die ... status_line`); `send` JSON (Authorization `Bearer tok1`,
  content-type `application/json`, JSON body) and `send` form-data (needs a
  **real temp file** as content, e.g. `File::Temp`; multipart content-type);
  `get` (GET method + auth header). Note the code concatenates
  `baseUrl . endpoint` -> expect double slash `https://suomi.example/` +
  `/v1/...`.

- **file.t** — mock `_deliver_config` to a Test::MockObject whose `stagingDir`
  is a `File::Temp` dir. `WriteiPostEPL` latin1 (ASCII preserved, `\x{f6}`
  byte `f6`; `\x{20ac}` -> `?`, warn suppressed via `local $SIG{__WARN__}`);
  single-level missing staging dir auto-created (`mkdir` is not recursive);
  `WriteiPostPDF`; `WriteiPostArchive` ZIP contains given pdf/xml names,
  overwrite warns + replaces; `GetTransferConfig` returns
  host/password/port/protocol/remotedir/user; `FileTransfer`: sftp path
  through mocked `C4::KohaSuomi::SFTP::sftp_transfer` (capture
  `[filename]`, `\%cfg`, stagingdir) -> 1; empty config -> 1 ("skipped");
  unknown protocol -> 0.

## Out of scope

CreateLetters/SendMessages/DispatchXML/PDF rendering logic, DB integration
tests, cronjobs.

## Run

```
prove -lrv Koha/Plugin/Fi/KohaSuomi/KSMessaging/t
```

from the repo root, with `PERL5LIB` pointing at the Koha checkout.