# Dukandar Backend (দোকানদার ব্যাকএন্ড)

FastAPI backend for the **দোকানদার** subscription/licensing service. **SQLite (WAL) is the default database** — zero setup,
tuned for a single API process; PostgreSQL stays optional (`DATABASE_URL=postgresql+asyncpg://...`). It also serves the admin panel SPA
(`../admin-panel/`, configurable via `ADMIN_PANEL_DIR`) at `/admin`.

Repository layout: `backend/` (this), `admin-panel/` (vanilla JS SPA), `app/` (Flutter app), `docker-compose.yml` at the repo root.
The server stores **only** shop accounts, subscriptions, devices, payments and notifications — never any shopkeeper business data
(customers, transactions, memos). Unknown JSON fields are rejected everywhere.

Contract: see `../docs/API_CONTRACT.md`. Mobile API base: `https://<host>/api/v1`, panel: `https://<host>/admin`.

---

## বাংলা — দ্রুত শুরু

### সার্ভারে (VPS) ডিপ্লয় — Docker Compose দিয়ে

1. Ubuntu 22.04/24.04 VPS-এ Docker ইনস্টল করুন: `curl -fsSL https://get.docker.com | sh`
2. কোড কপি করুন: `git clone <repo> && cd dukandar`
3. কনফিগ তৈরি করুন:
   ```bash
   cp backend/.env.example backend/.env
   # তিনটি JWT secret আলাদা আলাদা করে তৈরি করুন:
   python3 -c "import secrets; print(secrets.token_urlsafe(48))"
   nano backend/.env   # JWT_*_SECRET, SUPERADMIN_EMAIL, SUPERADMIN_PASSWORD বদলান; TRUST_PROXY_HEADERS=true
   mkdir -p data && sudo chown 10001:10001 data   # SQLite ফাইল এখানে থাকবে (কন্টেইনারের appuser uid 10001)
   ```
4. চালু করুন (repo root থেকে): `docker compose up -d --build` — ডিফল্টে শুধু `api` কন্টেইনার, ডাটাবেস `./data/dukandar.db` (SQLite)।
   PostgreSQL চাইলে: `.env`-এ `DATABASE_URL=postgresql+asyncpg://dukandar:<pass>@db:5432/dukandar` দিয়ে `docker compose --profile postgres up -d --build`।
   প্রথমবার চালুর সময় সার্ভার নিজেই মাইগ্রেশন চালায়, `.env` এর ইমেইল/পাসওয়ার্ড দিয়ে **সুপার অ্যাডমিন**, ডিফল্ট প্ল্যান
   "স্ট্যান্ডার্ড" (৩০০ টাকা/৩০ দিন) ও সেটিংস তৈরি করে। আলাদা করে কিছু চালাতে হয় না।
5. (ঐচ্ছিক) আরও অ্যাডমিন/পাসওয়ার্ড বদল: `docker compose exec api python scripts/create_superadmin.py admin@example.com`
6. (ঐচ্ছিক) ডেমো ডেটা: `docker compose exec api python scripts/seed_demo.py`
7. ব্রাউজারে `https://<domain>/admin` খুলুন → `.env` এর ইমেইল/পাসওয়ার্ড দিয়ে লগইন → **সেটিংস** পেজে বিকাশ/নগদ নম্বর ও নির্দেশনা দিন → **দোকান** যুক্ত করুন (অস্থায়ী পাসওয়ার্ড একবারই দেখাবে)।

### nginx + HTTPS (অবশ্যই)

API কন্টেইনার শুধু `127.0.0.1:8000`-এ শোনে। সামনে nginx + Let's Encrypt বসান:

```nginx
server {
    server_name api.example.com;
    listen 443 ssl http2;
    ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;
    client_max_body_size 64k;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
server { listen 80; server_name api.example.com; return 301 https://$host$request_uri; }
```
`sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d api.example.com`

> অ্যাডমিন কুকি `Secure` ফ্ল্যাগসহ — HTTPS ছাড়া অ্যাডমিন প্যানেলে লগইন হবে না (লোকাল টেস্টে `ADMIN_COOKIE_SECURE=false`)।

### অ্যাপকে সার্ভারের সাথে যুক্ত করা

Flutter অ্যাপে `AppConfig.baseUrl = "https://api.example.com/api/v1"` সেট করুন (`lib/` এ)। অ্যাপ প্রতি লঞ্চে ও প্রতি ৬ ঘণ্টায় `GET /app/license` কল করে, ৭ দিন অফলাইন ক্যাশ রাখে।

### দৈনিক কাজ (রিমাইন্ডার/বকেয়া নোটিফিকেশন)

সার্ভার নিজেই প্রতিদিন সকাল ৯টায় (Asia/Dhaka) চালায়। হাতে চালাতে: `docker compose exec api python -m app.jobs.daily`.
একাধিক API ইনস্ট্যান্স চালালে `SCHEDULER_ENABLED=false` দিয়ে cron থেকে একবারই চালান।

### ব্যাকআপ

**SQLite (ডিফল্ট):** ডাটাবেস WAL মোডে চলে, তাই চালু অবস্থায় `cp` দিয়ে কপি করবেন না — `-wal` ফাইলের ডেটা বাদ পড়তে পারে। সবসময় `.backup` ব্যবহার করুন:

