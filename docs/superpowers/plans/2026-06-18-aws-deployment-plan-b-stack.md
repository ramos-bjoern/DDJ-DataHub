# DDJ-DataHub AWS Deployment — Plan B: Stack auf EC2 deployen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den DDJ-DataHub Docker-Compose-Stack auf der EC2-Instanz deployen, TLS via Certbot/Let's Encrypt einrichten und den Stack als systemd-Service für Autostart konfigurieren.

**Architecture:** Alle Container (Nginx, Directus, PostgreSQL, Redis, PgBouncer) laufen auf der EC2-Instanz. Nginx terminiert TLS direkt via Certbot/Let's Encrypt auf Port 443. PostgreSQL bleibt im Docker-Container — kein RDS. Eine `docker-compose.prod.yml` überschreibt nur Production-spezifische Werte (Port 80/443 statt 8090, Production-URL, CORS).

```
Internet
    ↓ HTTPS Port 443
EC2 18.196.95.31
    ↓
Nginx (Docker) — TLS via Certbot
    ↓
Directus (Docker)
    ↓
PgBouncer → PostgreSQL (Docker)
         + Redis (Docker)
```

**Tech Stack:** Docker Compose, Nginx 1.27 + Certbot, Directus 11.3.5, PostgreSQL 16, Redis 7.2, PgBouncer, Amazon Linux 2023

**Voraussetzung:** Plan A abgeschlossen — EC2 läuft unter `18.196.95.31`, Route53-PR für `datahub.rndtech.de` ist gemergt und DNS propagiert.

**DNS prüfen bevor du anfängst:**
```bash
dig datahub.rndtech.de +short
# Muss 18.196.95.31 liefern
```

---

## Dateistruktur

```
DDJ-DataHub/
├── docker-compose.yml         # Basis — lokal mit Port 8090
├── docker-compose.prod.yml    # Production-Overrides — Port 80, Production-URL
├── .env.prod.example          # Production .env Vorlage (ohne Secrets)
└── nginx/conf.d/
    └── directus.conf          # wird für Certbot angepasst (Port 443)
```

---

## Task 1: docker-compose.prod.yml und .env.prod.example anlegen

**Files:**
- Create: `docker-compose.prod.yml`
- Create: `.env.prod.example`

- [ ] **Schritt 1: `docker-compose.prod.yml` anlegen**

```yaml
# Production-Overrides für AWS EC2
# Verwendung: docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
services:

  directus:
    environment:
      PUBLIC_URL: "https://datahub.rndtech.de"
      CORS_ORIGIN: "https://datahub.rndtech.de,https://rnd.de,https://*.rnd.de"
      CACHE_TTL: "60"
      LOG_LEVEL: "warn"

  nginx:
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/lib/letsencrypt:/var/lib/letsencrypt:ro
```

**Erklärung:** Die prod-Datei überschreibt nur was sich von lokal unterscheidet:
- Directus kennt die echte HTTPS-URL
- Nginx bekommt Port 443 zusätzlich zu 80
- Certbot-Zertifikate vom Host werden in den Nginx-Container gemountet

- [ ] **Schritt 2: `.env.prod.example` anlegen**

```dotenv
# === Production .env für AWS EC2 ===
# Kopieren: cp .env.prod.example .env

# PostgreSQL (läuft als Docker-Container auf EC2)
POSTGRES_DB=datahub
POSTGRES_USER=datahub_user
POSTGRES_PASSWORD=REPLACE_ME_strong_password

# PgBouncer
PGBOUNCER_DATABASE=datahub
PGBOUNCER_AUTH_USER=datahub_user
PGBOUNCER_AUTH_PASSWORD=REPLACE_ME_strong_password
PGBOUNCER_POOL_MODE=transaction
PGBOUNCER_MAX_CLIENT_CONN=200
PGBOUNCER_DEFAULT_POOL_SIZE=20

# Directus
# SECRET: openssl rand -hex 32
SECRET=REPLACE_ME_openssl_rand_hex_32
ADMIN_EMAIL=admin@rndtech.de
ADMIN_PASSWORD=REPLACE_ME_admin_password

DB_CLIENT=pg
DB_HOST=pgbouncer
DB_PORT=5432
DB_DATABASE=datahub
DB_USER=datahub_user
DB_PASSWORD=REPLACE_ME_strong_password

# Cache
CACHE_ENABLED=true
CACHE_STORE=redis
CACHE_REDIS=redis://redis:6379
REDIS=redis://redis:6379
CACHE_TTL=60

# CORS
CORS_ENABLED=true
CORS_ORIGIN=https://datahub.rndtech.de,https://rnd.de,https://*.rnd.de

# Production URL
PUBLIC_URL=https://datahub.rndtech.de

# Directus Replicas
DIRECTUS_REPLICAS=1

# Logging
LOG_LEVEL=warn
```

- [ ] **Schritt 3: Committen**

```bash
git add docker-compose.prod.yml .env.prod.example
git commit -m "feat: add production docker-compose overrides and env template for EC2"
git push origin main
```

