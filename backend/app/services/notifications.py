from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import now_utc
from app.db.models import Notification, NotificationRead


async def create_notification(
    db: AsyncSession, *, shop_id: uuid.UUID | None, title_bn: str, body_bn: str, kind: str = "info", dedupe_key: str | None = None
) -> Notification | None:
    """Create a notification; when dedupe_key is given, skip if one already exists."""
    if dedupe_key:
        exists = await db.scalar(select(Notification.id).where(Notification.dedupe_key == dedupe_key))
        if exists:
            return None
    n = Notification(shop_id=shop_id, title_bn=title_bn[:200], body_bn=body_bn, kind=kind, dedupe_key=dedupe_key)
    db.add(n)
    await db.flush()
    return n


async def list_for_shop(db: AsyncSession, shop_id: uuid.UUID, limit: int = 50) -> list[dict]:
    rows = (
        await db.execute(
            select(Notification, NotificationRead.read_at)
            .outerjoin(
                NotificationRead,
                (NotificationRead.notification_id == Notification.id) & (NotificationRead.shop_id == shop_id),
            )
            .where(or_(Notification.shop_id == shop_id, Notification.shop_id.is_(None)))
            .order_by(Notification.created_at.desc())
            .limit(limit)
        )
    ).all()
    out = []
    for n, bread in rows:
        read = (n.read_at is not None) if n.shop_id is not None else (bread is not None)
        out.append({"id": n.id, "title_bn": n.title_bn, "body_bn": n.body_bn, "kind": n.kind, "created_at": n.created_at, "read": read})
    return out


async def mark_read(db: AsyncSession, shop_id: uuid.UUID, notification_id: uuid.UUID) -> bool:
    n = await db.scalar(select(Notification).where(Notification.id == notification_id))
    if n is None or (n.shop_id is not None and n.shop_id != shop_id):
        return False
    ts: datetime = now_utc()
    if n.shop_id is not None:
        if n.read_at is None:
            n.read_at = ts
    else:
        existing = await db.scalar(
            select(NotificationRead).where(NotificationRead.notification_id == n.id, NotificationRead.shop_id == shop_id)
        )
        if existing is None:
            db.add(NotificationRead(notification_id=n.id, shop_id=shop_id, read_at=ts))
    return True
