"""Async engine + session factory.

SQLite (default) is tuned for a single-process API: WAL journal, NORMAL sync, memory temp store, 20 MB page cache,
256 MB mmap and a 5 s busy timeout, applied on every new connection. A small AsyncAdaptedQueuePool keeps a handful of
warm aiosqlite connections (each one is a thread) so reads run concurrently under WAL while writers queue on busy_timeout.
PostgreSQL uses SQLAlchemy defaults with pool_pre_ping.
"""
from __future__ import annotations

from collections.abc import AsyncGenerator
from pathlib import Path

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import AsyncAdaptedQueuePool, StaticPool

from app.core.config import get_settings

SQLITE_PRAGMAS: dict[str, str | int] = {
    "journal_mode": "WAL",
    "synchronous": "NORMAL",
    "busy_timeout": 5000,
    "foreign_keys": "ON",
    "cache_size": -20000,
    "temp_store": "MEMORY",
    "mmap_size": 268435456,
}


def _sqlite_path(url: str) -> str | None:
    """File path portion of a sqlite URL, or None for :memory:."""
    path = url.split("///", 1)[1] if "///" in url else ""
    path = path.split("?", 1)[0]
    if not path or path == ":memory:":
        return None
    return path


def _apply_pragmas(dbapi_conn, _record) -> None:
    cur = dbapi_conn.cursor()
    try:
        for k, v in SQLITE_PRAGMAS.items():
            cur.execute(f"PRAGMA {k}={v}")
    finally:
        cur.close()


def make_engine(url: str):
    if not url.startswith("sqlite"):
        return create_async_engine(url, pool_pre_ping=True, pool_size=10, max_overflow=10)

    path = _sqlite_path(url)
    connect_args = {"check_same_thread": False}
    if path is None:
        # in-memory: one shared connection (tests)
        engine = create_async_engine(url, connect_args=connect_args, poolclass=StaticPool)
    else:
        Path(path).expanduser().resolve().parent.mkdir(parents=True, exist_ok=True)
        connect_args["timeout"] = 5
        engine = create_async_engine(url, connect_args=connect_args, poolclass=AsyncAdaptedQueuePool,
                                     pool_size=8, max_overflow=8, pool_recycle=3600, pool_pre_ping=False)
    event.listen(engine.sync_engine, "connect", _apply_pragmas)
    return engine


engine = make_engine(get_settings().database_url)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session
