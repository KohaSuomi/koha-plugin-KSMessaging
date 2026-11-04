# Suomi.fi‐käyttöönotto

1. Ilmoittakaa, että haluatte aloittaa viestien lähetys REST-rajapinnan kautta: [viestit-kayttoonotot@dvv.fi](mailto:viestit-kayttoonotot@dvv.fi)

   - Ohjeita: [https://kehittajille.suomi.fi/palvelut/viestit/kayttoonotto](https://kehittajille.suomi.fi/palvelut/viestit/kayttoonotto)

2. Varmistakaa, että teillä on paperipostisopimus Postin kanssa, se tarvitaan mahdollisten kirjeiden lähetykseen suomi.fi:n kautta.

   - [https://kehittajille.suomi.fi/palvelut/viestit/kayttoonotto/tulostus-kuoritus-ja-jakelupalvelun-kayttoonotto](https://kehittajille.suomi.fi/palvelut/viestit/kayttoonotto/tulostus-kuoritus-ja-jakelupalvelun-kayttoonotto)

3. Tunnukset palvelimelle

   - REST-rajapintaa varten käyttäjätunnus, salasana ja palvelutunnus (serviceid), saadaan DVV:ltä

   - Paperipostia varten tunnus ja salasana, saadaan Postilta.

4. Asetukset REST-lähetykseen

   Kopioi asetukset liitännäisen **Määritä**-sivun kenttään YAML-muodossa
   (katso README, "Configuring"). Jos asetukset pidetään `koha-conf.xml`-tiedostossa,
   kääri sama YAML `<ksmessaging><![CDATA[ ... ]]></ksmessaging>`-osaan.

```
suomifi:
  branches:
    default:
      ipostpdf:
        customerid: 123456          # six digit customerid required by suomifi for print letters, although not actually used atm
        customerpass: "1234"
        ovtid: "000000000000"      # 12 digit OVT-id for organization
        printprovider: posti        # suomi.fi supports Edita and OpusCapita, but because of legal stuff not in use atm
        senderid: koha_sftp
        fileprefix: koha            # senderid is used if this is not set
      stagingdir: /var/spool/koha/pate-staging/
      contact: foobaa@kohala.fi    # e-mail address to contact in case of errors
      cachekey: token-name
      rest:
        baseUrl: https://api.messages.suomi.fi
        serviceid: foo_baa          # palvelutunnus
        username: koha_foo          # käyttäjätunnus
        password: pass              # salasana (bootstrap, tallennetaan plugin_dataan)
```

5. Ota Suomi.fi-viestiasetukset käyttöön liitännäisen **Määritä**-sivulla
   painamalla **Määritä Suomi.fi-viestintä**. Skriptiä ei tarvita.

   - Painike lisää `suomifi`-viestinsiirtotyypin, jota ei ole vakioasennuksessa,
     ja kopioi jokaisen `circulation`- ja `reserves`-viestinsiirtotyypin
     valinnan uuteen `suomifi`-tyyppiin.

   - Suomi.fi-valinnan näkyvyyttä asiakkaan viestiasetuksissa säädetään
     `SuomiFiMessaging`-järjestelmäasetuksella (paikalliset asetukset).

6. Määrittele viestipohjiin suomifi-viesteille pohjat.

7. Viestiasetuksiin ilmestyy uusi valinta, suomifi

   Asiakasviesteissä olevan valinnan saa näkyviin tai pois näkyvistä
   SuomiFiMessaging-järjestelmäasetuksella, löytyy paikallisista asetuksista.

8. Palautuskehotuksiin suomifi-vaihtoehtoa ei tarvitse valita, kaikki tulosteet saadaan lähtemään automaattisesti Suomi.fi-palveluun. Näin tapahtuu myös noutoilmoituksille joista muodostuu tuloste, jos muuta tapaa ei ole.

9. Kehittäjä ajastaa cronit:

```
  30 09 * * *        $TRIGGER cronjobs/pate.pl --suomifi
  45 09 * * *        $TRIGGER cronjobs/pate.pl --suomifi
  */15 10-19 * * *   $TRIGGER cronjobs/pate.pl --suomifi
  00 20 * * *        $TRIGGER cronjobs/pate.pl --suomifi
  52 20 * * *        $TRIGGER cronjobs/pate.pl --letters-as-suomifi-rest #Tämä lähettää print-tyyppiset kirjeet Suomi.fi:n kautta
```

   Korvaa `cronjobs/pate.pl` polulla
   `<pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/pate.pl`.
