# DDJ-DataHub — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vollständigen lokalen Docker-Stack aufsetzen: PostgreSQL + PgBouncer + Redis + Directus + Nginx, betriebsbereit mit Rollen-Konzept und öffentlicher API-Freigabe.

**Architecture:** Nginx als einziger Eintrittspunkt leitet an Directus weiter; Directus cached über Redis und verbindet sich via PgBouncer mit PostgreSQL. Alle Secrets in `.env`, keine Bind-Mounts auf Hostpfade.

**Tech Stack:** Docker Compose, PostgreSQL 16, PgBouncer (bitnami), Redis alpine, Directus (latest), Nginx alpine

---

## Dateistruktur

```
DDJ-DataHub/
├── docker-compose.yml           # alle 5 Services, Volumes, Networks
├── .env.example                 # Vorlage mit allen Env-Vars, keine echten Secrets
├── .env                         # lokale Secrets — NICHT im Repo
├── .gitignore                   # .env ausschließen
├── nginx/
│   └── conf.d/
│       └── directus.conf        # Proxy-Regeln, CORS, Rate-Limiting, CSP
├── postgres/
│   └── init/
│       └── 01-extensions.sql    # pg_stat_statements aktivieren
└── docs/
    └── superpowers/
        ├── specs/
        │   └── 2026-06-16-ddj-datahub-design.md
        └── plans/
            └── 2026-06-16-ddj-datahub-setup.md
```

---

## Task 1: .gitignore und .env.example anlegen

**Files:**
- Create: `.gitignore`
- Create: `.env.example`

- [ ] **Schritt 1: .gitignore anlegen**

```
# .gitignore
.env
*.log
uploads/
```

- [ ] **Schritt 2: .env.example anlegen**

```dotenv
# PostgreSQL
POSTGRES_DB=datahub
POSTGRES_USER=datahub_user
POSTGRES_PASSWORD=change_me_postgres

# PgBouncer
PGBOUNCER_DATABASE=datahub
PGBOUNCER_AUTH_USER=datahub_user
PGBOUNCER_AUTH_PASSWORD=change_me_postgres
PGBOUNCER_POOL_MODE=transaction
PGBOUNCER_MAX_CLIENT_CONN=200
PGBOUNCER_DEFAULT_POOL_SIZE=20

# Directus
SECRET=change_me_secret_min_32_chars_long
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=change_me_admin

DB_CLIENT=pg
DB_HOST=pgbouncer
DB_PORT=5432
DB_DATABASE=datahub
DB_USER=datahub_user
DB_PASSWORD=change_me_postgres

CACHE_ENABLED=true
CACHE_STORE=redis
CACHE_REDIS=redis://redis:6379
CACHE_TTL=30

CORS_ENABLED=true
CORS_ORIGIN=https://rnd.de,https://*.rnd.de

PUBLIC_URL=http://localhost:8080
```

- [ ] **Schritt 3: .env aus .env.example erstellen und Werte setzen**

```bash
cp .env.example .env
```

Dann in `.env` konkrete Werte eintragen (lokale Entwicklung reichen einfache Passwörter):

```dotenv
POSTGRES_PASSWORD=localdev123
PGBOUNCER_AUTH_PASSWORD=localdev123
SECRET=localdev_secret_32chars_xxxxxxxx
ADMIN_EMAIL=admin@datahub.local
ADMIN_PASSWORD=Admin1234!
DB_PASSWORD=localdev123
PUBLIC_URL=http://localhost:8080
```

- [ ] **Schritt 4: Committen**

```bash
git add .gitignore .env.example
git commit -m "chore: add .gitignore and .env.example"
```

---

## Task 2: PostgreSQL Init-Script

**Files:**
- Create: `postgres/init/01-extensions.sql`

- [ ] **Schritt 1: Init-Verzeichnis anlegen**

```bash
mkdir -p postgres/init
```

- [ ] **Schritt 2: SQL-Script anlegen**

