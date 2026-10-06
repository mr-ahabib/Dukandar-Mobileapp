from __future__ import annotations

from datetime import timedelta

from app.core.security import now_utc
from app.db.models import AppSettings, Shop
from app.services.subscription import compute_status, extend_paid_until
from tests.conftest import app_login


def _shop(**kw) -> Shop:
    s = Shop(shop_name="x", owner_name="y", phone="01700000000", password_hash="h")
    for k, v in kw.items():
        setattr(s, k, v)
    s.is_disabled = kw.get("is_disabled", False)
    return s


def test_trial_status():
    now = now_utc()
    info = compute_status(_shop(trial_ends_at=now + timedelta(days=5)), 10, now)
    assert info.status == "trial" and info.days_left == 5 and "ট্রায়াল" in info.message_bn


def test_active_status():
    now = now_utc()
    info = compute_status(_shop(paid_until=now + timedelta(days=12)), 10, now)
    assert info.status == "active" and info.days_left == 12 and info.next_due_at == now + timedelta(days=12)


def test_due_within_grace():
    now = now_utc()
    paid_until = now - timedelta(days=3)
    info = compute_status(_shop(paid_until=paid_until), 10, now)
    assert info.status == "due"
    assert info.grace_ends_at == paid_until + timedelta(days=10)
    assert info.days_left == 7
    assert "ফি জমা দিন" in info.message_bn


def test_suspended_after_grace():
    now = now_utc()
    info = compute_status(_shop(paid_until=now - timedelta(days=11)), 10, now)
    assert info.status == "suspended" and info.days_left == 0


def test_grace_days_setting_respected():
    now = now_utc()
    shop = _shop(paid_until=now - timedelta(days=6))
    assert compute_status(shop, 10, now).status == "due"
    assert compute_status(shop, 5, now).status == "suspended"


def test_trial_expired_goes_due_then_suspended():
    now = now_utc()
    assert compute_status(_shop(trial_ends_at=now - timedelta(days=2)), 10, now).status == "due"
    assert compute_status(_shop(trial_ends_at=now - timedelta(days=20)), 10, now).status == "suspended"


def test_disabled_overrides_everything():
    now = now_utc()
    assert compute_status(_shop(paid_until=now + timedelta(days=30), is_disabled=True), 10, now).status == "disabled"


def test_extend_paid_until_from_future_or_now():
    now = now_utc()
    s = _shop(paid_until=now + timedelta(days=10))
    frm, until = extend_paid_until(s, 30, 2, now)
    assert frm == now + timedelta(days=10) and until == now + timedelta(days=70)
    s2 = _shop(paid_until=now - timedelta(days=40))  # lapsed: start from now
    frm, until = extend_paid_until(s2, 30, 1, now)
    assert frm == now and until == now + timedelta(days=30)


async def test_license_endpoint_reflects_grace_and_payment_info(client, db, shop):
    shop.trial_ends_at = None
    shop.paid_until = now_utc() - timedelta(days=2)
    db.add(AppSettings(id=1, grace_days=10, trial_days=14, reminder_days_before=3, bkash_number="01700000001", instructions_bn="পাঠান"))
    await db.commit()
    tok = (await app_login(client)).json()["access_token"]
    r = await client.get("/api/v1/app/license", headers={"Authorization": f"Bearer {tok}"})
    lic = r.json()
    assert lic["status"] == "due" and lic["days_left"] == 8
    assert lic["payment_info"]["bkash"] == "01700000001"
    assert lic["device_locked"] is False
