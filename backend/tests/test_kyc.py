"""Self-registration with KYC: register, status mapping, admin review, file access, rate limit."""
from __future__ import annotations

import json
import os
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import now_utc
from app.db.models import KycSubmission, Notification, Shop
from app.jobs.daily import run_daily
from app.services.subscription import compute_status
from tests.conftest import SHOP_PHONE, admin_login, app_login, device_payload

REG_PHONE = "01812345678"


@pytest.fixture(autouse=True)
def kyc_tmp_dir(tmp_path, monkeypatch):
    """Store KYC files under a temp dir so tests never touch backend/data."""
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
    get_settings.cache_clear()
    yield tmp_path / "data"
    get_settings.cache_clear()


def jpeg_bytes(size=(64, 64), color=(200, 30, 30)) -> bytes:
    """Minimal JPEG-looking blob: SOI + APP0/JFIF header + payload + EOI (the server validates magic bytes, not decodability)."""
    body = bytes(color) * (size[0] * size[1] // 3 + 1)
    return b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00" + body + b"\xff\xd9"


def png_bytes() -> bytes:
    return b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + b"\x00" * 64


def liveness_payload(**kw) -> str:
    base = {"passed": True, "challenges": ["blink", "turn_left", "smile"], "score": 0.93, "captured_at": now_utc().isoformat()}
    base.update(kw)
    return json.dumps(base)


def reg_form(phone=REG_PHONE, device_id="dev-reg-0001", **over) -> dict:
    data = {
        "shop_name": "করিম স্টোর", "owner_name": "করিম", "phone": phone, "password": "secret6", "address": "মিরপুর",
        "nid_number": "1234567890123", "device": json.dumps(device_payload(device_id)), "liveness": liveness_payload(),
    }
    data.update(over)
    return data


def reg_files(front=None, back=None, selfie=None, frames=()) -> list:
    files = [
        ("nid_front", ("f.jpg", front or jpeg_bytes(), "image/jpeg")),
        ("nid_back", ("b.jpg", back or jpeg_bytes(color=(30, 30, 200)), "image/jpeg")),
        ("selfie", ("s.jpg", selfie or jpeg_bytes(color=(30, 200, 30)), "image/jpeg")),
    ]
    for i, fr in enumerate(frames):
        files.append(("liveness_frames", (f"fr{i}.jpg", fr, "image/jpeg")))
    return files


async def register(client, **kw):
    frames = kw.pop("frames", ())
    files_kw = {k: kw.pop(k) for k in ("front", "back", "selfie") if k in kw}
    return await client.post("/api/v1/app/auth/register", data=reg_form(**kw), files=reg_files(frames=frames, **files_kw))


# ---------------------------------------------------------------- register
async def test_register_success_pending_no_trial_and_files_stored(client, db, plan, kyc_tmp_dir):
    r = await register(client, frames=[jpeg_bytes((16, 16)), jpeg_bytes((16, 16))])
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["access_token"] and body["refresh_token"]
    lic = body["license"]
    assert lic["status"] == "pending_verification"
    assert lic["verification"] == "pending"
    assert lic["trial_ends_at"] is None and lic["paid_until"] is None
    assert lic["payment_popup"]["show"] is False and lic["payment_popup"]["every_minutes"] == 30
    assert body["shop"]["phone"] == REG_PHONE

    shop = await db.scalar(select(Shop).where(Shop.phone == REG_PHONE))
    assert shop.verification == "pending" and shop.trial_ends_at is None and shop.nid_number == "1234567890123"
    assert shop.plan_id == plan.id
    sub = await db.scalar(select(KycSubmission).where(KycSubmission.shop_id == shop.id))
    assert set(sub.files_json) == {"nid_front", "nid_back", "selfie", "frame_0", "frame_1"}
    assert sub.liveness_json["score"] == 0.93 and sub.liveness_json["challenges"] == ["blink", "turn_left", "smile"]
    d = kyc_tmp_dir / "kyc" / str(shop.id)
    for kind in ("nid_front", "nid_back", "selfie", "frame_0", "frame_1"):
        p = d / f"{kind}.jpg"
        assert p.is_file()
        assert oct(p.stat().st_mode & 0o777) == "0o600"
    assert os.listdir(d) and not (d.parent / "public").exists()

    # the token works: /me and /license both carry the verification fields
    h = {"Authorization": f"Bearer {body['access_token']}"}
    me = (await client.get("/api/v1/app/me", headers=h)).json()
    assert me["license"]["status"] == "pending_verification" and me["license"]["verification"] == "pending"
    lic2 = (await client.get("/api/v1/app/license", headers=h)).json()
    assert lic2["status"] == "pending_verification" and "payment_popup" in lic2
    # login with the new credentials also works and reports pending
    r = await app_login(client, phone=REG_PHONE, password="secret6", device_id="dev-reg-0001")
    assert r.status_code == 200 and r.json()["license"]["status"] == "pending_verification"


async def test_register_phone_taken_by_existing_or_pending(client, shop):
    r = await register(client, phone=SHOP_PHONE)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "PHONE_TAKEN"
    assert (await register(client)).status_code == 201
    r = await register(client, device_id="dev-reg-0002")
    assert r.status_code == 409 and r.json()["detail"]["code"] == "PHONE_TAKEN"


async def test_register_oversize_image_rejected(client, db):
    big = jpeg_bytes() + b"\0" * (3 * 1024 * 1024)
    r = await register(client, front=big)
    assert r.status_code == 413, r.text
    assert r.json()["detail"]["code"] == "FILE_TOO_LARGE" and r.json()["detail"]["field"] == "nid_front"
    # frames have a 1MB cap
    r = await register(client, frames=[jpeg_bytes() + b"\0" * (1024 * 1024 + 10)])
    assert r.status_code == 413
    assert await db.scalar(select(Shop).where(Shop.phone == REG_PHONE)) is None


async def test_register_bad_mime_rejected_png_allowed(client):
    r = await register(client, selfie=b"GIF89a" + b"\0" * 100)
    assert r.status_code == 422 and r.json()["detail"]["code"] == "BAD_IMAGE"
    r = await register(client, selfie=b"<html>not an image</html>")
    assert r.status_code == 422
    assert (await register(client, selfie=png_bytes())).status_code == 201


async def test_register_validation_errors(client):
    assert (await register(client, nid_number="12345")).status_code == 422
    assert (await register(client, phone="12345")).status_code == 422
    assert (await register(client, password="123")).status_code == 422
    assert (await register(client, liveness=liveness_payload(passed=False))).status_code == 422
    assert (await register(client, liveness=liveness_payload(score=1.7))).status_code == 422
    assert (await register(client, liveness="not json")).status_code == 422
    assert (await register(client, device='{"device_id": "x"}')).status_code == 422
    r = await client.post("/api/v1/app/auth/register", data=reg_form(), files=reg_files()[:2])  # selfie missing
    assert r.status_code == 422


async def _approve(client, shop_id: str):
    csrf = await admin_login(client)
    return await client.post(f"/admin/api/kyc/{shop_id}/approve", headers={"X-CSRF-Token": csrf})


async def _reject(client, shop_id: str, reason="NID ছবি অস্পষ্ট।"):
    csrf = await admin_login(client)
    return await client.post(f"/admin/api/kyc/{shop_id}/reject", headers={"X-CSRF-Token": csrf}, json={"reason_bn": reason})


async def test_reregister_after_reject_replaces_kyc_and_resets_pending(client, db, superadmin, kyc_tmp_dir):
    first = (await register(client)).json()
    shop_id = first["shop"]["id"]
    assert (await _reject(client, shop_id)).status_code == 200
    # rejected -> license says so, with reason
    h = {"Authorization": f"Bearer {first['access_token']}"}
    lic = (await client.get("/api/v1/app/license", headers=h)).json()
    assert lic["status"] == "rejected" and lic["verification"] == "rejected" and lic["rejection_reason_bn"] == "NID ছবি অস্পষ্ট।"

    r = await register(client, device_id="dev-reg-new1", shop_name="করিম স্টোর ২", nid_number="9876543210")
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["shop"]["id"] == shop_id  # same account, same phone
    assert body["license"]["status"] == "pending_verification" and body["license"]["rejection_reason_bn"] is None
    shop = await db.scalar(select(Shop).where(Shop.id == uuid.UUID(shop_id)))
    await db.refresh(shop)
    assert shop.verification == "pending" and shop.rejection_reason_bn is None and shop.nid_number == "9876543210"
    assert shop.shop_name == "করিম স্টোর ২"
    subs = (await db.execute(select(KycSubmission).where(KycSubmission.shop_id == shop.id).order_by(KycSubmission.submitted_at))).scalars().all()
    assert len(subs) == 2 and subs[0].decision == "rejected" and subs[1].decision is None
    # old device was replaced by the new one; old refresh token revoked
    assert [d.device_id for d in shop.devices if d.is_active] == ["dev-reg-new1"]
    assert (await client.post("/api/v1/app/auth/refresh", json={"refresh_token": first["refresh_token"]})).status_code == 401


# ---------------------------------------------------------------- status mapping
def test_compute_status_pending_and_rejected_override_subscription():
    now = now_utc()
    s = Shop(shop_name="x", owner_name="y", phone="01700000000", password_hash="h", is_disabled=False)
    s.verification = "pending"
    s.paid_until = now + timedelta(days=10)
    info = compute_status(s, 10, now)
    assert info.status == "pending_verification" and info.days_left == 0
    s.verification = "rejected"
    s.rejection_reason_bn = "ভুল NID"
    info = compute_status(s, 10, now)
    assert info.status == "rejected" and "ভুল NID" in info.message_bn
    s.verification = "approved"
    assert compute_status(s, 10, now).status == "active"


def test_payment_popup_only_for_due():
    from app.services.settings_service import SettingsSnapshot
    from app.services.subscription import build_license

    st = SettingsSnapshot(bkash_number=None, nagad_number=None, instructions_bn=None, grace_days=10, trial_days=14, reminder_days_before=3,
                          support_phone=None, popup_every_minutes=45)
    now = now_utc()
    s = Shop(shop_name="x", owner_name="y", phone="01700000000", password_hash="h", is_disabled=False)
    s.verification = "approved"
    s.paid_until = now - timedelta(days=2)
    lic = build_license(s, st)
    assert lic["status"] == "due" and lic["payment_popup"]["show"] is True and lic["payment_popup"]["every_minutes"] == 45
    assert lic["payment_popup"]["title_bn"] and lic["payment_popup"]["body_bn"]
    s.paid_until = now + timedelta(days=2)
    lic = build_license(s, st)
    assert lic["status"] == "active" and lic["payment_popup"]["show"] is False


# ---------------------------------------------------------------- admin review
async def test_admin_list_detail_approve_starts_trial(client, db, superadmin, plan):
    reg = (await register(client, frames=[jpeg_bytes((16, 16))])).json()
    shop_id = reg["shop"]["id"]
    csrf = await admin_login(client)

    dash = (await client.get("/admin/api/dashboard")).json()
    assert dash["pending_kyc"] == 1

    lst = (await client.get("/admin/api/kyc", params={"status": "pending"})).json()
    assert lst["total"] == 1
    item = lst["items"][0]
    assert item["shop"]["id"] == shop_id and item["shop"]["verification"] == "pending" and item["shop"]["status"] == "pending_verification"
    assert item["nid_number"] == "1234567890123" and item["files"] == ["nid_front", "nid_back", "selfie", "frame_0"]
    assert item["liveness"]["score"] == 0.93
    assert (await client.get("/admin/api/kyc", params={"status": "approved"})).json()["total"] == 0

    det = (await client.get(f"/admin/api/kyc/{shop_id}")).json()
    assert det["file_urls"]["selfie"] == f"/admin/api/kyc/{shop_id}/file/selfie"
    assert len(det["history"]) == 1

    # shop list shows the verification chip data too
    shops = (await client.get("/admin/api/shops")).json()["items"]
    assert shops[0]["verification"] == "pending"

    r = await client.post(f"/admin/api/kyc/{shop_id}/approve", headers={"X-CSRF-Token": csrf})
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["shop"]["verification"] == "approved" and out["shop"]["status"] == "trial" and out["decision"] == "approved"
    shop = await db.scalar(select(Shop).where(Shop.id == uuid.UUID(shop_id)))
    await db.refresh(shop)
    assert shop.verified_at is not None
    assert abs((shop.trial_ends_at - (now_utc() + timedelta(days=14))).total_seconds()) < 120
    note = await db.scalar(select(Notification).where(Notification.shop_id == shop.id))
    assert note.body_bn == "অ্যাকাউন্ট যাচাই সম্পন্ন হয়েছে। আপনার ফ্রি ট্রায়াল শুরু হলো।"
    audit = (await client.get(f"/admin/api/shops/{shop_id}/audit")).json()
    assert any(a["action"] == "kyc.approved" for a in audit)

    # app sees trial now
    h = {"Authorization": f"Bearer {reg['access_token']}"}
    lic = (await client.get("/api/v1/app/license", headers=h)).json()
    assert lic["status"] == "trial" and lic["verification"] == "approved" and lic["verified_at"] and lic["days_left"] == 14

    # second review is a conflict; dashboard count drops
    assert (await client.post(f"/admin/api/kyc/{shop_id}/approve", headers={"X-CSRF-Token": csrf})).status_code == 409
    assert (await client.get("/admin/api/dashboard", params={"_": 1})).json()["pending_kyc"] == 0
    assert (await client.get("/admin/api/kyc", params={"status": "approved"})).json()["total"] == 1


async def test_admin_reject_puts_reason_in_license(client, db, superadmin):
    reg = (await register(client)).json()
    shop_id = reg["shop"]["id"]
    csrf = await admin_login(client)
    assert (await client.post(f"/admin/api/kyc/{shop_id}/reject", headers={"X-CSRF-Token": csrf}, json={})).status_code == 422
    r = await client.post(f"/admin/api/kyc/{shop_id}/reject", headers={"X-CSRF-Token": csrf}, json={"reason_bn": "সেলফি ও NID মিলছে না।"})
    assert r.status_code == 200, r.text
    assert r.json()["shop"]["verification"] == "rejected" and r.json()["reason_bn"] == "সেলফি ও NID মিলছে না।"
    h = {"Authorization": f"Bearer {reg['access_token']}"}
    lic = (await client.get("/api/v1/app/license", headers=h)).json()
    assert lic["status"] == "rejected" and lic["rejection_reason_bn"] == "সেলফি ও NID মিলছে না।" and lic["trial_ends_at"] is None
    note = await db.scalar(select(Notification).where(Notification.shop_id == uuid.UUID(shop_id)))
    assert "সেলফি ও NID মিলছে না।" in note.body_bn
    assert (await client.get("/admin/api/kyc", params={"status": "rejected"})).json()["total"] == 1


async def test_admin_file_access_requires_cookie_and_is_private(client, superadmin):
    reg = (await register(client)).json()
    shop_id = reg["shop"]["id"]
    url = f"/admin/api/kyc/{shop_id}/file/selfie"
    assert (await client.get(url)).status_code == 401
    # a shop bearer token is not enough either
    assert (await client.get(url, headers={"Authorization": f"Bearer {reg['access_token']}"})).status_code == 401
    assert (await client.get("/admin/api/kyc")).status_code == 401
    await admin_login(client)
    r = await client.get(url)
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("image/jpeg")
    assert r.headers["content-disposition"].startswith("inline")
    assert "no-store" in r.headers["cache-control"]
    assert r.content.startswith(b"\xff\xd8\xff")
    assert (await client.get(f"/admin/api/kyc/{shop_id}/file/frame_2")).status_code == 404
    assert (await client.get(f"/admin/api/kyc/{shop_id}/file/..%2F..%2Fdukandar.db")).status_code == 404
    # the file is not reachable via the static admin mount
    assert (await client.get(f"/admin/kyc/{shop_id}/selfie.jpg")).status_code in (404, 405)


async def test_register_rate_limited(client, rate_limited):
    # REGISTER_LIMIT is 10/hour: the first ten succeed, the eleventh is throttled.
    codes = []
    for i in range(11):
        codes.append((await register(client, phone=f"017100000{i:02d}", device_id=f"dev-rl-00{i:02d}")).status_code)
    assert codes[:10] == [201] * 10 and codes[10] == 429


async def test_daily_job_skips_pending_shops(client, db, plan):
    (await register(client)).json()
    now = now_utc()
    stats = await run_daily(db, now + timedelta(days=30))
    assert stats["due"] == 0 and stats["info"] == 0
    notes = (await db.execute(select(Notification))).scalars().all()
    assert notes == []
