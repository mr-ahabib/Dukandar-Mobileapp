from __future__ import annotations

from datetime import timedelta

from app.core.security import now_utc
from tests.conftest import STAFF_EMAIL, STAFF_PW, SUPER_EMAIL, SUPER_PW, admin_login, app_login


async def test_admin_login_sets_cookie_and_csrf(client, superadmin):
    r = await client.post("/admin/api/auth/login", json={"email": SUPER_EMAIL, "password": SUPER_PW})
    assert r.status_code == 200
    assert "admin_session" in r.cookies
    set_cookie = r.headers["set-cookie"].lower()
    assert "httponly" in set_cookie and "samesite=strict" in set_cookie
    me = await client.get("/admin/api/auth/me")
    assert me.status_code == 200 and me.json()["admin"]["role"] == "superadmin"


async def test_admin_unauthenticated_401(client):
    assert (await client.get("/admin/api/dashboard")).status_code == 401


async def test_admin_lockout_after_8_failures(client, superadmin):
    for _ in range(8):
        r = await client.post("/admin/api/auth/login", json={"email": SUPER_EMAIL, "password": "WrongPassword1"})
        assert r.status_code == 401
    r = await client.post("/admin/api/auth/login", json={"email": SUPER_EMAIL, "password": SUPER_PW})
    assert r.status_code == 423


async def test_admin_login_rate_limit(client, superadmin, rate_limited):
    codes = [(await client.post("/admin/api/auth/login", json={"email": SUPER_EMAIL, "password": "WrongPassword1"})).status_code for _ in range(6)]
    assert codes[-1] == 429


async def test_csrf_enforced_on_mutations(client, superadmin):
    csrf = await admin_login(client)
    body = {"name": "প্রো", "price_bdt": 500, "period_days": 30}
    r = await client.post("/admin/api/plans", json=body)
    assert r.status_code == 403 and r.json()["detail"]["code"] == "CSRF_INVALID"
    r = await client.post("/admin/api/plans", json=body, headers={"X-CSRF-Token": "bogus"})
    assert r.status_code == 403
    r = await client.post("/admin/api/plans", json=body, headers={"X-CSRF-Token": csrf})
    assert r.status_code == 201
    # GET never needs CSRF
    assert (await client.get("/admin/api/plans")).status_code == 200


async def test_rbac_staff_vs_superadmin(client, superadmin, staff):
    csrf = await admin_login(client, STAFF_EMAIL, STAFF_PW)
    h = {"X-CSRF-Token": csrf}
    assert (await client.get("/admin/api/admins")).status_code == 403
    assert (await client.post("/admin/api/admins", json={"email": "x@y.com", "password": "Password1234", "role": "staff"}, headers=h)).status_code == 403
    assert (await client.patch("/admin/api/settings", json={"grace_days": 5}, headers=h)).status_code == 403
    # staff may read settings and manage shops
    assert (await client.get("/admin/api/settings")).status_code == 200
    r = await client.post("/admin/api/shops", json={"shop_name": "দোকান", "owner_name": "মালিক", "phone": "01811111111"}, headers=h)
    assert r.status_code == 201 and len(r.json()["temp_password"]) >= 8
    # superadmin can do admin mgmt
    csrf = await admin_login(client)
    h = {"X-CSRF-Token": csrf}
    r = await client.post("/admin/api/admins", json={"email": "new@y.com", "password": "Password1234", "role": "staff"}, headers=h)
    assert r.status_code == 201
    assert (await client.post("/admin/api/admins", json={"email": "weak@y.com", "password": "short", "role": "staff"}, headers=h)).status_code == 422
    assert (await client.patch("/admin/api/settings", json={"grace_days": 7}, headers=h)).json()["grace_days"] == 7


async def test_record_payment_extends_paid_until(client, db, shop, superadmin):
    csrf = await admin_login(client)
    h = {"X-CSRF-Token": csrf}
    r = await client.post(f"/admin/api/shops/{shop.id}/payments", json={"amount_bdt": 600, "method": "bkash", "trx_id": "TRX1", "months": 2}, headers=h)
    assert r.status_code == 201, r.text
    pay = r.json()
    await db.refresh(shop)
    assert shop.paid_until is not None
    assert abs((shop.paid_until - (now_utc() + timedelta(days=60))).total_seconds()) < 120
    detail = (await client.get(f"/admin/api/shops/{shop.id}")).json()
    assert detail["status"] == "active" and detail["paid_until"] == pay["paid_until"]
    # second payment stacks on top
    await client.post(f"/admin/api/shops/{shop.id}/payments", json={"amount_bdt": 300, "method": "cash", "months": 1}, headers=h)
    await db.refresh(shop)
    assert abs((shop.paid_until - (now_utc() + timedelta(days=90))).total_seconds()) < 120
    hist = (await client.get(f"/admin/api/shops/{shop.id}/payments")).json()
    assert len(hist) == 2
    # shop sees a notification about it
    tok = (await app_login(client)).json()["access_token"]
    me = (await client.get("/api/v1/app/me", headers={"Authorization": f"Bearer {tok}"})).json()
    assert me["license"]["status"] == "active" and any(n["kind"] == "info" for n in me["notifications"])


