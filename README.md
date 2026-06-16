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

| Service | Port | Beschreibung |
|---|---|---|
| Nginx | 8080 | Einziger Eintrittspunkt, Reverse Proxy |
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
