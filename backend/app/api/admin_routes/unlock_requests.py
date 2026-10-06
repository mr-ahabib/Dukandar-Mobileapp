from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import or_, select

from app.api.admin_routes._common import PageParams, page_out, page_params, paginate
from app.core.audit import audit
from app.core.deps import DB, CurrentAdmin, MutatingAdmin, parse_uuid
from app.db.models import Shop, UnlockRequest
from app.schemas.admin import UnlockRequestOut
from app.schemas.common import Page

router = APIRouter(prefix="/unlock-requests", tags=["admin:unlock-requests"])


def _out(r: UnlockRequest) -> UnlockRequestOut:
    return UnlockRequestOut(
        id=r.id, shop_id=r.shop_id, shop_name=r.shop.shop_name if r.shop else None, phone=r.shop.phone if r.shop else None,
        device_id=r.device_id, request_code=r.request_code, unlock_code=r.unlock_code, reason=r.reason, details=r.details,
        app_version=r.app_version, attempts=r.attempts, status=r.status, created_at=r.created_at, used_at=r.used_at,
    )


@router.get("", response_model=Page[UnlockRequestOut])
async def list_requests(auth: CurrentAdmin, db: DB, p: PageParams = Depends(page_params), status: str | None = None):
    stmt = select(UnlockRequest).join(Shop, Shop.id == UnlockRequest.shop_id).order_by(UnlockRequest.created_at.desc())
    if status:
        stmt = stmt.where(UnlockRequest.status == status)
    if p.q:
        like = f"%{p.q}%"
        stmt = stmt.where(or_(UnlockRequest.request_code.ilike(like), Shop.shop_name.ilike(like), Shop.phone.ilike(like)))
    rows, total = await paginate(db, stmt, p)
    return page_out([_out(r) for r in rows], total, p)


@router.post("/{req_id}/close", response_model=UnlockRequestOut)
async def close_request(request: Request, req_id: str, auth: MutatingAdmin, db: DB):
    r = await db.scalar(select(UnlockRequest).where(UnlockRequest.id == parse_uuid(req_id, "request")))
    if r is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "request not found")
    if r.status == "open":
        r.status = "closed"
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="unlock_request.closed", target_type="unlock_request",
                target_id=r.request_code, request=request, meta={"shop_id": str(r.shop_id)})
    await db.commit()
    await db.refresh(r)
    return _out(r)
