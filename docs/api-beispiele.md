# DDJ-DataHub API — Praxisbeispiele für Entwickler

**Basis-URL:** `https://datahub.rndtech.de`  
**Authentifizierung:** Bearer-Token im `Authorization`-Header  
**Format:** JSON

Ersetze in allen Beispielen:
- `DEIN_API_TOKEN` → Widget-Token vom Admin-Team
- `COLLECTION_NAME` → Name der Collection (z.B. `bundestagswahl_ergebnisse`)

---

## 1. Python-Beispiele

### 1.1 Einzelne Collection abrufen

```python
import requests

API_BASE = "https://datahub.rndtech.de"
API_TOKEN = "DEIN_API_TOKEN"

# Header mit Token für alle Requests
headers = {
    "Authorization": f"Bearer {API_TOKEN}"
}

# Collection abrufen — hier Bundestagswahl-Ergebnisse für 2025
response = requests.get(
    f"{API_BASE}/items/bundestagswahl_ergebnisse",
    headers=headers,
    params={
        "filter[wahl_jahr][_eq]": 2025,   # nur Einträge für 2025
        "sort[]": "-zweitstimmen_prozent", # absteigend nach Stimmenanteil
    },
    timeout=10  # Timeout nach 10 Sekunden
)

# HTTP-Statuscode prüfen
response.raise_for_status()  # wirft Exception bei 4xx/5xx

# JSON parsen
daten = response.json()["data"]

# Felder auslesen
for eintrag in daten:
    partei  = eintrag["partei"]
    prozent = eintrag["zweitstimmen_prozent"]
    sitze   = eintrag["sitze"]
    print(f"{partei:10} {prozent:5.1f}%  {sitze} Sitze")
```

### 1.2 Fehlerbehandlung

```python
import requests
from requests.exceptions import Timeout, ConnectionError, HTTPError

API_BASE = "https://datahub.rndtech.de"
API_TOKEN = "DEIN_API_TOKEN"

def lade_collection(collection: str, params: dict = None) -> list:
    """
    Lädt alle Einträge einer Collection.
    Gibt eine leere Liste zurück wenn ein Fehler auftritt.
    """
    headers = {"Authorization": f"Bearer {API_TOKEN}"}

    try:
        response = requests.get(
            f"{API_BASE}/items/{collection}",
            headers=headers,
            params=params or {},
            timeout=10
        )
        response.raise_for_status()
        return response.json()["data"]

    except Timeout:
        print(f"Fehler: Zeitüberschreitung beim Abrufen von '{collection}'")
        return []

    except ConnectionError:
        print("Fehler: Server nicht erreichbar")
        return []

    except HTTPError as e:
        status = e.response.status_code
        if status == 401:
            print("Fehler: Ungültiger API-Token")
        elif status == 403:
            print(f"Fehler: Kein Zugriff auf Collection '{collection}'")
        elif status == 404:
            print(f"Fehler: Collection '{collection}' nicht gefunden")
        else:
            print(f"HTTP-Fehler {status}")
        return []

# Verwendung
ergebnisse = lade_collection(
    "bundestagswahl_ergebnisse",
    {"filter[wahl_jahr][_eq]": 2025}
)

for e in ergebnisse:
    print(f"{e['partei']}: {e['zweitstimmen_prozent']}%")
```

---

## 2. JavaScript-Beispiele

### 2.1 Einzelne Collection abrufen und ins DOM rendern

