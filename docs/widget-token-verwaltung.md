# Widget-Token-Verwaltung

Jedes Widget bekommt einen eigenen API-Token mit minimalen Rechten. So kann ein einzelnes Widget gesperrt oder eingeschränkt werden ohne andere zu beeinflussen.

## Konzept

```
Widget Trikot-Voting  → Token A → trikots (read) + trikots_voting (create, read)
Widget Wahlergebnisse → Token B → wahlergebnisse (read)
Widget Umfrage        → Token C → umfrage_antworten (create)
```

Jedes Token gehört zu einem eigenen Directus-User der einer eigenen Rolle zugeordnet ist. Die Rolle hat nur die Permissions die das Widget wirklich braucht.

---

## Neues Widget einrichten

### Voraussetzungen

- Admin-Zugang zu `https://datahub.rndtech.de/admin`
- Die Collection für das Widget ist bereits angelegt

### Schritt 1: Admin-Token holen

```bash
TOKEN=$(curl -s -X POST https://datahub.rndtech.de/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@rndtech.de","password":"DEIN_PASSWORT"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")
```

### Schritt 2: Policy anlegen

Eine Policy definiert die Zugriffsrechte. Ersetze `WIDGET_NAME` mit einem sprechenden Namen (z.B. `trikot-voting`):

```bash
WIDGET_NAME="trikot-voting"

POLICY_ID=$(curl -s -X POST https://datahub.rndtech.de/policies \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Widget-${WIDGET_NAME} Policy\",
    \"icon\": \"widgets\",
    \"admin_access\": false,
    \"app_access\": false
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")

echo "Policy ID: $POLICY_ID"
```

### Schritt 3: Rolle anlegen und mit Policy verknüpfen

```bash
ROLE_ID=$(curl -s -X POST https://datahub.rndtech.de/roles \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"Widget-${WIDGET_NAME}\", \"icon\": \"widgets\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")

echo "Role ID: $ROLE_ID"

curl -s -X POST https://datahub.rndtech.de/access \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"role\": \"$ROLE_ID\", \"policy\": \"$POLICY_ID\", \"sort\": 1}" > /dev/null

echo "Rolle mit Policy verknüpft"
```

### Schritt 4: Permissions setzen

Für jede Collection die das Widget braucht eine Permission setzen. Ersetze `COLLECTION` und `ACTION` (`read`, `create`, `update`, `delete`):

```bash
# Beispiel: trikots lesen
curl -s -X POST https://datahub.rndtech.de/permissions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"policy\": \"$POLICY_ID\",
    \"collection\": \"trikots\",
    \"action\": \"read\",
    \"fields\": [\"*\"],
    \"permissions\": {},
    \"validation\": {}
  }" > /dev/null

# Beispiel: trikots_voting schreiben
curl -s -X POST https://datahub.rndtech.de/permissions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"policy\": \"$POLICY_ID\",
    \"collection\": \"trikots_voting\",
    \"action\": \"create\",
    \"fields\": [\"trikot_id\", \"bewertung\"],
    \"permissions\": {},
    \"validation\": {\"bewertung\": {\"_gte\": 0, \"_lte\": 5}}
  }" > /dev/null

echo "Permissions gesetzt"
```

### Schritt 5: Widget-User mit statischem Token anlegen

```bash
# Token generieren (merken — wird im Widget-JS eingebettet)
WIDGET_TOKEN="widget_${WIDGET_NAME}_$(openssl rand -hex 8)"
echo "Widget-Token: $WIDGET_TOKEN"

curl -s -X POST https://datahub.rndtech.de/users \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"first_name\": \"Widget\",
    \"last_name\": \"${WIDGET_NAME}\",
    \"email\": \"widget-${WIDGET_NAME}@system.datahub\",
    \"password\": \"$(openssl rand -base64 24)\",
    \"role\": \"$ROLE_ID\",
    \"status\": \"active\",
    \"token\": \"$WIDGET_TOKEN\"
  }" | python3 -c "
import sys,json
d = json.load(sys.stdin)
if 'data' in d:
    print(f'User angelegt: {d[\"data\"][\"email\"]}')
else:
    print('FEHLER:', d)
"
```

### Schritt 6: Token im Widget verwenden

```js
const API   = 'https://datahub.rndtech.de'
const TOKEN = 'widget_trikot-voting_abc123'  // aus Schritt 5

// Daten lesen
const res = await fetch(`${API}/items/trikots`, {
  headers: { 'Authorization': `Bearer ${TOKEN}` }
})

// Daten schreiben
await fetch(`${API}/items/trikots_voting`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ trikot_id: 41, bewertung: 4.5 })
})
```

---

## Widget-Token sperren

Wenn ein Widget gesperrt werden soll (z.B. Abstimmung beendet):

```bash
TOKEN="ADMIN_TOKEN"
USER_EMAIL="widget-trikot-voting@system.datahub"

# User-ID holen
USER_ID=$(curl -s "https://datahub.rndtech.de/users?filter[email][_eq]=${USER_EMAIL}" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])")

# User deaktivieren
curl -s -X PATCH "https://datahub.rndtech.de/users/$USER_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "suspended"}' > /dev/null

echo "Widget-Token gesperrt"
```

---

## Bestehende Widget-Tokens anzeigen

```bash
curl -s "https://datahub.rndtech.de/users?filter[email][_contains]=widget-&fields=email,status,role" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "
import sys,json
for u in json.load(sys.stdin)['data']:
    print(f'{u[\"status\"]:10} {u[\"email\"]}')
"
```

---

## Übersicht aktuelle Widgets

| Widget | Token-User | Collections | Status |
|---|---|---|---|
| Trikot-Voting | widget-trikot@example.com | trikots (r), trikots_voting (cr) | aktiv |

*Diese Tabelle manuell aktualisieren wenn neue Widgets hinzukommen.*
