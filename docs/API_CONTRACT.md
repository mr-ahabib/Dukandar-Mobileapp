# Dukandar – Shared Contract (Backend ⇄ Mobile App)

Product: "দোকানদার" – offline-first ledger/billing app for Bangladeshi shopkeepers.
Business model: we (the company) sell monthly subscriptions. The server stores ONLY
shopkeeper account + subscription + device/licensing info. **All business data
(customers, transactions, memos, expenses, photos) lives only on the phone**,
with local + Google Drive backups controlled by the shopkeeper.

Base URL (app): `https://<host>/api/v1`  (configurable in app: `AppConfig.baseUrl`)
Admin panel: `https://<host>/admin` (static SPA served by FastAPI)
All JSON. Dates are ISO‑8601 UTC strings. Money is integer BDT.

## Statuses

| status      | meaning                                                                  | app behaviour                                 |
|-------------|--------------------------------------------------------------------------|-----------------------------------------------|
| `trial`     | free trial active (`trial_ends_at` in future)                            | works; banner shows days left                 |
| `active`    | paid; `paid_until` ≥ today                                               | works                                         |
| `due`       | `paid_until` passed, within grace (10 days) → `grace_ends_at`            | works; persistent "ফি জমা দিন" banner + daily local notification |
| `suspended` | grace over, unpaid                                                       | app blocked by paywall screen (data untouched) |
| `disabled`  | admin disabled the account                                               | blocked                                        |

Device lock (tamper): `device.locked = true` → app shows TamperLockScreen,
nothing else usable until unlock code entered.

## App endpoints (mobile)

### POST `/app/auth/login`
```json
{ "phone": "01712345678", "password": "secret", "device": {
    "device_id": "<stable android id>", "model": "Redmi Note 12", "os": "Android 14",
    "app_version": "1.0.0", "signature_sha256": "<hex>" } }
```
→ 200 `{ "access_token": "...", "refresh_token": "...", "token_type": "bearer",
         "shop": ShopPublic, "license": License }`
Errors: 401 invalid; 423 device locked (`{detail:{code:"DEVICE_LOCKED", unlock_request_id, hint}}`);
409 another device already bound (`code:"DEVICE_CONFLICT"`) – admin must reset device from panel.

### POST `/app/auth/refresh`  `{ "refresh_token": "..." }` → same shape as login (rotates refresh).
### POST `/app/auth/logout`    (bearer) → 204
### GET  `/app/me` (bearer) → `{ "shop": ShopPublic, "license": License, "notifications": [Notification] }`
### GET  `/app/license` (bearer) → License   (app calls on every launch & every 6h; caches for 7 days offline)
### POST `/app/tamper-report` (no bearer required: uses shop phone + device_id)
```json
{ "phone": "017...", "device_id": "...", "reason": "ROOT_DETECTED|SIGNATURE_MISMATCH|DEBUGGER|HOOKING_FRAMEWORK|EMULATOR|TAMPERED_BINARY",
  "details": "free text", "app_version": "1.0.0" }
```
→ 200 `{ "locked": true, "unlock_request_id": "UL-7F3K2Q", "message": "..." }`
Server: sets device.locked, creates `unlock_requests` row with an 8‑digit `unlock_code`
visible ONLY in admin panel. Idempotent (returns existing open request).
### POST `/app/unlock` `{ "phone", "device_id", "unlock_request_id", "unlock_code" }`
→ 200 `{ "unlocked": true }` ; 400 wrong code (max 5 attempts then request is burned, admin must issue a new one).
### POST `/app/notifications/{id}/read` (bearer) → 204
### POST `/app/payment-claim` (bearer) `{ "method":"bkash|nagad|rocket|cash", "trx_id":"...", "amount": 300, "note":"" }`
→ 201 PaymentClaim (pending; admin verifies in panel → subscription extended)

### Schemas
```
ShopPublic { id, shop_name, owner_name, phone, address, plan: PlanPublic, created_at }
PlanPublic { id, name, price_bdt, period_days }
License    { status, plan_name, price_bdt, trial_ends_at?, paid_until?, grace_ends_at?,
             next_due_at?, days_left, grace_days: 10, message_bn, server_time,
             device_locked: false, features: ["ledger","billing","cash_drawer","reports","backup","drive"],
             payment_info: { bkash: "017...", nagad: "...", instructions_bn: "..." } }
Notification { id, title_bn, body_bn, kind: "due|info|warning", created_at, read }
```

