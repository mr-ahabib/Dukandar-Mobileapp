from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from sqlalchemy import select

from app.api.admin_routes._common import PageParams, page_out, page_params, paginate
from app.core.audit import audit
from app.core.deps import DB, CurrentAdmin, MutatingAdmin
from app.db.models import Notification
from app.schemas.admin import BroadcastIn, NotificationAdminOut
from app.schemas.common import Page
from app.services.notifications import create_notification

router = APIRouter(prefix="/notifications", tags=["admin:notifications"])


@router.get("", response_model=Page[NotificationAdminOut])
async def list_notifications(auth: CurrentAdmin, db: DB, p: PageParams = Depends(page_params)):
    stmt = select(Notification).order_by(Notification.created_at.desc())
    if p.q:
        stmt = stmt.where(Notification.title_bn.ilike(f"%{p.q}%"))
    rows, total = await paginate(db, stmt, p)
    return page_out([NotificationAdminOut.model_validate(r) for r in rows], total, p)


@router.post("/broadcast", status_code=status.HTTP_201_CREATED)
async def broadcast(request: Request, body: BroadcastIn, auth: MutatingAdmin, db: DB):
    created = 0
    if body.shop_ids:
        for sid in body.shop_ids:
            await create_notification(db, shop_id=sid, title_bn=body.title_bn, body_bn=body.body_bn, kind=body.kind)
            created += 1
    else:
        await create_notification(db, shop_id=None, title_bn=body.title_bn, body_bn=body.body_bn, kind=body.kind)
        created = 1
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="notification.broadcast", target_type="notification", target_id=None,
                request=request, meta={"title_bn": body.title_bn, "kind": body.kind, "targets": len(body.shop_ids or [])})
    await db.commit()
    return {"created": created, "broadcast": not body.shop_ids}
