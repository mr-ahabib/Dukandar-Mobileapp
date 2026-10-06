from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import or_, select

from app.api.admin_routes._common import PageParams, page_out, page_params, paginate
from app.core.deps import DB, CurrentAdmin
from app.db.models import AuditLog
from app.schemas.admin import AuditOut
from app.schemas.common import Page

router = APIRouter(prefix="/audit-logs", tags=["admin:audit"])


@router.get("", response_model=Page[AuditOut])
async def list_audit(auth: CurrentAdmin, db: DB, p: PageParams = Depends(page_params), action: str | None = None):
    stmt = select(AuditLog).order_by(AuditLog.created_at.desc())
    if action:
        stmt = stmt.where(AuditLog.action.ilike(f"{action}%"))
    if p.q:
        like = f"%{p.q}%"
        stmt = stmt.where(or_(AuditLog.action.ilike(like), AuditLog.target_id.ilike(like), AuditLog.actor_id.ilike(like)))
    rows, total = await paginate(db, stmt, p)
    return page_out([AuditOut.model_validate(r) for r in rows], total, p)
