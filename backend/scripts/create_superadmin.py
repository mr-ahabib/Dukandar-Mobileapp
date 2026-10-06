#!/usr/bin/env python
"""Create (or promote) a superadmin. Usage: python scripts/create_superadmin.py [email]"""
from __future__ import annotations

import asyncio
import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select  # noqa: E402

from app.core.security import hash_password, validate_admin_password  # noqa: E402
from app.db.models import Admin  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402


async def main() -> None:
    email = (sys.argv[1] if len(sys.argv) > 1 else input("Admin email: ")).strip().lower()
    if "@" not in email:
        sys.exit("invalid email")
    while True:
        pw = getpass.getpass("Password (min 10 chars, 1 uppercase, 1 digit): ")
        try:
            validate_admin_password(pw)
        except ValueError as e:
            print(e)
            continue
        if pw != getpass.getpass("Repeat password: "):
            print("passwords do not match")
            continue
        break
    async with SessionLocal() as db:
        admin = await db.scalar(select(Admin).where(Admin.email == email))
        if admin:
            admin.password_hash = hash_password(pw)
            admin.role = "superadmin"
            admin.is_active = True
            admin.locked_until = None
            admin.failed_attempts = 0
            print(f"updated existing admin {email} -> superadmin")
        else:
            db.add(Admin(email=email, password_hash=hash_password(pw), role="superadmin", is_active=True))
            print(f"created superadmin {email}")
        await db.commit()


if __name__ == "__main__":
    asyncio.run(main())
