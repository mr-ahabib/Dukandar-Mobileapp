from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy import select

from app.api.app_routes._helpers import shop_by_phone
from app.core.audit import audit
from app.core.deps import DB
from app.core.rate_limit import LOGIN_LIMIT, limiter
from app.core.security import generate_request_code, verify_password
from app.db.models import UnlockRequest
from app.schemas.app import TamperIn, TamperOut, UnlockIn, UnlockOut
from app.services.unlock import lock_device_and_create_request, try_unlock

router = APIRouter(tags=["app:security"])

LOCK_MESSAGE = "নিরাপত্তাজনিত কারণে এই ডিভাইসটি লক করা হয়েছে। আনলক কোডের জন্য সাপোর্টে যোগাযোগ করুন এবং রিকোয়েস্ট আইডি জানান।"


@router.post("/tamper-report", response_model=TamperOut)
@limiter.limit("10/minute")
async def tamper_report(request: Request, body: TamperIn, db: DB):
    shop = await shop_by_phone(db, body.phone)
    if shop is None:
        # Never reveal whether the phone exists: return a synthetic (unusable) request id.
        return TamperOut(locked=True, unlock_request_id=generate_request_code(), message=LOCK_MESSAGE)
    device = next((d for d in shop.devices if d.device_id == body.device_id), None)
    req, created = await lock_device_and_create_request(db, shop, device, body.device_id, body.reason, body.details, body.app_version)
    if created:
        await audit(db, actor_type="shop", actor_id=str(shop.id), action="tamper.locked", target_type="device", target_id=body.device_id,
                    request=request, meta={"reason": body.reason, "request_code": req.request_code, "app_version": body.app_version})
    await db.commit()
    return TamperOut(locked=True, unlock_request_id=req.request_code, message=LOCK_MESSAGE)


@router.post("/unlock", response_model=UnlockOut)
@limiter.limit(LOGIN_LIMIT)
async def unlock(request: Request, body: UnlockIn, db: DB):
    generic = {"code": "UNLOCK_FAILED", "message": "ভুল আনলক কোড বা রিকোয়েস্ট আইডি।"}
    shop = await shop_by_phone(db, body.phone)
    req = None
    if shop is not None:
        req = await db.scalar(
            select(UnlockRequest).where(
                UnlockRequest.shop_id == shop.id,
                UnlockRequest.device_id == body.device_id,
                UnlockRequest.request_code == body.unlock_request_id,
            )
        )
    if shop is None or req is None:
        verify_password(body.unlock_code, None)  # constant-time padding
        raise HTTPException(status.HTTP_400_BAD_REQUEST, generic)
    device = next((d for d in shop.devices if d.device_id == body.device_id), None)
    result = await try_unlock(db, req, device, body.unlock_code)
    action = "unlock.success" if result.ok else ("unlock.burned" if result.burned else "unlock.failed")
    await audit(db, actor_type="shop", actor_id=str(shop.id), action=action, target_type="unlock_request", target_id=req.request_code,
                request=request, meta={"attempts": req.attempts})
    await db.commit()
    if not result.ok:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, {
            "code": "REQUEST_BURNED" if result.burned else "WRONG_CODE",
            "message": result.message,
            "attempts_left": result.attempts_left,
        })
    return UnlockOut(unlocked=True)
