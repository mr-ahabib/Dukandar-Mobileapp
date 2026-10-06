/* Dukandar admin panel — vanilla JS SPA (no build step). API under /admin/api */
(() => {
  "use strict";
  const API = "/admin/api";
  const VERSION = (document.currentScript?.src.match(/[?&]v=([^&]+)/) || [])[1] || "dev";
  const state = { admin: null, csrf: sessionStorage.getItem("csrf") || "", route: "dashboard", params: {}, dash: null, revenue: null };
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const app = $("#app"), layer = $("#layer"), toasts = $("#toasts");

  // ---------- utils ----------
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const bn = (s) => String(s).replace(/\d/g, (d) => "০১২৩৪৫৬৭৮৯"[d]);
  const money = (n) => "৳ " + bn(Number(n || 0).toLocaleString("en-US"));
  const fmtDate = (iso, withTime = false) => {
    if (!iso) return "—";
    const o = { day: "2-digit", month: "short", year: "numeric", timeZone: "Asia/Dhaka" };
    if (withTime) Object.assign(o, { hour: "2-digit", minute: "2-digit" });
    return new Date(iso).toLocaleString("en-GB", o);
  };
  const ago = (iso) => {
    const s = Math.max(0, (Date.now() - new Date(iso)) / 1000);
    if (s < 60) return "এইমাত্র"; if (s < 3600) return bn(Math.floor(s / 60)) + " মিনিট আগে";
    if (s < 86400) return bn(Math.floor(s / 3600)) + " ঘণ্টা আগে"; return bn(Math.floor(s / 86400)) + " দিন আগে";
  };
  const MONTH_BN = ["জানু", "ফেব্রু", "মার্চ", "এপ্রিল", "মে", "জুন", "জুলাই", "আগস্ট", "সেপ্টে", "অক্টো", "নভে", "ডিসে"];
  const debounce = (fn, ms = 300) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
  const STATUS_BN = { trial: "ট্রায়াল", active: "সক্রিয়", due: "বকেয়া", suspended: "স্থগিত", disabled: "বন্ধ", pending: "অপেক্ষমাণ", pending_verification: "যাচাই বাকি", approved: "অনুমোদিত", rejected: "বাতিল", open: "খোলা", used: "ব্যবহৃত", burned: "বার্নড", closed: "বন্ধ", locked: "লকড", superadmin: "সুপার অ্যাডমিন", staff: "স্টাফ", info: "তথ্য", warning: "সতর্কতা" };
  const chip = (st) => `<span class="chip ${esc(st)}">${esc(STATUS_BN[st] || st)}</span>`;
  const VERIF_BN = { pending: "যাচাই বাকি", approved: "যাচাইকৃত", rejected: "বাতিল" };
  const vchip = (v) => `<span class="chip ${v === "pending" ? "pending_verification" : esc(v)}">${esc(VERIF_BN[v] || v)}</span>`;
  const CHALLENGE_BN = { blink: "চোখের পলক", turn_left: "বামে ঘোরা", turn_right: "ডানে ঘোরা", smile: "হাসি", nod: "মাথা নাড়ানো", open_mouth: "মুখ খোলা" };
  const KIND_BN = { nid_front: "NID সামনে", nid_back: "NID পেছনে", selfie: "সেলফি", frame_0: "ফ্রেম ১", frame_1: "ফ্রেম ২", frame_2: "ফ্রেম ৩" };
  const colorOf = (str) => "c" + ([...String(str || "")].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7) % 6);
  const REASON_BN = { ROOT_DETECTED: "রুট ডিটেক্টেড", SIGNATURE_MISMATCH: "সিগনেচার মিলছে না", DEBUGGER: "ডিবাগার", HOOKING_FRAMEWORK: "হুকিং ফ্রেমওয়ার্ক", EMULATOR: "ইমুলেটর", TAMPERED_BINARY: "পরিবর্তিত অ্যাপ" };
  const METHOD_BN = { bkash: "বিকাশ", nagad: "নগদ", rocket: "রকেট", cash: "নগদ টাকা", bank: "ব্যাংক", other: "অন্যান্য" };
  const ACTION_BN = {
    "shop.created": "দোকান যুক্ত", "shop.updated": "দোকান আপডেট", "shop.disabled": "দোকান বন্ধ", "shop.enabled": "দোকান চালু", "shop.password_reset": "পাসওয়ার্ড রিসেট",
    "shop.device_reset": "ডিভাইস রিসেট", "payment.recorded": "পেমেন্ট রেকর্ড", "payment_claim.created": "পেমেন্ট ক্লেইম", "payment_claim.approved": "ক্লেইম অনুমোদন",
    "payment_claim.rejected": "ক্লেইম বাতিল", "tamper.locked": "ডিভাইস লক (ট্যাম্পার)", "unlock.success": "আনলক সফল", "unlock.failed": "ভুল আনলক কোড", "unlock.burned": "আনলক রিকোয়েস্ট বার্নড",
    "unlock_request.closed": "আনলক রিকোয়েস্ট বন্ধ", "app.login": "অ্যাপ লগইন", "app.login_failed": "অ্যাপ লগইন ব্যর্থ", "app.logout": "অ্যাপ লগআউট", "device.bound": "ডিভাইস যুক্ত",
    "device.conflict": "ডিভাইস কনফ্লিক্ট", "refresh.reuse_detected": "টোকেন রিইউজ শনাক্ত", "admin.login": "অ্যাডমিন লগইন", "admin.login_failed": "অ্যাডমিন লগইন ব্যর্থ", "admin.locked_out": "অ্যাডমিন লকআউট",
    "admin.logout": "অ্যাডমিন লগআউট", "admin.created": "অ্যাডমিন যুক্ত", "admin.updated": "অ্যাডমিন আপডেট", "plan.created": "প্ল্যান যুক্ত", "plan.updated": "প্ল্যান আপডেট",
    "settings.updated": "সেটিংস আপডেট", "kyc.approved": "KYC অনুমোদন", "kyc.rejected": "KYC বাতিল", "shop.registered": "অ্যাপ থেকে রেজিস্ট্রেশন", "shop.reregistered": "পুনরায় আবেদন", "notification.broadcast": "নোটিফিকেশন পাঠানো", "subscription.transition": "সাবস্ক্রিপশন স্ট্যাটাস পরিবর্তন", "job.daily_ran": "দৈনিক জব চলেছে",
  };
  const actionTone = (a) => /failed|burned|locked|conflict|reuse|rejected|disabled/.test(a) ? "danger" : /due|warning|transition/.test(a) ? "warn" : /login|logout|job/.test(a) ? "muted" : "";

  const svg = (d, w = 2) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
  const I = {
    dash: svg('<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>'),
    shop: svg('<path d="M3 9l1.5-5h15L21 9"/><path d="M4 9v11h16V9"/><path d="M9 20v-6h6v6"/>'),
    claim: svg('<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/><path d="M6 15h4"/>'),
    lock: svg('<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 018 0v4"/>'),
    plan: svg('<path d="M20 7l-8-4-8 4 8 4 8-4z"/><path d="M4 12l8 4 8-4"/><path d="M4 17l8 4 8-4"/>'),
    bell: svg('<path d="M18 8a6 6 0 10-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 01-3.4 0"/>'),
    users: svg('<path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87"/><path d="M16 3.13a4 4 0 010 7.75"/>'),
    gear: svg('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z"/>'),
    list: svg('<path d="M8 6h13M8 12h13M8 18h13"/><path d="M3 6h.01M3 12h.01M3 18h.01"/>'),
    search: svg('<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>'),
    plus: svg('<path d="M12 5v14M5 12h14"/>', 2.2),
    x: svg('<path d="M18 6L6 18M6 6l12 12"/>'),
    copy: svg('<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/>'),
    out: svg('<path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/>'),
    menu: svg('<path d="M3 6h18M3 12h18M3 18h18"/>'),
    money: svg('<circle cx="12" cy="12" r="9"/><path d="M15 9.5a3 3 0 00-3-1.5c-1.7 0-3 1-3 2s1.3 2 3 2 3 1 3 2-1.3 2-3 2a3 3 0 01-3-1.5"/><path d="M12 6v2M12 16v2"/>'),
    check: svg('<path d="M20 6L9 17l-5-5"/>', 2.2),
    phone: svg('<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>'),
    inbox: svg('<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.5 5.1L2 12v6a2 2 0 002 2h16a2 2 0 002-2v-6l-3.5-6.9A2 2 0 0016.8 4H7.2a2 2 0 00-1.7 1.1z"/>'),
    user: svg('<path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/>'),
    chev: svg('<path d="M6 9l6 6 6-6"/>'),
    eye: svg('<path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/>'),
    eyeOff: svg('<path d="M17.9 17.9A10.9 10.9 0 0112 20C5 20 1 12 1 12a20 20 0 015.1-6.1M9.9 4.2A10 10 0 0112 4c7 0 11 8 11 8a20 20 0 01-2.2 3.2"/><path d="M14.1 14.1a3 3 0 01-4.2-4.2"/><path d="M1 1l22 22"/>'),
    clock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
    alert: svg('<path d="M10.3 3.9L1.8 18a2 2 0 001.7 3h17a2 2 0 001.7-3L13.7 3.9a2 2 0 00-3.4 0z"/><path d="M12 9v4M12 17h.01"/>'),
    refresh: svg('<path d="M21 12a9 9 0 11-2.6-6.4"/><path d="M21 3v6h-6"/>'),
    edit: svg('<path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/>'),
    grid: svg('<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/>'),
    table: svg('<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18"/>'),
    sparkle: svg('<path d="M12 2l2.4 7.2L22 12l-7.6 2.8L12 22l-2.4-7.2L2 12l7.6-2.8z"/>'),
    toggle: svg('<rect x="1" y="5" width="22" height="14" rx="7"/><circle cx="16" cy="12" r="3"/>'),
    tag: svg('<path d="M20.59 13.41l-7.17 7.17a2 2 0 01-2.83 0L2 12V2h10l8.59 8.59a2 2 0 010 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/>'),
    idcard: svg('<rect x="2" y="4" width="20" height="16" rx="2"/><circle cx="8.5" cy="11" r="2.5"/><path d="M4.5 18c.6-2 2.2-3 4-3s3.4 1 4 3"/><path d="M14 9h5M14 13h5"/>'),
    shield: svg('<path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5l8-3z"/><path d="M9 12l2 2 4-4"/>'),
    trend: svg('<path d="M3 17l6-6 4 4 8-8"/><path d="M14 7h7v7"/>'),
    zoom: svg('<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3M11 8v6M8 11h6"/>'),
  };

  function toast(msg, kind = "ok", ms = 3200) {
    const t = document.createElement("div");
    t.className = `toast ${kind}`; t.textContent = msg; toasts.appendChild(t);
    setTimeout(() => { t.style.opacity = "0"; t.style.transition = "opacity .3s"; setTimeout(() => t.remove(), 300); }, ms);
  }
  async function copy(text) { try { await navigator.clipboard.writeText(text); toast("কপি হয়েছে"); } catch { toast("কপি করা যায়নি", "error"); } }

  // ---------- API + 30s GET cache ----------
  const CACHE_TTL = 30_000;
  const cache = new Map(); // url -> { t, data }
  const inflight = new Map();
  const invalidate = (prefix) => { for (const k of cache.keys()) if (!prefix || k.includes(API + prefix)) cache.delete(k); };
  class ApiError extends Error { constructor(status, detail) { super(typeof detail === "string" ? detail : detail?.message || "ত্রুটি"); this.status = status; this.detail = detail; } }
  async function api(path, { method = "GET", body, query, fresh = false } = {}) {
    const url = new URL(API + path, location.origin);
    if (query) Object.entries(query).forEach(([k, v]) => (v !== undefined && v !== null && v !== "") && url.searchParams.set(k, v));
    const key = url.toString();
    if (method === "GET") {
      const hit = cache.get(key);
      if (!fresh && hit && Date.now() - hit.t < CACHE_TTL) return hit.data;
      if (inflight.has(key)) return inflight.get(key);
    }
    const run = (async () => {
      const headers = { Accept: "application/json" };
      if (body !== undefined) headers["Content-Type"] = "application/json";
      if (method !== "GET") headers["X-CSRF-Token"] = state.csrf;
      const res = await fetch(url, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined, credentials: "same-origin" });
      if (res.status === 401 && !path.startsWith("/auth/login")) setLoggedOut();
      let data = null;
      if (res.status !== 204) { try { data = await res.json(); } catch { /* no body */ } }
      if (!res.ok) {
        let detail = data?.detail ?? res.statusText;
        if (detail?.code === "VALIDATION_ERROR") detail = { ...detail, message: detail.errors.map((e) => `${FIELD_BN[e.loc.slice(-1)[0]] || e.loc.slice(-1)[0]}: ${e.msg}`).join("; ") };
        if (res.status === 429) detail = { message: "অনেকবার চেষ্টা হয়েছে, পরে আবার চেষ্টা করুন" };
        if (res.status === 403 && detail?.code === "CSRF_INVALID") detail = { message: "সেশন শেষ, আবার লগইন করুন" };
        throw new ApiError(res.status, detail);
      }
      if (method === "GET") cache.set(key, { t: Date.now(), data }); else invalidate();
      return data;
    })();
    if (method === "GET") { inflight.set(key, run); run.finally(() => inflight.delete(key)); }
    return run;
  }
  const errMsg = (e) => (e instanceof ApiError ? e.message : "নেটওয়ার্ক ত্রুটি");
  const FIELD_BN = { shop_name: "দোকানের নাম", owner_name: "মালিকের নাম", phone: "মোবাইল নম্বর", email: "ইমেইল", password: "পাসওয়ার্ড", amount_bdt: "পরিমাণ", months: "মাস", trx_id: "TrxID", name: "নাম", price_bdt: "মূল্য", period_days: "মেয়াদ", title_bn: "শিরোনাম", body_bn: "বার্তা", bkash_number: "বিকাশ নম্বর", nagad_number: "নগদ নম্বর", support_phone: "সাপোর্ট ফোন" };

  function setLoggedOut() { state.admin = null; state.csrf = ""; state.dash = null; sessionStorage.removeItem("csrf"); cache.clear(); layer.innerHTML = ""; renderLogin(); }
  async function logout() {
    try { await api("/auth/logout", { method: "POST" }); } catch { /* cookie may already be gone */ }
    setLoggedOut();
  }

  // ---------- overlays (focus-trapped, Esc closes, focus restored) ----------
  function openOverlay(html, { side = false, wide = false, onClose } = {}) {
    const opener = document.activeElement;
    const ov = document.createElement("div");
    ov.className = `overlay ${side ? "right" : "center"}`;
    ov.innerHTML = `<div class="${side ? "drawer" : "modal" + (wide ? " wide" : "")}" role="dialog" aria-modal="true">${html}</div>`;
    let closed = false;
    const close = () => { if (closed) return; closed = true; ov.remove(); document.removeEventListener("keydown", onKey); onClose && onClose(); opener?.focus?.(); };
    const focusables = () => $$("a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex='-1'])", ov);
    const onKey = (e) => {
      if (e.key === "Escape") { e.stopPropagation(); return close(); }
      if (e.key !== "Tab") return;
      const f = focusables(); if (!f.length) return;
      const first = f[0], last = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    document.addEventListener("keydown", onKey);
    ov.addEventListener("mousedown", (e) => { if (e.target === ov) close(); });
    $$("[data-close]", ov).forEach((b) => b.addEventListener("click", close));
    layer.appendChild(ov);
    const first = $("input,select,textarea,button.primary,button", ov); first && setTimeout(() => first.focus(), 30);
    return { el: ov, body: ov.firstElementChild, close };
  }
  function confirmDialog({ title, text, okText = "নিশ্চিত", danger = false }) {
    return new Promise((resolve) => {
      let done = false;
      const m = openOverlay(`
        <div class="modal-h"><h3>${esc(title)}</h3><button class="close" data-close aria-label="বন্ধ">${I.x}</button></div>
        <div class="modal-b" style="padding:24px 28px"><p>${esc(text)}</p></div>
        <div class="modal-f"><button class="btn" data-close>বাতিল</button><button class="btn ${danger ? "danger solid" : "primary"}" id="ok">${esc(okText)}</button></div>`,
        { onClose: () => { if (!done) resolve(false); } });
      $("#ok", m.el).addEventListener("click", () => { done = true; resolve(true); m.close(); });
      setTimeout(() => $("#ok", m.el)?.focus(), 40);
    });
  }

  // ---------- forms with Bangla validation ----------
  const PHONE_RE = /^01[3-9]\d{8}$/;
  function validateField(f, v) {
    const empty = v === "" || v === null || v === undefined;
    if (empty) return f.required ? "এই ঘরটি পূরণ করুন" : "";
    if (f.type === "number") { if (Number.isNaN(v)) return "সংখ্যা দিন"; if (f.min !== undefined && v < f.min) return `কমপক্ষে ${bn(f.min)} হতে হবে`; if (f.max !== undefined && v > f.max) return `সর্বোচ্চ ${bn(f.max)} হতে পারে`; }
    if (f.kind === "phone" && !PHONE_RE.test(v)) return "সঠিক মোবাইল নম্বর দিন (01XXXXXXXXX)";
    if (f.type === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)) return "সঠিক ইমেইল ঠিকানা দিন";
    if (f.kind === "adminpw" && !(v.length >= 10 && /[A-Z]/.test(v) && /\d/.test(v))) return "কমপক্ষে ১০ অক্ষর, একটি বড় হাতের অক্ষর ও একটি সংখ্যা";
    if (f.maxlength && String(v).length > f.maxlength) return `সর্বোচ্চ ${bn(f.maxlength)} অক্ষর`;
    return f.validate ? f.validate(v) || "" : "";
  }
  function fieldHtml(f) {
    const id = "f_" + f.name, dis = f.disabled ? "disabled" : "";
    let input;
    if (f.type === "select") input = `<select class="input" id="${id}" name="${f.name}" ${dis}>${f.options.map((o) => `<option value="${esc(o.value)}" ${String(o.value) === String(f.value) ? "selected" : ""}>${esc(o.label)}</option>`).join("")}</select>`;
    else if (f.type === "textarea") input = `<textarea class="input" id="${id}" name="${f.name}" maxlength="${f.maxlength || 2000}" placeholder="${esc(f.placeholder || "")}" ${dis}>${esc(f.value ?? "")}</textarea>`;
    else if (f.type === "password") input = `<div class="pw-wrap"><input class="input" id="${id}" name="${f.name}" type="password" value="${esc(f.value ?? "")}" autocomplete="new-password" ${dis}><button type="button" class="eye" data-eye aria-label="পাসওয়ার্ড দেখান">${I.eye}</button></div>`;
    else input = `<input class="input" id="${id}" name="${f.name}" type="${f.type || "text"}" value="${esc(f.value ?? "")}" placeholder="${esc(f.placeholder || "")}" ${f.min !== undefined ? `min="${f.min}"` : ""} ${f.max !== undefined ? `max="${f.max}"` : ""} ${f.maxlength ? `maxlength="${f.maxlength}"` : ""} inputmode="${f.kind === "phone" ? "numeric" : f.type === "number" ? "decimal" : "text"}" autocomplete="off" ${dis}>`;
    return `<div class="field ${f.span ? "span" : ""}" data-field="${f.name}"><label for="${id}">${esc(f.label)}${f.required ? '<span class="req">*</span>' : ""}</label>${input}${f.hint ? `<div class="hint">${esc(f.hint)}</div>` : ""}<div class="ferr"></div></div>`;
  }
  function wireEyes(root) {
    $$("[data-eye]", root).forEach((b) => b.addEventListener("click", () => { const i = b.previousElementSibling; const show = i.type === "password"; i.type = show ? "text" : "password"; b.innerHTML = show ? I.eyeOff : I.eye; i.focus(); }));
  }
  function readForm(form, fields) {
    const data = {}; let ok = true;
    fields.forEach((f) => {
      const el = form.elements[f.name]; if (!el) return;
      let v = el.value;
      if (f.type === "number") v = v === "" ? null : Number(v);
      else if (typeof v === "string") v = v.trim();
      const err = validateField(f, v);
      const wrap = $(`[data-field="${f.name}"]`, form);
      wrap.classList.toggle("invalid", !!err); el.classList.toggle("invalid", !!err); $(".ferr", wrap).textContent = err;
      if (err) { ok = false; return; }
      if ((v === "" || v === null) && f.optional) return;
      data[f.name] = v;
    });
    return ok ? data : null;
  }
  function formModal({ title, fields, submitText = "সংরক্ষণ", wide = false, onSubmit, intro = "" }) {
    const m = openOverlay(`
      <form class="modal-form" novalidate>
        <div class="modal-h"><h3>${esc(title)}</h3><button type="button" class="close" data-close aria-label="বন্ধ">${I.x}</button></div>
        <div class="modal-b">${intro}<div class="form-grid">${fields.map(fieldHtml).join("")}</div><div id="ferr" class="callout danger hidden" style="margin-top:14px"></div></div>
        <div class="modal-f"><button type="button" class="btn" data-close>বাতিল</button><button class="btn primary" type="submit">${esc(submitText)}</button></div>
      </form>`, { wide });
    const form = $("form", m.el); wireEyes(form);
    form.addEventListener("input", (e) => { const w = e.target.closest(".field"); if (w?.classList.contains("invalid")) { w.classList.remove("invalid"); e.target.classList.remove("invalid"); } });
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const data = readForm(form, fields);
      if (!data) { $(".field.invalid .input", form)?.focus(); return; }
      const btn = $("button[type=submit]", form); btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
      try { await onSubmit(data, m); }
      catch (err) { const el = $("#ferr", form); el.textContent = errMsg(err); el.classList.remove("hidden"); btn.disabled = false; btn.textContent = submitText; }
    });
    return m;
  }

  // ---------- shell ----------
  const NAV = [
    { id: "dashboard", bn: "ড্যাশবোর্ড", icon: I.dash },
    { id: "shops", bn: "দোকানসমূহ", icon: I.shop, c: "#86EFAC" },
    { id: "kyc", bn: "KYC যাচাই", icon: I.idcard, badge: "pending_kyc", tone: "warn", c: "#FCD34D" },
    { id: "claims", bn: "পেমেন্ট ক্লেইম", icon: I.claim, badge: "pending_claims", tone: "info", c: "#93C5FD" },
    { id: "unlocks", bn: "আনলক রিকোয়েস্ট", icon: I.lock, badge: "open_unlock_requests", tone: "danger", c: "#FDA4AF" },
    { id: "plans", bn: "প্ল্যান", icon: I.plan, c: "#C4B5FD" },
    { id: "notifications", bn: "নোটিফিকেশন", icon: I.bell, c: "#5EEAD4" },
    { id: "admins", bn: "অ্যাডমিন", icon: I.users, superadmin: true, c: "#F9A8D4" },
    { id: "settings", bn: "সেটিংস", icon: I.gear, c: "#CBD5E1" },
    { id: "audit", bn: "অডিট লগ", icon: I.list, c: "#FDBA74" },
  ];
  const isSuper = () => state.admin?.role === "superadmin";
  const badgeHtml = (n) => n.badge && state.dash?.[n.badge] ? `<span class="badge ${n.tone || ""}">${bn(state.dash[n.badge])}</span>` : "";

  const ROUTE_META = { dashboard:{t:"ড্যাশবোর্ড",e:"Overview",icon:null}, shops:{t:"দোকানসমূহ",e:"Shops"}, kyc:{t:"KYC যাচাই",e:"KYC review"}, claims:{t:"পেমেন্ট ক্লেইম",e:"Payment claims"}, unlocks:{t:"আনলক রিকোয়েস্ট",e:"Unlock requests"}, plans:{t:"প্ল্যান",e:"Plans"}, notifications:{t:"নোটিফিকেশন",e:"Notifications"}, admins:{t:"অ্যাডমিন",e:"Admins"}, settings:{t:"সেটিংস",e:"Settings"}, audit:{t:"অডিট লগ",e:"Audit log"} };
  function renderShell() {
    const visible = NAV.filter((n) => !n.superadmin || isSuper());
    const sysIds = new Set(["admins", "settings", "audit"]);
    const mainNav = visible.filter((n) => !sysIds.has(n.id)), sysNav = visible.filter((n) => sysIds.has(n.id));
    const navHtml = (list) => list.map((n) => `<a href="#/${n.id}" data-nav="${n.id}" class="${state.route === n.id ? "active" : ""}" style="--nav-c:${n.c || "#fff"}">${n.icon}<span>${n.bn}</span>${badgeHtml(n)}</a>`).join("");
    const a = state.admin;
    const pending = (state.dash?.pending_claims || 0) + (state.dash?.open_unlock_requests || 0) + (state.dash?.pending_kyc || 0);
    app.innerHTML = `
      <div class="shell">
        <aside class="sidebar" id="sidebar">
          <div class="brand"><div class="logo">দ</div><div><div class="name">দোকানদার</div></div></div>
          <nav class="nav">${navHtml(mainNav)}</nav>
          <nav class="nav">${navHtml(sysNav)}</nav>
          <div class="bottom">
            <div class="side-user"><span class="avatar">${esc((a.email[0] || "A").toUpperCase())}</span><div class="grow"><div class="nm ellipsis">${esc(a.email)}</div><div class="rl">${esc(STATUS_BN[a.role] || a.role)}</div></div></div>
            <nav class="nav"><button type="button" class="nav-logout" id="side-logout">${I.out}<span>লগআউট</span></button></nav>
          </div>
        </aside>
        <main class="main">
          <header class="topbar">
            <button class="btn ghost icon menu-btn" id="menu" aria-label="মেনু">${I.menu}</button>
            <div class="title-block"><span class="title-ic" id="page-ic">${I.dash}</span><div><h1 id="page-title">ড্যাশবোর্ড</h1></div></div>
            <div class="spacer"></div>
            <div class="gsearch" id="gsearch">${I.search}<input class="input" id="gq" placeholder="দোকান খুঁজুন" autocomplete="off" aria-label="দোকান খুঁজুন"><kbd>/</kbd></div>
            <div class="top-actions">
              <button class="icon-btn" id="top-refresh" title="রিফ্রেশ" aria-label="রিফ্রেশ">${I.refresh}</button>
              <button class="icon-btn" id="top-bell" title="অপেক্ষমাণ" aria-label="অপেক্ষমাণ">${I.bell}${pending ? `<span class="dot"></span>` : ""}</button>
            </div>
            <div class="me-wrap">
              <button class="me-btn" id="me-btn" aria-haspopup="menu" aria-expanded="false"><span class="avatar ${colorOf(a.email)}">${esc((a.email[0] || "A").toUpperCase())}</span>
                <span class="who"><div class="email ellipsis">${esc(a.email)}</div><div class="role">${esc(STATUS_BN[a.role] || a.role)}</div></span>${I.chev}</button>
            </div>
          </header>
          <div class="content" id="view"></div>
        </main>
      </div>`;
    $("#side-logout").addEventListener("click", logout);
    $("#menu").addEventListener("click", () => $("#sidebar").classList.toggle("open"));
    $$("[data-nav]").forEach((x) => x.addEventListener("click", () => $("#sidebar").classList.remove("open")));
    $("#top-refresh")?.addEventListener("click", () => { invalidate(); route(); });
    $("#top-bell")?.addEventListener("click", () => { location.hash = state.dash?.pending_kyc ? "#/kyc" : state.dash?.pending_claims ? "#/claims" : "#/unlocks"; });
    wireUserMenu(); wireGlobalSearch();
  }
  function wireUserMenu() {
    const wrap = $(".me-wrap"), btn = $("#me-btn");
    const closeMenu = () => { $(".menu", wrap)?.remove(); btn.setAttribute("aria-expanded", "false"); document.removeEventListener("mousedown", outside); };
    const outside = (e) => { if (!wrap.contains(e.target)) closeMenu(); };
    btn.addEventListener("click", () => {
      if ($(".menu", wrap)) return closeMenu();
      const a = state.admin;
      wrap.insertAdjacentHTML("beforeend", `<div class="menu" role="menu">
        <div class="hd"><div class="email ellipsis">${esc(a.email)}</div><div class="role">${esc(STATUS_BN[a.role] || a.role)}</div></div>
        <button role="menuitem" id="m-profile">${I.user} প্রোফাইল</button>
        <button role="menuitem" class="danger" id="m-logout">${I.out} লগআউট</button></div>`);
      btn.setAttribute("aria-expanded", "true");
      $("#m-profile", wrap).addEventListener("click", () => { closeMenu(); showProfile(); });
      $("#m-logout", wrap).addEventListener("click", () => { closeMenu(); logout(); });
      document.addEventListener("mousedown", outside);
      $("#m-profile", wrap).focus();
    });
    wrap.addEventListener("keydown", (e) => { if (e.key === "Escape") { closeMenu(); btn.focus(); } });
  }
  function showProfile() {
    const a = state.admin;
    openOverlay(`<div class="modal-h"><h3>প্রোফাইল</h3><button class="close" data-close aria-label="বন্ধ">${I.x}</button></div>
      <div class="modal-b"><div class="row" style="gap:14px;margin-bottom:16px"><span class="avatar" style="width:44px;height:44px;font-size:18px">${esc((a.email[0] || "A").toUpperCase())}</span><div><div style="font-weight:600">${esc(a.email)}</div><div class="small muted">${chip(a.role)}</div></div></div>
      <dl class="kv"><dt>শেষ লগইন</dt><dd>${fmtDate(a.last_login_at, true)}</dd><dt>অ্যাকাউন্ট তৈরি</dt><dd>${fmtDate(a.created_at, true)}</dd><dt>অবস্থা</dt><dd>${a.is_active ? chip("active") : chip("disabled")}</dd><dt>ID</dt><dd class="mono small">${esc(a.id)}</dd></dl>
      <div class="hint small faint" style="margin-top:12px">পাসওয়ার্ড বদলাতে সুপার অ্যাডমিনের সাথে যোগাযোগ করুন</div></div>
      <div class="modal-f"><button class="btn danger" id="p-logout">লগআউট</button><button class="btn" data-close>বন্ধ করুন</button></div>`);
    $("#p-logout", layer).addEventListener("click", logout);
  }
  function wireGlobalSearch() {
    const wrap = $("#gsearch"), input = $("#gq");
    let sel = -1, items = [];
    const hide = () => { $(".results", wrap)?.remove(); sel = -1; };
    const show = (html) => { hide(); wrap.insertAdjacentHTML("beforeend", `<div class="results" role="listbox">${html}</div>`); };
    const search = debounce(async () => {
      const q = input.value.trim(); if (q.length < 2) return hide();
      try {
        const p = await api("/shops", { query: { q, page_size: 8 } }); items = p.items;
        if (!items.length) return show(`<div class="none">কোনো দোকান নেই</div>`);
        show(items.map((s, i) => `<button type="button" data-i="${i}" role="option"><span class="avatar ${colorOf(s.shop_name)}" style="width:26px;height:26px;font-size:11px">${esc(s.shop_name[0])}</span><span class="grow"><div class="ellipsis" style="font-weight:600">${esc(s.shop_name)}</div><div class="small faint">${esc(s.owner_name)} · <span class="mono">${esc(s.phone)}</span></div></span>${chip(s.status)}</button>`).join(""));
        $$("[data-i]", wrap).forEach((b) => b.addEventListener("click", () => pick(items[+b.dataset.i])));
      } catch { hide(); }
    }, 300);
    const pick = (s) => { hide(); input.value = ""; openShop(s.id, () => {}); };
    input.addEventListener("input", search);
    input.addEventListener("keydown", (e) => {
      const opts = $$("[data-i]", wrap);
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { if (!opts.length) return; e.preventDefault(); sel = (sel + (e.key === "ArrowDown" ? 1 : -1) + opts.length) % opts.length; opts.forEach((o, i) => o.classList.toggle("sel", i === sel)); }
      else if (e.key === "Enter" && sel >= 0 && items[sel]) pick(items[sel]);
      else if (e.key === "Escape") { hide(); input.blur(); }
    });
    document.addEventListener("mousedown", (e) => { if (!wrap.contains(e.target)) hide(); });
    document.addEventListener("keydown", (e) => { if (e.key === "/" && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName) && !$(".overlay")) { e.preventDefault(); input.focus(); } });
  }
  function setTitle(bnTitle, en) {
    const t = $("#page-title"), ic = $("#page-ic");
    if (t) t.textContent = bnTitle;
    if (ic) { const nav = NAV.find((n) => n.bn === bnTitle); if (nav) ic.innerHTML = nav.icon; }
    document.title = `${bnTitle} · দোকানদার অ্যাডমিন`;
  }
  function refreshBadges() { NAV.forEach((n) => { const a = $(`[data-nav="${n.id}"]`); if (!a || !n.badge) return; a.querySelector(".badge")?.remove(); a.insertAdjacentHTML("beforeend", badgeHtml(n)); }); }
  async function refreshDash(fresh = true) { try { state.dash = await api("/dashboard", { fresh }); refreshBadges(); } catch { /* ignore */ } }

  // ---------- building blocks ----------
  const pageHeader = (title, desc = "", actions = "") => {
    return `<div class="page-h"><div class="page-title-block"><h2>${esc(title)}</h2>${desc ? `<div class="desc">${desc}</div>` : ""}</div>${actions ? `<div class="toolbar">${actions}</div>` : ""}</div>`;
  };
  const skeleton = (rows = 6) => `<div class="skeleton">${Array.from({ length: rows }, () => `<div class="sk-row"><span class="sk w80"></span><span class="sk w60"></span><span class="sk w40"></span><span class="sk w60"></span><span class="sk w40"></span></div>`).join("")}</div>`;
  const empty = (title, sub = "", icon = I.inbox) => `<div class="empty"><div class="ico">${icon}</div><h4>${esc(title)}</h4><div class="small">${esc(sub)}</div></div>`;
  const errState = (e, retryId) => `<div class="err-state"><div class="callout danger"><span>${esc(errMsg(e))}</span>${retryId ? `<button class="btn sm" id="${retryId}" style="margin-left:auto">আবার চেষ্টা করুন</button>` : ""}</div></div>`;
  const loadingInline = () => `<div class="empty"><span class="spinner"></span></div>`;

  function pager(p, onPage) {
    const pages = Math.max(1, Math.ceil(p.total / p.page_size));
    const info = p.total > 0 ? `মোট ${bn(p.total)}` : "";
    if (p.total <= p.page_size) return { info, html: "" };
    const from = (p.page - 1) * p.page_size + 1, to = Math.min(p.total, p.page * p.page_size);
    const nums = new Set([1, pages, p.page - 1, p.page, p.page + 1].filter((n) => n >= 1 && n <= pages));
    let last = 0, btns = "";
    for (const n of [...nums].sort((a, b) => a - b)) { if (n - last > 1) btns += `<button disabled>…</button>`; btns += `<button data-pg="${n}" class="${n === p.page ? "on" : ""}">${bn(n)}</button>`; last = n; }
    const html = `<div class="pager"><span class="pages"><button data-pg="${p.page - 1}" ${p.page <= 1 ? "disabled" : ""}>‹</button>${btns}<button data-pg="${p.page + 1}" ${p.page >= pages ? "disabled" : ""}>›</button></span></div>`;
    setTimeout(() => $$(".pager [data-pg]").forEach((b) => b.addEventListener("click", () => onPage(+b.dataset.pg))));
    return { info: `${bn(from)}–${bn(to)} / ${info}`, html };
  }
  /** Sortable table over the current page of rows. cols: {key,label,sort?:fn|true,render,cls} */
  function table(cols, rows, { onRow, rowCls, sort } = {}) {
    const st = sort || { key: null, dir: 1 };
    const sorted = [...rows];
    if (st.key) { const c = cols.find((x) => x.key === st.key); const g = typeof c.sort === "function" ? c.sort : (r) => r[c.key]; sorted.sort((a, b) => { const x = g(a), y = g(b); if (x == null) return 1; if (y == null) return -1; return (x > y ? 1 : x < y ? -1 : 0) * st.dir; }); }
    const head = cols.map((c) => `<th class="${c.sort ? "sortable" : ""} ${st.key === c.key ? "sorted" : ""} ${c.cls || ""}" ${c.sort ? `data-sort="${c.key}"` : ""}>${c.label}${c.sort ? `<span class="arrow">${st.key === c.key ? (st.dir > 0 ? "▲" : "▼") : "⇅"}</span>` : ""}</th>`).join("");
    const body = sorted.map((r, i) => `<tr ${onRow ? `class="clickable ${rowCls ? rowCls(r) : ""}" data-row="${i}"` : rowCls ? `class="${rowCls(r)}"` : ""}>${cols.map((c) => `<td class="${c.cls || ""}">${c.render(r)}</td>`).join("")}</tr>`).join("");
    const html = `<div class="table-wrap"><table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
    const wire = (root, rerender) => {
      $$("[data-sort]", root).forEach((th) => th.addEventListener("click", () => { const k = th.dataset.sort; st.dir = st.key === k ? -st.dir : 1; st.key = k; rerender(st); }));
      if (onRow) $$("tr[data-row]", root).forEach((tr) => tr.addEventListener("click", () => onRow(sorted[+tr.dataset.row])));
    };
    return { html, wire, st };
  }
  /** Standard list page: header + card with table, pager, skeleton, empty, error, retry. */
  function listPage(view, { title, en, desc, actions, load, cols, onRow, emptyText, emptySub, emptyIcon, extraTop = "" }) {
    setTitle(title, en);
    view.innerHTML = pageHeader(title, desc, actions) + extraTop + `<div class="card" id="list">${skeleton()}</div>`;
    let page = 1, sort = { key: null, dir: 1 }, lastPage = null;
    const draw = () => {
      const list = $("#list"); if (!list || !lastPage) return;
      if (!lastPage.items.length) { list.innerHTML = empty(emptyText, emptySub, emptyIcon); return; }
      const t = table(cols, lastPage.items, { onRow, sort });
      const p = pager(lastPage, (n) => { page = n; run(); });
      list.innerHTML = `<div class="list-info">${p.info}</div>` + t.html + p.html;
      t.wire(list, (s) => { sort = s; draw(); });
    };
    const run = async (fresh = false) => {
      const list = $("#list"); if (!list) return; if (!lastPage) list.innerHTML = skeleton();
      try { lastPage = await load(page, fresh); draw(); }
      catch (e) { list.innerHTML = errState(e, "retry"); $("#retry", list)?.addEventListener("click", () => run(true)); }
    };
    return { run, reset: () => { page = 1; lastPage = null; }, refresh: () => run(true), get items() { return lastPage?.items || []; } };
  }

  // ---------- login ----------
  function renderLogin(prefill = "") {
    setTitleDoc("লগইন");
    app.innerHTML = `
      <div class="login">
        <div class="box">
        <div class="mark">দ</div>
        <h2>দোকানদার অ্যাডমিন</h2>
        <form id="loginForm" novalidate>
          <div class="field" data-field="email"><label for="l-email">Email</label><input class="input" id="l-email" name="email" type="email" value="${esc(prefill)}" placeholder="admin@example.com" autocomplete="username" autofocus><div class="ferr"></div></div>
          <div class="field" data-field="password"><label for="l-pw">পাসওয়ার্ড</label><div class="pw-wrap"><input class="input" id="l-pw" name="password" type="password" autocomplete="current-password"><button type="button" class="eye" data-eye aria-label="পাসওয়ার্ড দেখান">${I.eye}</button></div><div class="ferr"></div></div>
          <div id="lerr" class="callout danger hidden" role="alert"></div>
          <button class="btn primary block" type="submit">লগইন</button>
        </form>
        </div>
        <div class="foot">${esc(location.hostname)} · ${esc(VERSION)}</div>
      </div>`;
    const form = $("#loginForm"); wireEyes(form);
    const fields = [{ name: "email", type: "email", required: true }, { name: "password", required: true }];
    form.addEventListener("input", (e) => { e.target.closest(".field")?.classList.remove("invalid"); e.target.classList.remove("invalid"); $("#lerr").classList.add("hidden"); });
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const data = readForm(form, fields); if (!data) { $(".field.invalid .input", form)?.focus(); return; }
      const btn = $("button[type=submit]", form); btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
      try {
        const r = await api("/auth/login", { method: "POST", body: { email: data.email.toLowerCase(), password: data.password } });
        state.csrf = r.csrf_token; sessionStorage.setItem("csrf", r.csrf_token); state.admin = r.admin; cache.clear();
        await boot(true);
      } catch (err) {
        const el = $("#lerr"); el.textContent = err.status === 423 ? "অনেকবার ভুল চেষ্টা। ১৫ মিনিট পর আবার চেষ্টা করুন" : err.status === 401 ? "ইমেইল বা পাসওয়ার্ড ভুল" : errMsg(err);
        el.classList.remove("hidden"); btn.disabled = false; btn.textContent = "লগইন"; $("#l-pw").select();
      }
    });
    setTimeout(() => (prefill ? $("#l-pw") : $("#l-email"))?.focus(), 30);
  }
  const setTitleDoc = (t) => { document.title = `${t} · দোকানদার অ্যাডমিন`; };

  // ---------- pages ----------
  const pages = {};

  // ---- dashboard ----
  const revenueChart = (rows) => {
    if (!rows?.length) return "";
    const max = Math.max(1, ...rows.map((r) => r.total_bdt));
    const W = 600, H = 180, padL = 44, padR = 8, padB = 24, padT = 12, plotH = H - padB - padT, bw = (W - padL - padR) / rows.length, gap = Math.min(20, bw * 0.35);
    const cur = rows.length - 1;
    const fmtK = (n) => n >= 1000 ? bn(Math.round(n / 1000 * 10) / 10) + "k" : bn(n);
    const ticks = [0, 0.5, 1].map((f) => { const y = padT + plotH * (1 - f); return `<line class="grid" x1="${padL}" x2="${W - padR}" y1="${y}" y2="${y}"/><text class="axis" x="${padL - 8}" y="${y + 3}" text-anchor="end">${fmtK(Math.round(max * f))}</text>`; }).join("");
    const bars = rows.map((r, i) => {
      const h = Math.max(r.total_bdt ? 2 : 1, Math.round((r.total_bdt / max) * plotH));
      const x = padL + i * bw + gap / 2, y = H - padB - h, [yy, mm] = r.month.split("-"), cx = (x + (bw - gap) / 2).toFixed(1);
      return `<rect class="bar ${i === cur ? "cur" : ""} ${r.total_bdt ? "" : "zero"}" x="${x.toFixed(1)}" y="${y}" width="${(bw - gap).toFixed(1)}" height="${h}" rx="2"><title>${MONTH_BN[+mm - 1]} ${yy}: ৳${r.total_bdt.toLocaleString("en-US")} (${r.payments} পেমেন্ট)</title></rect>
        ${r.total_bdt ? `<text class="val" x="${cx}" y="${y - 5}" text-anchor="middle">${fmtK(r.total_bdt)}</text>` : ""}
        <text class="lbl" x="${cx}" y="${H - 6}" text-anchor="middle">${MONTH_BN[+mm - 1]} ${bn(yy.slice(2))}</text>`;
    }).join("");
    return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="গত ${bn(rows.length)} মাসের আয়">${ticks}${bars}</svg>`;
  };
  const deltaHtml = (cur, prev) => {
    if (!prev && !cur) return `<span class="delta flat">—</span>`;
    if (!prev) return `<span class="delta up">+${bn(100)}%</span>`;
    const pct = Math.round(((cur - prev) / prev) * 100);
    return `<span class="delta ${pct > 0 ? "up" : pct < 0 ? "down" : "flat"}">${pct > 0 ? "+" : pct < 0 ? "−" : ""}${bn(Math.abs(pct))}%</span>`;
  };
  pages.dashboard = async (view) => {
    setTitle("ড্যাশবোর্ড", "Overview");
    view.innerHTML = `
            <div class="page-h"><h2>ড্যাশবোর্ড</h2></div>
      <div class="kpi-grid">${Array.from({ length: 4 }, () => `<div class="kpi"><span class="sk w40"></span><span class="sk tall w60"></span></div>`).join("")}</div>
      <div class="kpi-grid secondary">${Array.from({ length: 4 }, () => `<div class="kpi"><span class="sk w60"></span></div>`).join("")}</div>
      <div class="grid-dash">
        <div class="card" style="padding:24px">${skeleton(4)}</div>
        <div class="card" style="padding:24px">${skeleton(4)}</div>
      </div>
    `;

    try {
      const [d, rev] = await Promise.all([api("/dashboard"), api("/dashboard/revenue", { query: { months: 6 } })]);
      state.dash = d; state.revenue = rev; refreshBadges();
      const v = $("#view"); if (!v || state.route !== "dashboard") return;

      const curM = rev[rev.length - 1]?.total_bdt || 0, prevM = rev[rev.length - 2]?.total_bdt || 0;
      const pendingCount = (d.pending_claims || 0) + (d.open_unlock_requests || 0) + (d.pending_kyc || 0);
      const attention = [
        { t: "KYC যাচাই বাকি", n: d.pending_kyc || 0, go: "kyc", ic: I.idcard, c: "amber" },
        { t: "অপেক্ষমাণ পেমেন্ট ক্লেইম", n: d.pending_claims || 0, go: "claims", ic: I.claim, c: "blue" },
        { t: "খোলা আনলক রিকোয়েস্ট", n: d.open_unlock_requests || 0, go: "unlocks", ic: I.lock, c: "rose" },
        { t: "গ্রেস পিরিয়ডে দোকান", n: d.due || 0, go: "shops?status=due", ic: I.clock, c: "amber" },
        { t: "লকড ডিভাইস", n: d.locked_devices || 0, go: "unlocks", ic: I.alert, c: "rose" },
        { t: "স্থগিত দোকান", n: d.suspended || 0, go: "shops?status=suspended", ic: I.shop, c: "slate" },
      ];
      const recent = (d.recent_activity || []).slice(0, 8);

      v.innerHTML = `
        <div class="page-h">
          <h2>ড্যাশবোর্ড</h2>
          <div class="toolbar">
            <button class="btn" id="refresh">রিফ্রেশ</button>
            <button class="btn primary" id="add-shop">${I.plus} দোকান যোগ করুন</button>
          </div>
        </div>

        <div class="kpi-grid">
          <div class="kpi link blue" data-go="shops" tabindex="0" role="link">
            <span class="lbl">মোট দোকান</span>
            <span class="val">${bn(d.total_shops)}</span>
            <span class="sub">ট্রায়াল ${bn(d.trial)} · বন্ধ ${bn(d.disabled)}</span>
            <span class="ic">${I.shop}</span>
          </div>
          <div class="kpi link green" data-go="shops?status=active" tabindex="0" role="link">
            <span class="lbl">সক্রিয়</span>
            <span class="val">${bn(d.active)}</span>
            <span class="sub">মোট দোকানের ${bn(Math.round((d.active / Math.max(1, d.total_shops)) * 100))}%</span>
            <span class="ic">${I.check}</span>
          </div>
          <div class="kpi link amber" data-go="shops?status=due" tabindex="0" role="link">
            <span class="lbl">বকেয়া</span>
            <span class="val">${bn(d.due)}</span>
            <span class="sub">গ্রেস পিরিয়ডে</span>
            <span class="ic">${I.clock}</span>
          </div>
          <div class="kpi violet">
            <span class="lbl">এই মাসের আয়</span>
            <span class="val">${money(d.revenue_this_month_bdt)}</span>
            <span class="sub">${deltaHtml(curM, prevM)} গত মাসের তুলনায়</span>
            <span class="ic">${I.trend}</span>
          </div>
        </div>

        <div class="kpi-grid secondary">
          <div class="kpi teal"><span class="ic">${I.money}</span><span class="lbl">MRR</span><span class="val">${money(d.mrr_bdt)}</span></div>
          <div class="kpi link amber" data-go="kyc" tabindex="0" role="link"><span class="ic">${I.idcard}</span><span class="lbl">KYC যাচাই বাকি</span><span class="val">${bn(d.pending_kyc || 0)}</span></div>
          <div class="kpi link blue" data-go="claims" tabindex="0" role="link"><span class="ic">${I.claim}</span><span class="lbl">অপেক্ষমাণ ক্লেইম</span><span class="val">${bn(d.pending_claims)}</span></div>
          <div class="kpi link rose" data-go="unlocks" tabindex="0" role="link"><span class="ic">${I.lock}</span><span class="lbl">আনলক রিকোয়েস্ট</span><span class="val">${bn(d.open_unlock_requests)}</span></div>
          <div class="kpi link slate" data-go="shops?status=suspended" tabindex="0" role="link"><span class="ic">${I.alert}</span><span class="lbl">স্থগিত</span><span class="val">${bn(d.suspended)}</span></div>
        </div>

        <div class="grid-dash">
          <div class="card">
            <div class="card-h" style="--dot:#22C55E">
              <h3>আয় — গত ${bn(rev.length)} মাস</h3>
              <span class="small muted">মোট ${money(rev.reduce((a, r) => a + r.total_bdt, 0))}</span>
            </div>
            <div class="chart">${revenueChart(rev)}</div>
          </div>
          <div class="card">
            <div class="card-h" style="--dot:#F59E0B"><h3>মনোযোগ দরকার</h3>${pendingCount ? `<span class="badge warn">${bn(pendingCount)}</span>` : ""}</div>
            <div class="card-b tight">
              <ul class="attn">
                ${attention.map((a) => `<li class="${a.c}"><span class="ic">${a.ic}</span><span class="t">${esc(a.t)}</span><span class="n ${a.n ? "" : "zero"}">${bn(a.n)}</span><button class="btn sm" data-go="${a.go}">দেখুন</button></li>`).join("")}
              </ul>
            </div>
          </div>
        </div>

        <div class="card">
          <div class="card-h" style="--dot:#7C3AED"><h3>সাম্প্রতিক কার্যক্রম</h3><a href="#/audit" class="small">সব দেখুন</a></div>
          <div class="card-b tight">
            ${recent.length ? `<div class="table-wrap"><table><thead><tr><th>সময়</th><th>কার্যক্রম</th><th>অ্যাক্টর</th><th>টার্গেট</th></tr></thead><tbody>
              ${recent.map((a) => `<tr><td class="small nowrap muted">${fmtDate(a.created_at, true)}</td><td><span class="title">${esc(ACTION_BN[a.action] || a.action)}</span></td><td class="small">${esc(a.actor_type)}${a.actor_id ? ` <span class="mono faint">${esc(a.actor_id.slice(0, 8))}</span>` : ""}</td><td class="small">${esc(a.target_type || "")}${a.target_id ? ` <span class="mono faint">${esc(a.target_id.slice(0, 8))}</span>` : ""}</td></tr>`).join("")}
            </tbody></table></div>` : empty("কোনো কার্যক্রম নেই")}
          </div>
        </div>
      `;

      $("#refresh")?.addEventListener("click", () => { invalidate(); pages.dashboard(view); });
      $("#add-shop")?.addEventListener("click", () => addShop(() => { invalidate(); pages.dashboard(view); }));
      $$("[data-go]", v).forEach((t) => {
        const go = () => (location.hash = "#/" + t.dataset.go);
        t.addEventListener("click", go);
        t.addEventListener("keydown", (e) => e.key === "Enter" && go());
      });
    } catch (e) {
      const v = $("#view");
      if (v) {
        v.innerHTML = pageHeader("ড্যাশবোর্ড") + errState(e, "retry");
        $("#retry")?.addEventListener("click", () => pages.dashboard(view));
      }
    }
  };
  const auditItem = (a) => `<li><span class="dot ${actionTone(a.action)}"></span><div class="grow"><div><b>${esc(ACTION_BN[a.action] || a.action)}</b> <span class="faint small mono">${esc(a.action)}</span></div>
    <div class="small muted ellipsis">${esc(a.actor_type)}${a.actor_id ? " · " + esc(a.actor_id.slice(0, 8)) : ""}${a.target_type ? " → " + esc(a.target_type) + " " + esc((a.target_id || "").slice(0, 12)) : ""}${a.meta ? " · " + esc(JSON.stringify(a.meta).slice(0, 110)) : ""}</div></div>
    <span class="when" title="${esc(fmtDate(a.created_at, true))}">${ago(a.created_at)}</span></li>`;

  // ---- shops ----
  pages.shops = async (view, params) => {
    let q = params.q || "", status = params.status || "";
    const statuses = ["", "pending_verification", "trial", "active", "due", "suspended", "disabled"];
    const lp = listPage(view, {
      title: "দোকানসমূহ",
      actions: `<div class="search">${I.search}<input class="input" id="q" placeholder="নাম বা ফোন" value="${esc(q)}"></div>
        <select class="input auto" id="st" aria-label="স্ট্যাটাস">${statuses.map((s) => `<option value="${s}" ${s === status ? "selected" : ""}>${s ? STATUS_BN[s] : "সব স্ট্যাটাস"}</option>`).join("")}</select>
        <button class="btn primary" id="add">${I.plus} দোকান যোগ করুন</button>`,
      load: (page, fresh) => api("/shops", { query: { q, page, page_size: 25, status_filter: status }, fresh }),
      cols: [
        { key: "shop_name", label: "দোকান", sort: true, render: (s) => `<div class="shop-cell"><span class="shop-avatar ${colorOf(s.shop_name)}">${esc((s.shop_name || "দ")[0])}</span><div><div class="title">${esc(s.shop_name)}</div><div class="sub">${esc(s.owner_name)}</div></div></div>` },
        { key: "phone", label: "ফোন", sort: true, cls: "mono", render: (s) => `<span class="mono">${esc(s.phone)}</span>` },
        { key: "plan", label: "প্ল্যান", sort: (s) => s.plan?.name, render: (s) => s.plan ? `<div class="title">${esc(s.plan.name)}</div><div class="sub">${money(s.plan.price_bdt)}</div>` : "—" },
        { key: "status", label: "স্ট্যাটাস", sort: true, render: (s) => (s.verification && s.verification !== "approved" ? vchip(s.verification) + " " : "") + (s.status !== "pending_verification" && s.status !== "rejected" ? chip(s.status) : "") + (s.days_left && s.status !== "disabled" ? ` <span class="small muted num">(${bn(s.days_left)} দিন)</span>` : "") },
        { key: "until", label: "মেয়াদ", sort: (s) => s.paid_until || s.trial_ends_at, cls: "small", render: (s) => s.paid_until ? "পেইড: " + fmtDate(s.paid_until) : s.trial_ends_at ? "ট্রায়াল: " + fmtDate(s.trial_ends_at) : "—" },
        { key: "device", label: "ডিভাইস", render: (s) => s.device ? `<span class="small">${esc(s.device.model || s.device.device_id.slice(0, 10))}</span> ${s.device.locked ? chip("locked") : ""}` : '<span class="faint small">—</span>' },
        { key: "created_at", label: "যুক্ত", sort: true, cls: "small muted nowrap", render: (s) => fmtDate(s.created_at) },
      ],
      onRow: (s) => openShop(s.id, () => lp.refresh()),
      emptyText: "কোনো দোকান নেই", emptyIcon: I.shop,
    });
    $("#q").addEventListener("input", debounce((e) => { q = e.target.value.trim(); lp.reset(); lp.run(); }));
    $("#st").addEventListener("change", (e) => { status = e.target.value; lp.reset(); lp.run(); });
    $("#add").addEventListener("click", () => addShop(() => lp.refresh()));
    lp.run();
  };

  async function addShop(refresh) {
    let plans = []; try { plans = (await api("/plans", { query: { page_size: 100 } })).items.filter((p) => p.is_active); } catch { /* ignore */ }
    formModal({
      title: "দোকান যোগ করুন", submitText: "যোগ করুন",
      fields: [
        { name: "shop_name", label: "দোকানের নাম", required: true, maxlength: 120 },
        { name: "owner_name", label: "মালিকের নাম", required: true, maxlength: 120 },
        { name: "phone", label: "মোবাইল নম্বর", required: true, kind: "phone", placeholder: "01XXXXXXXXX", maxlength: 11 },
        { name: "plan_id", label: "প্ল্যান", type: "select", options: plans.map((p) => ({ value: p.id, label: `${p.name} — ${money(p.price_bdt)}/${p.period_days} দিন` })), optional: true },
        { name: "trial_days", label: "ট্রায়াল (দিন)", type: "number", min: 0, max: 365, optional: true, hint: "খালি রাখলে সেটিংসের ডিফল্ট" },
        { name: "address", label: "ঠিকানা", optional: true, maxlength: 255 },
        { name: "notes", label: "নোট", type: "textarea", optional: true, span: true },
      ],
      onSubmit: async (data, m) => {
        const r = await api("/shops", { method: "POST", body: data }); m.close(); refresh(); refreshDash();
        showSecret("দোকান যোগ হয়েছে", `${r.shop.shop_name} (${r.shop.phone}) এর অস্থায়ী পাসওয়ার্ড। শুধু একবার দেখানো হবে।`, r.temp_password);
      },
    });
  }
  function showSecret(title, text, secret) {
    const m = openOverlay(`<div class="modal-h"><h3>${esc(title)}</h3><button class="close" data-close aria-label="বন্ধ">${I.x}</button></div>
      <div class="modal-b stack"><div class="callout warn">${esc(text)}</div><div class="secret"><code id="sec">${esc(secret)}</code><button class="btn sm" id="cp">কপি</button></div></div>
      <div class="modal-f"><button class="btn primary" data-close>বন্ধ করুন</button></div>`);
    $("#cp", m.el).addEventListener("click", () => copy(secret));
  }

  async function openShop(id, refresh) {
    const d = openOverlay(`<div class="drawer-h"><h3>দোকানের বিবরণ</h3><button class="close" data-close aria-label="বন্ধ">${I.x}</button></div><div class="tabs"></div><div class="drawer-b">${loadingInline()}</div>`, { side: true, onClose: refresh });
    let shop, tab = "info";
    const tabCache = {}; // avoid re-fetch on tab switch within the drawer
    const load = async (fresh = false) => { shop = await api(`/shops/${id}`, { fresh }); if (fresh) { delete tabCache.payments; delete tabCache.audit; } };
    const render = async (fresh = false) => {
      const b = $(".drawer-b", d.el);
      try { await load(fresh); } catch (e) { b.innerHTML = errState(e); return; }
      $(".drawer-h h3", d.el).innerHTML = `${esc(shop.shop_name)} ${shop.verification && shop.verification !== "approved" ? vchip(shop.verification) : chip(shop.status)}`;
      const tabs = $(".tabs", d.el);
      tabs.innerHTML = [["info", "তথ্য"], ["payments", "পেমেন্ট"], ["device", "ডিভাইস"], ["audit", "অডিট"]].map(([k, l]) => `<button class="${tab === k ? "on" : ""}" data-tab="${k}" role="tab" aria-selected="${tab === k}">${l}</button>`).join("");
      $$("[data-tab]", tabs).forEach((x) => x.addEventListener("click", () => { tab = x.dataset.tab; render(); }));
      if (tab === "info") b.innerHTML = infoTab();
      else if (tab === "device") b.innerHTML = deviceTab();
      else { if (!tabCache[tab]) { b.innerHTML = loadingInline(); try { tabCache[tab] = tab === "payments" ? await paymentsTab() : await auditTab(); } catch (e) { b.innerHTML = errState(e); return; } } b.innerHTML = tabCache[tab]; }
      bind(b);
    };
    const infoTab = () => `
      <div class="stack">
        <div class="row wrap">
          <button class="btn sm primary" id="pay">পেমেন্ট রেকর্ড</button>
          <button class="btn sm" id="edit">সম্পাদনা</button>
          <button class="btn sm" id="notify">নোটিফিকেশন</button>
          <button class="btn sm" id="pwreset">পাসওয়ার্ড রিসেট</button>
          ${shop.is_disabled ? `<button class="btn sm" id="enable">চালু করুন</button>` : `<button class="btn sm danger" id="disable">বন্ধ করুন</button>`}
        </div>
        <dl class="kv">
          <dt>মালিক</dt><dd>${esc(shop.owner_name)}</dd><dt>ফোন</dt><dd class="mono">${esc(shop.phone)}</dd><dt>ঠিকানা</dt><dd>${esc(shop.address || "—")}</dd>
          <dt>প্ল্যান</dt><dd>${shop.plan ? `${esc(shop.plan.name)} · ${money(shop.plan.price_bdt)} / ${bn(shop.plan.period_days)} দিন` : "—"}</dd>
          <dt>স্ট্যাটাস</dt><dd>${chip(shop.status)} ${shop.days_left ? `<span class="small muted">${bn(shop.days_left)} দিন বাকি</span>` : ""}</dd>
          <dt>যাচাই</dt><dd>${vchip(shop.verification || "approved")} ${shop.verified_at ? `<span class="small muted">${fmtDate(shop.verified_at)}</span>` : ""} ${shop.nid_number ? `<button class="btn link small" id="kyc-open">KYC দেখুন</button>` : ""}${shop.verification === "rejected" && shop.rejection_reason_bn ? `<div class="small muted">${esc(shop.rejection_reason_bn)}</div>` : ""}</dd>
          ${shop.nid_number ? `<dt>NID</dt><dd class="mono">${esc(shop.nid_number)}</dd>` : ""}
          <dt>ট্রায়াল শেষ</dt><dd>${fmtDate(shop.trial_ends_at)}</dd><dt>পেইড পর্যন্ত</dt><dd>${fmtDate(shop.paid_until)}</dd><dt>গ্রেস শেষ</dt><dd>${fmtDate(shop.grace_ends_at)}</dd>
          <dt>নোট</dt><dd>${esc(shop.notes || "—")}</dd><dt>যোগ হয়েছে</dt><dd>${fmtDate(shop.created_at, true)}</dd><dt>ID</dt><dd class="mono small">${esc(shop.id)}</dd>
        </dl>
      </div>`;
    const paymentsTab = async () => {
      const rows = await api(`/shops/${id}/payments`);
      return `<div class="stack"><div class="row between"><h4>পেমেন্ট</h4><button class="btn sm primary" id="pay">পেমেন্ট রেকর্ড</button></div>
        ${rows.length ? `<div class="card"><div class="table-wrap"><table><thead><tr><th>তারিখ</th><th class="num">পরিমাণ</th><th>মাধ্যম</th><th>TRX ID</th><th class="num">মাস</th><th>মেয়াদ</th></tr></thead><tbody>
        ${rows.map((p) => `<tr><td class="small nowrap">${fmtDate(p.created_at)}</td><td class="num">${money(p.amount_bdt)}</td><td>${esc(METHOD_BN[p.method] || p.method)}</td><td class="mono small">${esc(p.trx_id || "—")}</td><td class="num">${bn(p.months)}</td><td class="small">${fmtDate(p.paid_from)} → ${fmtDate(p.paid_until)}</td></tr>`).join("")}
        </tbody></table></div></div>` : `<div class="card">${empty("কোনো পেমেন্ট নেই")}</div>`}</div>`;
    };
    const deviceTab = () => {
      const dv = shop.device;
      return `<div class="stack"><div class="row between"><h4>ডিভাইস</h4>${dv ? `<button class="btn sm danger" id="devreset">ডিভাইস রিসেট</button>` : ""}</div>
        ${dv ? `<dl class="kv"><dt>মডেল</dt><dd>${esc(dv.model || "—")}</dd><dt>OS</dt><dd>${esc(dv.os || "—")}</dd><dt>অ্যাপ ভার্সন</dt><dd>${esc(dv.app_version || "—")}</dd>
          <dt>Device ID</dt><dd class="mono small">${esc(dv.device_id)}</dd><dt>সিগনেচার</dt><dd class="mono small" style="word-break:break-all">${esc(dv.signature_sha256 || "—")}</dd>
          <dt>লক</dt><dd>${dv.locked ? chip("locked") + ` <span class="small">${esc(REASON_BN[dv.lock_reason] || dv.lock_reason || "")}</span>` : chip("active").replace("সক্রিয়", "আনলকড")}</dd>
          <dt>শেষ দেখা</dt><dd>${fmtDate(dv.last_seen_at, true)}</dd><dt>যুক্ত</dt><dd>${fmtDate(dv.created_at, true)}</dd></dl>
          <div class="hint small faint">ফোন বদলালে ডিভাইস রিসেট করুন; পরের লগইনে নতুন ডিভাইস যুক্ত হবে।</div>` : `<div class="card">${empty("কোনো ডিভাইস যুক্ত নেই")}</div>`}</div>`;
    };
    const auditTab = async () => { const rows = await api(`/shops/${id}/audit`); return `<div class="card">${rows.length ? `<ul class="timeline">${rows.map(auditItem).join("")}</ul>` : empty("কোনো লগ নেই")}</div>`; };
    const act = async (fn, okMsg) => { try { await fn(); okMsg && toast(okMsg); render(true); refreshDash(); } catch (e) { toast(errMsg(e), "error"); } };
    const bind = (b) => {
      $("#edit", b)?.addEventListener("click", editShop);
      $("#kyc-open", b)?.addEventListener("click", () => openKyc(shop.id, () => render(true)));
      $("#pay", b)?.addEventListener("click", recordPayment);
      $("#notify", b)?.addEventListener("click", () => sendNotification([shop.id], shop.shop_name));
      $("#pwreset", b)?.addEventListener("click", async () => {
        if (!(await confirmDialog({ title: "পাসওয়ার্ড রিসেট", text: `${shop.shop_name} এর জন্য নতুন অস্থায়ী পাসওয়ার্ড তৈরি হবে। পুরনো পাসওয়ার্ড বাতিল হবে।`, okText: "রিসেট" }))) return;
        try { const r = await api(`/shops/${id}/reset-password`, { method: "POST" }); showSecret("নতুন পাসওয়ার্ড", "শুধু একবার দেখানো হবে।", r.temp_password); } catch (e) { toast(errMsg(e), "error"); }
      });
      $("#disable", b)?.addEventListener("click", async () => {
        if (!(await confirmDialog({ title: "দোকান বন্ধ করুন", text: "অ্যাকাউন্ট বন্ধ হলে অ্যাপ ব্যবহার করা যাবে না। ডেটা অক্ষত থাকবে।", okText: "বন্ধ করুন", danger: true }))) return;
        act(() => api(`/shops/${id}/disable`, { method: "POST" }), "দোকান বন্ধ করা হয়েছে");
      });
      $("#enable", b)?.addEventListener("click", () => act(() => api(`/shops/${id}/enable`, { method: "POST" }), "দোকান চালু করা হয়েছে"));
      $("#devreset", b)?.addEventListener("click", async () => {
        if (!(await confirmDialog({ title: "ডিভাইস রিসেট", text: "বর্তমান ডিভাইস খুলে যাবে, সব সেশন লগআউট হবে এবং খোলা আনলক রিকোয়েস্ট বন্ধ হবে।", okText: "রিসেট", danger: true }))) return;
        act(() => api(`/shops/${id}/reset-device`, { method: "POST" }), "ডিভাইস রিসেট হয়েছে");
      });
    };
    const editShop = async () => {
      let plans = []; try { plans = (await api("/plans", { query: { page_size: 100 } })).items; } catch { /* ignore */ }
      formModal({
        title: "দোকান সম্পাদনা", fields: [
          { name: "shop_name", label: "দোকানের নাম", value: shop.shop_name, required: true, maxlength: 120 },
          { name: "owner_name", label: "মালিকের নাম", value: shop.owner_name, required: true, maxlength: 120 },
          { name: "phone", label: "মোবাইল নম্বর", value: shop.phone, required: true, kind: "phone", maxlength: 11 },
          { name: "plan_id", label: "প্ল্যান", type: "select", value: shop.plan?.id, options: plans.map((p) => ({ value: p.id, label: `${p.name} — ${money(p.price_bdt)}` })) },
          { name: "trial_ends_at", label: "ট্রায়াল শেষ", type: "datetime-local", value: toLocalInput(shop.trial_ends_at), optional: true },
          { name: "paid_until", label: "পেইড পর্যন্ত", type: "datetime-local", value: toLocalInput(shop.paid_until), optional: true },
          { name: "address", label: "ঠিকানা", value: shop.address || "", optional: true, maxlength: 255 },
          { name: "notes", label: "নোট", type: "textarea", value: shop.notes || "", optional: true, span: true },
        ],
        onSubmit: async (data, m) => {
          ["trial_ends_at", "paid_until"].forEach((k) => { if (data[k]) data[k] = new Date(data[k]).toISOString(); });
          await api(`/shops/${id}`, { method: "PATCH", body: data }); m.close(); toast("সংরক্ষিত"); render(true);
        },
      });
    };
    const recordPayment = () => formModal({
      title: `পেমেন্ট রেকর্ড — ${shop.shop_name}`, submitText: "রেকর্ড করুন",
      intro: `<div class="callout" style="margin-bottom:14px">প্ল্যান: ${shop.plan ? `${esc(shop.plan.name)} · ${money(shop.plan.price_bdt)} / ${bn(shop.plan.period_days)} দিন` : "—"} · মেয়াদ: ${fmtDate(shop.paid_until)}</div>`,
      fields: [
        { name: "amount_bdt", label: "পরিমাণ (৳)", type: "number", min: 0, value: shop.plan?.price_bdt ?? 300, required: true },
        { name: "months", label: "মাস", type: "number", min: 1, max: 36, value: 1, required: true },
        { name: "method", label: "মাধ্যম", type: "select", value: "bkash", options: Object.entries(METHOD_BN).map(([v, l]) => ({ value: v, label: l })) },
        { name: "trx_id", label: "TRX ID", optional: true, maxlength: 64 },
        { name: "note", label: "নোট", type: "textarea", optional: true, span: true },
      ],
      onSubmit: async (data, m) => { await api(`/shops/${id}/payments`, { method: "POST", body: data }); m.close(); toast("পেমেন্ট রেকর্ড হয়েছে"); tab = "payments"; render(true); refreshDash(); },
    });
    render();
  }
  const toLocalInput = (iso) => { if (!iso) return ""; const d = new Date(iso); const p = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; };

  function sendNotification(shopIds, label) {
    formModal({
      title: shopIds ? `নোটিফিকেশন — ${label}` : "সবাইকে নোটিফিকেশন", submitText: "পাঠান",
      fields: [
        { name: "title_bn", label: "শিরোনাম", required: true, maxlength: 200, span: true },
        { name: "body_bn", label: "বার্তা", type: "textarea", required: true, span: true },
        { name: "kind", label: "ধরন", type: "select", value: "info", options: [{ value: "info", label: "তথ্য" }, { value: "warning", label: "সতর্কতা" }, { value: "due", label: "বকেয়া" }] },
      ],
      onSubmit: async (data, m) => { await api("/notifications/broadcast", { method: "POST", body: shopIds ? { ...data, shop_ids: shopIds } : data }); m.close(); toast("পাঠানো হয়েছে"); if (state.route === "notifications") route(); },
    });
  }

  // ---- KYC ----
  const livenessHtml = (lv) => {
    if (!lv) return `<div class="callout">লাইভনেস তথ্য নেই</div>`;
    const pct = Math.round((Number(lv.score) || 0) * 100);
    return `<div class="live ${lv.passed ? "pass" : "fail"}" style="--pct:${pct}"><div class="score"><span>${bn(pct)}%</span></div>
      <div class="grow"><div><b>${lv.passed ? "লাইভনেস পাস" : "লাইভনেস ফেল"}</b> <span class="small muted">· ${bn((lv.challenges || []).length)}টি চ্যালেঞ্জ${lv.captured_at ? " · " + fmtDate(lv.captured_at, true) : ""}</span></div>
      <div class="chal">${(lv.challenges || []).map((c) => `<span class="chip ${lv.passed ? "approved" : "rejected"}">${esc(CHALLENGE_BN[c] || c)}</span>`).join("")}</div></div></div>`;
  };
  const kycImages = (det) => {
    const kinds = ["nid_front", "nid_back", "selfie", "frame_0", "frame_1", "frame_2"].filter((k) => k.startsWith("frame") ? det.files.includes(k) : true);
    return `<div class="kyc-grid">${kinds.map((k) => {
      const url = det.file_urls?.[k]; const cls = k === "selfie" ? "selfie" : k.startsWith("nid") ? "nid" : "frame";
      return url ? `<a class="kyc-img ${cls}" href="${esc(url)}" data-zoom="${esc(url)}" data-cap="${esc(KIND_BN[k] || k)}"><img src="${esc(url)}" alt="${esc(KIND_BN[k] || k)}" loading="lazy"><span class="cap">${esc(KIND_BN[k] || k)}</span></a>`
                 : `<div class="kyc-img missing">${esc(KIND_BN[k] || k)} নেই</div>`;
    }).join("")}</div>`;
  };
  function zoomImage(url, cap) {
    const z = document.createElement("div"); z.className = "zoom"; z.setAttribute("role", "dialog");
    z.innerHTML = `<span class="cap">${esc(cap || "")}</span><button class="close" aria-label="বন্ধ">${I.x}</button><img src="${esc(url)}" alt="${esc(cap || "")}">`;
    const close = () => { z.remove(); document.removeEventListener("keydown", onKey); };
    const onKey = (e) => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
    z.addEventListener("click", close); document.addEventListener("keydown", onKey, true);
    document.body.appendChild(z);
  }
  async function openKyc(shopId, refresh) {
    const d = openOverlay(`<div class="drawer-h"><h3>KYC যাচাই</h3><button class="close" data-close aria-label="বন্ধ">${I.x}</button></div><div class="drawer-b">${loadingInline()}</div>`, { side: true, onClose: refresh });
    let det;
    const render = async (fresh = false) => {
      const b = $(".drawer-b", d.el);
      try { det = await api(`/kyc/${shopId}`, { fresh }); } catch (e) { b.innerHTML = errState(e); return; }
      const s = det.shop, v = s.verification;
      $(".drawer-h h3", d.el).innerHTML = `${esc(s.shop_name)} ${vchip(v)}`;
      b.innerHTML = `<div class="stack">
        ${v === "pending" ? `<div class="row wrap"><button class="btn primary" id="k-approve">${I.check} অনুমোদন করুন</button><button class="btn danger" id="k-reject">বাতিল করুন</button><button class="btn ghost" id="k-shop">দোকান দেখুন</button></div>`
          : `<div class="callout ${v === "approved" ? "ok" : "danger"}"><span>${v === "approved" ? `যাচাই সম্পন্ন ${fmtDate(s.verified_at, true)} · ট্রায়াল শেষ ${fmtDate(s.trial_ends_at)}` : `বাতিল ${fmtDate(det.reviewed_at, true)}${det.reason_bn ? " · কারণ: " + esc(det.reason_bn) : ""}`}</span><button class="btn sm" id="k-shop" style="margin-left:auto">দোকান</button></div>`}
        <div class="sec-h" style="--dot:#2563EB">দোকানের তথ্য</div>
        <dl class="kv"><dt>দোকান</dt><dd>${esc(s.shop_name)}</dd><dt>মালিক</dt><dd>${esc(s.owner_name)}</dd><dt>ফোন</dt><dd class="mono">${esc(s.phone)}</dd><dt>ঠিকানা</dt><dd>${esc(s.address || "—")}</dd>
          <dt>NID নম্বর</dt><dd class="mono" style="font-size:14px;letter-spacing:.04em">${esc(det.nid_number || "—")}</dd><dt>আবেদন</dt><dd>${fmtDate(det.submitted_at, true)}</dd>
          <dt>ডিভাইস</dt><dd>${s.device ? esc(s.device.model || s.device.device_id.slice(0, 12)) + ` <span class="small faint">${esc(s.device.os || "")}</span>` : "—"}</dd></dl>
        <div class="sec-h" style="--dot:#16A34A">লাইভনেস</div>
        ${livenessHtml(det.liveness)}
        <div class="sec-h" style="--dot:#7C3AED">ছবি <span class="small faint" style="font-weight:400">· বড় করতে ক্লিক করুন</span></div>
        ${kycImages(det)}
        ${det.history?.length > 1 ? `<div class="sec-h" style="--dot:#64748B">আগের আবেদন</div><ul class="timeline">${det.history.slice(1).map((h) => `<li><span class="dot ${h.decision === "rejected" ? "danger" : ""}"></span><div class="grow"><div><b>${esc(VERIF_BN[h.decision] || "অপেক্ষমাণ")}</b>${h.reason_bn ? ` <span class="small muted">· ${esc(h.reason_bn)}</span>` : ""}</div></div><span class="when">${fmtDate(h.submitted_at)}</span></li>`).join("")}</ul>` : ""}
      </div>`;
      $$("[data-zoom]", b).forEach((a) => a.addEventListener("click", (e) => { e.preventDefault(); zoomImage(a.dataset.zoom, a.dataset.cap); }));
      $("#k-shop", b)?.addEventListener("click", () => openShop(s.id, () => {}));
      $("#k-approve", b)?.addEventListener("click", async () => {
        if (!(await confirmDialog({ title: "KYC অনুমোদন", text: `${s.shop_name} (${s.phone}) যাচাইকৃত হবে এবং আজ থেকে ফ্রি ট্রায়াল শুরু হবে।`, okText: "অনুমোদন" }))) return;
        try { await api(`/kyc/${shopId}/approve`, { method: "POST" }); toast("অনুমোদিত — ট্রায়াল শুরু"); refreshDash(); render(true); } catch (e) { toast(errMsg(e), "error"); }
      });
      $("#k-reject", b)?.addEventListener("click", () => formModal({
        title: `KYC বাতিল — ${s.shop_name}`, submitText: "বাতিল করুন",
        fields: [{ name: "reason_bn", label: "কারণ", type: "textarea", required: true, maxlength: 500, span: true, hint: "দোকানদার এই কারণ দেখবে এবং আবার আবেদন করতে পারবে", placeholder: "যেমন: NID ছবি অস্পষ্ট, সেলফির সাথে মিলছে না" }],
        onSubmit: async (data, m) => { await api(`/kyc/${shopId}/reject`, { method: "POST", body: data }); m.close(); toast("বাতিল হয়েছে"); refreshDash(); render(true); },
      }));
    };
    render();
  }
  pages.kyc = async (view, params) => {
    let status = params.status ?? "pending", q = "";
    const lp = listPage(view, {
      title: "KYC যাচাই",
      actions: `<div class="search">${I.search}<input class="input" id="q" placeholder="দোকান, ফোন বা NID"></div>${segment("tg", ["pending", "approved", "rejected", ""], status)}`,
      load: (page, fresh) => api("/kyc", { query: { status, page, q }, fresh }),
      cols: [
        { key: "submitted_at", label: "আবেদন", sort: true, cls: "small nowrap", render: (r) => fmtDate(r.submitted_at, true) },
        { key: "shop", label: "দোকান", sort: (r) => r.shop.shop_name, render: (r) => `<div class="shop-cell"><span class="shop-avatar ${colorOf(r.shop.shop_name)}">${esc((r.shop.shop_name || "দ")[0])}</span><div><div class="title">${esc(r.shop.shop_name)}</div><div class="sub">${esc(r.shop.owner_name)} · <span class="mono">${esc(r.shop.phone)}</span></div></div></div>` },
        { key: "nid_number", label: "NID", cls: "mono", render: (r) => esc(r.nid_number || "—") },
        { key: "liveness", label: "লাইভনেস", sort: (r) => r.liveness?.score, render: (r) => r.liveness ? `<span class="chip ${r.liveness.passed ? "approved" : "rejected"}">${bn(Math.round((r.liveness.score || 0) * 100))}%</span> <span class="small muted">${bn((r.liveness.challenges || []).length)} চ্যালেঞ্জ</span>` : '<span class="faint">—</span>' },
        { key: "files", label: "ছবি", cls: "small", render: (r) => `${bn(r.files.length)}টি` },
        { key: "verification", label: "অবস্থা", sort: (r) => r.shop.verification, render: (r) => vchip(r.shop.verification) + (r.reviewed_at ? `<div class="sub">${fmtDate(r.reviewed_at, true)}</div>` : "") },
        { key: "_a", label: "", cls: "actions", render: (r) => `<button class="btn sm ${r.shop.verification === "pending" ? "primary" : ""}" data-open="${r.shop.id}">${r.shop.verification === "pending" ? "যাচাই করুন" : "দেখুন"}</button>` },
      ],
      onRow: (r) => openKyc(r.shop.id, () => lp.refresh()),
      emptyText: status === "pending" ? "যাচাইয়ের জন্য কোনো আবেদন নেই" : "কোনো আবেদন নেই", emptyIcon: I.idcard,
    });
    $("#q").addEventListener("input", debounce((e) => { q = e.target.value.trim(); lp.reset(); lp.run(); }));
    wireSegment("tg", (s) => { status = s; lp.reset(); lp.run(); });
    lp.run();
  };

  // ---- payment claims ----
  const segment = (id, opts, cur) => `<div class="seg" id="${id}" role="tablist">${opts.map((s) => `<button data-s="${s}" class="${s === cur ? "on" : ""}" role="tab">${s ? STATUS_BN[s] : "সব"}</button>`).join("")}</div>`;
  const wireSegment = (id, onChange) => $$(`#${id} button`).forEach((b) => b.addEventListener("click", () => { $$(`#${id} button`).forEach((x) => x.classList.toggle("on", x === b)); onChange(b.dataset.s); }));
  pages.claims = async (view) => {
    let status = "pending", q = "";
    const lp = listPage(view, {
      title: "পেমেন্ট ক্লেইম",
      actions: `<div class="search">${I.search}<input class="input" id="q" placeholder="TRX ID, দোকান বা ফোন"></div>${segment("tg", ["pending", "approved", "rejected", ""], status)}`,
      load: (page, fresh) => api("/payment-claims", { query: { status, page, q }, fresh }),
      cols: [
        { key: "created_at", label: "তারিখ", sort: true, cls: "small nowrap", render: (c) => fmtDate(c.created_at, true) },
        { key: "shop_name", label: "দোকান", sort: true, render: (c) => `<div class="title">${esc(c.shop_name || "")}</div><div class="sub mono">${esc(c.phone || "")}</div>` },
        { key: "amount", label: "পরিমাণ", sort: true, cls: "num", render: (c) => money(c.amount) },
        { key: "method", label: "মাধ্যম", sort: true, render: (c) => esc(METHOD_BN[c.method] || c.method) },
        { key: "trx_id", label: "TRX ID", cls: "mono", render: (c) => esc(c.trx_id) + (c.note ? `<div class="sub">${esc(c.note)}</div>` : "") },
        { key: "status", label: "স্ট্যাটাস", sort: true, render: (c) => chip(c.status) },
        { key: "_a", label: "", cls: "actions", render: (c) => c.status === "pending" ? `<button class="btn sm primary" data-approve="${c.id}">অনুমোদন</button> <button class="btn sm" data-reject="${c.id}">বাতিল</button>` : `<span class="small faint">${fmtDate(c.reviewed_at, true)}</span>` },
      ],
      emptyText: "কোনো ক্লেইম নেই", emptyIcon: I.claim,
    });
    view.addEventListener("click", (e) => {
      const ap = e.target.closest("[data-approve]"), rj = e.target.closest("[data-reject]");
      if (ap) {
        const c = lp.items.find((x) => x.id === ap.dataset.approve);
        formModal({ title: `ক্লেইম অনুমোদন — ${c.shop_name}`, submitText: "অনুমোদন",
          intro: `<div class="callout" style="margin-bottom:14px">${money(c.amount)} · ${esc(METHOD_BN[c.method] || c.method)} · TRX ID <span class="mono">${esc(c.trx_id)}</span></div>`,
          fields: [{ name: "months", label: "মাস", type: "number", min: 1, max: 36, value: 1, required: true }, { name: "note", label: "নোট", optional: true, type: "textarea", span: true }],
          onSubmit: async (data, m) => { await api(`/payment-claims/${c.id}/approve`, { method: "POST", body: data }); m.close(); toast("অনুমোদিত"); lp.refresh(); refreshDash(); } });
      } else if (rj) {
        formModal({ title: "ক্লেইম বাতিল", submitText: "বাতিল",
          fields: [{ name: "note", label: "কারণ", hint: "দোকানদার দেখতে পাবে", type: "textarea", optional: true, span: true }],
          onSubmit: async (data, m) => { await api(`/payment-claims/${rj.dataset.reject}/reject`, { method: "POST", body: data }); m.close(); toast("বাতিল হয়েছে"); lp.refresh(); refreshDash(); } });
      }
    });
    $("#q").addEventListener("input", debounce((e) => { q = e.target.value.trim(); lp.reset(); lp.run(); }));
    wireSegment("tg", (s) => { status = s; lp.reset(); lp.run(); });
    lp.run();
  };

  // ---- unlock requests ----
  pages.unlocks = async (view) => {
    let status = "open", q = "";
    const lp = listPage(view, {
      title: "আনলক রিকোয়েস্ট",
      actions: `<div class="search">${I.search}<input class="input" id="q" placeholder="রিকোয়েস্ট কোড, দোকান বা ফোন"></div>${segment("tg", ["open", "used", "burned", "closed", ""], status)}`,
      extraTop: `<div class="hint small muted">রিকোয়েস্ট কোড মিলিয়ে পরিচয় যাচাই করে আনলক কোড দিন। ৫ বার ভুল হলে রিকোয়েস্ট বার্ন হয়।</div>`,
      load: (page, fresh) => api("/unlock-requests", { query: { status, page, q }, fresh }),
      cols: [
        { key: "created_at", label: "সময়", sort: true, cls: "small nowrap", render: (r) => fmtDate(r.created_at, true) },
        { key: "shop_name", label: "দোকান", sort: true, render: (r) => `<div class="title">${esc(r.shop_name || "")}</div><div class="sub mono">${esc(r.phone || "")}</div>` },
        { key: "request_code", label: "রিকোয়েস্ট কোড", cls: "mono", render: (r) => esc(r.request_code) },
        { key: "reason", label: "কারণ", sort: true, render: (r) => `${esc(REASON_BN[r.reason] || r.reason)}<div class="sub mono">${esc(r.device_id.slice(0, 18))} · v${esc(r.app_version || "—")}</div>${r.details ? `<div class="sub">${esc(r.details)}</div>` : ""}` },
        { key: "unlock_code", label: "আনলক কোড", render: (r) => `<span class="row"><span class="code-big">${esc(r.unlock_code)}</span><button class="btn sm icon" data-copy="${esc(r.unlock_code)}" title="কপি" aria-label="কপি">${I.copy}</button></span>` },
        { key: "attempts", label: "চেষ্টা", sort: true, cls: "num", render: (r) => `${bn(r.attempts)}/৫` },
        { key: "status", label: "স্ট্যাটাস", sort: true, render: (r) => chip(r.status) + (r.used_at ? `<div class="sub">${fmtDate(r.used_at, true)}</div>` : "") },
        { key: "_a", label: "", cls: "actions", render: (r) => r.status === "open" ? `<button class="btn sm" data-close-req="${r.id}">বন্ধ করুন</button>` : "" },
      ],
      emptyText: "কোনো আনলক রিকোয়েস্ট নেই", emptyIcon: I.lock,
    });
    view.addEventListener("click", async (e) => {
      const cp = e.target.closest("[data-copy]"), cl = e.target.closest("[data-close-req]");
      if (cp) return copy(cp.dataset.copy);
      if (cl) {
        if (!(await confirmDialog({ title: "রিকোয়েস্ট বন্ধ করুন", text: "এই কোড আর কাজ করবে না। ডিভাইস লকই থাকবে।", okText: "বন্ধ করুন", danger: true }))) return;
        try { await api(`/unlock-requests/${cl.dataset.closeReq}/close`, { method: "POST" }); toast("বন্ধ হয়েছে"); lp.refresh(); refreshDash(); } catch (err) { toast(errMsg(err), "error"); }
      }
    });
    $("#q").addEventListener("input", debounce((e) => { q = e.target.value.trim(); lp.reset(); lp.run(); }));
    wireSegment("tg", (s) => { status = s; lp.reset(); lp.run(); });
    lp.run();
  };

  // ---- plans ----
  pages.plans = async (view) => {
    setTitle("প্ল্যান", "Subscription plans");
    let currentView = localStorage.getItem("plans_view_mode") || "cards";
    let plansData = null;

    const render = () => {
      if (!plansData) {
        view.innerHTML = pageHeader("প্ল্যান", "") +
          `<div class="plans-kpi-grid">${Array.from({ length: 4 }, () => `<div class="plan-kpi-card"><span class="sk w40"></span><span class="sk tall w60"></span></div>`).join("")}</div>` +
          `<div class="card" style="padding:28px">${skeleton(4)}</div>`;
        return;
      }

      const items = plansData.items || [];
      const total = items.length;
      const active = items.filter((p) => p.is_active).length;
      const inactive = total - active;
      const avgPrice = total ? Math.round(items.reduce((s, p) => s + p.price_bdt, 0) / total) : 0;
      const minDays = total ? Math.min(...items.map((p) => p.period_days)) : 0;
      const maxDays = total ? Math.max(...items.map((p) => p.period_days)) : 0;

      const actions = `
        <div class="view-switch-seg" role="group" aria-label="ভিউ পরিবর্তন">
          <button class="view-btn ${currentView === "cards" ? "active" : ""}" id="v-cards" type="button">
            ${I.grid} <span>কার্ড</span>
          </button>
          <button class="view-btn ${currentView === "table" ? "active" : ""}" id="v-table" type="button">
            ${I.table} <span>টেবিল</span>
          </button>
        </div>
        <button class="btn primary" id="add-plan">${I.plus} প্ল্যান যোগ করুন</button>
      `;

      const kpisHtml = `
        <div class="plans-kpi-grid">
          <div class="plan-kpi-card">
            <div class="kpi-icon brand">${I.plan}</div>
            <div class="kpi-info">
              <span class="kpi-label">মোট প্ল্যান</span>
              <div class="kpi-val">${bn(total)}</div>
            </div>
          </div>
          <div class="plan-kpi-card">
            <div class="kpi-icon ok">${I.check}</div>
            <div class="kpi-info">
              <span class="kpi-label">সক্রিয়</span>
              <div class="kpi-val">${bn(active)}</div>
            </div>
          </div>
          <div class="plan-kpi-card">
            <div class="kpi-icon info">${I.money}</div>
            <div class="kpi-info">
              <span class="kpi-label">গড় মূল্য</span>
              <div class="kpi-val">${money(avgPrice)}</div>
            </div>
          </div>
          <div class="plan-kpi-card">
            <div class="kpi-icon warn">${I.clock}</div>
            <div class="kpi-info">
              <span class="kpi-label">মেয়াদ</span>
              <div class="kpi-val">${total ? bn(minDays) + (minDays !== maxDays ? "–" + bn(maxDays) : "") : "০"} <span class="kpi-unit">দিন</span></div>
            </div>
          </div>
        </div>
      `;

      let contentHtml = "";

      if (!items.length) {
        contentHtml = `
          <div class="card" style="margin-top:10px">
            <div class="empty">
              <div class="ico">${I.plan}</div>
              <h4>কোনো প্ল্যান নেই</h4>
              <button class="btn primary" id="add-first-plan" style="margin-top:16px">${I.plus} প্ল্যান যোগ করুন</button>
            </div>
          </div>`;
      } else if (currentView === "cards") {
        contentHtml = `
          <div class="plans-grid">
            ${items.map((p) => {
              const daily = Math.round(p.price_bdt / Math.max(1, p.period_days));
              return `
                <div class="plan-card ${p.is_active ? "is-active" : "is-inactive"}">
                  <div class="plan-card-header">
                    <div><h3 class="plan-title">${esc(p.name)}</h3><div class="plan-id-sub mono">${esc(p.id.slice(0, 8))}</div></div>
                    ${p.is_active ? chip("active") : '<span class="chip disabled">নিষ্ক্রিয়</span>'}
                  </div>
                  <div class="plan-price-main">
                    <span class="currency">৳</span>
                    <span class="amount">${bn(p.price_bdt.toLocaleString("en-US"))}</span>
                    <span class="period">/ ${bn(p.period_days)} দিন</span>
                  </div>
                  <div class="plan-specs-box">
                    <div class="spec-row"><span>দৈনিক</span><span class="spec-val">${money(daily)}</span></div>
                    <div class="spec-row"><span>তৈরি</span><span class="spec-val">${fmtDate(p.created_at)}</span></div>
                  </div>
                  <div class="plan-card-footer">
                    <button class="btn sm" data-edit="${p.id}">সম্পাদনা</button>
                    <button class="btn sm ${p.is_active ? "danger" : ""}" data-toggle="${p.id}">${p.is_active ? "নিষ্ক্রিয় করুন" : "সক্রিয় করুন"}</button>
                  </div>
                </div>
              `;
            }).join("")}
          </div>
        `;
      } else {
        contentHtml = `
          <div class="card plans-table-card">
            <div class="list-info">
              <span>মোট ${bn(total)}</span>
              <span>সক্রিয় ${bn(active)} · নিষ্ক্রিয় ${bn(inactive)}</span>
            </div>
            <div class="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>প্ল্যান</th>
                    <th class="num">মূল্য</th>
                    <th class="num">মেয়াদ</th>
                    <th class="num">দৈনিক</th>
                    <th>স্ট্যাটাস</th>
                    <th class="nowrap">তৈরি</th>
                    <th class="actions"></th>
                  </tr>
                </thead>
                <tbody>
                  ${items.map((p) => {
                    const daily = Math.round(p.price_bdt / Math.max(1, p.period_days));
                    return `
                      <tr>
                        <td>
                          <div class="title">${esc(p.name)}</div>
                          <div class="sub mono">${esc(p.id.slice(0, 8))}</div>
                        </td>
                        <td class="num">${money(p.price_bdt)}</td>
                        <td class="num">${bn(p.period_days)} দিন</td>
                        <td class="num muted">${money(daily)}</td>
                        <td>${p.is_active ? '<span class="chip active">সক্রিয়</span>' : '<span class="chip disabled">নিষ্ক্রিয়</span>'}</td>
                        <td class="small muted nowrap">${fmtDate(p.created_at)}</td>
                        <td class="actions">
                          <button class="btn sm" data-edit="${p.id}">সম্পাদনা</button>
                          <button class="btn sm ${p.is_active ? "danger" : ""}" data-toggle="${p.id}">${p.is_active ? "নিষ্ক্রিয় করুন" : "সক্রিয় করুন"}</button>
                        </td>
                      </tr>
                    `;
                  }).join("")}
                </tbody>
              </table>
            </div>
          </div>
        `;
      }

      view.innerHTML = pageHeader("প্ল্যান", "", actions) + kpisHtml + contentHtml;

      $("#v-cards")?.addEventListener("click", () => {
        currentView = "cards";
        localStorage.setItem("plans_view_mode", "cards");
        render();
      });
      $("#v-table")?.addEventListener("click", () => {
        currentView = "table";
        localStorage.setItem("plans_view_mode", "table");
        render();
      });
      $("#add-plan")?.addEventListener("click", () => planForm(null, reload));
      $("#add-first-plan")?.addEventListener("click", () => planForm(null, reload));

      $$("[data-edit]", view).forEach((btn) => {
        btn.addEventListener("click", () => {
          const id = btn.dataset.edit;
          const pl = items.find((x) => x.id === id);
          if (pl) planForm(pl, reload);
        });
      });

      $$("[data-toggle]", view).forEach((btn) => {
        btn.addEventListener("click", async () => {
          const id = btn.dataset.toggle;
          const pl = items.find((x) => x.id === id);
          if (!pl) return;
          const newStatus = !pl.is_active;
          btn.disabled = true;
          try {
            await api(`/plans/${id}`, { method: "PATCH", body: { is_active: newStatus } });
            toast(newStatus ? "সক্রিয় হয়েছে" : "নিষ্ক্রিয় হয়েছে");
            reload();
          } catch (err) {
            toast(errMsg(err), "error");
            btn.disabled = false;
          }
        });
      });
    };

    const reload = async (fresh = true) => {
      try {
        plansData = await api("/plans", { query: { page_size: 100 }, fresh });
        render();
      } catch (err) {
        view.innerHTML = pageHeader("প্ল্যান") + errState(err, "retry-plans");
        $("#retry-plans")?.addEventListener("click", () => reload(true));
      }
    };

    render();
    await reload(false);
  };

  const planForm = (pl, refresh) => formModal({
    title: pl ? "প্ল্যান সম্পাদনা" : "প্ল্যান যোগ করুন",
    submitText: pl ? "সংরক্ষণ" : "যোগ করুন",
    fields: [
      { name: "name", label: "নাম", placeholder: "যেমন: স্ট্যান্ডার্ড", value: pl?.name || "", required: true, maxlength: 100, span: true },
      { name: "price_bdt", label: "মূল্য (৳)", type: "number", min: 0, value: pl?.price_bdt ?? 300, required: true },
      { name: "period_days", label: "মেয়াদ (দিন)", type: "number", min: 1, value: pl?.period_days ?? 30, required: true },
      { name: "is_active", label: "স্ট্যাটাস", type: "select", value: String(pl?.is_active ?? true), options: [{ value: "true", label: "সক্রিয়" }, { value: "false", label: "নিষ্ক্রিয়" }] },
    ],
    onSubmit: async (data, m) => {
      data.is_active = data.is_active === "true";
      await api(pl ? `/plans/${pl.id}` : "/plans", { method: pl ? "PATCH" : "POST", body: data });
      m.close();
      toast("সংরক্ষিত");
      refresh();
    },
  });

  // ---- notifications ----
  pages.notifications = async (view) => {
    const lp = listPage(view, {
      title: "নোটিফিকেশন",
      actions: `<button class="btn primary" id="bc">${I.plus} সবাইকে পাঠান</button>`,
      load: (page, fresh) => api("/notifications", { query: { page }, fresh }),
      cols: [
        { key: "created_at", label: "তারিখ", sort: true, cls: "small nowrap", render: (n) => fmtDate(n.created_at, true) },
        { key: "kind", label: "ধরন", sort: true, render: (n) => chip(n.kind) },
        { key: "title_bn", label: "শিরোনাম", sort: true, render: (n) => `<div class="title">${esc(n.title_bn)}</div><div class="sub">${esc(n.body_bn.slice(0, 140))}</div>` },
        { key: "shop_id", label: "প্রাপক", cls: "small", render: (n) => n.shop_id ? `<span class="mono">${esc(n.shop_id.slice(0, 8))}</span>${n.read_at ? " · পড়েছে" : ""}` : "সবাই" },
      ],
      emptyText: "কোনো নোটিফিকেশন নেই", emptyIcon: I.bell,
    });
    $("#bc").addEventListener("click", () => sendNotification(null));
    lp.run();
  };

  // ---- admins ----
  pages.admins = async (view) => {
    if (!isSuper()) { setTitle("অ্যাডমিন", "Admins"); view.innerHTML = pageHeader("অ্যাডমিন") + `<div class="callout">শুধু সুপার অ্যাডমিনের জন্য</div>`; return; }
    const lp = listPage(view, {
      title: "অ্যাডমিন",
      actions: `<button class="btn primary" id="add">${I.plus} অ্যাডমিন যোগ করুন</button>`,
      load: (page, fresh) => api("/admins", { query: { page_size: 100 }, fresh }),
      cols: [
        { key: "email", label: "Email", sort: true, render: (a) => `<span class="title">${esc(a.email)}</span>${a.id === state.admin.id ? ' <span class="small faint">(আপনি)</span>' : ""}` },
        { key: "role", label: "রোল", sort: true, render: (a) => chip(a.role) },
        { key: "is_active", label: "স্ট্যাটাস", sort: true, render: (a) => (a.is_active ? chip("active") : chip("disabled").replace("বন্ধ", "নিষ্ক্রিয়")) + (a.locked_until && new Date(a.locked_until) > new Date() ? " " + chip("locked") : "") },
        { key: "last_login_at", label: "শেষ লগইন", sort: true, cls: "small nowrap", render: (a) => fmtDate(a.last_login_at, true) },
        { key: "_a", label: "", cls: "actions", render: (a) => `<button class="btn sm" data-edit="${a.id}">সম্পাদনা</button>` },
      ],
      emptyText: "কোনো অ্যাডমিন নেই", emptyIcon: I.users,
    });
    view.addEventListener("click", (e) => { const b = e.target.closest("[data-edit]"); if (b) adminForm(lp.items.find((x) => x.id === b.dataset.edit), () => lp.refresh()); });
    $("#add").addEventListener("click", () => adminForm(null, () => lp.refresh()));
    lp.run();
  };
  const adminForm = (a, refresh) => formModal({
    title: a ? "অ্যাডমিন সম্পাদনা" : "অ্যাডমিন যোগ করুন", submitText: a ? "সংরক্ষণ" : "যোগ করুন", fields: [
      ...(a ? [] : [{ name: "email", label: "Email", type: "email", required: true, span: true }]),
      { name: "password", label: a ? "নতুন পাসওয়ার্ড" : "পাসওয়ার্ড", hint: "কমপক্ষে ১০ অক্ষর, একটি বড় হাতের অক্ষর ও একটি সংখ্যা", type: "password", kind: "adminpw", required: !a, optional: !!a, span: true },
      { name: "role", label: "রোল", type: "select", value: a?.role || "staff", options: [{ value: "staff", label: "স্টাফ" }, { value: "superadmin", label: "সুপার অ্যাডমিন" }] },
      ...(a ? [{ name: "is_active", label: "স্ট্যাটাস", type: "select", value: String(a.is_active), options: [{ value: "true", label: "সক্রিয়" }, { value: "false", label: "নিষ্ক্রিয়" }] },
              { name: "unlock", label: "লকআউট তুলুন", type: "select", value: "false", options: [{ value: "false", label: "না" }, { value: "true", label: "হ্যাঁ" }] }] : []),
    ],
    onSubmit: async (data, m) => {
      if (a) { data.is_active = data.is_active === "true"; data.unlock = data.unlock === "true"; if (!data.unlock) delete data.unlock; }
      await api(a ? `/admins/${a.id}` : "/admins", { method: a ? "PATCH" : "POST", body: data }); m.close(); toast("সংরক্ষিত"); refresh();
    },
  });

  // ---- settings ----
  pages.settings = async (view) => {
    setTitle("সেটিংস", "Settings");
    view.innerHTML = pageHeader("সেটিংস") + `<div class="grid-2"><div class="card">${skeleton(4)}</div><div class="card">${skeleton(3)}</div></div>`;
    try {
      const s = await api("/settings"); const ro = !isSuper();
      const fields = [
        { name: "bkash_number", label: "বিকাশ নম্বর", value: s.bkash_number, kind: "phone", optional: true, maxlength: 11, disabled: ro },
        { name: "nagad_number", label: "নগদ নম্বর", value: s.nagad_number, kind: "phone", optional: true, maxlength: 11, disabled: ro },
        { name: "support_phone", label: "সাপোর্ট ফোন", value: s.support_phone, kind: "phone", optional: true, maxlength: 11, disabled: ro },
        { name: "instructions_bn", label: "পেমেন্ট নির্দেশনা", type: "textarea", value: s.instructions_bn, optional: true, hint: "অ্যাপে দেখানো হয়", disabled: ro },
        { name: "trial_days", label: "ট্রায়াল (দিন)", type: "number", min: 0, max: 365, value: s.trial_days, required: true, disabled: ro },
        { name: "grace_days", label: "গ্রেস পিরিয়ড (দিন)", type: "number", min: 0, max: 90, value: s.grace_days, required: true, hint: "এর পর দোকান স্থগিত হয়", disabled: ro },
        { name: "reminder_days_before", label: "রিমাইন্ডার (দিন আগে)", type: "number", min: 0, max: 30, value: s.reminder_days_before, required: true, disabled: ro },
        { name: "popup_every_minutes", label: "পেমেন্ট পপআপ (মিনিট পর পর)", type: "number", min: 1, max: 1440, value: s.popup_every_minutes ?? 30, required: true, hint: "বকেয়া থাকলে অ্যাপে কতক্ষণ পর পর পপআপ দেখাবে", disabled: ro },
      ];
      const f = (n) => fieldHtml(fields.find((x) => x.name === n));
      $("#view").innerHTML = pageHeader("সেটিংস", "", ro ? "" : `<button class="btn primary" type="submit" form="sf">সংরক্ষণ</button>`) + `
        ${ro ? `<div class="callout">শুধু সুপার অ্যাডমিন সেটিংস পরিবর্তন করতে পারেন</div>` : ""}
        <form id="sf" class="grid-2" novalidate>
          <div class="card"><div class="card-h" style="--dot:#2563EB"><h3>পেমেন্ট তথ্য</h3></div><div class="card-b stack">${f("bkash_number")}${f("nagad_number")}${f("support_phone")}${f("instructions_bn")}</div></div>
          <div class="stack">
            <div class="card"><div class="card-h" style="--dot:#F59E0B"><h3>সাবস্ক্রিপশন নিয়ম</h3></div><div class="card-b stack">${f("trial_days")}${f("grace_days")}${f("reminder_days_before")}${f("popup_every_minutes")}<div class="hint small faint">শেষ আপডেট: ${fmtDate(s.updated_at, true)}</div></div></div>
            <div class="card"><div class="card-h" style="--dot:#7C3AED"><h3>About</h3></div><div class="card-b"><dl class="kv"><dt>ভার্সন</dt><dd class="mono">${esc(VERSION)}</dd><dt>হোস্ট</dt><dd class="mono">${esc(location.host)}</dd><dt>API</dt><dd class="mono">${esc(API)}</dd></dl></div></div>
          </div>
        </form>`;
      const form = $("#sf");
      form.addEventListener("input", (e) => { e.target.closest(".field")?.classList.remove("invalid"); e.target.classList.remove("invalid"); });
      form.addEventListener("submit", async (e) => {
        e.preventDefault(); if (ro) return;
        const data = readForm(form, fields); if (!data) { $(".field.invalid .input", form)?.focus(); return; }
        fields.forEach((x) => { if (x.optional && data[x.name] === undefined) data[x.name] = null; });
        try { await api("/settings", { method: "PATCH", body: data }); toast("সংরক্ষিত"); } catch (err) { toast(errMsg(err), "error"); }
      });
    } catch (e) { $("#view").innerHTML = pageHeader("সেটিংস") + errState(e, "retry"); $("#retry")?.addEventListener("click", () => pages.settings(view)); }
  };

  // ---- audit ----
  pages.audit = async (view) => {
    let q = "";
    const lp = listPage(view, {
      title: "অডিট লগ",
      actions: `<div class="search">${I.search}<input class="input" id="q" placeholder="action বা ID"></div>`,
      load: (page, fresh) => api("/audit-logs", { query: { page, q, page_size: 50 }, fresh }),
      cols: [
        { key: "created_at", label: "সময়", sort: true, cls: "small nowrap", render: (a) => fmtDate(a.created_at, true) },
        { key: "action", label: "কার্যক্রম", sort: true, render: (a) => `<div class="title">${esc(ACTION_BN[a.action] || a.action)}</div><div class="sub mono">${esc(a.action)}</div>` },
        { key: "actor_type", label: "অ্যাক্টর", sort: true, cls: "small", render: (a) => `${esc(a.actor_type)}<div class="mono faint">${esc((a.actor_id || "").slice(0, 8))}</div>` },
        { key: "target_type", label: "টার্গেট", sort: true, cls: "small", render: (a) => `${esc(a.target_type || "")}<div class="mono faint">${esc((a.target_id || "").slice(0, 14))}</div>` },
        { key: "ip", label: "IP", cls: "mono small", render: (a) => esc(a.ip || "") },
        { key: "meta", label: "বিবরণ", cls: "small mono", render: (a) => `<div style="max-width:320px;word-break:break-all">${a.meta ? esc(JSON.stringify(a.meta)) : ""}</div>` },
      ],
      emptyText: "কোনো লগ নেই", emptyIcon: I.list,
    });
    $("#q").addEventListener("input", debounce((e) => { q = e.target.value.trim(); lp.reset(); lp.run(); }));
    lp.run();
  };

  // ---------- router ----------
  function parseHash() {
    const h = location.hash.replace(/^#\/?/, "") || "dashboard";
    const [path, qs] = h.split("?"); const params = Object.fromEntries(new URLSearchParams(qs || ""));
    return { route: pages[path] ? path : "dashboard", params };
  }
  async function route() {
    if (!state.admin) return renderLogin();
    const { route: r, params } = parseHash(); state.route = r; state.params = params;
    if (!$("#view")) renderShell();
    $$("[data-nav]").forEach((a) => a.classList.toggle("active", a.dataset.nav === r));
    const view = $("#view"); view.innerHTML = "";
    await pages[r](view, params);
    window.scrollTo(0, 0);
  }
  window.addEventListener("hashchange", route);

  async function boot(fresh = false) {
    try {
      const me = await api("/auth/me", { fresh: true }); state.admin = me.admin; state.csrf = me.csrf_token; sessionStorage.setItem("csrf", me.csrf_token);
      renderShell(); await route(); refreshDash(false);
    } catch { if (!fresh) renderLogin(); }
  }
  boot();
})();
