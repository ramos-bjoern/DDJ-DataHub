# DDJ-DataHub — Benutzerhandbuch

**URL:** https://datahub.rndtech.de/admin  
**Für:** Data-Team, Redaktion, Entwickler

---

## Was ist DDJ-DataHub?

DDJ-DataHub ist eine interne Datenplattform für das Data-Team. Ihr könnt hier:

- Eigene Datentabellen (Collections) anlegen und befüllen
- Daten über eine automatische REST-API bereitstellen
- Widgets und iFrame-Embeds auf rnd.de mit Daten versorgen
- Leserbefragungen, Umfragen und interaktive Daten verwalten

---

## Erste Schritte

### Einloggen

1. `https://datahub.rndtech.de/admin` aufrufen
2. Mit eurer E-Mail-Adresse und Passwort anmelden
3. Bei Fragen zur Zugangsvergabe: Admin kontaktieren

### Rollen

| Rolle | Was ich damit kann |
|---|---|
| **Data-Manager** | Collections anlegen, Felder definieren, Daten importieren, Flows konfigurieren |
| **Data-Editor** | Daten in bestehenden Collections bearbeiten, neue Einträge erstellen |
| **Internal-Viewer** | Daten nur lesen (für interne Dashboards) |

---

## Collections — Datentabellen verwalten

Eine **Collection** ist eine Datentabelle — vergleichbar mit einem Excel-Sheet oder einer Datenbanktabelle.

### Neue Collection anlegen (Data-Manager)

1. `Settings → Data Model → Create Collection`
2. Name vergeben (z.B. `wahlergebnisse`, nur Kleinbuchstaben und Unterstriche)
3. Felder hinzufügen:
   - **String** — kurze Texte (Name, Titel)
   - **Text** — längere Texte
   - **Integer** — ganze Zahlen
   - **Float/Decimal** — Dezimalzahlen
   - **Boolean** — Ja/Nein
   - **Timestamp** — Datum und Uhrzeit
   - **Image** — Bild aus der Mediathek

4. `Save` klicken

### Daten eingeben

1. Im linken Menü die Collection auswählen
2. `+ Create Item` klicken
3. Felder ausfüllen
4. `Save` klicken

### Daten importieren (CSV)

1. Collection öffnen
2. Oben rechts: `Import` → CSV-Datei hochladen
3. Spalten den Feldern zuordnen
4. Import starten

---

## API — Daten abrufen

Jede Collection ist automatisch über die REST-API erreichbar.

### Basis-URL

```
https://datahub.rndtech.de/items/<collection-name>
```

### Beispiele

```bash
# Alle Bundestagswahl-Ergebnisse 2025
https://datahub.rndtech.de/items/bundestagswahl_ergebnisse?filter[wahl_jahr][_eq]=2025

# Leserbefragung zum Thema Politik
https://datahub.rndtech.de/items/leserbefragung?filter[thema][_eq]=Politik&sort[]=-stimmen

# Ergebnis aggregieren (Summe der Stimmen pro Antwort)
https://datahub.rndtech.de/items/leserbefragung?aggregate[sum]=stimmen&groupBy[]=antwort
```

### Mit Widget-Token (für eingebettete Widgets)

```js
fetch('https://datahub.rndtech.de/items/leserbefragung', {
  headers: { 'Authorization': 'Bearer DEIN_WIDGET_TOKEN' }
})
```

Den Token bekommt ihr vom Admin-Team.

---

## Beispiel-Collections (Präsentationsdaten)

### Bundestagswahl-Ergebnisse

**Collection:** `bundestagswahl_ergebnisse`  
**Enthält:** Zweitstimmen in Prozent und Sitze pro Partei für 2017, 2021 und 2025

```
https://datahub.rndtech.de/items/bundestagswahl_ergebnisse?filter[wahl_jahr][_eq]=2025&sort[]=-zweitstimmen_prozent
```

### Leserbefragungen

**Collection:** `leserbefragung`  
**Enthält:** Antworten und Stimmenanzahl zu drei aktuellen Themen (Politik, Technologie, Mobilität)

```
https://datahub.rndtech.de/items/leserbefragung?filter[thema][_eq]=Technologie&sort[]=-stimmen
```

---

## Flows — Automatisierungen

Flows erlauben euch Aktionen zu automatisieren — z.B. täglich Daten berechnen oder bei neuen Einträgen eine Benachrichtigung senden.

### Neuen Flow anlegen

1. `Settings → Flows → Create Flow`
2. Trigger wählen:
   - **Schedule** — zu einem bestimmten Zeitpunkt (Cron)
   - **Event** — wenn ein Datensatz erstellt/geändert wird
   - **Webhook** — wenn eine externe URL aufgerufen wird
3. Operationen hinzufügen (Daten lesen, schreiben, HTTP-Request etc.)
4. `Save` klicken

---

## Mediathek — Bilder und Dateien

Unter `Files` könnt ihr Bilder und Dateien hochladen die dann in Collections verwendet werden können (z.B. als Bild-Feld).

Bilder sind nach dem Upload unter dieser URL erreichbar:
```
https://datahub.rndtech.de/assets/<uuid>
```

---

## Häufige Fragen

**Ich kann keine Collection anlegen.**  
→ Du brauchst die Rolle `Data-Manager`. Wende dich an den Admin.

**Meine Änderungen sind in der API nicht sichtbar.**  
→ Die API cached Antworten für 10–60 Sekunden. Kurz warten.

**Wie gebe ich eine Collection für ein Widget frei?**  
→ Das macht der Admin. Kurze Beschreibung des Widgets + benötigte Collections an den Admin schicken.

**Wie bekomme ich einen Widget-Token?**  
→ Beim Admin anfragen. Token sind pro Widget individuell und können einzeln gesperrt werden.

**Wie importiere ich viele Daten auf einmal?**  
→ CSV-Import unter `Content → [Collection] → Import`. Alternativ per API (curl oder Python-Script).

---

## Kontakt & Support

Bei Fragen oder Problemen: Bjørn Ramos (ramos.bjoern@rnd.de)