```bash
sqlite3 data/dukandar.db ".backup 'backup-$(date +%F).db'"            # হোস্টে sqlite3 থাকলে
docker compose exec api python -c "import sqlite3; s=sqlite3.connect('data/dukandar.db'); d=sqlite3.connect('data/backup.db'); s.backup(d); d.close()"
```
ফেরত আনতে: সার্ভার বন্ধ করে `backup.db` কে `data/dukandar.db` নামে রাখুন (পুরনো `-wal`/`-shm` ফাইল মুছে দিন)।

**PostgreSQL (ঐচ্ছিক):** `docker compose exec db pg_dump -U dukandar dukandar | gzip > backup-$(date +%F).sql.gz`

---

## English — local development

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# edit .env: ADMIN_COOKIE_SECURE=false, ENV=development, SUPERADMIN_EMAIL / SUPERADMIN_PASSWORD
# DATABASE_URL defaults to sqlite+aiosqlite:///./data/dukandar.db (the data/ folder is created automatically)
uvicorn app.main:app --reload   # on startup: alembic upgrade head + superadmin + default plan + settings (AUTO_MIGRATE=true)
```
PostgreSQL instead: `createdb dukandar` and set `DATABASE_URL=postgresql+asyncpg://dukandar:dukandar@localhost:5432/dukandar`.

### Database & performance

- **SQLite** (default): on every connection the engine sets `journal_mode=WAL`, `synchronous=NORMAL`, `busy_timeout=5000`,
  `foreign_keys=ON`, `cache_size=-20000` (20 MB), `temp_store=MEMORY`, `mmap_size=256MB` (`app/db/session.py`). A small
  `AsyncAdaptedQueuePool` (8 warm aiosqlite connections) lets reads run concurrently under WAL while writers serialise on
  `busy_timeout`. Run **one** API process per database file (use `SCHEDULER_ENABLED` as documented; for horizontal scaling move to PostgreSQL).
- Hot-path indexes: `devices(shop_id,is_active)`, `payments(shop_id,created_at)`, `payments(created_at)`,
  `notifications(shop_id,created_at)`, `payment_claims(status,created_at)`, `unlock_requests(status,created_at)` plus the originals
  (`shops.phone` unique, `audit_logs.created_at`, `refresh_tokens.token_hash` unique).
- Dashboard counts come from one grouped query (status computed in SQL via `status_sql()`), the shops list is a single query with
  the plan and the active device joined, the settings row is cached in-process for 60 s, responses are serialised by FastAPI's native Pydantic bytes path (faster than ORJSON in FastAPI ≥0.140) and gzipped (>1 KB),
  and admin panel assets are served with `Cache-Control: immutable` under a `?v=STATIC_VERSION` query string.
- Benchmark a running server: `python scripts/bench.py --n 200` (prints p50/p95 per endpoint).
Optional: `alembic upgrade head` manually (set `AUTO_MIGRATE=false` to disable auto-migration), `python scripts/create_superadmin.py`
(create/promote/reset an admin interactively), `python scripts/seed_demo.py` (2 demo shops, password 123456).

- Admin panel: http://127.0.0.1:8000/admin
- OpenAPI docs (non-production only): http://127.0.0.1:8000/api/docs
- Health: `GET /healthz`

### Tests

```bash
pytest -q
```
Tests run on in-memory SQLite by default; set `DATABASE_URL_TEST=postgresql+asyncpg://dukandar:dukandar@localhost/dukandar_test`
to run the same suite against PostgreSQL (JSONB, timestamptz, partial unique index enforcing one active device per shop).

Lint: `ruff check app scripts tests`

### Project layout

```
app/main.py                 app factory, security headers, rate limiting, /admin static mount, /healthz
app/core/                   config (pydantic-settings), security (argon2id, JWT, CSRF, policies), deps (auth/RBAC), audit, rate_limit, scheduler
app/db/                     SQLAlchemy 2 async models + session (SQLite pragmas / pool config)
app/schemas/                Pydantic v2 schemas (extra="forbid")
app/api/app_routes/         mobile API  (/api/v1/app/...)
app/api/admin_routes/       admin API   (/admin/api/...)
app/services/               subscription status, unlock codes, notifications, settings
app/jobs/daily.py           daily reminder/due/transition job (python -m app.jobs.daily)
app/core/bootstrap.py       startup: migrations + superadmin + default plan/settings
../admin-panel/             admin SPA (vanilla JS, no build step) served at /admin (ADMIN_PANEL_DIR)
alembic/                    migrations (alembic upgrade head)
scripts/                    create_superadmin.py, seed_demo.py, bench.py (latency benchmark)
tests/                      pytest suite
```

### Security summary

argon2id password hashes; HS256 JWTs with separate secrets (app access 15 min, app refresh 30 days with rotation + reuse detection
that revokes the whole family, admin session 8 h in an httpOnly/Secure/SameSite=Strict cookie scoped to `/admin`);
CSRF double-submit (`X-CSRF-Token`) on every admin mutation; slowapi limits (5/min) on app login, unlock and admin login;
admin lockout 15 min after 8 failures; CSP/HSTS/X-Frame-Options/nosniff/Referrer-Policy headers; CORS off unless `CORS_ORIGINS` set;
identical responses for unknown phone vs wrong password (with constant-time argon2 verify); BD phone validation; 64 KB request body cap;
audit log for every admin mutation, tamper/unlock event, login and subscription transition.

### Subscription statuses

`trial` → (trial end) → `due` (grace, default 10 days) → `suspended`; a payment makes it `active` until `paid_until`, then `due` → `suspended`.
`disabled` overrides everything. Status is computed on every request from `paid_until`/`trial_ends_at` + `settings.grace_days`.