```html
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Wahlergebnisse</title>
</head>
<body>
  <h2>Bundestagswahl 2025</h2>
  <ul id="ergebnisse">Lade Daten…</ul>

  <script>
    const API_BASE  = "https://datahub.rndtech.de";
    const API_TOKEN = "DEIN_API_TOKEN";

    async function ladeErgebnisse() {
      const liste = document.getElementById("ergebnisse");

      try {
        const response = await fetch(
          `${API_BASE}/items/bundestagswahl_ergebnisse` +
          `?filter[wahl_jahr][_eq]=2025&sort[]=-zweitstimmen_prozent`,
          {
            headers: {
              "Authorization": `Bearer ${API_TOKEN}`
            }
          }
        );

        // Fehler bei HTTP-Statuscodes 4xx/5xx
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const json  = await response.json();
        const daten = json.data;

        // Liste leeren und befüllen
        liste.innerHTML = "";
        daten.forEach(eintrag => {
          const li = document.createElement("li");
          li.textContent =
            `${eintrag.partei}: ${eintrag.zweitstimmen_prozent}% ` +
            `(${eintrag.sitze} Sitze)`;
          liste.appendChild(li);
        });

      } catch (fehler) {
        liste.innerHTML = `<li>Fehler beim Laden: ${fehler.message}</li>`;
        console.error("API-Fehler:", fehler);
      }
    }

    // Beim Laden der Seite aufrufen
    ladeErgebnisse();
  </script>
</body>
</html>
```

### 2.2 Tabelle mit dynamischen Daten

```javascript
const API_BASE  = "https://datahub.rndtech.de";
const API_TOKEN = "DEIN_API_TOKEN";

async function ladeTabelle(collection, felder, container) {
  /**
   * Lädt eine Collection und rendert sie als HTML-Tabelle.
   * @param {string} collection  - Name der Collection
   * @param {string[]} felder    - Spalten die angezeigt werden sollen
   * @param {HTMLElement} container - Ziel-Element im DOM
   */
  try {
    const response = await fetch(
      `${API_BASE}/items/${collection}?fields=${felder.join(",")}`,
      { headers: { "Authorization": `Bearer ${API_TOKEN}` } }
    );

    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const { data } = await response.json();

    // Tabelle aufbauen
    const tabelle = document.createElement("table");
    const kopfzeile = tabelle.insertRow();
    felder.forEach(feld => {
      kopfzeile.insertCell().textContent = feld;
    });

    data.forEach(eintrag => {
      const zeile = tabelle.insertRow();
      felder.forEach(feld => {
        zeile.insertCell().textContent = eintrag[feld] ?? "–";
      });
    });

    container.innerHTML = "";
    container.appendChild(tabelle);

  } catch (fehler) {
    container.textContent = `Fehler: ${fehler.message}`;
  }
}

// Verwendung
ladeTabelle(
  "bundestagswahl_ergebnisse",
  ["partei", "zweitstimmen_prozent", "sitze"],
  document.getElementById("tabellen-container")
);
```

---

## 3. Mehrere Collections kombinieren

### 3.1 Python — Parallel abrufen und zusammenführen

```python
import requests
from concurrent.futures import ThreadPoolExecutor

API_BASE = "https://datahub.rndtech.de"
API_TOKEN = "DEIN_API_TOKEN"
HEADERS = {"Authorization": f"Bearer {API_TOKEN}"}

def lade(collection, params=None):
    """Hilfsfunktion: Collection abrufen."""
    r = requests.get(
        f"{API_BASE}/items/{collection}",
        headers=HEADERS,
        params=params or {},
        timeout=10
    )
    r.raise_for_status()
    return r.json()["data"]

# Beide Collections parallel laden (spart Zeit)
with ThreadPoolExecutor() as pool:
    future_2021 = pool.submit(lade, "bundestagswahl_ergebnisse",
                              {"filter[wahl_jahr][_eq]": 2021})
    future_2025 = pool.submit(lade, "bundestagswahl_ergebnisse",
                              {"filter[wahl_jahr][_eq]": 2025})

ergebnisse_2021 = {e["partei"]: e for e in future_2021.result()}
ergebnisse_2025 = {e["partei"]: e for e in future_2025.result()}

# Vergleich: Stimmenveränderung 2021 → 2025
print(f"{'Partei':10} {'2021':>6} {'2025':>6} {'Diff':>6}")
print("-" * 32)

parteien = sorted(set(ergebnisse_2021) | set(ergebnisse_2025))
for partei in parteien:
    p2021 = ergebnisse_2021.get(partei, {}).get("zweitstimmen_prozent", 0)
    p2025 = ergebnisse_2025.get(partei, {}).get("zweitstimmen_prozent", 0)
    diff  = p2025 - p2021
    zeichen = "▲" if diff > 0 else "▼" if diff < 0 else "="
    print(f"{partei:10} {p2021:6.1f} {p2025:6.1f} {zeichen}{abs(diff):.1f}")
```