async def test_payment_claim_approve_flow(client, db, shop, superadmin):
    tok = (await app_login(client)).json()["access_token"]
    r = await client.post("/api/v1/app/payment-claim", json={"method": "nagad", "trx_id": "NG123", "amount": 300, "note": ""},
                          headers={"Authorization": f"Bearer {tok}"})
    assert r.status_code == 201 and r.json()["status"] == "pending"
    cid = r.json()["id"]
    assert (await client.post("/api/v1/app/payment-claim", json={"method": "nagad", "trx_id": "NG123", "amount": 300},
                              headers={"Authorization": f"Bearer {tok}"})).status_code == 409
    csrf = await admin_login(client)
    pending = (await client.get("/admin/api/payment-claims?status=pending")).json()
    assert pending["total"] == 1
    dash = (await client.get("/admin/api/dashboard")).json()
    assert dash["pending_claims"] == 1 and dash["total_shops"] == 1 and dash["trial"] == 1
    r = await client.post(f"/admin/api/payment-claims/{cid}/approve", json={"months": 1}, headers={"X-CSRF-Token": csrf})
    assert r.status_code == 200 and r.json()["status"] == "approved"
    await db.refresh(shop)
    assert shop.paid_until and shop.paid_until > now_utc() + timedelta(days=29)
    assert (await client.post(f"/admin/api/payment-claims/{cid}/reject", headers={"X-CSRF-Token": csrf})).status_code == 409


async def test_shop_crud_disable_reset_password_and_audit(client, db, shop, superadmin):
    csrf = await admin_login(client)
    h = {"X-CSRF-Token": csrf}
    r = await client.patch(f"/admin/api/shops/{shop.id}", json={"address": "মিরপুর"}, headers=h)
    assert r.status_code == 200 and r.json()["address"] == "মিরপুর"
    assert (await client.patch(f"/admin/api/shops/{shop.id}", json={"customers": []}, headers=h)).status_code == 422
    r = await client.post(f"/admin/api/shops/{shop.id}/disable", headers=h)
    assert r.json()["status"] == "disabled"
    assert (await app_login(client)).status_code == 403
    await client.post(f"/admin/api/shops/{shop.id}/enable", headers=h)
    temp = (await client.post(f"/admin/api/shops/{shop.id}/reset-password", headers=h)).json()["temp_password"]
    assert (await app_login(client, password=temp)).status_code == 200
    audit = (await client.get(f"/admin/api/shops/{shop.id}/audit")).json()
    actions = {a["action"] for a in audit}
    assert {"shop.updated", "shop.disabled", "shop.enabled", "shop.password_reset"} <= actions
    logs = (await client.get("/admin/api/audit-logs?q=shop.")).json()
    assert logs["total"] >= 4
    lst = (await client.get("/admin/api/shops?q=রহিম")).json()
    assert lst["total"] == 1


async def test_broadcast_notification_and_read(client, db, shop, superadmin):
    csrf = await admin_login(client)
    body = {"title_bn": "ঈদ মোবারক", "body_bn": "শুভেচ্ছা", "kind": "info"}
    r = await client.post("/admin/api/notifications/broadcast", json=body, headers={"X-CSRF-Token": csrf})
    assert r.status_code == 201
    tok = (await app_login(client)).json()["access_token"]
    ah = {"Authorization": f"Bearer {tok}"}
    notes = (await client.get("/api/v1/app/me", headers=ah)).json()["notifications"]
    assert len(notes) == 1 and notes[0]["read"] is False
    assert (await client.post(f"/api/v1/app/notifications/{notes[0]['id']}/read", headers=ah)).status_code == 204
    notes = (await client.get("/api/v1/app/me", headers=ah)).json()["notifications"]
    assert notes[0]["read"] is True


async def test_security_headers_present(client):
    r = await client.get("/healthz")
    assert r.status_code == 200 and r.json() == {"status": "ok"}
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["x-content-type-options"] == "nosniff"
    assert "default-src 'self'" in r.headers["content-security-policy"]
    assert "max-age" in r.headers["strict-transport-security"]
    assert "access-control-allow-origin" not in r.headers
