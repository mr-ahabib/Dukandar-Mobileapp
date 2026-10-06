from __future__ import annotations

import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import FileResponse
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.admin_routes._common import PageParams, page_out, page_params
from app.api.admin_routes.shops import get_shop_or_404, shop_out
from app.core.audit import audit
from app.core.deps import DB, CurrentAdmin, MutatingAdmin, parse_uuid
from app.core.security import now_utc
from app.db.models import KycSubmission, Shop
from app.schemas.admin import KycDetailOut, KycListItemOut, KycRejectIn
from app.schemas.common import Page
from app.services import kyc as kyc_svc
from app.services.notifications import create_notification
from app.services.settings_service import get_settings_snapshot

router = APIRouter(prefix="/kyc", tags=["admin:kyc"])

APPROVED_TITLE = "অ্যাকাউন্ট যাচাই সম্পন্ন"
APPROVED_BODY = "অ্যাকাউন্ট যাচাই সম্পন্ন হয়েছে। আপনার ফ্রি ট্রায়াল শুরু হলো।"


async def _latest_submission(db: AsyncSession, shop_id: uuid.UUID) -> KycSubmission | None:
    return await db.scalar(select(KycSubmission).where(KycSubmission.shop_id == shop_id).order_by(KycSubmission.submitted_at.desc()).limit(1))


async def _item(db: AsyncSession, shop: Shop, sub: KycSubmission | None, st) -> KycListItemOut:
    return KycListItemOut(
        shop=await shop_out(db, shop, st), nid_number=sub.nid_number if sub else shop.nid_number,
        submitted_at=sub.submitted_at if sub else None, liveness=sub.liveness_json if sub else None,
        files=sorted((sub.files_json or {}).keys(), key=lambda k: kyc_svc.ALL_KINDS.index(k) if k in kyc_svc.ALL_KINDS else 99) if sub else [],
        decision=sub.decision if sub else None, reason_bn=sub.reason_bn if sub else None, reviewed_at=sub.reviewed_at if sub else None,
    )


@router.get("", response_model=Page[KycListItemOut])
async def list_kyc(auth: CurrentAdmin, db: DB, p: PageParams = Depends(page_params), status: str | None = None):
    st = await get_settings_snapshot(db)
    # latest submission per shop
    latest = (
        select(KycSubmission.shop_id, func.max(KycSubmission.submitted_at).label("mx")).group_by(KycSubmission.shop_id).subquery()
    )
    stmt = (
        select(Shop, KycSubmission)
        .join(latest, latest.c.shop_id == Shop.id)
        .join(KycSubmission, (KycSubmission.shop_id == latest.c.shop_id) & (KycSubmission.submitted_at == latest.c.mx))
        .order_by(KycSubmission.submitted_at.desc())
    )
    if status in ("pending", "approved", "rejected"):
        stmt = stmt.where(Shop.verification == status)
    if p.q:
        like = f"%{p.q}%"
        stmt = stmt.where(or_(Shop.shop_name.ilike(like), Shop.owner_name.ilike(like), Shop.phone.ilike(like), KycSubmission.nid_number.ilike(like)))
    total = await db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0
    rows = (await db.execute(stmt.offset(p.offset).limit(p.page_size))).unique().all()
    return page_out([await _item(db, shop, sub, st) for shop, sub in rows], int(total), p)


@router.get("/{shop_id}", response_model=KycDetailOut)
async def kyc_detail(shop_id: str, auth: CurrentAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    sub = await _latest_submission(db, shop.id)
    if sub is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no KYC submission for this shop")
    st = await get_settings_snapshot(db)
    base = await _item(db, shop, sub, st)
    history = (await db.execute(select(KycSubmission).where(KycSubmission.shop_id == shop.id).order_by(KycSubmission.submitted_at.desc()))).scalars().all()
    return KycDetailOut(
        **base.model_dump(),
        file_urls={k: f"/admin/api/kyc/{shop.id}/file/{k}" for k in base.files},
        history=[{"id": str(h.id), "submitted_at": h.submitted_at, "decision": h.decision, "reason_bn": h.reason_bn, "reviewed_at": h.reviewed_at}
                 for h in history],
    )


@router.get("/{shop_id}/file/{kind}", include_in_schema=False)
async def kyc_file(shop_id: str, kind: str, auth: CurrentAdmin, db: DB):
    sid = parse_uuid(shop_id, "shop")
    sub = await _latest_submission(db, sid)
    path = kyc_svc.resolve_file(sid, sub.files_json or {}, kind) if sub else None
    if path is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "file not found")
    with open(path, "rb") as fh:
        head = fh.read(8)
    return FileResponse(
        path, media_type=kyc_svc.sniff_media_type(head),
        headers={"Content-Disposition": f'inline; filename="{kind}.jpg"', "Cache-Control": "no-store, private", "Pragma": "no-cache"},
    )


async def _pending_shop_and_sub(db: AsyncSession, shop_id: str) -> tuple[Shop, KycSubmission]:
    shop = await get_shop_or_404(db, shop_id)
    if shop.verification != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, {"code": "ALREADY_REVIEWED", "message": "এই আবেদন আগেই যাচাই হয়েছে"})
    sub = await _latest_submission(db, shop.id)
    if sub is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no KYC submission for this shop")
    return shop, sub


@router.post("/{shop_id}/approve", response_model=KycListItemOut)
async def approve(request: Request, shop_id: str, auth: MutatingAdmin, db: DB):
    shop, sub = await _pending_shop_and_sub(db, shop_id)
    st = await get_settings_snapshot(db)
    now = now_utc()
    shop.verification = "approved"
    shop.verified_at = now
    shop.rejection_reason_bn = None
    shop.nid_number = sub.nid_number
    shop.trial_ends_at = now + timedelta(days=st.trial_days)
    sub.decision = "approved"
    sub.reviewed_by = auth.admin.id
    sub.reviewed_at = now
    await create_notification(db, shop_id=shop.id, kind="info", title_bn=APPROVED_TITLE, body_bn=APPROVED_BODY)
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="kyc.approved", target_type="shop", target_id=str(shop.id),
                request=request, meta={"submission_id": str(sub.id), "trial_days": st.trial_days})
    await db.commit()
    shop = await get_shop_or_404(db, shop_id)
    return await _item(db, shop, sub, st)


@router.post("/{shop_id}/reject", response_model=KycListItemOut)
async def reject(request: Request, shop_id: str, body: KycRejectIn, auth: MutatingAdmin, db: DB):
    shop, sub = await _pending_shop_and_sub(db, shop_id)
    now = now_utc()
    shop.verification = "rejected"
    shop.rejection_reason_bn = body.reason_bn
    sub.decision = "rejected"
    sub.reason_bn = body.reason_bn
    sub.reviewed_by = auth.admin.id
    sub.reviewed_at = now
    await create_notification(db, shop_id=shop.id, kind="warning", title_bn="অ্যাকাউন্ট যাচাই করা যায়নি",
                              body_bn=f"কারণ: {body.reason_bn} অনুগ্রহ করে সঠিক তথ্য দিয়ে আবার আবেদন করুন।")
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="kyc.rejected", target_type="shop", target_id=str(shop.id),
                request=request, meta={"submission_id": str(sub.id), "reason_bn": body.reason_bn})
    await db.commit()
    shop = await get_shop_or_404(db, shop_id)
    return await _item(db, shop, sub, await get_settings_snapshot(db))