### 3.2 JavaScript — `Promise.all` für parallele Requests

```javascript
const API_BASE  = "https://datahub.rndtech.de";
const API_TOKEN = "DEIN_API_TOKEN";

async function ladeCollection(collection, params = {}) {
  const url = new URL(`${API_BASE}/items/${collection}`);
  Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));

  const response = await fetch(url.toString(), {
    headers: { "Authorization": `Bearer ${API_TOKEN}` }
  });

  if (!response.ok) throw new Error(`${collection}: HTTP ${response.status}`);
  return (await response.json()).data;
}

async function vergleicheWahlen() {
  // Beide Jahrgänge parallel laden
  const [ergebnisse2021, ergebnisse2025] = await Promise.all([
    ladeCollection("bundestagswahl_ergebnisse", {"filter[wahl_jahr][_eq]": 2021}),
    ladeCollection("bundestagswahl_ergebnisse", {"filter[wahl_jahr][_eq]": 2025}),
  ]);

  // Nach Partei indexieren
  const nach2021 = Object.fromEntries(ergebnisse2021.map(e => [e.partei, e]));
  const nach2025 = Object.fromEntries(ergebnisse2025.map(e => [e.partei, e]));

  // Vergleich aufbauen
  const parteien = [...new Set([
    ...ergebnisse2021.map(e => e.partei),
    ...ergebnisse2025.map(e => e.partei)
  ])];

  return parteien.map(partei => ({
    partei,
    prozent2021: nach2021[partei]?.zweitstimmen_prozent ?? 0,
    prozent2025: nach2025[partei]?.zweitstimmen_prozent ?? 0,
    differenz:   (nach2025[partei]?.zweitstimmen_prozent ?? 0)
               - (nach2021[partei]?.zweitstimmen_prozent ?? 0)
  })).sort((a, b) => b.prozent2025 - a.prozent2025);
}

// Verwendung
vergleicheWahlen()
  .then(daten => console.table(daten))
  .catch(fehler => console.error("Fehler:", fehler));
```

---

## 4. iFrame-Widget-Integration

Dieses Minimalbeispiel lädt Daten von der DDJ-DataHub-API und stellt sie als einfache Tabelle dar. Die HTML-Datei kann direkt als iFrame auf rnd.de eingebettet werden.

