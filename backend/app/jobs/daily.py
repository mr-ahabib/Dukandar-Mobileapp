"""Daily subscription job. Run in-process via APScheduler or manually: `python -m app.jobs.daily`."""
from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.audit import audit
from app.core.config import get_settings
from app.db.models import Shop
from app.services.notifications import create_notification
from app.services.settings_service import get_settings_snapshot
from app.services.subscription import compute_status

log = logging.getLogger("dukandar.daily")

DUE_BODY = "আপনার মাসিক সাবস্ক্রিপশন ফি জমা দিন। বিকাশ/নগদে পেমেন্ট করে অ্যাপে ট্রানজেকশন আইডি জমা দিন।"


async def run_daily(db: AsyncSession, now: datetime | None = None) -> dict[str, int]:
    """Compute status for every shop, emit reminders/due notices, audit transitions."""
    s = get_settings()
    now = now or datetime.now(UTC)
    local_day = now.astimezone(ZoneInfo(s.scheduler_timezone)).date().isoformat()
    st = await get_settings_snapshot(db)
    shops = (await db.execute(select(Shop))).scalars().unique().all()
    stats = {"shops": 0, "info": 0, "due": 0, "transitions": 0}
    for shop in shops:
        stats["shops"] += 1
        info = compute_status(shop, st.grace_days, now)

        if shop.last_status != info.status:
            await audit(db, actor_type="system", actor_id=None, action="subscription.transition", target_type="shop", target_id=str(shop.id),
                        meta={"from": shop.last_status, "to": info.status, "paid_until": shop.paid_until.isoformat() if shop.paid_until else None})
            shop.last_status = info.status
            stats["transitions"] += 1

        if info.status in ("pending_verification", "rejected"):
            continue  # unverified shops get no subscription reminders

        if info.status in ("active", "trial") and info.next_due_at:
            remind_at = info.next_due_at - timedelta(days=st.reminder_days_before)
            if remind_at <= now < info.next_due_at and info.days_left <= st.reminder_days_before:
                due_str = info.next_due_at.astimezone(ZoneInfo(s.scheduler_timezone)).strftime("%d-%m-%Y")
                n = await create_notification(
                    db, shop_id=shop.id, kind="info", title_bn="সাবস্ক্রিপশন ফি শীঘ্রই দিতে হবে",
                    body_bn=f"আপনার সাবস্ক্রিপশনের মেয়াদ শেষ হবে {due_str} তারিখে ({info.days_left} দিন বাকি)। সময়মতো ফি জমা দিন।",
                    dedupe_key=f"info:{shop.id}:{info.next_due_at.date().isoformat()}",
                )
                stats["info"] += 1 if n else 0

        if info.status == "due":
            n = await create_notification(
                db, shop_id=shop.id, kind="due", title_bn="ফি জমা দিন",
                body_bn=f"{DUE_BODY} আর {info.days_left} দিনের মধ্যে ফি না দিলে অ্যাপ বন্ধ হয়ে যাবে।",
                dedupe_key=f"due:{shop.id}:{local_day}",
            )
            stats["due"] += 1 if n else 0

    await audit(db, actor_type="system", actor_id=None, action="job.daily_ran", meta=stats)
    await db.commit()
    log.info("daily job: %s", stats)
    return stats


async def _main() -> None:
    from app.db.session import SessionLocal

    logging.basicConfig(level=logging.INFO)
    async with SessionLocal() as db:
        print(await run_daily(db))


if __name__ == "__main__":
    asyncio.run(_main())
