from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select

from app.core.security import now_utc
from app.db.models import AuditLog, Notification
from app.jobs.daily import run_daily


async def test_daily_job_reminder_due_and_transition_audit(db, shop):
    now = now_utc()
    # 1) active, due in 2 days -> info reminder (reminder_days_before=3)
    shop.trial_ends_at = None
    shop.paid_until = now + timedelta(days=2)
    await db.commit()
    stats = await run_daily(db, now)
    assert stats["info"] == 1 and stats["due"] == 0 and stats["transitions"] == 1
    # idempotent for the same due date
    stats = await run_daily(db, now + timedelta(hours=1))
    assert stats["info"] == 0

    # 2) in grace -> due notification once per day
    stats = await run_daily(db, now + timedelta(days=3))
    assert stats["due"] == 1 and stats["transitions"] == 1
    stats = await run_daily(db, now + timedelta(days=3, hours=2))
    assert stats["due"] == 0
    stats = await run_daily(db, now + timedelta(days=4))
    assert stats["due"] == 1
    due_notes = await db.scalar(select(func.count()).select_from(Notification).where(Notification.kind == "due"))
    assert due_notes == 2
    note = await db.scalar(select(Notification).where(Notification.kind == "due"))
    assert "আপনার মাসিক সাবস্ক্রিপশন ফি জমা দিন" in note.body_bn

    # 3) grace over -> suspended transition audited, no more due notices
    stats = await run_daily(db, now + timedelta(days=13))
    assert stats["due"] == 0 and stats["transitions"] == 1
    trans = (await db.execute(select(AuditLog).where(AuditLog.action == "subscription.transition").order_by(AuditLog.created_at))).scalars().all()
    assert [t.meta["to"] for t in trans] == ["active", "due", "suspended"]
