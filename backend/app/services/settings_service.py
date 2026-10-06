from __future__ import annotations

import time
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models import AppSettings

SETTINGS_CACHE_TTL = 60.0


@dataclass(frozen=True, slots=True)
class SettingsSnapshot:
    """Immutable copy of the settings row for read paths (safe to share across requests)."""

    bkash_number: str | None
    nagad_number: str | None
    instructions_bn: str | None
    grace_days: int
    trial_days: int
    reminder_days_before: int
    support_phone: str | None
    popup_every_minutes: int = 30


_cache: tuple[float, SettingsSnapshot] | None = None


def invalidate_settings_cache() -> None:
    global _cache
    _cache = None


def _snapshot(row: AppSettings) -> SettingsSnapshot:
    return SettingsSnapshot(
        bkash_number=row.bkash_number, nagad_number=row.nagad_number, instructions_bn=row.instructions_bn,
        grace_days=row.grace_days, trial_days=row.trial_days, reminder_days_before=row.reminder_days_before,
        support_phone=row.support_phone, popup_every_minutes=row.popup_every_minutes,
    )


async def get_app_settings(db: AsyncSession) -> AppSettings:
    """Return the singleton settings ORM row (for mutations), creating it with defaults when missing."""
    row = await db.scalar(select(AppSettings).where(AppSettings.id == 1))
    if row is None:
        s = get_settings()
        row = AppSettings(
            id=1,
            grace_days=s.default_grace_days,
            trial_days=s.default_trial_days,
            reminder_days_before=s.default_reminder_days_before,
            popup_every_minutes=s.default_popup_every_minutes,
            instructions_bn="বিকাশ/নগদে Send Money করে ট্রানজেকশন আইডি অ্যাপে জমা দিন।",
        )
        db.add(row)
        await db.flush()
    invalidate_settings_cache()
    return row


async def get_settings_snapshot(db: AsyncSession) -> SettingsSnapshot:
    """Read-only settings, cached in-process for SETTINGS_CACHE_TTL seconds. Mutations call invalidate_settings_cache()."""
    global _cache
    now = time.monotonic()
    if _cache and now - _cache[0] < SETTINGS_CACHE_TTL:
        return _cache[1]
    snap = _snapshot(await get_app_settings(db))
    _cache = (now, snap)
    return snap
