from __future__ import annotations

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from sqlalchemy import or_, select

from app.api.admin_routes._common import PageParams, page_out, page_params, paginate
from app.api.admin_routes.shops import record_payment
from app.core.audit import audit
from app.core.deps import DB, CurrentAdmin, MutatingAdmin, parse_uuid
from app.core.security import now_utc
from app.db.models import PaymentClaim, Shop
from app.schemas.admin import ClaimApproveIn, ClaimRejectIn, PaymentClaimAdminOut
from app.schemas.common import Page
from app.services.notifications import create_notification

router = APIRouter(prefix="/payment-claims", tags=["admin:payment-claims"])


def _out(c: PaymentClaim) -> PaymentClaimAdminOut:
    return PaymentClaimAdminOut(
        id=c.id, shop_id=c.shop_id, shop_name=c.shop.shop_name if c.shop else None, phone=c.shop.phone if c.shop else None,
        amount=c.amount, method=c.method, trx_id=c.trx_id, note=c.note, status=c.status, reviewed_by=c.reviewed_by,
        reviewed_at=c.reviewed_at, created_at=c.created_at,
    )


@router.get("", response_model=Page[PaymentClaimAdminOut])
async def list_claims(auth: CurrentAdmin, db: DB, p: PageParams = Depends(page_params), status: str | None = None):
    stmt = select(PaymentClaim).join(Shop, Shop.id == PaymentClaim.shop_id).order_by(PaymentClaim.created_at.desc())
    if status:
        stmt = stmt.where(PaymentClaim.status == status)
    if p.q:
        like = f"%{p.q}%"
        stmt = stmt.where(or_(PaymentClaim.trx_id.ilike(like), Shop.shop_name.ilike(like), Shop.phone.ilike(like)))
    rows, total = await paginate(db, stmt, p)
    return page_out([_out(r) for r in rows], total, p)


async def _get_pending(db, claim_id: str) -> PaymentClaim:
    c = await db.scalar(select(PaymentClaim).where(PaymentClaim.id == parse_uuid(claim_id, "claim")))
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "claim not found")
    if c.status != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, {"code": "ALREADY_REVIEWED", "message": "এই ক্লেইম আগেই যাচাই হয়েছে"})
    return c


@router.post("/{claim_id}/approve", response_model=PaymentClaimAdminOut)
async def approve(request: Request, claim_id: str, auth: MutatingAdmin, db: DB, body: ClaimApproveIn = Body(default=ClaimApproveIn())):
    c = await _get_pending(db, claim_id)
    shop = await db.scalar(select(Shop).where(Shop.id == c.shop_id))
    if shop is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "shop not found")
    await record_payment(db, request, auth.admin.id, shop, amount_bdt=c.amount, method=c.method, trx_id=c.trx_id, months=body.months,
                         note=body.note or c.note, source="claim")
    c.status = "approved"
    c.reviewed_by = auth.admin.id
    c.reviewed_at = now_utc()
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="payment_claim.approved", target_type="payment_claim",
                target_id=str(c.id), request=request, meta={"shop_id": str(shop.id), "months": body.months})
    await db.commit()
    await db.refresh(c)
    return _out(c)


@router.post("/{claim_id}/reject", response_model=PaymentClaimAdminOut)
async def reject(request: Request, claim_id: str, auth: MutatingAdmin, db: DB, body: ClaimRejectIn = Body(default=ClaimRejectIn())):
    c = await _get_pending(db, claim_id)
    c.status = "rejected"
    c.reviewed_by = auth.admin.id
    c.reviewed_at = now_utc()
    await create_notification(
        db, shop_id=c.shop_id, kind="warning", title_bn="পেমেন্ট যাচাই করা যায়নি",
        body_bn=f"ট্রানজেকশন {c.trx_id} যাচাই করা যায়নি।" + (f" কারণ: {body.note}" if body.note else "") + " অনুগ্রহ করে সাপোর্টে যোগাযোগ করুন।",
    )
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="payment_claim.rejected", target_type="payment_claim",
                target_id=str(c.id), request=request, meta={"note": body.note})
    await db.commit()
    await db.refresh(c)
    return _out(c)