---

## Task 2: Nginx-Config für Production (Port 443 + Certbot)

**Files:**
- Create: `nginx/conf.d/directus.prod.conf`

Certbot braucht zunächst Port 80 um das Zertifikat auszustellen. Danach wird auf HTTPS umgeleitet. Wir erstellen eine separate Prod-Config die nach dem Certbot-Lauf aktiviert wird.

- [ ] **Schritt 1: `nginx/conf.d/directus.prod.conf` anlegen**

```nginx
# Rate-Limit-Zonen
limit_req_zone $http_authorization   zone=api_read:20m  rate=300r/m;
limit_req_zone $binary_remote_addr   zone=api_write:10m rate=10r/m;
limit_req_zone $binary_remote_addr   zone=api_auth:10m  rate=5r/m;

# Nginx-Cache für GET /items/*
proxy_cache_path /tmp/nginx_cache
    levels=1:2
    keys_zone=items_cache:10m
    max_size=200m
    inactive=60s
    use_temp_path=off;

# CORS
map $http_origin $cors_origin {
    default "";
    "~^https://(www\.)?rnd\.de$"    $http_origin;
    "~^https://[^/]+\.rnd\.de$"     $http_origin;
    "~^https://datahub\.rndtech\.de$" $http_origin;
}

# HTTP → HTTPS Redirect
server {
    listen 80;
    server_name datahub.rndtech.de;

    # Certbot ACME Challenge
    location /.well-known/acme-challenge/ {
        root /var/lib/letsencrypt;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl;
    server_name datahub.rndtech.de;

    ssl_certificate     /etc/letsencrypt/live/datahub.rndtech.de/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/datahub.rndtech.de/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # Sicherheits-Header
    add_header X-Content-Type-Options  "nosniff" always;
    add_header Referrer-Policy         "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "frame-ancestors 'self' https://rnd.de https://*.rnd.de" always;

    # CORS
    add_header Access-Control-Allow-Origin  $cors_origin always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
    add_header X-Cache-Status $upstream_cache_status always;

    proxy_hide_header X-Powered-By;
    proxy_hide_header Server;
    proxy_hide_header Access-Control-Allow-Origin;
    proxy_hide_header Access-Control-Allow-Methods;
    proxy_hide_header Access-Control-Allow-Headers;
    proxy_hide_header Access-Control-Allow-Credentials;

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout    300;
    proxy_connect_timeout 300;

    location ~ ^/auth/ {
        limit_req zone=api_auth burst=3 nodelay;
        proxy_pass http://directus:8055;
    }

    location ~ ^/items/ {
        proxy_ignore_headers     Cache-Control Expires;
        proxy_cache              items_cache;
        proxy_cache_key          "$request_method$request_uri$http_authorization";
        proxy_cache_valid        200 10s;
        proxy_cache_valid        404  5s;
        proxy_cache_methods      GET HEAD;
        proxy_cache_lock         on;
        proxy_cache_lock_timeout 5s;
        proxy_cache_use_stale    error timeout updating http_500 http_502 http_503;
        limit_req zone=api_read  burst=100 delay=50;
        proxy_pass http://directus:8055;
    }

    location / {
        proxy_pass http://directus:8055;
    }
}
```

- [ ] **Schritt 2: Committen**

```bash
git add nginx/conf.d/directus.prod.conf
git commit -m "feat: add nginx production config with TLS, CORS and caching for datahub.rndtech.de"
git push origin main
```

---

## Task 3: Stack auf EC2 deployen

Alle folgenden Schritte laufen **auf der EC2-Instanz**. Verbinden per SSH:

```bash
ssh -i ~/.ssh/one-platform-udpm.pem ec2-user@18.196.95.31
```

Oder per SSM (kein SSH-Port nötig):
```bash
aws ssm start-session --target i-053f7a8b1820f9f47 --profile OnePlatform-UDPM.AdministratorAccess
```

- [ ] **Schritt 1: Warten bis User Data fertig ist**

```bash
# Prüfen ob Docker verfügbar ist (User Data läuft ~2 Min nach Instance-Start)
docker --version
docker compose version
which certbot
```

Erwartete Ausgabe: Docker 26.x, Docker Compose 2.x, certbot-Pfad.

Falls noch nicht fertig: `cat /var/log/cloud-init-output.log | tail -20` zeigt den Fortschritt.

- [ ] **Schritt 2: Repo klonen**

```bash
cd /opt/ddj-datahub
git clone https://github.com/ramos-bjoern/DDJ-DataHub.git .
```

- [ ] **Schritt 3: Production `.env` befüllen**

```bash
cp .env.prod.example .env
```

Dann `.env` bearbeiten — alle `REPLACE_ME`-Werte ersetzen:

```bash
# Starkes Passwort generieren
openssl rand -hex 32   # → für SECRET
openssl rand -base64 24  # → für POSTGRES_PASSWORD und ADMIN_PASSWORD
```

