"""Test fixtures.

Uses DATABASE_URL_TEST (PostgreSQL) when set; otherwise falls back to an in-memory SQLite database so the
suite runs on machines without Postgres access. Production target remains PostgreSQL.
"""
from __future__ import annotations

import os
import uuid
from datetime import timedelta

os.environ.setdefault("ENV", "test")
os.environ["DATABASE_URL"] = os.environ.get("DATABASE_URL_TEST", "sqlite+aiosqlite:///:memory:")
os.environ["ADMIN_COOKIE_SECURE"] = "false"
os.environ["SCHEDULER_ENABLED"] = "false"
os.environ["AUTO_MIGRATE"] = "false"
os.environ["ADMIN_PANEL_DIR"] = "../admin-panel"
os.environ["JWT_APP_ACCESS_SECRET"] = "test-access"
os.environ["JWT_APP_REFRESH_SECRET"] = "test-refresh"
os.environ["JWT_ADMIN_SECRET"] = "test-admin"

import pytest  # noqa: E402
import pytest_asyncio  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker  # noqa: E402

from app.core.rate_limit import limiter  # noqa: E402
from app.core.security import hash_password, now_utc  # noqa: E402
from app.db import models as m  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import get_db, make_engine  # noqa: E402
from app.main import app  # noqa: E402
from app.services.settings_service import invalidate_settings_cache  # noqa: E402

TEST_URL = os.environ["DATABASE_URL"]


@pytest_asyncio.fixture
async def engine():
    invalidate_settings_cache()  # settings snapshot cache is process-global
    eng = make_engine(TEST_URL)
    async with eng.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield eng
    async with eng.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await eng.dispose()


@pytest_asyncio.fixture
async def session_factory(engine):
    return async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


@pytest_asyncio.fixture
async def db(session_factory):
    async with session_factory() as s:
        yield s


@pytest_asyncio.fixture
async def client(session_factory):
    async def _override():
        async with session_factory() as s:
            yield s

    app.dependency_overrides[get_db] = _override
    limiter.enabled = False
    limiter.reset()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as c:
        yield c
    app.dependency_overrides.clear()
    limiter.enabled = True


@pytest.fixture
def rate_limited():
    limiter.enabled = True
    limiter.reset()
    yield
    limiter.enabled = False


# ---- data helpers ----
SHOP_PHONE = "01711111111"
SHOP_PASSWORD = "secret6"
SUPER_EMAIL = "root@example.com"
SUPER_PW = "SuperSecret123"
STAFF_EMAIL = "staff@example.com"
STAFF_PW = "StaffSecret123"


@pytest_asyncio.fixture
async def plan(db):
    p = m.Plan(name="স্ট্যান্ডার্ড", price_bdt=300, period_days=30, is_active=True)
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return p


@pytest_asyncio.fixture
async def shop(db, plan):
    s = m.Shop(shop_name="রহিম স্টোর", owner_name="রহিম", phone=SHOP_PHONE, password_hash=hash_password(SHOP_PASSWORD),
               plan_id=plan.id, trial_ends_at=now_utc() + timedelta(days=14))
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return s


@pytest_asyncio.fixture
async def superadmin(db):
    a = m.Admin(email=SUPER_EMAIL, password_hash=hash_password(SUPER_PW), role="superadmin", is_active=True)
    db.add(a)
    await db.commit()
    return a


@pytest_asyncio.fixture
async def staff(db):
    a = m.Admin(email=STAFF_EMAIL, password_hash=hash_password(STAFF_PW), role="staff", is_active=True)
    db.add(a)
    await db.commit()
    return a


def device_payload(device_id: str = "dev-abc-123") -> dict:
    return {"device_id": device_id, "model": "Redmi Note 12", "os": "Android 14", "app_version": "1.0.0", "signature_sha256": "ab" * 32}


async def app_login(client: AsyncClient, phone=SHOP_PHONE, password=SHOP_PASSWORD, device_id="dev-abc-123"):
    return await client.post("/api/v1/app/auth/login", json={"phone": phone, "password": password, "device": device_payload(device_id)})


async def admin_login(client: AsyncClient, email=SUPER_EMAIL, password=SUPER_PW) -> str:
    r = await client.post("/admin/api/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["csrf_token"]


def new_uuid() -> str:
    return str(uuid.uuid4())
