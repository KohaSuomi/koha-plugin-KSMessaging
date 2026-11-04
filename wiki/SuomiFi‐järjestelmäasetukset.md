# SuomiFi‐järjestelmäasetukset

Suomi.fi-viestien lähetykseen liittyy yksi järjestelmäasetus sekä kaksi
Asetukset-sivulla määritettävää asetusta.

1. SuomiFiMessaging

   - Arvo 0: Suomifi-viestienvalinta ei näy asiakkaiden viestiasetuksissa.

   - Arvo 1: Suomifi-viestivalinta näkyy asiakkaiden viestiasetuksissa.

   Sarakkeen takana olevaa `SuomiFiMessaging`-järjestelmäasetusta ei ole
   määritelty missään `.pref`-tiedostossa eikä lisäosa lähetä viestejä sen
   perusteella, joten se ei näy kohdassa **Ylläpito → Järjestelmäasetukset**
   eikä estä ilmoituksia. Siksi se kytketään Asetukset-sivulta
   **Näytä Suomi.fi-sarake** -painikkeella.

2. Vaihtoehtoiset lähettäjätiedot (entinen SuomiFiAltSender)

   Järjestelmäasetusta `SuomiFiAltSender` ei enää luoda. Lähettäjätiedot
   määritetään lisäosan Asetukset-sivulla kentässä
   **Suomifi alternative sender addresses (YAML)** ja tallennetaan
   `plugin_data`-tauluun avaimella `suomifi_alt_sender`. Kirjasto, jolla
   vanhassa järjestelmäasetuksessa on vielä arvot, käyttää niitä edelleen.

   Mahdollista on täyttää neljä riviä tekstiä, eli koko osoitetiedot jos on
   tarpeen.

```
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
```

3. Kustannuspaikka (entinen SuomiFiCostPool)

   Järjestelmäasetusta `SuomiFiCostPool` ei enää luoda. Kustannuspaikka
   määritetään lisäosan Asetukset-sivulla kentässä
   **Suomifi cost pool (YAML)** ja tallennetaan `plugin_data`-tauluun avaimella
   `suomifi_cost_pool`.

   - Laskulle voidaan erotella rivit kirjastopistekohtaisesti. Mahdollista
     käyttää koko kirjastopistettä tai osaa siitä. Esim. TU ottaa kaikki
     pisteet jotka alkavat kirjaimilla TU.

   - **Pitää olla isoja kirjaimia tai numeroita, ja merkkejä tulee olla 1-15
     kappaletta.**

```
KOHAPK: KOHA1234
TU: TU23456
```
