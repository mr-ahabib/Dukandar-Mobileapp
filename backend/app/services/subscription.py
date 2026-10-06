"""Subscription status computation. Pure function + License builder."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import case

from app.core.security import now_utc
from app.db.models import AppSettings, Shop
from app.services.settings_service import SettingsSnapshot

FEATURES = ["ledger", "billing", "cash_drawer", "reports", "backup", "drive"]


@dataclass
class StatusInfo:
    status: str  # pending_verification|rejected|trial|active|due|suspended|disabled
    days_left: int
    trial_ends_at: datetime | None
    paid_until: datetime | None
    grace_ends_at: datetime | None
    next_due_at: datetime | None
    message_bn: str


def _days_between(later: datetime, earlier: datetime) -> int:
    """Whole days from earlier to later (rounded up)."""
    delta = later - earlier
    days = delta.days
    if delta.seconds > 0 or delta.microseconds > 0:
        days += 1
    return max(days, 0)


def compute_status(shop: Shop, grace_days: int, now: datetime | None = None) -> StatusInfo:
    now = now or now_utc()
    paid_until = shop.paid_until
    trial_ends = shop.trial_ends_at
    grace_ends = (paid_until + timedelta(days=grace_days)) if paid_until else None

    verification = getattr(shop, "verification", None) or "approved"
    if verification == "pending":
        return StatusInfo("pending_verification", 0, None, None, None, None,
                          "আপনার অ্যাকাউন্ট যাচাই করা হচ্ছে। যাচাই শেষ হলে ফ্রি ট্রায়াল শুরু হবে।")
    if verification == "rejected":
        return StatusInfo("rejected", 0, None, None, None, None,
                          "দুঃখিত, আপনার আবেদন গ্রহণ করা যায়নি। " + (shop.rejection_reason_bn or "") + " অনুগ্রহ করে আবার আবেদন করুন।")

    if shop.is_disabled:
        return StatusInfo("disabled", 0, trial_ends, paid_until, grace_ends, None,
                          "আপনার অ্যাকাউন্টটি বন্ধ করা হয়েছে। সহায়তার জন্য আমাদের সাথে যোগাযোগ করুন।")

    if paid_until and paid_until >= now:
        d = _days_between(paid_until, now)
        return StatusInfo("active", d, trial_ends, paid_until, grace_ends, paid_until,
                          f"আপনার সাবস্ক্রিপশন সক্রিয় আছে। মেয়াদ শেষ হবে {d} দিন পর।")

    if paid_until and paid_until < now:
        if grace_ends and grace_ends >= now:
            d = _days_between(grace_ends, now)
            return StatusInfo("due", d, trial_ends, paid_until, grace_ends, paid_until,
                              f"আপনার মাসিক সাবস্ক্রিপশন ফি জমা দিন। আর {d} দিনের মধ্যে ফি না দিলে অ্যাপ বন্ধ হয়ে যাবে।")
        return StatusInfo("suspended", 0, trial_ends, paid_until, grace_ends, paid_until,
                          "আপনার সাবস্ক্রিপশনের মেয়াদ শেষ। অ্যাপ চালু রাখতে অনুগ্রহ করে ফি জমা দিন।")

    # never paid
    if trial_ends and trial_ends >= now:
        d = _days_between(trial_ends, now)
        return StatusInfo("trial", d, trial_ends, None, None, trial_ends,
                          f"আপনার ফ্রি ট্রায়াল চলছে। আর {d} দিন বাকি।")

    if trial_ends and trial_ends < now:
        g = trial_ends + timedelta(days=grace_days)
        if g >= now:
            d = _days_between(g, now)
            return StatusInfo("due", d, trial_ends, None, g, trial_ends,
                              f"আপনার ফ্রি ট্রায়াল শেষ। মাসিক সাবস্ক্রিপশন ফি জমা দিন। আর {d} দিন সময় আছে।")
        return StatusInfo("suspended", 0, trial_ends, None, g, trial_ends,
                          "আপনার ফ্রি ট্রায়াল শেষ। অ্যাপ চালু রাখতে অনুগ্রহ করে ফি জমা দিন।")

    return StatusInfo("suspended", 0, None, None, None, None,
                      "কোনো সক্রিয় সাবস্ক্রিপশন নেই। অনুগ্রহ করে ফি জমা দিন।")


def status_sql(grace_days: int, now: datetime | None = None):
    """SQL CASE mirroring compute_status(); portable (only comparisons against bound datetimes)."""
    now = now or now_utc()
    grace_cut = now - timedelta(days=grace_days)
    return case(
        (Shop.verification == "pending", "pending_verification"),
        (Shop.verification == "rejected", "rejected"),
        (Shop.is_disabled.is_(True), "disabled"),
        (Shop.paid_until >= now, "active"),
        (Shop.paid_until >= grace_cut, "due"),
        (Shop.paid_until.is_not(None), "suspended"),
        (Shop.trial_ends_at >= now, "trial"),
        (Shop.trial_ends_at >= grace_cut, "due"),
        else_="suspended",
    )


def build_license(shop: Shop, settings_row: AppSettings | SettingsSnapshot, device_locked: bool = False) -> dict[str, Any]:
    now = now_utc()
    info = compute_status(shop, settings_row.grace_days, now)
    plan = shop.plan
    every = getattr(settings_row, "popup_every_minutes", 30) or 30
    return {
        "status": info.status,
        "verification": getattr(shop, "verification", None) or "approved",
        "rejection_reason_bn": shop.rejection_reason_bn if getattr(shop, "verification", None) == "rejected" else None,
        "verified_at": getattr(shop, "verified_at", None),
        "payment_popup": {
            "show": info.status == "due",
            "every_minutes": every,
            "title_bn": "সাবস্ক্রিপশন ফি বকেয়া",
            "body_bn": info.message_bn if info.status == "due" else "",
        },
        "plan_name": plan.name if plan else None,
        "price_bdt": plan.price_bdt if plan else None,
        "trial_ends_at": info.trial_ends_at,
        "paid_until": info.paid_until,
        "grace_ends_at": info.grace_ends_at,
        "next_due_at": info.next_due_at,
        "days_left": info.days_left,
        "grace_days": settings_row.grace_days,
        "message_bn": info.message_bn,
        "server_time": now,
        "device_locked": device_locked,
        "features": FEATURES,
        "payment_info": {
            "bkash": settings_row.bkash_number,
            "nagad": settings_row.nagad_number,
            "instructions_bn": settings_row.instructions_bn,
            "support_phone": settings_row.support_phone,
        },
    }


def extend_paid_until(shop: Shop, period_days: int, months: int, now: datetime | None = None) -> tuple[datetime, datetime]:
    """Extend from max(now, paid_until). Returns (paid_from, paid_until)."""
    now = now or now_utc()
    base = shop.paid_until if shop.paid_until and shop.paid_until > now else now
    new_until = base + timedelta(days=period_days * months)
    shop.paid_until = new_until
    return base, new_until
