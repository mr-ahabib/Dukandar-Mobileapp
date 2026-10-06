from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy import select

from app.core.audit import audit
from app.core.deps import DB, CurrentShop
from app.core.rate_limit import limiter
from app.db.models import PaymentClaim
from app.schemas.app import PaymentClaimIn, PaymentClaimOut

router = APIRouter(tags=["app:payments"])


@router.post("/payment-claim", response_model=PaymentClaimOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")
async def create_claim(request: Request, body: PaymentClaimIn, auth: CurrentShop, db: DB):
    dup = await db.scalar(
        select(PaymentClaim).where(PaymentClaim.shop_id == auth.shop.id, PaymentClaim.trx_id == body.trx_id, PaymentClaim.status != "rejected")
    )
    if dup:
        raise HTTPException(status.HTTP_409_CONFLICT, {"code": "DUPLICATE_TRX", "message": "এই ট্রানজেকশন আইডি আগেই জমা দেওয়া হয়েছে"})
    claim = PaymentClaim(shop_id=auth.shop.id, amount=body.amount, method=body.method, trx_id=body.trx_id, note=body.note or None, status="pending")
    db.add(claim)
    await db.flush()
    await audit(db, actor_type="shop", actor_id=str(auth.shop.id), action="payment_claim.created", target_type="payment_claim",
                target_id=str(claim.id), request=request, meta={"amount": body.amount, "method": body.method})
    await db.commit()
    await db.refresh(claim)
    return claim
