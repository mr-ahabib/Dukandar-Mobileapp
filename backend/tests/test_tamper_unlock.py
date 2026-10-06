from __future__ import annotations

from sqlalchemy import select

from app.db.models import AuditLog, UnlockRequest
from tests.conftest import SHOP_PHONE, admin_login, app_login

DEV = "dev-abc-123"


async def _tamper(client, reason="ROOT_DETECTED", phone=SHOP_PHONE, device_id=DEV):
    body = {"phone": phone, "device_id": device_id, "reason": reason, "details": "su found", "app_version": "1.0.0"}
    return await client.post("/api/v1/app/tamper-report", json=body)


async def test_tamper_locks_device_and_login_returns_423(client, db, shop):
    assert (await app_login(client)).status_code == 200
    r = await _tamper(client)
    assert r.status_code == 200
    body = r.json()
    assert body["locked"] is True and body["unlock_request_id"].startswith("UL-") and len(body["unlock_request_id"]) == 9
    # idempotent
    r2 = await _tamper(client)
    assert r2.json()["unlock_request_id"] == body["unlock_request_id"]
    r = await app_login(client)
    assert r.status_code == 423
    assert r.json()["detail"]["code"] == "DEVICE_LOCKED"
    assert r.json()["detail"]["unlock_request_id"] == body["unlock_request_id"]
    assert await db.scalar(select(AuditLog).where(AuditLog.action == "tamper.locked")) is not None


async def test_tamper_unknown_phone_does_not_leak(client, shop):
    r = await _tamper(client, phone="01999999999")
    assert r.status_code == 200 and r.json()["locked"] is True


async def test_unlock_flow_with_wrong_code_burn(client, db, shop, superadmin):
    await app_login(client)
    req_code = (await _tamper(client)).json()["unlock_request_id"]
    # Admin reads the code in the panel
    await admin_login(client)
    r = await client.get("/admin/api/unlock-requests?status=open")
    assert r.status_code == 200
    item = r.json()["items"][0]
    assert item["request_code"] == req_code and len(item["unlock_code"]) == 8
    real = item["unlock_code"]
    wrong = "00000000" if real != "00000000" else "11111111"

    def payload(code):
        return {"phone": SHOP_PHONE, "device_id": DEV, "unlock_request_id": req_code, "unlock_code": code}

    r = await client.post("/api/v1/app/unlock", json=payload(wrong))
    assert r.status_code == 400 and r.json()["detail"]["attempts_left"] == 4
    r = await client.post("/api/v1/app/unlock", json=payload(real))
    assert r.status_code == 200 and r.json() == {"unlocked": True}
    assert (await app_login(client)).status_code == 200
    # a used code can't be reused
    assert (await client.post("/api/v1/app/unlock", json=payload(real))).status_code == 400

    # second lock -> burn after 5 wrong attempts
    req2 = (await _tamper(client, reason="DEBUGGER")).json()["unlock_request_id"]
    assert req2 != req_code
    row = await db.scalar(select(UnlockRequest).where(UnlockRequest.request_code == req2))
    real2 = row.unlock_code
    wrong2 = "00000000" if real2 != "00000000" else "11111111"
    for _ in range(5):
        r = await client.post("/api/v1/app/unlock", json={**payload(wrong2), "unlock_request_id": req2})
        assert r.status_code == 400
    assert r.json()["detail"]["code"] == "REQUEST_BURNED"
    # even the real code no longer works
    r = await client.post("/api/v1/app/unlock", json={**payload(real2), "unlock_request_id": req2})
    assert r.status_code == 400
    await db.refresh(row)
    assert row.status == "burned"
    # a fresh tamper report issues a new open request
    req3 = (await _tamper(client)).json()["unlock_request_id"]
    assert req3 not in (req_code, req2)


async def test_admin_close_and_device_reset(client, db, shop, superadmin):
    await app_login(client)
    await _tamper(client)
    csrf = await admin_login(client)
    item = (await client.get("/admin/api/unlock-requests?status=open")).json()["items"][0]
    r = await client.post(f"/admin/api/unlock-requests/{item['id']}/close", headers={"X-CSRF-Token": csrf})
    assert r.status_code == 200 and r.json()["status"] == "closed"
    # device still locked; admin resets device -> shop can bind a new device
    r = await client.post(f"/admin/api/shops/{shop.id}/reset-device", headers={"X-CSRF-Token": csrf})
    assert r.status_code == 200 and r.json()["device"] is None
    assert (await app_login(client, device_id="dev-new-9999")).status_code == 200
