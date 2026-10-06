from __future__ import annotations

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.core.config import get_settings

log = logging.getLogger("dukandar.scheduler")
_scheduler: AsyncIOScheduler | None = None


async def _daily_job() -> None:
    from app.db.session import SessionLocal
    from app.jobs.daily import run_daily

    try:
        async with SessionLocal() as db:
            await run_daily(db)
    except Exception:  # pragma: no cover
        log.exception("daily job failed")


def start_scheduler() -> AsyncIOScheduler | None:
    global _scheduler
    s = get_settings()
    if not s.scheduler_enabled:
        return None
    _scheduler = AsyncIOScheduler(timezone=s.scheduler_timezone)
    _scheduler.add_job(_daily_job, CronTrigger(hour=s.scheduler_hour, minute=0, timezone=s.scheduler_timezone),
                       id="daily_subscription_job", replace_existing=True, misfire_grace_time=3600)
    _scheduler.start()
    log.info("scheduler started (daily at %02d:00 %s)", s.scheduler_hour, s.scheduler_timezone)
    return _scheduler


def stop_scheduler() -> None:
    global _scheduler
    if _scheduler:
        _scheduler.shutdown(wait=False)
        _scheduler = None
