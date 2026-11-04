# Suomi.fi‐testausohje

## Pääkäyttäjät

1. Toimita Suomi.fi:n REST-tunnukset ja PostiMessaging tunnukset kehittäjälle.

2. DVV antaa pari testihetua testausta varten. Käy lisäämässä oma sähköposti hetuille ja muuta ilmoituksen kieli sille kielelle mitä halutaan testata. Hetuja saattaa käyttää joku muukin, DVV:llä ei ole uniikkeja hetuja kaikille.

3. Tee testiaineistot halutuilla kielillä.

4. Toimita tieto viestistä, hetusta ja kielestä kehittäjälle.

5. Sovi kehittäjän kanssa testauksesta.

## Kehittäjät

1. Lisää suomifi-asetukset koha-conf.xml tiedostoon ja muuta tunnukset, contact ja cachekey oikeiksi.

```
<ksmessaging>
  <suomifi>
    <branches>
      <default>
         <ipostpdf>
          <customerid>123456</customerid> <!-- six digit customerid required by suomifi for print letters, although not actually used atm -->
          <customerpass>1234</customerpass>
          <ovtid>000000000000</ovtid> <!-- 12 digit OVT-id for organization -->
          <printprovider>posti</printprovider> <!-- suomi.fi supports Edita and OpusCapita, but because of legal stuff not in use atm, noSendOC will prevent the letters from being delivered on paper -->
          <senderid>koha_sftp</senderid>
          <fileprefix>koha</fileprefix> <!-- senderid is used if this is not set -->
         </ipostpdf>
         <stagingdir>/var/spool/koha/pate-staging/</stagingdir>
         <contact>foobaa@kohala.fi</contact> <!-- e-mail address to contact in case of errors -->
         <cachekey>token-name</cachekey>
         <rest>
          <baseUrl>https://api.messages-qa.suomi.fi</baseUrl> <!-- Tämä on testausosoite, tuotannolle on oma -->
          <serviceid>foo_baa</serviceid> <!-- palvelutunnus -->
          <username>koha_foo</username> <!-- käyttäjätunnus -->
          <password>pass</password> <!-- salasana -->
         </rest>
       </default>
    </branches>
  </suomifi>
</ksmessaging>
```

   Tai kopioi asetukset liitännäisen **Configure**-sivulle ja paina
   **Set up Suomi.fi messaging**.

2. Varmista, että Suomi.fi-viestiasetukset on otettu käyttöön
   **Configure**-sivulla (**Set up Suomi.fi messaging**).

   Viestitäppien näkyvyyttä voi säätää paikallisella SuomiFiMessaging-järjestelmäasetuksella.

3. Vaihda väliaikainen salasana (tehtävä myös tuotantokäyttöönotossa) ja vaihda uusi salasana asetukseen.

```
perl -I <pluginsdir> <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/change-suomifi-password.pl --old_password='<salasana>'
```

4. Muuta testikannassa muut pending-tilassa olevat viestit failed-tilaan. Jätä jäljelle testauksessa käytetyt. Testin voi ajaa vain yhdellä hetulla kerrallaan, joten jos halutaan eri hetulle eri kielisiä versioita, niin muuta viestien tiloja tarvittaessa.

5. Aja lähetysskripti halutuilla parametreillä.

   - Suomifi-tyyppisten viestien lähetys

```
perl -I <pluginsdir> <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/pate.pl --suomifi --test-id=<testihetu> --messages=<number>
```

   - Print-tyyppisten lähetys Suomi.fi:n kautta

```
perl -I <pluginsdir> <pluginsdir>/Koha/Plugin/Fi/KohaSuomi/KSMessaging/cronjobs/pate.pl --letters-as-suomifi-rest --test-id=<testihetu> --messages=<number>
```

6. Jos halutaan testata hetuttoman asiakkaan lähetystä, jätetään testihetu asettamatta. Tässä tapauksessa pitää sopia Postin kanssa, että he lähettävät sähköpostiin testitulosteen tarkistettavaksi.

Kirjeen testaukseen Postin kanssa sinne pitää lähettää seuraavat tiedot. Suomi.fi:n messageId-arvoa varten täytyy aktivoida DEBUG-tulostus sessiolle `export DEBUG=1`

```
Ympäristö: stage
Aineiston nimi: <messageId>.zip // Sama kuin SendLetterId + .zip
Lähetysaika: <lähetysaika>
SendLetterid: <messageId> //Tulee Suomi.fin vastauksessa
Asiakastunnus: <Postin asiakastunnus>
```
