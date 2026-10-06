from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import JSON, TypeDecorator, Uuid

# Portable JSON column: JSONB on PostgreSQL (production), plain JSON elsewhere (tests).
JSONType = JSON().with_variant(JSONB(), "postgresql")


class TZDateTime(TypeDecorator):
    """timestamptz on PostgreSQL; guarantees tz-aware UTC values on dialects (SQLite) that drop tzinfo."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is not None and value.tzinfo is not None and dialect.name != "postgresql":
            return value.astimezone(UTC).replace(tzinfo=None)
        return value

    def process_result_value(self, value, dialect):
        if value is not None and value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value


def _utcnow() -> datetime:
    return datetime.now(UTC)


class Base(DeclarativeBase):
    pass


class UUIDMixin:
    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(TZDateTime(), default=_utcnow, server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(TZDateTime(), default=_utcnow, onupdate=_utcnow, server_default=func.now(), nullable=False)
