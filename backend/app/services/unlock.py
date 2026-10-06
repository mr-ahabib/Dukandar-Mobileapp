"""Tamper lock / unlock request handling."""
from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import generate_request_code, generate_unlock_code, hash_password, now_utc, verify_password
from app.db.models import Device, Shop, UnlockRequest

MAX_ATTEMPTS = 5


async def get_open_request(db: AsyncSession, shop_id, device_id: str) -> UnlockRequest | None:
    return await db.scalar(
        select(UnlockRequest)
        .where(UnlockRequest.shop_id == shop_id, UnlockRequest.device_id == device_id, UnlockRequest.status == "open")
        .order_by(UnlockRequest.created_at.desc())
    )


async def lock_device_and_create_request(
    db: AsyncSession, shop: Shop, device: Device | None, device_id: str, reason: str, details: str | None, app_version: str | None
) -> tuple[UnlockRequest, bool]:
    """Idempotent: returns (request, created)."""
    if device is not None:
        device.locked = True
        device.lock_reason = reason
    existing = await get_open_request(db, shop.id, device_id)
    if existing:
        return existing, False

    code = generate_unlock_code()
    req_code = generate_request_code()
    for _ in range(5):  # ensure unique request code
        if not await db.scalar(select(UnlockRequest.id).where(UnlockRequest.request_code == req_code)):
            break
        req_code = generate_request_code()
    req = UnlockRequest(
        shop_id=shop.id,
        device_id=device_id,
        request_code=req_code,
        unlock_code_hash=hash_password(code),
        unlock_code=code,
        reason=reason,
        details=(details or "")[:2000] or None,
        app_version=app_version,
        attempts=0,
        status="open",
    )
    db.add(req)
    await db.flush()
    return req, True


@dataclass
class UnlockResult:
    ok: bool
    burned: bool = False
    attempts_left: int = 0
    message: str = ""


async def try_unlock(db: AsyncSession, req: UnlockRequest, device: Device | None, code: str) -> UnlockResult:
    if req.status != "open":
        return UnlockResult(False, burned=req.status == "burned", attempts_left=0, message="এই রিকোয়েস্টটি আর বৈধ নয়।")
    if verify_password(code, req.unlock_code_hash):
        req.status = "used"
        req.used_at = now_utc()
        req.attempts += 1
        if device is not None:
            device.locked = False
            device.lock_reason = None
        return UnlockResult(True, message="ডিভাইস আনলক হয়েছে।")
    req.attempts += 1
    if req.attempts >= MAX_ATTEMPTS:
        req.status = "burned"
        return UnlockResult(False, burned=True, attempts_left=0,
                            message="ভুল কোড ৫ বার দেওয়া হয়েছে। রিকোয়েস্টটি বাতিল। নতুন কোডের জন্য সাপোর্টে যোগাযোগ করুন।")
    left = MAX_ATTEMPTS - req.attempts
    return UnlockResult(False, attempts_left=left, message=f"ভুল আনলক কোড। আর {left} বার চেষ্টা করতে পারবেন।")
