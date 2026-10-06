from __future__ import annotations

from tests.conftest import SHOP_PHONE, app_login, device_payload


async def test_login_success_returns_tokens_and_license(client, shop):
    r = await app_login(client)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["token_type"] == "bearer"
    assert data["license"]["status"] == "trial"
    assert data["shop"]["phone"] == SHOP_PHONE
    assert data["shop"]["plan"]["price_bdt"] == 300
    assert "ledger" in data["license"]["features"]


async def test_login_wrong_password_and_unknown_phone_identical(client, shop):
    r1 = await app_login(client, password="wrong12")
    r2 = await app_login(client, phone="01999999999", password="wrong12")
    assert r1.status_code == r2.status_code == 401
    assert r1.json()["detail"] == r2.json()["detail"]


async def test_login_rejects_unknown_fields(client, shop):
    r = await client.post("/api/v1/app/auth/login", json={"phone": SHOP_PHONE, "password": "secret6", "device": device_payload(), "customers": []})
    assert r.status_code == 422


async def test_login_rejects_invalid_bd_phone(client, shop):
    r = await client.post("/api/v1/app/auth/login", json={"phone": "12345", "password": "secret6", "device": device_payload()})
    assert r.status_code == 422


async def test_second_device_conflict(client, shop):
    assert (await app_login(client, device_id="dev-one-0001")).status_code == 200
    r = await app_login(client, device_id="dev-two-0002")
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "DEVICE_CONFLICT"


async def test_me_and_license_with_bearer(client, shop):
    tok = (await app_login(client)).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}
    r = await client.get("/api/v1/app/me", headers=h)
    assert r.status_code == 200
    assert r.json()["license"]["status"] == "trial"
    assert r.json()["notifications"] == []
    r = await client.get("/api/v1/app/license", headers=h)
    assert r.status_code == 200
    assert r.json()["grace_days"] == 10
    assert (await client.get("/api/v1/app/me")).status_code == 401


async def test_refresh_rotation_and_reuse_detection(client, shop):
    first = (await app_login(client)).json()
    r = await client.post("/api/v1/app/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert r.status_code == 200
    second = r.json()
    assert second["refresh_token"] != first["refresh_token"]
    # reuse of the old token -> family revoked
    r = await client.post("/api/v1/app/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert r.status_code == 401
    assert r.json()["detail"]["code"] == "REFRESH_REUSED"
    # the newest token is now revoked too
    r = await client.post("/api/v1/app/auth/refresh", json={"refresh_token": second["refresh_token"]})
    assert r.status_code == 401


async def test_logout_revokes_refresh(client, shop):
    data = (await app_login(client)).json()
    r = await client.post("/api/v1/app/auth/logout", headers={"Authorization": f"Bearer {data['access_token']}"})
    assert r.status_code == 204
    r = await client.post("/api/v1/app/auth/refresh", json={"refresh_token": data["refresh_token"]})
    assert r.status_code == 401


async def test_login_rate_limited(client, shop, rate_limited):
    codes = []
    for _ in range(7):
        codes.append((await app_login(client, password="badpass1")).status_code)
    assert codes[:5] == [401] * 5
    assert 429 in codes[5:]


async def test_disabled_shop_cannot_login(client, db, shop):
    shop.is_disabled = True
    await db.commit()
    r = await app_login(client)
    assert r.status_code == 403
    assert r.json()["detail"]["code"] == "ACCOUNT_DISABLED"
