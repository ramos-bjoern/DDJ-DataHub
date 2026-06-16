# DDJ-DataHub — Architektur-Spec

**Datum:** 2026-06-16  
**Status:** Freigegeben  
**Stack:** Directus + PostgreSQL + Redis + PgBouncer + Nginx

---

## Ziel

Interne Datenplattform für ein Data-Team (20+ Personen). Das Team soll über eine Admin-GUI selbst Datenstrukturen anlegen und pflegen. Aus diesen Strukturen entstehen automatisch REST- und GraphQL-APIs, die interne Tools und öffentliche Widgets/iFrame-Embeds konsumieren können.

---

## Architektur

```
                    ┌─────────────────────────────────┐
                    │          Nginx (Reverse Proxy)   │
                    │  - TLS-Terminierung              │
                    │  - CORS-Header für Public API    │
                    │  - Rate-Limiting auf /items/*    │
                    │  - CSP für iFrame-Embeds         │
                    └────────────┬────────────────────┘
                                 │
                    ┌────────────▼────────────────────┐
                    │          Directus               │
                    │  - Admin-GUI  (/admin)          │
                    │  - REST-API   (/items/*)        │
                    │  - GraphQL    (/graphql)        │
                    │  - Rollen & Permissions         │
                    └──────┬──────────────┬───────────┘
                           │              │
               ┌───────────▼──┐     ┌────▼──────────┐
               │    Redis     │     │   PgBouncer   │
               │  (API-Cache) │     │ (Conn. Pool)  │
               └──────────────┘     └──────┬────────┘
                                           │
                              ┌────────────▼────────┐
                              │      PostgreSQL      │
                              │  - Collections      │
                              │  - Views (Aggr.)    │
                              │  - Persistenz       │
                              └─────────────────────┘
```

### Container

| Container | Image | Zweck |
|---|---|---|
| `nginx` | `nginx:alpine` | Reverse Proxy, TLS, CORS, Rate-Limiting |
| `directus` | `directus/directus` | Admin-GUI + REST/GraphQL-API |
| `redis` | `redis:alpine` | API-Response-Cache für Directus |
| `pgbouncer` | `bitnami/pgbouncer` | Connection Pooling vor PostgreSQL |
| `postgres` | `postgres:16` | Primäre Datenbank |

### Datenflüsse

| Quelle | Ziel | Auth |
|---|---|---|
| Data-Team (Browser) | `nginx → directus/admin` | Directus Login (Rolle) |
| Interne Apps | `nginx → directus/items/*` | Internal-Viewer API-Token |
| Öffentliche Widgets | `nginx → directus/items/*` | Public Token + CORS |
| Widget Write | `nginx → directus/items/<collection>` | Public Token, Rate-Limited |

---

## Persistenz

- `postgres_data` — Named Volume für PostgreSQL-Daten
- `directus_uploads` — Named Volume für Directus-Uploads und Extensions
- Kein Bind-Mount auf Hostpfade — vollständig Cloud-kompatibel

---

## Performance

### Redis (API-Cache)
Directus cached API-Responses in Redis. TTL per Env-Var konfigurierbar (z.B. 30 Sekunden für Aggregationen). Entlastet PostgreSQL bei vielen gleichzeitigen Widget-Loads erheblich.

```
CACHE_ENABLED=true
CACHE_STORE=redis
CACHE_REDIS=redis://redis:6379
CACHE_TTL=30
```

### PgBouncer (Connection Pooling)
Puffert Datenbankverbindungen. Directus öffnet bei Last viele Connections — PgBouncer reduziert den PostgreSQL-Overhead auf ein Minimum. Wichtig bei 20+ Nutzern und gleichzeitigen Widget-Requests.

### PostgreSQL-Optimierung
- Indexes auf häufig gefilterte Spalten (Data-Team beim Collection-Setup)
- `pg_stat_statements` aktivieren für spätere Query-Analyse
- Aggregationen als PostgreSQL-Views — Directus sieht sie als read-only Collections

```sql
-- Beispiel: Aggregations-View
CREATE VIEW vote_results AS
  SELECT option_id, COUNT(*) AS votes
  FROM votes
  GROUP BY option_id;
```

### Nginx-Cache
Statische API-Responses (Stammdaten, die sich selten ändern) können zusätzlich auf Nginx-Ebene gecached werden — ohne Directus-Overhead.

### Skalierung
Mehrere Directus-Instanzen hinter Nginx möglich (Nginx upstream). Redis wird dann als geteilter Cache zwingend. PgBouncer bleibt Single-Instance-tauglich bis hohe Last.

