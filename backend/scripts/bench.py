#!/usr/bin/env python
"""Latency benchmark against a running server (default http://127.0.0.1:8000).

Hits /healthz, admin login + dashboard + shops list, and app login + /me, N times each (default 200) and prints p50/p95/max.
Usage: python scripts/bench.py [--base URL] [--n 200] [--admin-email E --admin-password P] [--phone 01711111111 --password 123456]
Credentials default to SUPERADMIN_EMAIL/SUPERADMIN_PASSWORD from the environment / .env and the seed_demo shop.
"""
from __future__ import annotations

import argparse
import os
import statistics
import sys
import time
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def _env_default(key: str, fallback: str = "") -> str:
    if os.environ.get(key):
        return os.environ[key]
    env = Path(__file__).resolve().parents[1] / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip()
    return fallback


def timed(client: httpx.Client, n: int, fn) -> list[float]:
    out = []
    for _ in range(n):
        t = time.perf_counter()
        r = fn(client)
        out.append((time.perf_counter() - t) * 1000)
        if r.status_code >= 400:
            raise SystemExit(f"{r.request.method} {r.request.url.path} -> {r.status_code}: {r.text[:200]}")
    return out


def report(name: str, ms: list[float]) -> None:
    ms = sorted(ms)
    p = lambda q: ms[min(len(ms) - 1, int(round(q * (len(ms) - 1))))]  # noqa: E731
    print(f"{name:<34} n={len(ms):<4} p50={statistics.median(ms):6.1f} ms  p95={p(0.95):6.1f} ms  max={ms[-1]:6.1f} ms")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--admin-email", default=_env_default("SUPERADMIN_EMAIL", "admin@example.com"))
    ap.add_argument("--admin-password", default=_env_default("SUPERADMIN_PASSWORD", "ChangeMe12345"))
    ap.add_argument("--phone", default="01711111111")
    ap.add_argument("--password", default="123456")
    a = ap.parse_args()
    device = {"device_id": "bench-device-1", "model": "Bench", "os": "Android 14", "app_version": "1.0.0", "signature_sha256": "ab" * 32}

    with httpx.Client(base_url=a.base, timeout=30) as c:
        print(f"target {a.base}  iterations {a.n}\n")
        report("GET /healthz", timed(c, a.n, lambda c: c.get("/healthz")))

        # admin: login is rate limited (5/min) -> measure a handful, then reuse the session
        login_ms = []
        csrf = None
        for _ in range(3):
            t = time.perf_counter()
            r = c.post("/admin/api/auth/login", json={"email": a.admin_email, "password": a.admin_password})
            login_ms.append((time.perf_counter() - t) * 1000)
            if r.status_code != 200:
                raise SystemExit(f"admin login failed: {r.status_code} {r.text}")
            csrf = r.json()["csrf_token"]
        report("POST /admin/api/auth/login (argon2)", login_ms)
        report("GET /admin/api/dashboard", timed(c, a.n, lambda c: c.get("/admin/api/dashboard")))
        report("GET /admin/api/dashboard/revenue", timed(c, a.n, lambda c: c.get("/admin/api/dashboard/revenue?months=6")))
        report("GET /admin/api/shops?page_size=25", timed(c, a.n, lambda c: c.get("/admin/api/shops?page_size=25")))
        report("GET /admin/api/shops?q=017", timed(c, a.n, lambda c: c.get("/admin/api/shops?q=017&page_size=25")))
        report("GET /admin/api/payment-claims", timed(c, a.n, lambda c: c.get("/admin/api/payment-claims?status=pending")))
        report("GET /admin/api/audit-logs", timed(c, a.n, lambda c: c.get("/admin/api/audit-logs?page_size=50")))
        report("GET /admin/ (index)", timed(c, a.n, lambda c: c.get("/admin/")))
        # Reuse the shop's bound device (if any) so the benchmark never binds/conflicts a real device.
        found = c.get("/admin/api/shops", params={"q": a.phone, "page_size": 1}).json().get("items", [])
        bound = found[0].get("device") if found and found[0].get("phone") == a.phone else None
        if bound:
            device = {k: bound[k] for k in ("device_id", "model", "os", "app_version", "signature_sha256") if bound.get(k)}
        c.post("/admin/api/auth/logout", headers={"X-CSRF-Token": csrf})

        # app: login also rate limited -> 3 samples, then /me and /license with the token
        app_ms, token = [], None
        for _ in range(3):
            t = time.perf_counter()
            r = c.post("/api/v1/app/auth/login", json={"phone": a.phone, "password": a.password, "device": device})
            app_ms.append((time.perf_counter() - t) * 1000)
            if r.status_code != 200:
                raise SystemExit(f"app login failed: {r.status_code} {r.text}\n(hint: pass --phone/--password of a seeded shop; "
                                 "a shop bound to another device is reused automatically when the admin session can see it)")
            token = r.json()["access_token"]
        report("POST /api/v1/app/auth/login (argon2)", app_ms)
        h = {"Authorization": f"Bearer {token}"}
        report("GET /api/v1/app/me", timed(c, a.n, lambda c: c.get("/api/v1/app/me", headers=h)))
        report("GET /api/v1/app/license", timed(c, a.n, lambda c: c.get("/api/v1/app/license", headers=h)))


if __name__ == "__main__":
    main()
