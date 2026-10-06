# Dukandar Admin Panel (দোকানদার অ্যাডমিন)

Single-page admin UI for the Dukandar backend. **Vanilla HTML/CSS/JS — no build step, no dependencies.**

- `index.html` – shell (loads Inter + Noto Sans Bengali from Google Fonts)
- `styles.css` – design system: green palette via CSS variables, 240px light sidebar, 56px topbar, 1200px content width,
  flat white cards (1px border, radius 10, no shadows), 44px table rows, 22px status chips, 36px buttons/inputs,
  480px modals, 520px drawers, bottom-right toasts
- `app.js` – hash router, `api()` fetch wrapper (same-origin cookie session + `X-CSRF-Token`, 401 → login, 30 s in-memory GET cache
  invalidated on every mutation), sortable `table()`/`listPage()` helpers, focus-trapped modals, Bangla form validation, all pages

Assets are referenced as `/admin/app.js?v=__V__`; the backend replaces `__V__` with `STATIC_VERSION` and serves versioned assets with
`Cache-Control: immutable`. Bump `STATIC_VERSION` in `backend/.env` after changing the panel. The version string is shown on the
login footer and under সেটিংস › About.

## How it is served

The backend serves this folder at `https://<host>/admin` (FastAPI `StaticFiles`). The location is configured with
`ADMIN_PANEL_DIR` in `backend/.env` (default `../admin-panel`; in Docker the folder is copied to `/srv/admin-panel`).
The panel talks only to `/admin/api/*` on the same origin, so CSP stays `default-src 'self'` and no CORS is needed.

To edit: change the files and reload the browser — no compile step. Keep all JS in `app.js` (CSP forbids inline scripts).

## Copy conventions

Bangla is the primary language. English appears only for technical terms (Email, Device ID, TRX ID, MRR, API, IP).
Button labels are verbs (যোগ করুন, সংরক্ষণ, বাতিল, রিসেট, বন্ধ করুন); no emoji, exclamation marks or marketing copy.
Error and empty states are one short factual line.

## Pages

লগইন (Email, password with show/hide, one button, environment/version footer) ·
ড্যাশবোর্ড (4 primary KPIs: মোট দোকান / সক্রিয় / বকেয়া / এই মাসের আয়; secondary row: MRR / ক্লেইম / আনলক / স্থগিত;
6-month revenue bars with axis from `GET /admin/api/dashboard/revenue`; "মনোযোগ দরকার" count list; recent activity table from `recent_activity`) ·
টপবার: global shop search (`/` shortcut), refresh, pending indicator, avatar menu with প্রোফাইল / লগআউট; sidebar bottom also has লগআউট ·
দোকানসমূহ (search, status filter, add shop with one-time temporary password, detail drawer: তথ্য / পেমেন্ট / ডিভাইস / অডিট,
record payment, reset password, disable/enable, device reset, send notification) ·
পেমেন্ট ক্লেইম (approve/reject) · আনলক রিকোয়েস্ট (request code, reason, device, 8-digit unlock code with copy, close) ·
প্ল্যান (cards/table view) · নোটিফিকেশন (broadcast) · অ্যাডমিন (superadmin only) ·
সেটিংস (bKash/Nagad, instructions, trial/grace/reminder days, About; superadmin edits) · অডিট লগ
