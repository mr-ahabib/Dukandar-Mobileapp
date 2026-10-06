"""First-run bootstrap: migrations, superadmin, default plan and settings row."""
from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import hash_password, validate_admin_password, verify_password

log = logging.getLogger("dukandar.bootstrap")
BACKEND_DIR = Path(__file__).resolve().parents[2]


def _upgrade_sync() -> None:
    from alembic.config import Config

    from alembic import command

    cfg = Config(str(BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    command.upgrade(cfg, "head")


async def run_migrations() -> None:
    # alembic/env.py calls asyncio.run(); run it in a worker thread so it does not clash with the running loop.
    await asyncio.to_thread(_upgrade_sync)
    log.info("database migrated to head")


async def seed_defaults() -> None:
    from app.db.models import Admin, Plan
    from app.db.session import SessionLocal
    from app.services.settings_service import get_app_settings

    s = get_settings()
    async with SessionLocal() as db:
        await get_app_settings(db)  # creates the singleton row if missing
        if not await db.scalar(select(Plan.id).limit(1)):
            db.add(Plan(name="স্ট্যান্ডার্ড", price_bdt=300, period_days=30, is_active=True))
            log.info("seeded default plan স্ট্যান্ডার্ড (300 BDT / 30 days)")

        email = s.superadmin_email.strip().lower()
        if email and s.superadmin_password:
            admin = await db.scalar(select(Admin).where(Admin.email == email))
            if admin is None:
                try:
                    validate_admin_password(s.superadmin_password)
                except ValueError as e:
                    log.error("SUPERADMIN_PASSWORD rejected (%s); superadmin NOT created", e)
                else:
                    db.add(Admin(email=email, password_hash=hash_password(s.superadmin_password), role="superadmin", is_active=True))
                    log.warning("created superadmin %s from environment", email)
            elif not verify_password(s.superadmin_password, admin.password_hash):
                log.warning("SUPERADMIN_PASSWORD in .env differs from the stored password for %s; NOT overwriting. "
                            "Use scripts/create_superadmin.py to change it.", email)
        elif not await db.scalar(select(Admin.id).limit(1)):
            log.warning("no admin exists and SUPERADMIN_EMAIL/SUPERADMIN_PASSWORD are not set; run scripts/create_superadmin.py")
        await db.commit()


async def run_bootstrap() -> None:
    s = get_settings()
    if s.auto_migrate:
        await run_migrations()
    try:
        await seed_defaults()
    except Exception:  # pragma: no cover
        log.exception("bootstrap seeding failed (is the database migrated?)")