```sql
-- postgres/init/01-extensions.sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

`pg_stat_statements` ermöglicht später Query-Performance-Analyse direkt in PostgreSQL — kein Runtime-Overhead, aber wertvolle Diagnose-Daten.

- [ ] **Schritt 3: Committen**

```bash
git add postgres/
git commit -m "chore: add postgres init script with pg_stat_statements"
```

---

## Task 3: Nginx-Konfiguration

**Files:**
- Create: `nginx/conf.d/directus.conf`

- [ ] **Schritt 1: Verzeichnis anlegen**

```bash
mkdir -p nginx/conf.d
```

- [ ] **Schritt 2: Nginx-Konfiguration anlegen**

```nginx
# nginx/conf.d/directus.conf

# Rate-Limit-Zonen
limit_req_zone $binary_remote_addr zone=api_read:10m rate=60r/m;
limit_req_zone $binary_remote_addr zone=api_write:10m rate=10r/m;

server {
    listen 80;
    server_name _;

    # Sicherheits-Header
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # CSP: erlaubt iFrame-Einbettung nur von rnd.de
    add_header Content-Security-Policy "frame-ancestors 'self' https://rnd.de https://*.rnd.de" always;

    # CORS für öffentliche API-Endpunkte
    add_header Access-Control-Allow-Origin "https://rnd.de" always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;

    # OPTIONS preflight
    if ($request_method = OPTIONS) {
        return 204;
    }

    # Rate-Limiting: Write-Endpunkte strenger
    location ~ ^/items/[^/]+$ {
        if ($request_method = POST) {
            limit_req zone=api_write burst=5 nodelay;
        }
        limit_req zone=api_read burst=20 nodelay;
        proxy_pass http://directus:8055;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Alle anderen Anfragen (Admin, GraphQL, Auth)
    location / {
        proxy_pass http://directus:8055;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
    }
}
```

- [ ] **Schritt 3: Committen**

```bash
git add nginx/
git commit -m "chore: add nginx reverse proxy config with CORS and rate-limiting"
```

---

## Task 4: docker-compose.yml

**Files:**
- Create: `docker-compose.yml`

- [ ] **Schritt 1: docker-compose.yml anlegen**

```yaml
# docker-compose.yml
services:

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-datahub}
      POSTGRES_USER: ${POSTGRES_USER:-datahub_user}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-datahub_user} -d ${POSTGRES_DB:-datahub}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - internal

  pgbouncer:
    image: bitnami/pgbouncer:latest
    restart: unless-stopped
    environment:
      POSTGRESQL_HOST: postgres
      POSTGRESQL_PORT: 5432
      POSTGRESQL_DATABASE: ${PGBOUNCER_DATABASE:-datahub}
      POSTGRESQL_USERNAME: ${PGBOUNCER_AUTH_USER:-datahub_user}
      POSTGRESQL_PASSWORD: ${PGBOUNCER_AUTH_PASSWORD}
      PGBOUNCER_POOL_MODE: ${PGBOUNCER_POOL_MODE:-transaction}
      PGBOUNCER_MAX_CLIENT_CONN: ${PGBOUNCER_MAX_CLIENT_CONN:-200}
      PGBOUNCER_DEFAULT_POOL_SIZE: ${PGBOUNCER_DEFAULT_POOL_SIZE:-20}
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -p 5432"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - internal

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --save "" --appendonly no
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - internal

  directus:
    image: directus/directus:latest
    restart: unless-stopped
    environment:
      SECRET: ${SECRET}
      ADMIN_EMAIL: ${ADMIN_EMAIL}
      ADMIN_PASSWORD: ${ADMIN_PASSWORD}

      DB_CLIENT: pg
      DB_HOST: pgbouncer
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB:-datahub}
      DB_USER: ${POSTGRES_USER:-datahub_user}
      DB_PASSWORD: ${POSTGRES_PASSWORD}

      CACHE_ENABLED: "true"
      CACHE_STORE: redis
      CACHE_REDIS: redis://redis:6379
      CACHE_TTL: "30"

      CORS_ENABLED: "true"
      CORS_ORIGIN: ${CORS_ORIGIN:-http://localhost:8080}

      PUBLIC_URL: ${PUBLIC_URL:-http://localhost:8080}

      QUERY_LIMIT_DEFAULT: "100"
      QUERY_LIMIT_MAX: "500"
    volumes:
      - directus_uploads:/directus/uploads
    depends_on:
      pgbouncer:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8055/server/health || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 60s
    networks:
      - internal

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    depends_on:
      directus:
        condition: service_healthy
    networks:
      - internal

volumes:
  postgres_data:
  directus_uploads:

networks:
  internal:
    driver: bridge
```

- [ ] **Schritt 2: Committen**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose stack (postgres, pgbouncer, redis, directus, nginx)"
```

---

## Task 5: Stack starten und Healthchecks verifizieren

- [ ] **Schritt 1: Stack starten**

```bash
docker compose up -d
```

- [ ] **Schritt 2: Container-Status prüfen (alle müssen `healthy` oder `running` sein)**

```bash
docker compose ps
```

Erwartete Ausgabe: alle 5 Services `running`, Directus nach ~60s `healthy`.

- [ ] **Schritt 3: Directus-Logs verfolgen bis ready**

```bash
docker compose logs -f directus
```

Warten bis diese Zeile erscheint:
```
Server started at http://0.0.0.0:8055
```
Mit `Ctrl+C` beenden.

- [ ] **Schritt 4: Admin-GUI aufrufen**

Browser öffnen: `http://localhost:8080/admin`

Login mit:
- Email: Wert aus `.env` → `ADMIN_EMAIL`
- Passwort: Wert aus `.env` → `ADMIN_PASSWORD`

Erwartung: Directus Admin-Dashboard lädt.

- [ ] **Schritt 5: API-Health-Check**

```bash
curl -s http://localhost:8080/server/health | python3 -m json.tool
```

Erwartete Ausgabe:
```json
{
  "status": "ok"
}
```

---

## Task 6: Rollen anlegen (Directus Admin-GUI)

Directus-Rollen werden über die GUI angelegt. Keine API-Calls nötig — der Admin-Bootstrap hat bereits den Administrator-Account erstellt.

- [ ] **Schritt 1: Data-Manager-Rolle anlegen**

In der Directus-GUI: `Settings → Roles & Permissions → Create Role`

- Name: `Data-Manager`
- App Access: `enabled`
- Admin Access: `disabled`
- Permissions: Alle Collections — `create`, `read`, `update`, `delete` ✓
- Schema: `create`, `update`, `delete` ✓ (darf Collections anlegen)
- Flows: `create`, `read`, `update`, `delete` ✓

- [ ] **Schritt 2: Data-Editor-Rolle anlegen**

`Settings → Roles & Permissions → Create Role`

- Name: `Data-Editor`
- App Access: `enabled`
- Admin Access: `disabled`
- Permissions: Alle Collections — `create`, `read`, `update` ✓, kein `delete`
- Schema: alle `disabled` (darf kein Schema ändern)
- Flows: nur `read` ✓ (sieht Flows, kann sie manuell triggern aber nicht bearbeiten)

- [ ] **Schritt 3: Internal-Viewer-Rolle anlegen**

`Settings → Roles & Permissions → Create Role`

- Name: `Internal-Viewer`
- App Access: `disabled` (kein GUI-Zugang nötig)
- Admin Access: `disabled`
- Permissions: Per Collection explizit `read` freischalten wenn nötig

- [ ] **Schritt 4: Internal-Viewer API-Token erstellen**

`Settings → Users → Create User`

- Email: `internal-viewer@system.local`
- Rolle: `Internal-Viewer`
- Password: beliebig (wird nicht genutzt)

Dann: User öffnen → `Token` generieren → Wert sichern (in `.env` als `INTERNAL_VIEWER_TOKEN=...` eintragen).

- [ ] **Schritt 5: Public Role konfigurieren**

`Settings → Roles & Permissions → Public`

- Alle Permissions auf `disabled` lassen (Default ist bereits nichts freigegeben)
- Wird in Task 7 Collection-spezifisch geöffnet

---

## Task 7: Beispiel-Collection anlegen und öffentlich freigeben

Dieser Task demonstriert den vollständigen Freigabe-Prozess anhand einer generischen Beispiel-Collection.

- [ ] **Schritt 1: Collection in Directus anlegen**

`Content → Collections → Create Collection`

- Name: `beispiel_eintraege`
- Felder hinzufügen:
  - `titel` — Type: `String`
  - `wert` — Type: `Integer`
  - `erstellt_am` — Type: `Timestamp`, Default: `$NOW`

- [ ] **Schritt 2: Testdaten eingeben**

`Content → beispiel_eintraege → Create Item`

3 Einträge anlegen:
```
{ titel: "Eintrag A", wert: 42 }
{ titel: "Eintrag B", wert: 17 }
{ titel: "Eintrag C", wert: 99 }
```

- [ ] **Schritt 3: Public Role Read-Permission freischalten**

`Settings → Roles & Permissions → Public → beispiel_eintraege`

- `read`: `enabled` (alle Felder)
- alle anderen: `disabled`

- [ ] **Schritt 4: Öffentlichen Zugriff testen**

```bash
curl -s "http://localhost:8080/items/beispiel_eintraege" | python3 -m json.tool
```

Erwartete Ausgabe:
```json
{
  "data": [
    { "id": 1, "titel": "Eintrag A", "wert": 42 },
    { "id": 2, "titel": "Eintrag B", "wert": 17 },
    { "id": 3, "titel": "Eintrag C", "wert": 99 }
  ]
}
```

- [ ] **Schritt 5: Aggregation testen**

```bash
curl -s "http://localhost:8080/items/beispiel_eintraege?aggregate[sum]=wert&aggregate[count]=*" | python3 -m json.tool
```

Erwartete Ausgabe:
```json
{
  "data": [
    {
      "sum": { "wert": 158 },
      "count": { "*": 3 }
    }
  ]
}
```

- [ ] **Schritt 6: Sortierung testen (Basis für Widget-Rang-Berechnung im Client)**

```bash
curl -s "http://localhost:8080/items/beispiel_eintraege?sort[]=-wert" | python3 -m json.tool
```

Erwartete Ausgabe: Einträge sortiert nach `wert` absteigend (C, A, B).

---

## Task 8: Directus Flow mit Cron anlegen

Dieser Task zeigt den Flows-Mechanismus anhand eines einfachen Beispiels: täglich um 06:00 Uhr wird ein Aggregations-Ergebnis in eine Ergebnis-Collection geschrieben.

- [ ] **Schritt 1: Ergebnis-Collection anlegen**

`Content → Collections → Create Collection`

- Name: `tagesberechnungen`
- Felder:
  - `bezeichnung` — Type: `String`
  - `ergebnis` — Type: `JSON`
  - `berechnet_am` — Type: `Timestamp`, Default: `$NOW`

- [ ] **Schritt 2: Flow anlegen**

`Settings → Flows → Create Flow`

- Name: `Tagesberechnung`
- Trigger: `Schedule`
- Cron: `0 6 * * *` (täglich 06:00)
- Description: `Berechnet tägliche Aggregation und schreibt Ergebnis`

- [ ] **Schritt 3: Read-Operation hinzufügen**

Im Flow-Editor: `+` → `Read Data`

- Collection: `beispiel_eintraege`
- Aggregate: `sum` auf `wert`
- Key: `rohdaten`

- [ ] **Schritt 4: Create-Operation hinzufügen**

Im Flow-Editor: `+` → `Create Data`

- Collection: `tagesberechnungen`
- Payload:
```json
{
  "bezeichnung": "Tages-Summe beispiel_eintraege.wert",
  "ergebnis": "{{rohdaten}}"
}
```

- [ ] **Schritt 5: Flow manuell triggern zum Testen**

Im Flow-Editor oben rechts: `Run Flow manually`

Dann prüfen:
```bash
curl -s "http://localhost:8080/items/tagesberechnungen" | python3 -m json.tool
```

Erwartete Ausgabe: ein neuer Eintrag mit dem berechneten Ergebnis.

---

## Task 9: README.md aktualisieren

**Files:**
- Modify: `README.md`

- [ ] **Schritt 1: README.md ersetzen**

```markdown
# DDJ-DataHub

Interne Datenplattform für das Data-Team. Basiert auf Directus, PostgreSQL, Redis, PgBouncer und Nginx.

## Voraussetzungen

- Docker >= 24
- Docker Compose >= 2.x

## Setup

1. Repository klonen
2. `.env` aus `.env.example` erstellen und Werte eintragen:
   ```bash
   cp .env.example .env
   # .env bearbeiten: Passwörter und SECRET setzen
   ```
3. Stack starten:
   ```bash
   docker compose up -d
   ```
4. Warten bis Directus startet (~60s), dann Admin-GUI aufrufen:
   `http://localhost:8080/admin`

## Services

| Service | Intern | Beschreibung |
|---|---|---|
| Nginx | Port 8080 | Einziger Eintrittspunkt, Reverse Proxy |
| Directus | intern:8055 | Admin-GUI + REST/GraphQL-API |
| Redis | intern:6379 | API-Response-Cache |
| PgBouncer | intern:5432 | Connection Pooling |
| PostgreSQL | intern:5432 | Datenbank |

## API-Zugriff

```bash
# Öffentliche Collections (kein Token nötig wenn Public Role konfiguriert)
curl http://localhost:8080/items/<collection>

# Interne Collections (API-Token nötig)
curl -H "Authorization: Bearer <TOKEN>" http://localhost:8080/items/<collection>
```

## Rollen

| Rolle | Zielgruppe |
|---|---|
| Administrator | Entwickler — voller Zugriff |
| Data-Manager | Data-Team-Lead — Collections anlegen, Flows konfigurieren |
| Data-Editor | Data-Team-Mitglied — Daten bearbeiten |
| Internal-Viewer | Interne Apps — read-only via API-Token |
| Public | Widgets/iFrames — nur explizit freigegebene Collections |

## Collection öffentlich freigeben

1. Collection in Directus Admin anlegen
2. `Settings → Roles & Permissions → Public` → Collection auf `read` (und ggf. `create`) setzen
3. Domain in `CORS_ORIGIN` in `.env` eintragen und `docker compose restart nginx directus`

## Logs

```bash
docker compose logs -f directus
docker compose logs -f nginx
```

## Stack stoppen

```bash
docker compose down          # Container stoppen, Volumes bleiben
docker compose down -v       # ACHTUNG: löscht auch alle Daten
```
```

- [ ] **Schritt 2: Committen**

```bash
git add README.md
git commit -m "docs: update README with setup instructions and role overview"
```

---

## Self-Review Checkliste

Nach dem Abarbeiten aller Tasks:

- [ ] `docker compose ps` — alle 5 Services `running` / `healthy`
- [ ] `http://localhost:8080/admin` — Directus Admin-GUI erreichbar
- [ ] `curl http://localhost:8080/server/health` — `{"status":"ok"}`
- [ ] `curl http://localhost:8080/items/beispiel_eintraege` — gibt Daten zurück
- [ ] Aggregation-Endpoint liefert `sum` und `count`
- [ ] Tagesberechnung-Flow hat einen Eintrag in `tagesberechnungen` erzeugt
- [ ] Rollen `Data-Manager`, `Data-Editor`, `Internal-Viewer` existieren in Directus
- [ ] `.env` ist in `.gitignore` und nicht im Repo