```html
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DDJ-DataHub Widget</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: Arial, sans-serif;
      font-size: 14px;
      padding: 12px;
      background: #fff;
    }
    h2 { margin-bottom: 12px; font-size: 16px; color: #1a1a2e; }
    table { width: 100%; border-collapse: collapse; }
    th {
      text-align: left;
      padding: 8px;
      background: #f0f0f0;
      border-bottom: 2px solid #ddd;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    td { padding: 8px; border-bottom: 1px solid #eee; }
    tr:hover td { background: #f9f9f9; }
    .balken {
      height: 10px;
      border-radius: 3px;
      display: inline-block;
      min-width: 4px;
    }
    .lade-hinweis { color: #888; font-style: italic; }
    .fehler { color: #c0392b; }
    footer {
      margin-top: 10px;
      font-size: 11px;
      color: #999;
    }
  </style>
</head>
<body>

  <h2 id="titel">Lade Daten…</h2>
  <table id="tabelle">
    <thead>
      <tr id="kopf"></tr>
    </thead>
    <tbody id="inhalt">
      <tr><td class="lade-hinweis" colspan="10">Daten werden geladen…</td></tr>
    </tbody>
  </table>
  <footer>Quelle: DDJ-DataHub · RND Datenrecherche</footer>

  <script>
    // ── Konfiguration ──────────────────────────────────────────────
    const API_BASE   = "https://datahub.rndtech.de";
    const API_TOKEN  = "DEIN_API_TOKEN";        // vom Admin-Team
    const COLLECTION = "bundestagswahl_ergebnisse"; // Collection-Name
    const TITEL      = "Bundestagswahl 2025 — Ergebnisse";
    const FILTER     = { "filter[wahl_jahr][_eq]": 2025 };
    const SORT       = "-zweitstimmen_prozent";
    // Spalten: [API-Feldname, Anzeigename, optional: Render-Funktion]
    const SPALTEN = [
      ["partei",               "Partei"],
      ["zweitstimmen_prozent", "Zweitstimmen",
        wert => {
          const balken = `<span class="balken"
            style="width:${wert * 4}px; background:currentColor"></span>`;
          return `${balken} ${wert.toFixed(1)} %`;
        }
      ],
      ["sitze", "Sitze"],
    ];
    // ── Ende Konfiguration ─────────────────────────────────────────

    async function ladeWidget() {
      const titelEl  = document.getElementById("titel");
      const kopfEl   = document.getElementById("kopf");
      const inhaltEl = document.getElementById("inhalt");

      titelEl.textContent = TITEL;

      try {
        // URL zusammenbauen
        const url = new URL(`${API_BASE}/items/${COLLECTION}`);
        url.searchParams.set("sort[]", SORT);
        Object.entries(FILTER).forEach(([k, v]) =>
          url.searchParams.set(k, v)
        );

        const response = await fetch(url.toString(), {
          headers: { "Authorization": `Bearer ${API_TOKEN}` }
        });

        if (!response.ok) throw new Error(`HTTP ${response.status}`);

        const { data } = await response.json();

        // Kopfzeile
        kopfEl.innerHTML = SPALTEN
          .map(([, name]) => `<th>${name}</th>`)
          .join("");

        // Datenzeilen
        inhaltEl.innerHTML = data.map(eintrag =>
          "<tr>" + SPALTEN.map(([feld, , render]) => {
            const wert = eintrag[feld] ?? "–";
            return `<td>${render ? render(wert) : wert}</td>`;
          }).join("") + "</tr>"
        ).join("");

      } catch (fehler) {
        inhaltEl.innerHTML =
          `<tr><td class="fehler" colspan="${SPALTEN.length}">
            Fehler beim Laden: ${fehler.message}
          </td></tr>`;
        console.error("DDJ-DataHub Widget Fehler:", fehler);
      }
    }

    ladeWidget();
  </script>
</body>
</html>
```

### iFrame-Einbettung auf rnd.de

```html
<iframe
  src="https://datahub.rndtech.de/assets/DATEI_UUID"
  width="100%"
  height="400"
  frameborder="0"
  title="Bundestagswahl 2025 — Ergebnisse"
  loading="lazy">
</iframe>
```

Oder wenn das Widget als eigenständige Seite deployt ist:

```html
<iframe
  src="https://widgets.rnd.de/bundestagswahl-2025/"
  width="100%"
  height="400"
  frameborder="0"
  title="Bundestagswahl 2025"
  loading="lazy">
</iframe>
```

---

## Nützliche API-Parameter

| Parameter | Beispiel | Beschreibung |
|---|---|---|
| `filter[feld][_eq]` | `filter[wahl_jahr][_eq]=2025` | Feld gleich Wert |
| `filter[feld][_gt]` | `filter[stimmen][_gt]=1000` | Größer als |
| `filter[feld][_in]` | `filter[partei][_in]=SPD,CDU` | Einer aus Liste |
| `sort[]` | `sort[]=-stimmen` | Sortierung (- = absteigend) |
| `limit` | `limit=10` | Maximale Anzahl Einträge |
| `offset` | `offset=10` | Einträge überspringen (Paginierung) |
| `fields` | `fields=partei,stimmen` | Nur diese Felder zurückgeben |
| `aggregate[count]` | `aggregate[count]=*` | Anzahl zählen |
| `aggregate[sum]` | `aggregate[sum]=stimmen` | Summe berechnen |
| `aggregate[avg]` | `aggregate[avg]=bewertung` | Durchschnitt berechnen |
| `groupBy[]` | `groupBy[]=partei` | Gruppieren nach Feld |
