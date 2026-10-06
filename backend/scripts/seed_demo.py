#!/usr/bin/env python
"""Seed demo data: one plan + two shops. Prints shop passwords. Usage: python scripts/seed_demo.py"""
from __future__ import annotations

import asyncio
import sys
from datetime import timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select  # noqa: E402

from app.core.security import hash_password, now_utc  # noqa: E402
from app.db.models import Plan, Shop  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.services.settings_service import get_app_settings  # noqa: E402


async def main() -> None:
    async with SessionLocal() as db:
        st = await get_app_settings(db)
        st.bkash_number = st.bkash_number or "01700000000"
        st.nagad_number = st.nagad_number or "01800000000"
        plan = await db.scalar(select(Plan).where(Plan.name == "স্ট্যান্ডার্ড"))
        if plan is None:
            plan = Plan(name="স্ট্যান্ডার্ড", price_bdt=300, period_days=30, is_active=True)
            db.add(plan)
            await db.flush()
        demo = [
            ("রহিম স্টোর", "আব্দুর রহিম", "01711111111", "123456", {"trial_ends_at": now_utc() + timedelta(days=st.trial_days)}),
            ("করিম ট্রেডার্স", "করিম মিয়া", "01822222222", "123456", {"paid_until": now_utc() + timedelta(days=20)}),
        ]
        for name, owner, phone, pw, extra in demo:
            if await db.scalar(select(Shop.id).where(Shop.phone == phone)):
                print(f"shop {phone} exists, skipping")
                continue
            db.add(Shop(shop_name=name, owner_name=owner, phone=phone, password_hash=hash_password(pw), address="ঢাকা", plan_id=plan.id, **extra))
            print(f"created shop {name} phone={phone} password={pw}")
        await db.commit()
    print("done")


if __name__ == "__main__":
    asyncio.run(main())
