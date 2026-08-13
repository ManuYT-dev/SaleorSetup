### Setup Linux
git clone https://github.com/ManuYT-dev/SaleorSetup.git
cd ./SaleorSetup
cp .env.example .env # change values in the new .env
chmod 770 setup.sh
./setup.sh

### Nice commands:
```bash
# Backup DB
docker compose exec -T db pg_dump -U saleor saleor > Directory_Path\saleor_backup_$(Get-Date -Format "yyyy-MM-dd_HHmmss").sql

# Backup Media
docker run --rm -v saleor-media:/media-data -v backup/path:/backup alpine tar -czf /backup/saleor_media_backup_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").tar.gz -C /media-data .

# Restore DB
Get-Content \path\to\backup.sql | docker compose exec -T db psql -U saleor -d saleor

# Populate DB
docker compose run --rm api python3 manage.py populatedb
```

### Changes before deploy

**storefront**
- [ ] `next.config.js` → set `unoptimized: false` in `images` (or remove the line entirely)
- [ ] `.env` → `NEXT_PUBLIC_SALEOR_API_URL=https://api.yourdomain.com/graphql/` (real domain, https)
- [ ] `.env` → `NEXT_PUBLIC_STOREFRONT_URL=https://yourdomain.com`
- [ ] Set `REVALIDATE_SECRET` and `SALEOR_WEBHOOK_SECRET` to real random ≥32-char strings (used for cache invalidation + webhook HMAC verification)
- [ ] Disable dummy payment: remove/unset `ALLOW_DUMMY_PAYMENT` and `NEXT_PUBLIC_ALLOW_DUMMY_PAYMENT` (or explicitly `false`)
- [ ] Configure real payment provider (e.g. Stripe) via `NEXT_PUBLIC_ENABLE_STRIPE_PAYMENTS=true` + keys set in Saleor Dashboard, not env

**saleor (api / worker — `backend.env` + `common.env`)**
- [ ] `SECRET_KEY` → replace `changeme` with a real random secret (never reuse dev value)
- [ ] `ALLOWED_HOSTS` → set to your real domain(s) only, remove `localhost,127.0.0.1,host.docker.internal`
- [ ] `PUBLIC_URL` → set to `https://api.yourdomain.com` (fixes the image/thumbnail URL issue permanently)
- [ ] `DASHBOARD_URL` → set to real dashboard domain, e.g. `https://admin.yourdomain.com/`
- [ ] `DEBUG` → ensure `False` / unset (Django debug mode must never be on in production)
- [ ] `EMAIL_URL` → replace Mailpit (`smtp://localhost:1025`) with a real SMTP provider (SendGrid, SES, Postmark, etc.)
- [ ] `DEFAULT_FROM_EMAIL` → real sender address
- [ ] `CACHE_URL` / `CELERY_BROKER_URL` → point at the real `cache` service, not `localhost` (in Docker Compose this should already use the service name — double check it's not hardcoded to `localhost`)
- [ ] `HTTP_IP_FILTER_ALLOW_LOOPBACK_IPS` → remove or set `False` (dev-only convenience flag)
- [ ] Change Postgres credentials — `POSTGRES_USER`/`POSTGRES_PASSWORD` (`saleor`/`saleor` is a default, not safe for prod)
- [ ] Disable/limit GraphQL introspection in production (check Saleor 3.23 docs for the current setting name)
- [ ] Confirm Saleor's built-in query cost/depth limiting is enabled (default on, but verify config wasn't loosened)
- [ ] Put the API behind HTTPS (reverse proxy / load balancer with TLS — Saleor itself doesn't terminate TLS)
- [ ] Set up a reverse proxy (nginx, Caddy, Traefik, or your cloud LB) in front of everything — don't expose container ports directly to the internet
- [ ] Add rate limiting at the proxy level for the GraphQL endpoint
- [ ] Set real `django-storages`/S3 (or equivalent) config for media storage instead of the local `saleor-media` volume, so media survives redeploys and scales
- [ ] Turn on regular automated DB + media backups (see commands above) — schedule, don't rely on manual runs
- [ ] Review Celery beat schedule/tasks for anything dev-only

**dashboard**
- [ ] Point dashboard at the real API URL (usually configured via its own env/build arg pointing to `https://api.yourdomain.com/graphql/`)
- [ ] Restrict access — e.g. VPN, IP allowlist, or at least strong auth — since this is your admin panel

---

### Ports — what runs where, and what should be exposed publicly

| Port | Service | What it is | Expose publicly? |
|------|---------|------------|-------------------|
| 8000 | `api` | Saleor GraphQL API | ✅ Yes — behind HTTPS reverse proxy + rate limiting |
| 3000 | `storefront` | Customer-facing Next.js site | ✅ Yes — behind HTTPS reverse proxy |
| 9000 → 80 | `dashboard` | Admin panel (Saleor Dashboard) | ⚠️ Only with strong access control (VPN/IP allowlist/auth) — not open to the world |
| 5432 | `db` | PostgreSQL | ❌ Never — internal network only, remove the `ports:` mapping entirely |
| 6379 | `cache` | Redis/Valkey | ❌ Never — internal network only, remove the `ports:` mapping entirely |
| 16686 | `jaeger` (UI) | Tracing dashboard | ❌ No — internal/VPN only, or disable in prod if not actively used |
| 4317 / 4318 | `jaeger` (OTLP) | Trace ingestion | ❌ No — internal network only |
| 1025 | `mailpit` (SMTP) | Fake local mail catcher | ❌ Remove entirely in prod — replace with real SMTP provider |
| 8025 | `mailpit` (Web UI) | View caught emails | ❌ Remove entirely in prod — dev tool only |

**Rule of thumb for the production compose file:** only `api`, `storefront`, and (restricted) `dashboard` should have a `ports:` entry or be behind your reverse proxy at all. Everything else (`db`, `cache`, `jaeger`, `mailpit`) should drop its `ports:` mapping so it's reachable only inside `saleor-backend-tier` — other containers can still talk to it by service name, but nothing outside Docker can reach it.