---

## Rollen- & Rechtekonzept

### Rollen-Hierarchie

| Rolle | Zielgruppe | Rechte |
|---|---|---|
| **Administrator** | Entwickler | Alles — Collections, Rollen, System-Config |
| **Data-Manager** | Data-Team-Lead | Collections + Felder anlegen, Daten importieren |
| **Data-Editor** | Data-Team-Mitglied | Daten lesen/schreiben, kein Schema-Ändern |
| **Internal-Viewer** | Interne Apps / Dashboards | Read-only auf freigegebene interne Collections |
| **Public** | Widgets, iFrame-Embeds | Explizit freigegebene Collections lesen/schreiben |

### Prinzipien

- **Default: nichts ist öffentlich.** Neue Collections sind nach dem Anlegen für die Public Role unsichtbar. Entwickler müssen explizit freischalten.
- **Public Role hat keinen Login.** Zugriff erfolgt über statischen Token oder ohne Token — nur mit den minimal nötigen Rechten.
- **Internal-Viewer-Token** ist ein eigener API-Token — nicht der Admin-Token. Wird in internen Apps als Env-Var gesetzt.
- **Data-Manager kann keine Rollen verwalten** — verhindert Rechte-Eskalation.
- **Permissions sind Collection-granular** — Public Role bekommt nie einen Generalschlüssel.

---

## API-Freigabe-Prozess

Jede Collection durchläuft diesen Prozess bevor sie öffentlich erreichbar ist:

```
1. Data-Team legt Collection in Directus Admin an
2. Entwickler prüft Schema und Feldnamen
3. Entwickler setzt Public-Role-Permission in Directus
   (READ und/oder INSERT, je nach Use-Case)
4. Entwickler trägt Domain in CORS-Whitelist ein (Nginx + Directus Env)
5. Collection ist für Widgets erreichbar
```

### Öffentliche API-Beispiele

```
# Daten lesen
GET /items/<collection>
Authorization: Bearer <PUBLIC_TOKEN>

# Daten schreiben (nur für explizit freigegebene Collections)
POST /items/<collection>
Authorization: Bearer <PUBLIC_TOKEN>
Content-Type: application/json
{ "field": "value" }

# Aggregierte Werte (über PostgreSQL-View)
GET /items/<aggregation_view>?sort[]=-count
Authorization: Bearer <PUBLIC_TOKEN>
```

Der `PUBLIC_TOKEN` hat nur die Rechte der Public Role. Er kann sicher im Widget-JS eingebettet werden.

---

## CORS & Sicherheit

### CORS (Nginx)

```nginx
add_header Access-Control-Allow-Origin "https://rnd.de";
add_header Access-Control-Allow-Origin "https://*.rnd.de";
```

Zusätzlich `CORS_ORIGIN` in Directus Env-Vars — doppelte Absicherung.

### Rate-Limiting (Nginx)

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;
limit_req zone=api burst=10 nodelay;
```

Write-Endpunkte können mit strengeren Zonen belegt werden.

### iFrame-Embed (CSP)

```nginx
add_header Content-Security-Policy "frame-ancestors 'self' https://rnd.de https://*.rnd.de";
```

### Weitere Security-Basics

- `ADMIN_ACCESS_TOKEN` und Datenbank-Passwörter nur über `.env` — nie im Code
- Directus Admin-Panel nicht über Public-Token erreichbar
- PostgreSQL nicht direkt exponiert (nur über PgBouncer intern)
- Nginx als einziger eingehender Punkt — Directus und PostgreSQL sind nicht direkt erreichbar

---

## Projektstruktur (geplant)

```
DDJ-DataHub/
├── docker-compose.yml
├── .env.example
├── .env                    # nicht ins Repo
├── nginx/
│   ├── nginx.conf
│   └── conf.d/
│       └── directus.conf
├── postgres/
│   └── init/
│       └── 01-extensions.sql
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-06-16-ddj-datahub-design.md
```

---

## Offene Punkte / spätere Erweiterungen

- TLS-Zertifikat: Let's Encrypt via Certbot oder Cloud Load Balancer
- Backup-Strategie für PostgreSQL-Volume
- Monitoring: Healthcheck-Endpoints sind vorbereitet, Anbindung an Alerting offen
- Mehrsprachigkeit in Directus-Collections (Directus hat eingebaute i18n-Unterstützung)
- Directus-Flows für automatische Benachrichtigungen bei neuen Daten
