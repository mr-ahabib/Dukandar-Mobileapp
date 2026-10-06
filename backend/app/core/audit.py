from __future__ import annotations

from typing import Any

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import now_utc
from app.db.models import AuditLog


def client_ip(request: Request | None) -> str | None:
    if request is None:
        return None
    if get_settings().trust_proxy_headers:
        xff = request.headers.get("x-forwarded-for")
        if xff:
            return xff.split(",")[0].strip()[:45]
    return request.client.host[:45] if request.client else None


async def audit(
    db: AsyncSession,
    *,
    actor_type: str,
    actor_id: str | None,
    action: str,
    target_type: str | None = None,
    target_id: str | None = None,
    request: Request | None = None,
    meta: dict[str, Any] | None = None,
) -> AuditLog:
    """Append an audit row (caller commits)."""
    row = AuditLog(
        created_at=now_utc(),
        actor_type=actor_type,
        actor_id=str(actor_id) if actor_id else None,
        action=action,
        target_type=target_type,
        target_id=str(target_id) if target_id else None,
        ip=client_ip(request),
        meta=meta,
    )
    db.add(row)
    return row