```bash
nano .env
# oder: vi .env
```

- [ ] **Schritt 4: Stack ohne TLS starten (für Certbot)**

Zuerst mit der normalen `directus.conf` (Port 80) starten damit Certbot arbeiten kann:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

- [ ] **Schritt 5: Stack-Status prüfen**

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

Erwartete Ausgabe: pgbouncer, redis, directus, nginx — alle `healthy`. postgres ebenfalls.

- [ ] **Schritt 6: Health-Check auf EC2**

```bash
curl -s http://localhost/server/health
```

Erwartete Ausgabe: `{"status":"ok"}`

---

## Task 4: TLS-Zertifikat mit Certbot ausstellen

- [ ] **Schritt 1: DNS-Propagierung prüfen (von EC2 aus)**

```bash
dig datahub.rndtech.de +short
```

Erwartete Ausgabe: `18.196.95.31` — muss stimmen sonst schlägt Certbot fehl.

- [ ] **Schritt 2: Certbot-Zertifikat ausstellen**

```bash
sudo certbot certonly \
  --webroot \
  --webroot-path /var/lib/letsencrypt \
  -d datahub.rndtech.de \
  --non-interactive \
  --agree-tos \
  -m admin@rndtech.de
```

Erwartete Ausgabe:
```
Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/datahub.rndtech.de/fullchain.pem
```

- [ ] **Schritt 3: Production-Nginx-Config aktivieren**

```bash
# Aktuelle Config sichern
cp /opt/ddj-datahub/nginx/conf.d/directus.conf \
   /opt/ddj-datahub/nginx/conf.d/directus.conf.local-backup

# Prod-Config aktivieren
cp /opt/ddj-datahub/nginx/conf.d/directus.prod.conf \
   /opt/ddj-datahub/nginx/conf.d/directus.conf
```

- [ ] **Schritt 4: Nginx neu laden**

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart nginx
```

- [ ] **Schritt 5: HTTPS testen**

```bash
curl -s https://datahub.rndtech.de/server/health
```

Erwartete Ausgabe: `{"status":"ok"}`

- [ ] **Schritt 6: HTTP→HTTPS Redirect testen**

```bash
curl -si http://datahub.rndtech.de/server/health | head -5
```

Erwartete Ausgabe: `HTTP/1.1 301 Moved Permanently`

- [ ] **Schritt 7: Certbot Auto-Renewal einrichten**

```bash
# Cron-Job: täglich prüfen ob Zertifikat erneuert werden muss
echo "0 3 * * * root certbot renew --quiet --post-hook 'docker compose -f /opt/ddj-datahub/docker-compose.yml -f /opt/ddj-datahub/docker-compose.prod.yml restart nginx'" \
  | sudo tee /etc/cron.d/certbot-renew
```

---

## Task 5: Autostart mit systemd

- [ ] **Schritt 1: systemd-Service anlegen**

```bash
sudo tee /etc/systemd/system/ddj-datahub.service > /dev/null <<'EOF'
[Unit]
Description=DDJ-DataHub Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/ddj-datahub
ExecStart=/usr/local/lib/docker/cli-plugins/docker-compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  up -d --remove-orphans
ExecStop=/usr/local/lib/docker/cli-plugins/docker-compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  down
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ddj-datahub
```

- [ ] **Schritt 2: Service-Status prüfen**

```bash
sudo systemctl status ddj-datahub
```

Erwartete Ausgabe: `Active: active (exited)` — korrekt für `Type=oneshot`.

- [ ] **Schritt 3: Reboot-Test**

```bash
sudo reboot
```

Nach ~3 Minuten wieder verbinden:

```bash
ssh -i ~/.ssh/one-platform-udpm.pem ec2-user@18.196.95.31
curl -s https://datahub.rndtech.de/server/health
```

Erwartete Ausgabe: `{"status":"ok"}`

---

## Self-Review Checkliste

- [ ] Stack läuft auf EC2: pgbouncer, redis, directus, nginx, postgres alle `healthy`
- [ ] `http://datahub.rndtech.de` leitet auf HTTPS um (301)
- [ ] `https://datahub.rndtech.de/server/health` → `{"status":"ok"}`
- [ ] `https://datahub.rndtech.de/admin` — Admin-GUI erreichbar
- [ ] Certbot-Zertifikat gültig (`curl -vI https://datahub.rndtech.de 2>&1 | grep "SSL certificate"`)
- [ ] Auto-Renewal Cron-Job aktiv (`cat /etc/cron.d/certbot-renew`)
- [ ] systemd-Service enabled (`systemctl is-enabled ddj-datahub`)
- [ ] Stack startet nach Reboot automatisch
- [ ] Keine Secrets in Git

---

## Nächste Schritte nach Plan B

- **Plan C:** GitHub Actions CI/CD — automatisches Deploy bei Push auf main
- **Datenmigration:** Lokale DB auf EC2 übertragen wenn nötig (`pg_dump` + `pg_restore`)
