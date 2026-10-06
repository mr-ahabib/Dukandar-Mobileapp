"""Dashboard grouped query, revenue series, SQL status filter and static caching headers."""
from __future__ import annotations

from datetime import timedelta

from app.core.security import hash_password, now_utc
from app.db import models as m
from tests.conftest import admin_login


async def _mk(db, plan, phone, **extra):
    s = m.Shop(shop_name="S" + phone[-2:], owner_name="O", phone=phone, password_hash=hash_password("x"), plan_id=plan.id, **extra)
    db.add(s)
    return s


async def test_dashboard_counts_match_statuses_and_mrr(client, db, plan, superadmin):
    now = now_utc()
    await _mk(db, plan, "01711111101", trial_ends_at=now + timedelta(days=5))                      # trial
    await _mk(db, plan, "01711111102", paid_until=now + timedelta(days=20))                        # active
    await _mk(db, plan, "01711111103", paid_until=now - timedelta(days=2))                         # due (grace 10)
    await _mk(db, plan, "01711111104", paid_until=now - timedelta(days=40))                        # suspended
    await _mk(db, plan, "01711111105", paid_until=now + timedelta(days=20), is_disabled=True)      # disabled
    await _mk(db, plan, "01711111106", trial_ends_at=now - timedelta(days=3))                      # due (trial grace)
    await db.commit()
    await admin_login(client)
    d = (await client.get("/admin/api/dashboard")).json()
    assert d["total_shops"] == 6 and d["trial"] == 1 and d["active"] == 1 and d["due"] == 2 and d["suspended"] == 1 and d["disabled"] == 1
    assert d["mrr_bdt"] == 300

    for status, expected in (("active", 1), ("due", 2), ("disabled", 1), ("trial", 1), ("suspended", 1)):
        r = (await client.get(f"/admin/api/shops?status_filter={status}")).json()
        assert r["total"] == expected, status
        assert all(i["status"] == status for i in r["items"])


async def test_revenue_series(client, db, shop, superadmin):
    now = now_utc()
    for amount, when in ((300, now), (600, now), (300, now - timedelta(days=65))):
        db.add(m.Payment(shop_id=shop.id, amount_bdt=amount, method="bkash", months=1, paid_from=when, paid_until=when, created_at=when))
    await db.commit()
    await admin_login(client)
    r = await client.get("/admin/api/dashboard/revenue?months=6")
    assert r.status_code == 200
    rows = r.json()
    assert len(rows) == 6 and rows[-1]["month"] == now.strftime("%Y-%m")
    assert rows[-1]["total_bdt"] == 900 and rows[-1]["payments"] == 2
    assert sum(x["total_bdt"] for x in rows) == 1200
    assert (await client.get("/admin/api/dashboard/revenue?months=0")).status_code == 422


async def test_admin_static_caching_headers(client):
    r = await client.get("/admin/")
    assert r.status_code == 200 and "__V__" not in r.text and "?v=" in r.text
    assert r.headers["cache-control"] == "no-cache"
    r = await client.get("/admin/app.js?v=abc")
    assert r.status_code == 200 and "immutable" in r.headers["cache-control"]
    r = await client.get("/admin/app.js")
    assert "must-revalidate" in r.headers["cache-control"]
    assert (await client.get("/healthz")).headers["content-type"].startswith("application/json")
