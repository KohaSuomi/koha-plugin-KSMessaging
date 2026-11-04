# SuomiFi‐järjestelmäasetukset

Suomi.fi-viestien lähetykseen liittyy kolme paikallistajärjestelmäasetusta.

1. SuomiFiMessaging

   - Arvo 0: Suomifi-viestienvalinta ei näy asiakkaiden viestiasetuksissa.

   - Arvo 1: Suomifi-viestivalinta näkyy asiakkaiden viestiasetuksissa.

2. SuomiFiAltSender

   - Voidaan määritellä vaihtoehtoisia lähettäjätietoja, normaalisti käyttää asiakkaan kotikirjastontietoja.

   - Mahdollista on täyttää neljä riviä tekstiä, eli koko osoitetiedot jos on tarpeen.

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

3. SuomiFiCostPool

   - Laskulle voidaan erotella rivit kirjastopistekohtaisesti. Mahdollista käyttää koko kirjastopistettä tai osaa siitä. Esim. TU ottaa kaikki pisteet jotka alkavat kirjaimilla TU.

   - **Pitää olla isoja kirjaimia tai numeroita, ja merkkejä tulee olla 1-15 kappaletta.**

```
KOHAPK: KOHA1234
TU: TU23456
```
