**Suomi** | [English](README.md)

# Koha-Suomi -lisäosa KSMessaging

KSMessaging lähettää Kohan viestijonosta ilmoituksia kirjaston asiakkaille
Suomi.fi- tai iPost-viestintärajapinnan kautta. Riippuen siitä, miten toimipiste
on konfiguroitu, ilmoitus joko

- lähetetään **Suomi.fi REST** -rajapintaan, jolloin asiakas saa viestin sähköisesti
  ja/tai paperilla ja kirjasto voi seurata toimituksen tilaa rajapinnan kautta,
- lähetetään **iPostina PDF-tiedostona**, joka siirretään tulostuspalvelulle
  SFTP- tai FTP-siirrolla, tai
- kirjoitetaan **iPost EPL** -tiedostoksi ja siirretään tulostuspalvelulle
  SFTP- tai FTP-siirrolla.

Tulostettavaksi jonoon asetetut kirjeet voidaan myös ohjata Suomi.fin kautta
muuttamatta kirjeiden valintaa, mikä on hyödyllistä, kun toimitustapa vaihtuu
joksikin aikaa. Lisäosa on Koha-Suomin portti Patesta ja toimii paikallisilla
Koha-tietokannoilla.

Asetukset ovat toimipistekohtaisia: jokainen kirjasto voi käyttää omaa
Suomi.fi-tiliä, iPost-asiakastunnusta, välitiedostonhakemistoa ja tiedonsiirron
asetuksia, ja toimipisteet joilla ei ole omia asetuksia käyttävät yhteistä
`default`-asetusta.

## Vaatimukset

- Koha 25.05 tai uudempi.
- Koha-Suomin **SsnProvider**-lisäosa. Asiakkaan henkilötunnus haetaan sillä, kun
  viesti lähetetään Suomi.fin tai iPost-PDF:n kautta. Ilman sitä `pate.pl` ei
  käynnisty.
- Koha, jossa on Koha-Suomin SFTP-moduuli (`C4::KohaSuomi::SFTP`). Sitä käytetään
  `sftp`-tiedonsiirtoprotokollaa varten.
- Memcached konfiguroituna Kohalle. Suomi.fi-käyttöoikeustunnus välitetään
  välimuistiin asetuksessa määritetyllä `cachekey`-avaimella.
- Perl-moduulit: `Net::SFTP::Foreign`, `Net::FTP`, `PDF::API2`, `String::Random`,
  `Text::Unaccent`, `YAML::XS`, `XML::Simple`, `File::Slurp`, `HTML::Template`,
  `Archive::Zip` ja `LWP::UserAgent`.
- Välitiedostonhakemisto, johon `koha`-käyttäjä voi kirjoittaa, sekä kirjoitettava
  `/var/spool/koha` Suomi.fi-salasanan varmuuskopioa varten.

## Lataaminen

Releesisivulta voit ladata uusimman `*.kpz`-tiedoston. KPZ on zip-paketti, joka
sisältää lisään Perl-tiedostot, pohjat sekä muut tarvittavat tiedostot.

## Asentaminen

### 1. Ota Kohan lisäosajärjestelmä käyttöön

Jos lisäosajärjestelmä ei ole vielä käytössä palvelimella:

- aseta koha-conf.xml-tiedostoon `<enable_plugins>1</enable_plugins>`
- varmista, että `<pluginsdir>`-polussa oleva hakemisto on olemassa ja
  veripalvelimen käyttäjän kirjoitettavissa
- salli Apache-asetuksissa pääsy lisäosahakemistoon:

      <Directory <pluginsdir>>
          Options Indexes FollowSymLinks
          AllowOverride None
          Require all granted
      </Directory>

- käynnistä veripalvelin uudelleen
- aseta järjestelmäasetus `UseKohaPlugins` arvoon `Kyllä`

Lisäosajärjestelmä on dokumentoitu Kohan dokumentaation lisäosia käsittelevässä
osassa.

### 2. Asenna lisäosa

Lataa KPZ-tiedosto kohdassa **Työkalut → Lisäosat → Lataa lisäosa**.

### 3. Suorita kertaluontoinen tietokantamääritys

Lisäosa ei luo omia tauluja, ja sen `install`- ja `upgrade`-koukut eivät tee
mitään, joten tietokannan määritys on manuaalinen kertaluontoinen vaihe:

    sudo -u koha perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/misc/set_suomifi_messaging.pl

Skripti

- lisää viestityypin `suomifi`,
- luo järjestelmäasetukset `SuomiFiMessaging`, `SuomiFiAltSender` ja
  `SuomiFiCostPool`,