## Admin endpoints (panel) – prefix `/admin/api`
Auth: `POST /admin/api/auth/login {email,password}` → sets httpOnly Secure SameSite=Strict
cookie `admin_session` (JWT, 8h) + returns `{csrf_token}`; every mutating request must send
header `X-CSRF-Token`. `POST /admin/api/auth/logout`. `GET /admin/api/auth/me`.
Roles: `superadmin` (everything, manage admins), `staff` (shops/payments/unlocks, no admin mgmt, no settings).
Security: argon2id hashes, login rate limit (5/min/IP, lockout 15 min after 8 fails),
audit log on every mutation, security headers (CSP, HSTS, X-Frame-Options DENY, nosniff),
CORS closed by default. Admin passwords ≥ 10 chars.

Resources (all paginated `?page=&page_size=&q=`):
- `GET/POST /shops`, `GET/PATCH /shops/{id}`, `POST /shops/{id}/reset-password` (returns temp password once),
  `POST /shops/{id}/disable`, `/enable`, `POST /shops/{id}/reset-device` (unbind device),
  `GET /shops/{id}/devices`, `GET /shops/{id}/payments`, `GET /shops/{id}/audit`
- `GET/POST /plans`, `PATCH /plans/{id}`
- `POST /shops/{id}/payments` `{amount_bdt, method, trx_id, months, note}` → extends `paid_until` by months*period
- `GET /payment-claims?status=pending`, `POST /payment-claims/{id}/approve`, `/reject`
- `GET /unlock-requests?status=open`  (shows unlock_code), `POST /unlock-requests/{id}/close`
- `POST /notifications/broadcast {title_bn, body_bn, kind, shop_ids?}`
- `GET /dashboard` → counts: total shops, active, due, suspended, locked devices, MRR, revenue this month, pending claims, open unlocks, recent activity
- `GET /audit-logs`
- `GET/POST /admins`, `PATCH /admins/{id}` (superadmin only)
- `GET/PATCH /settings` → payment_info (bkash/nagad numbers, instructions), grace_days, trial_days, reminder_days_before

Scheduler (APScheduler in-process, daily 09:00 Asia/Dhaka): for each shop create Notification
`due` on due day & each day during grace; `info` 3 days before due; audit transitions.

## Mobile app architecture notes
- Business data: sqflite (`dukandar.db`) + photos in `<appDocs>/photos/`. Never sent to server.
- Backup: zip(db + photos + settings.json) → (a) local: `<externalFiles>/DukandarBackup/` + Share sheet,
  (b) Google Drive `appDataFolder` via google_sign_in + googleapis.drive.v3. Auto-backup daily when on Wi‑Fi (user toggle).
- Secure storage (flutter_secure_storage): tokens, cached License JSON + fetched_at, device lock state.
- Tamper detection on launch (Kotlin MethodChannel `com.dukandar/security`): root (su binaries, test-keys, Magisk),
  signing cert SHA‑256 vs expected (debug builds skip), debugger attached, Frida/Xposed artefacts.
  On detection → local lock persisted immediately (works offline) → report to server when online → show code entry.
- Local notifications (flutter_local_notifications): schedule reminders from License.next_due_at (3 days before, due day, every day in grace 10:00).

## Deviations / additions (backend implementation, 2026-10-04)

Everything above is implemented as written. The backend adds the following details that the contract left open or
that were needed for correctness — the app may rely on them:

- **Pagination shape** for all admin list endpoints: `{ items: [...], page, page_size, total }`. `?q=` searches name/phone/trx/request code.
  `GET /shops` also accepts `?status_filter=trial|active|due|suspended|disabled`; claims and unlock requests accept `?status=`.
- **Admin auth**: `POST /admin/api/auth/login` returns `{ csrf_token, admin }`; `GET /admin/api/auth/me` returns `{ admin, csrf_token }` (so the SPA
  can recover the CSRF token after reload). Cookie `admin_session` has `Path=/admin`. Locked-out admin login → `423 {code:"ACCOUNT_LOCKED"}`.
- **Admin RBAC**: `PATCH /settings` is superadmin-only (staff can `GET`). `/admins` is superadmin-only as specified.
- **Error payloads** are always `{ detail: { code, message, ... } }`; validation errors are `422 { detail: { code:"VALIDATION_ERROR", errors:[...] } }`.
  Unknown JSON fields are rejected (422) on every endpoint — the server never accepts business data.
- **Login**: disabled account → `403 {code:"ACCOUNT_DISABLED"}` (not 401). `409 DEVICE_CONFLICT` includes `bound_model`.
  Refresh-token reuse → `401 {code:"REFRESH_REUSED"}` and the whole token family is revoked.
- **Tamper report** for an unknown phone returns a syntactically valid but unusable `unlock_request_id` (no account enumeration).
  `POST /app/unlock` wrong code → `400 {code:"WRONG_CODE", attempts_left}`; after 5 failures → `400 {code:"REQUEST_BURNED"}`.
  Unlock request statuses: `open | used | burned | closed`.