- kopioi kaikki kierto- ja varausviestityypit uuteen `suomifi`-viestityyppiin.

Asetusten lisäykset voi tehdä uudelleen turvallisesti, mutta viestityypit
kopioidaan ehdottoman, joten kahden ajon jälkeen jokaiselle kirjeelle syntyy
kaksoiskappale. Suorita skripti vain kerran.

Kolme `SuomiFi*`-järjestelmäasetusta ovat vanhoja ja lisäosa ei lue niitä:
lähettäjäosoitteet ja kustannuspooli määritetään lisäosan määrityssivulla. Älä
muokkaa niitä.

### 4. Valitse Suomi.fin kautta lähetettävät ilmoitukset

Kohdassa **Ylläpito → Viestityypit** valitse kirjeet, jotka lähetetään Suomi.fin
kautta viestityypin `suomifi` alla. Määritysskripti kopioi nykyiset
tulostusvalinnat, joten tarkista ne ensimmäisen asennuksen jälkeen.

Nämä valinnat lisäävät viestijonoon ilmoitukset, joiden viestityyppi on
`suomifi`, ja `pate.pl --suomifi` poimii juuri ne odottavat ilmoitukset.

## Määrittäminen

Asetukset muokataan kohdassa **Työkalut → Lisäosat → KSMessaging → Määritä**.
Sivulla on kolme YAML-kenttää. Jokaisen kentän sisällön on oltava
avain-arvo-rakenne; tyhjä kenttä, virheellinen YAML tai muu kuin
avain-arvo-rakenne hylätään ja mitään ei tallenneta.

Arvot tallennetaan tietokannan `plugin_data`-tauluun:

| Lisäosan avain | Määrityssivun kenttä | Sisältö |
| --- | --- | --- |
| `ksmessaging_config` | Asetukset (YAML) | pääasetukset |
| `suomifi_alt_sender` | Suomi.fi -vaihtoehtoiset lähettäjäosoitteet (YAML) | lähettäjälohko generoidussa kirjeessä |
| `suomifi_cost_pool` | Suomi.fi -kustannuspooli (YAML) | Suomi.fi REST -rajapintaan lähetettävä kustannuspooli |

YAML-kentissä olevat asetukset sisältävät palvelutunnukset ja tallennetaan
tietokantaan selvätekstinä. Rajoita tietokannan käyttöoikeuksia vastaavasti.

### Pääasetukset

Pääasetuksissa on kaksi rajapintaa, `suomifi` ja `letters`, joilla kummallakin on
omat `branches`-hakemistonsa. Viesti käsitellään aina asiakkaan toimipisteen
asetusten mukaan; jos toimipisteellä ei ole omaa osiotaan, käytetään
`default`-osiota.

    suomifi:
      branches:
        default:
          stagingdir: /tmp/ksmessaging
          contact: kirjasto@example.fi
          cachekey: ksmessaging_token
          rest:
            baseUrl: https://example.com/api
            username: user
            # REST-salasana hoidetaan sisäisesti (change-suomifi-password.pl)
            # ja tallennetaan erikseen plugin_data-tauluun.
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

Kaikissa toimipisteosioissa yhteiset asetukset:

| Avain | Kuvaus |
| --- | --- |
| `stagingdir` | Hakemisto, johon kirjeet kirjoitetaan ennen siirtoa. Luodaan, jos sitä ei ole. |
| `contact` | Yhteystiedot, jotka lähetetään Suomi.fille tulostuspalvelun yhteystietona. |
| `cachekey` | Memcached-avain Suomi.fi-käyttöoikeustunnusta. Anna jokaiselle toimipisteelle oma avain, jos toimipisteillä on eri Suomi.fi-tilit. |

`suomifi`-rajapinta, jota käyttävät `--suomifi`, `--letters-as-suomifi-ipost` ja
`--letters-as-suomifi-rest`:

| Avain | Kuvaus |
| --- | --- |
| `rest` | Suomi.fi REST -tili. `baseUrl` on rajapinnan perusosoite, `username` ja `serviceid` tunnistavat palvelun. Salasanaa ei määritetä tähän, ks. [Suomi.fi REST -salasana](#suomifi-rest--salasana). |
| `ipostpdf` | iPost-asiakas. `customerid` ja `customerpass` ovat iPost-tunnistetiedot, `ovtid` organisaatio, `senderid` lähettäjä, `printprovider` tiedostonimeen lisättävä tulostuspalvelu ja `fileprefix` tiedoston nimen alkuosa. `senderid` on pakollinen iPost-viesteille; tiedoston nimen alkuosa on oletuksena sama kuin `senderid`. |

`letters`-rajapinta, jota käyttää `--letters`:

| Avain | Kuvaus |
| --- | --- |
| `ipostepl` | EPL-tuloste. `encoding` on `latin1` tai `utf8`, `fileprefix` lisätään tiedoston nimen alkuun, ja `code`, `header` sekä `layout`-arvot kirjoitetaan EPL-mallikoodiin (`templatecode`, `contpagecode`, `firstpage`, `otherpages`). |
| `ipostpdf` | iPost-asiakas, samat avaimet kuin yllä. Kirje muunnetaan PDF-muotoon ja pakataan yhdessä iPost-lähetysXML:n kanssa. |
| `filetransfer` | Minne tiedostot lähetetään. `protocol` on `sftp` tai `ftp`, `port` on oletuksena 22 tai 21 ja `remotedir` oletuksena `~`. Jos `filetransfer` puuttuu, kirje kirjoitetaan vain hakemistoon `stagingdir` ja viesti merkitään silti lähetetyksi. |

`letters`-tasolla, `branches`-hakemiston vieressä:

| Avain | Kuvaus |
| --- | --- |
| `skipletters` | Pitukseltaan pilkkueroteltu luettelo kirjekoodeista, joita ei käsitellä, esimerkiksi `RETURN,OVERDUE`. |
| `combineacrossbranches` | `yes` siirtää kaikki tiedostot `default`-toimipisteen tiedonsiirron asetuksilla. Muuten toimipiste, jolla on oma `filetransfer`-osio, siirtää omilla asetuksillaan. |

### Suomi.fi REST -salasana

REST-salasana ei kuulu YAML-asetuksiin eikä määrityssivulla ole salasanakenttää.
Se tallennetaan `plugin_data`-tauluun avaimella
`suomifi_rest_password_<HAARUUDENKOODI>` ja sen kirjoittaa ainoastaan
`change-suomifi-password.pl --write_config`, kerran haaruutta kohden.

Ensimmäistä salasananvaihtoa ennen käytetään YAML-asetuksen `rest.password`-arvoa
vara-arvona. Näin aloitetaan: lisää nykyinen salasana YAML-asetukseen, suorita
salasananvaihto kerran lipulla `--write_config`, minkä jälkeen tallennettu
salasana otetaan käyttöön. Salasanan voi säilyttää myös koha-conf.xml-tiedoston
`<ksmessaging>`-osiossa, kun asetuksia ei tallenneta `plugin_data`-tauluun.

### Vaihtoehtoiset lähettäjäosoitteet

Oletuksena generoidussa kirjeessä lähettäjänä näkyvät toimipisteen nimi, osoite,
postinumero, kaupunki ja puhelinnumero. Niiden sijaan voidaan näyttää enintään
neljä riviä:

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

Ensimmäinen osuma voittaa: asiakkaan kieli ja toimipiste, asiakkaan kieli ja
toimipisteen osa, toimipiste ilman kieltä ja lopuksi `default`-osio. Kieliosio
voi olla myös luettelo ilman toimipisteitä, kuten yllä oleva `en:`, jolloin sitä
käytetään kyseisellä kielellä kaikissa toimipisteissä.

### Kustannuspooli

Kustannuspooli lisätään Suomi.fi REST -viestin paperipostiosuuteen:

    KOHAPK: KOHA1234
    TU: TU23456

Toimipisteen koodi täsmätään täsmälleen tai osana asiakkaan toimipisteen koodia,
ja arvon on koostuttava 1–15 suura kirjaimesta tai numerosta. Oletusosiota ei
ole: toimipisteelle, jolle ei löydy osumaa, viesti lähetetään ilman
kustannuspoolia.

### Varavaihtoehto: koha-conf.xml

Jos mitään ei tallenneta `plugin_data`-tauluun, lisäosa lukee saman
YAML-rakenteen koha-conf.xml-tiedoston `<ksmessaging>`-osiosta:

    <ksmessaging><![CDATA[
    suomifi:
      branches:
        default:
          ...
    ]]></ksmessaging>

Tämä on vain varavaihtoehto. Määrityssivu on suositeltava paikka, koska se
tarkistaa YAML-syntaksin ja pitää kaikki kolme asetusta yhdessä paikassa.

## Viestien lähettäminen

Lisäosa ei rekisteröi Kohan cron-tehtävää. Ylläpitäjä suorittaa
`KSMessaging/cronjobs/`-hakemiston skriptit `koha`-käyttäjänä ympäristössä, jossa
`KOHA_CONF` osoittaa sivuston määritystiedostoon ja Kohan Perl-kirjastot ovat
`PERL5LIB`-polussa. `pate.pl` lisää lisäosan hakemiston itse `@INC`-polkuun;
`change-suomifi-password.pl` ja `suomifi-status.pl` eivät, joten niiden
käynnistyksen vaatii, että `<pluginsdir>` on `PERL5LIB`-polussa. Kaikki kolme
hyväksyvät `--help`-valinnan.

Skriptit on normaalisti asennettu hakemistoon `<pluginsdir>`, esimerkiksi:

    sudo -u koha env KOHA_CONF=/etc/koha/sites/<sivusto>/koha-conf.xml \
        PERL5LIB=<Kohan Perl-kirjaston hakemisto>:<pluginsdir> \
        perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/pate.pl --suomifi

Suunnittele kullekin tilalle oma ajastuksensa, koska yksi ajo käsittelee yhden
rajapinnan.

### pate.pl

Yhdessä ajossa on annettava täsmälleen yksi tila:

| Valinta | Käsiteltävät viestit | Toiminta |
| --- | --- | --- |
| `--suomifi` | odottavat ilmoitukset, joiden viestityyppi on `suomifi` | Lähettää Suomi.fi REST -rajapintaan, jos toimipisteellä on `rest`-osio, muuten iPost-PDF:nä, jos toimipisteellä on `ipostpdf`-osio. Asiakkaan henkilötunnus vaaditaan iPost-PDF:lle; ilman sitä ilmoitus merkitään epäonnistuneeksi ja ajo jatkuu. |
| `--letters-as-suomifi-ipost` | odottavat tulostusilmoitukset | Muuntaa ilmoituksen PDF-muotoon, pakkaa sen iPost-lähetysXML:n kanssa ja siirtää sen tulostuspalvelulle. |
| `--letters-as-suomifi-rest` | odottavat tulostusilmoitukset | Muuntaa ilmoituksen PDF-muotoon, lähettää sen Suomi.fille ja luo sähköisen viestin sekä paperipostiviestin REST-rajapinnan kautta. |
| `--letters` | odottavat tulostusilmoitukset | Kirjoittaa ilmoituksen EPL-tiedostoksi, jos toimipisteellä on `ipostepl`-osio, tai PDF:n ja iPost-lähetysXML:n sisältäväksi zip-tiedostoksi, jos sillä on `ipostpdf`-osio, ja siirtää sitten tiedoston tulostuspalvelulle. |

`--letters-as-suomifi-ipost` ja `--letters-as-suomifi-rest` käyttävät toimipisteen
`suomifi`-osiota, joten Suomi.fi- tai iPost-tili kuuluu kohtaan `suomifi`, ei
kohtaan `letters`.

Tiedostot kirjoitetaan toimipisteen hakemistoon `stagingdir`:
`<toimipisteen koodi>-<viestin tunnus>.epl` tai
`<toimipisteen koodi>-<viestin tunnus>.zip` valinnalla `--letters`, ja
`<etuliite>_<aikaleima>.pdf` tai `<etuliite>_<aikaleima>.zip` Suomi.fi-tiloissa.
Tiedoston nimen alkuosa on oletuksena iPostin `senderid`, zip-arkistoon lisätään
`_suoratulostus`, kun asiakkaalla ei ole henkilötunnusta, ja `_printprovider`,
kun tulostuspalvelu on määritetty.

Muut valinnat:

| Valinta | Kuvaus |
| --- | --- |
| `--messages=234,2345` | Käsittele vain annetut viestitunnukset riippumatta viestityypistä tai tilasta. Hyödyllistä testauksessa. |
| `--test-id=TESTIHETU` | Käytä tätä henkilötunnusta asiakkaan oman sijaan. |
| `--help`, `-h` | Ohje. |

Skripti merkitsee jokaisen käsitellyn ilmoituksen lähetetyksi tai
epäonnistuneeksi, laskee toimituksetta jääneet viestit, odottaa sekunnin
ilmoitusten välillä ja tulostaa standardivirtaan
`N viestiä käsitelty, M toimituksetta.` Se päättyy arvolla 1, jos jokin viesti
jäi toimittamatta, muuten arvolla 0, joten cron-tehtävässä voidaan käyttää
paluuarvoa valvontaan.

Aseta ympäristömuuttuja `DEBUG=1`, jos haluat ratkaistun toimipisteasetuksen sekä
generoidut kirjeet tai lähetysXML:n standardivirtaan.

### change-suomifi-password.pl

Vaihtaa yhden toimipisteen Suomi.fi REST -salasanan ja tallentaa uuden salasanan
`plugin_data`-tauluun.

| Valinta | Kuvaus |
| --- | --- |
| `--branchcode=BRANCHCODE` | Toimipiste, jonka REST-tiliä ja tallennettua salasanaa käytetään. Oletuksena `default`. |
| `--old_password=OLD_PASSWORD` | Käytä tätä salasanaa tallennetun sijaan. |
| `--write_config` | Tallenna uusi salasana `plugin_data`-tauluun avaimella `suomifi_rest_password_<HAARUUDENKOODI>`. Ilman valintaa salasana vaihdetaan Suomi.fissä, mutta sitä ei tallenneta, ja lisäosa käyttää edelleen vanhaa salasanaa. |
| `--backup=BACKUP` | Tiedosto, johon uusi salasana kirjoitetaan ennen vaihtoa. Oletuksena `/var/spool/koha/suomifi_password_backup.txt`, muille toimipisteille `/var/spool/koha/suomifi_password_backup_<HAARUUDENKOODI>.txt`. |
| `--test_password` | Tarkistaa vain, että nykyinen salasana hyväksytään, ja poistuu vaihtamatta mitään. |
| `--verbose`, `-v` | Tulostaa ajeleet ja edistymisen. |

Uusi salasana kirjoitetaan aina varmuuskopiotiedostoon ennen vaihtoa, paitsi jos
käytetään `--test_password`-valintaa, jotta salasana voidaan palauttaa, jos vaihdot
epäonnistuu.

Suorita skripti kerran toimipistettä kohta lipulla `--write_config` alkukonfiguraation
jälkeen, jotta `plugin_data`-tauluun tallennettu salasana otetaan käyttöön.

### suomifi-status.pl

Lukee Suomi.fi REST -rajapinnasta jo lähetettyjen viestien toimitustilan ja
tulostaa sähköisen viestin ja paperipostin tilarivit aikaleimoineen. Skripti ei
muuta mitään.

    perl <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/suomifi-status.pl \
        --date=2026-01-31 --message_id=1234

| Valinta | Kuvaus |
| --- | --- |
| `--date=YYYY-MM-DD` | Tarkastele viestejä, jotka on päivitetty tästä päivästä alkaen. Oletuksena tänpäivä. |
| `--message_id=MESSAGE_ID` | Tarkastele yhtä viestiä sen sijaan. |

Tiedosto ei ole skriptipakettin repositoryssa suoritettavissa, joten aja se
valinnalla `perl`. Vain ilmoituksia, joiden viestityyppi on `print` ja tila
`sent`, tarkastetaan.

## Vianetsintä

- `No configuration found for ksmessaging.` — `plugin_data`-tauluun ei ole
  tallennettu mitään eikä koha-conf.xml-tiedostossa ole `<ksmessaging>`-osiota.
  Tallenna asetus lisäosan määrityssivulta.
- `The format for the branch is not configured.` — toimipisteellä ei ole
  `rest`- eikä `ipostpdf`-osiota kohtaan `suomifi`.
- `No suomi.fi message created ... No SSN available.` — SsnProviderilla ei ole
  asiakkaan henkilötunnusta. iPost-PDF:nä lähetettävä viesti tarvitsee sellaisen.
- Ilmoitukset pysyvät odotustilassa — niiden viestityyppiä käsittelevää tilaa ei
  ajeta, tai ajo epäonnistui ennen kuin se ehti niiden kohdalle.
- `Can't create directory` tai `Can't write to` — hakemisto `stagingdir` puuttuu
  eikä `koha`-käyttäjä voi luoda sitä, tai se ei ole kirjoitettavissa.
- `Unknown protocol` — `filetransfer.protocol` ei ole `sftp` eikä `ftp`.
- Toistuvat käyttöoikeustunnuspyynnöt tai virheet tunnuksessa — tarkista, että
  memcached on käynnissä Kohalle ja että `cachekey` on asetettu ja yksilöllinen
  Suomi.fi-tiliä kohti.
- Lisäosa voi näkyä nimellä **KSMessaging: Pate**. Se on lisäosan näyttönimi, ja
  kyseessä on sama lisäosa.
- Vastaanottajan ja lähettäjän maa lähetetään ISO 3166-1 alpha-2 -koodina. Vain
  maan nimet Ruotsi, Norja ja Tanska (suomeksi, ruotsiksi ja englanniksi)
  tunnistetaan, joten esimerkiksi kentässä oleva ISO-koodi `SE` lähetetään
  arvona `FI`, kuten myös tunnistamaton arvo.