- **Payment claim**: duplicate `trx_id` for the same shop → `409 DUPLICATE_TRX`. Admin approve accepts optional body `{ months (default 1), note }`;
  reject accepts `{ note }` and sends a `warning` notification to the shop.
- **License.payment_info** additionally contains `support_phone`. **Dashboard** additionally returns `trial` and `disabled` counts.
- **Notifications**: broadcasts are stored once (`shop_id = null`) and per-shop read state is tracked in `notification_reads`;
  `GET /admin/api/notifications` lists sent notifications. Daily-job notifications are de-duplicated per shop per day.
- **Request body limit** 64 KB; `/app/tamper-report` and `/app/payment-claim` are rate limited 10/min in addition to the specified 5/min limits.
- **Device reset** (`POST /shops/{id}/reset-device`) also revokes all refresh tokens and closes open unlock requests for the shop.
- **Data model extras**: `shops.last_status` (for transition auditing), `notifications.dedupe_key`, `refresh_tokens.family_id/used_at`,
  `unlock_requests.unlock_code` plaintext alongside `unlock_code_hash` (product requirement: admins read the code in the panel).

## Self-registration with KYC (added 2026-10-04)

Shopkeepers create their own account from the app. No phone call needed. The
account is unusable until an admin verifies the NID + live-face evidence.

### Shop verification states (new field `shop.verification`)
| verification            | app behaviour                                                        |
|-------------------------|----------------------------------------------------------------------|
| `pending`               | PendingVerificationScreen (info + "আবার দেখুন"); no business features  |
| `approved`              | normal; subscription status rules apply (trial starts at approval)   |
| `rejected`              | RejectedScreen with `rejection_reason_bn` + "আবার আবেদন করুন" (re-register allowed, same phone) |

License `status` additionally may be `pending_verification` or `rejected` (maps 1:1 to the above) so the app's existing gate can branch on it.

### POST `/app/auth/register`  (multipart/form-data, rate limited 3/hour/IP)
fields: `shop_name`, `owner_name`, `phone` (BD), `password` (≥6), `address`, `nid_number` (10/13/17 digits),
`device` (JSON string, same shape as login), `liveness` (JSON string: `{passed: true, challenges: ["blink","turn_left","smile"], score: 0.0-1.0, captured_at}`)
files: `nid_front` (jpeg ≤3MB), `nid_back` (jpeg ≤3MB), `selfie` (jpeg ≤3MB), `liveness_frames[]` (0–3 jpeg ≤1MB each, optional)
→ 201 same shape as login (`access_token`, `refresh_token`, `shop`, `license{status:"pending_verification"}`)
Errors: 409 `PHONE_TAKEN` (if an approved/pending shop exists), 422 validation, 413 too large.
Re-registration after `rejected`: same endpoint; replaces the KYC bundle and resets to `pending`.

Server stores KYC files under `data/kyc/<shop_id>/` (never public; served only to admins via
`GET /admin/api/kyc/{shop_id}/file/{kind}` with kind ∈ nid_front|nid_back|selfie|frame_0..2).

### GET `/app/me` / `/app/license` — License gains:
`verification: "pending|approved|rejected"`, `rejection_reason_bn?`, `verified_at?`,
`payment_popup: { show: bool, every_minutes: 30, title_bn, body_bn }`
(`show` is true for `due`; the app also shows it on every launch while due; suspended → paywall).

### Admin — KYC
- `GET /admin/api/kyc?status=pending|approved|rejected` → paginated `{shop, nid_number, submitted_at, liveness, files:[kinds]}`
- `GET /admin/api/kyc/{shop_id}` → detail incl. file URLs (admin-cookie protected)
- `POST /admin/api/kyc/{shop_id}/approve` → sets `approved`, `verified_at`, starts trial (`trial_ends_at = now + settings.trial_days`), creates notification "অ্যাকাউন্ট যাচাই সম্পন্ন — ট্রায়াল শুরু", audit.
- `POST /admin/api/kyc/{shop_id}/reject {reason_bn}` → sets `rejected`, notification with reason, audit.
- Dashboard gains `pending_kyc` count; sidebar badge.
- Settings gains `trial_days` (exists), `popup_every_minutes` (default 30).

### App — payment popup rules
- status `due` (grace running): show a modal popup on every app launch and every `popup_every_minutes` while the app is open; popup has "পেমেন্ট করুন" (→ SubscriptionScreen) and "পরে" (dismiss until next interval). Daily local notification continues.
- status `suspended`/`disabled`: PaywallScreen (blocking) as before.
- When a payment is recorded/approved the next license refresh returns `active` and all popups stop; the app also polls `/app/license` every 5 minutes while a popup is pending and after returning to foreground.
