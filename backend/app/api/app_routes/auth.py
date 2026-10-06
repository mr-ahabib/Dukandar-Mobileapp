from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile, status
from pydantic import ValidationError
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.app_routes._helpers import active_device, license_payload, shop_by_phone, shop_public
from app.core.audit import audit
from app.core.deps import DB, CurrentShop
from app.core.rate_limit import LOGIN_LIMIT, REGISTER_LIMIT, limiter
from app.core.security import create_token, decode_token, hash_password, needs_rehash, now_utc, sha256_hex, validate_bd_phone, verify_password
from app.db.models import Device, KycSubmission, Plan, RefreshToken, Shop
from app.schemas.app import AuthOut, DeviceIn, LoginIn, RefreshIn
from app.services import kyc as kyc_svc
from app.services.unlock import get_open_request

router = APIRouter(prefix="/auth", tags=["app:auth"])

INVALID = {"code": "INVALID_CREDENTIALS", "message": "ফোন নম্বর বা পাসওয়ার্ড ভুল"}


async def issue_tokens(db: AsyncSession, shop: Shop, device_id: str, family_id: uuid.UUID | None = None) -> tuple[str, str]:
    family_id = family_id or uuid.uuid4()
    access = create_token("app_access", str(shop.id), {"dev": device_id})
    refresh = create_token("app_refresh", str(shop.id), {"dev": device_id, "fam": str(family_id)})
    payload = decode_token("app_refresh", refresh)
    assert payload is not None
    db.add(
        RefreshToken(
            shop_id=shop.id,
            device_id=device_id,
            token_hash=sha256_hex(refresh),
            family_id=family_id,
            expires_at=datetime.fromtimestamp(payload["exp"], tz=UTC),
        )
    )
    return access, refresh


async def _auth_response(db: AsyncSession, shop: Shop, device: Device | None, access: str, refresh: str) -> AuthOut:
    lic = await license_payload(db, shop, device)
    return AuthOut(access_token=access, refresh_token=refresh, shop=shop_public(shop), license=lic)


def _locked_error(req) -> HTTPException:
    return HTTPException(
        status.HTTP_423_LOCKED,
        {
            "code": "DEVICE_LOCKED",
            "unlock_request_id": req.request_code if req else None,
            "hint": "নিরাপত্তাজনিত কারণে ডিভাইসটি লক করা হয়েছে। সাপোর্ট থেকে আনলক কোড সংগ্রহ করুন।",
        },
    )


@router.post("/login", response_model=AuthOut)
@limiter.limit(LOGIN_LIMIT)
async def login(request: Request, body: LoginIn, db: DB):
    shop = await shop_by_phone(db, body.phone)
    # Always run argon2 verify so timing doesn't reveal whether the phone exists.
    ok = verify_password(body.password, shop.password_hash if shop else None)
    if not shop or not ok:
        await audit(db, actor_type="shop", actor_id=None, action="app.login_failed", request=request, meta={"phone_suffix": body.phone[-4:]})
        await db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, INVALID)
    if shop.is_disabled:
        raise HTTPException(status.HTTP_403_FORBIDDEN, {"code": "ACCOUNT_DISABLED", "message": "অ্যাকাউন্ট বন্ধ করা হয়েছে। সাপোর্টে যোগাযোগ করুন।"})
    if needs_rehash(shop.password_hash):
        shop.password_hash = hash_password(body.password)

    dev_in: DeviceIn = body.device
    device = active_device(shop)
    now = now_utc()
    if device is None:
        device = Device(shop_id=shop.id, device_id=dev_in.device_id, is_active=True)
        db.add(device)
        shop.devices.append(device)
        await audit(db, actor_type="shop", actor_id=str(shop.id), action="device.bound", target_type="device", target_id=dev_in.device_id, request=request)
    elif device.device_id != dev_in.device_id:
        await audit(db, actor_type="shop", actor_id=str(shop.id), action="device.conflict", target_type="device", target_id=dev_in.device_id,
                    request=request, meta={"bound_device": device.device_id, "model": dev_in.model})
        await db.commit()
        raise HTTPException(status.HTTP_409_CONFLICT, {
            "code": "DEVICE_CONFLICT",
            "message": "এই অ্যাকাউন্টটি অন্য একটি ডিভাইসে যুক্ত আছে। ডিভাইস পরিবর্তন করতে সাপোর্টে যোগাযোগ করুন।",
            "bound_model": device.model,
        })

    device.model = dev_in.model or device.model
    device.os = dev_in.os or device.os
    device.app_version = dev_in.app_version or device.app_version
    device.signature_sha256 = dev_in.signature_sha256 or device.signature_sha256
    device.last_seen_at = now

    if device.locked:
        req = await get_open_request(db, shop.id, device.device_id)
        await db.commit()
        raise _locked_error(req)

    access, refresh = await issue_tokens(db, shop, device.device_id)
    await audit(db, actor_type="shop", actor_id=str(shop.id), action="app.login", target_type="device", target_id=device.device_id, request=request)
    await db.commit()
    await db.refresh(shop)
    return await _auth_response(db, shop, device, access, refresh)


def _verr(loc: str, msg: str) -> HTTPException:
    return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, {"code": "VALIDATION_ERROR", "errors": [{"loc": [loc], "msg": msg, "type": "value_error"}]})


@router.post("/register", response_model=AuthOut, status_code=status.HTTP_201_CREATED)
@limiter.limit(REGISTER_LIMIT)
async def register(
    request: Request,
    db: DB,
    shop_name: Annotated[str, Form(min_length=1, max_length=120)],
    owner_name: Annotated[str, Form(min_length=1, max_length=120)],
    phone: Annotated[str, Form(max_length=20)],
    password: Annotated[str, Form(min_length=6, max_length=128)],
    nid_number: Annotated[str, Form(max_length=30)],
    device: Annotated[str, Form(max_length=2000)],
    liveness: Annotated[str, Form(max_length=4000)],
    nid_front: Annotated[UploadFile, File()],
    nid_back: Annotated[UploadFile, File()],
    selfie: Annotated[UploadFile, File()],
    address: Annotated[str | None, Form(max_length=255)] = None,
    liveness_frames: Annotated[list[UploadFile] | None, File()] = None,
):
    """Self-registration with KYC. Creates a `pending` shop (no trial yet), stores the NID/selfie bundle privately, binds the device."""
    # ---- validate scalar fields ----
    try:
        phone_n = validate_bd_phone(phone)
    except ValueError as e:
        raise _verr("phone", str(e)) from None
    nid = kyc_svc.validate_nid(nid_number)
    try:
        dev_in = DeviceIn.model_validate(kyc_svc.parse_json_field("device", device))
    except ValidationError as e:
        raise _verr("device", e.errors()[0].get("msg", "invalid")) from None
    live = kyc_svc.validate_liveness(kyc_svc.parse_json_field("liveness", liveness))
    frames = [f for f in (liveness_frames or []) if f and f.filename]
    if len(frames) > kyc_svc.MAX_FRAMES:
        raise _verr("liveness_frames", f"সর্বোচ্চ {kyc_svc.MAX_FRAMES}টি ফ্রেম")

    # ---- read + validate images (size, magic bytes) before touching the DB ----
    blobs: dict[str, bytes] = {}
    for kind, up in (("nid_front", nid_front), ("nid_back", nid_back), ("selfie", selfie)):
        blobs[kind] = await kyc_svc.read_image(up, kind, kyc_svc.MAX_IMAGE)
    for i, up in enumerate(frames):
        blobs[f"frame_{i}"] = await kyc_svc.read_image(up, f"frame_{i}", kyc_svc.MAX_FRAME)

    # ---- phone uniqueness: rejected shops may re-apply with the same phone ----
    existing = await shop_by_phone(db, phone_n)
    if existing is not None and existing.verification != "rejected":
        raise HTTPException(status.HTTP_409_CONFLICT, {"code": "PHONE_TAKEN", "message": "এই নম্বরে আগেই অ্যাকাউন্ট আছে। লগইন করুন।"})

    now = now_utc()
    if existing is None:
        plan_id = await db.scalar(select(Plan.id).where(Plan.is_active.is_(True)).order_by(Plan.created_at).limit(1))
        shop = Shop(shop_name=shop_name.strip(), owner_name=owner_name.strip(), phone=phone_n, password_hash=hash_password(password),
                    address=(address or "").strip() or None, plan_id=plan_id, trial_ends_at=None, paid_until=None, verification="pending",
                    nid_number=nid, devices=[])
        db.add(shop)
        await db.flush()
        action = "shop.registered"
    else:
        shop = existing
        shop.shop_name = shop_name.strip()
        shop.owner_name = owner_name.strip()
        shop.password_hash = hash_password(password)
        shop.address = (address or "").strip() or None
        shop.nid_number = nid
        shop.verification = "pending"
        shop.rejection_reason_bn = None
        shop.verified_at = None
        shop.trial_ends_at = None
        shop.paid_until = None
        # previous sessions are invalid after a fresh application
        await db.execute(update(RefreshToken).where(RefreshToken.shop_id == shop.id).values(revoked=True))
        action = "shop.reregistered"

    files = kyc_svc.store_files(shop.id, blobs)
    db.add(KycSubmission(shop_id=shop.id, nid_number=nid, liveness_json=live, files_json=files, submitted_at=now))
    await db.flush()

    # ---- bind device (replace any previous active device on re-registration) ----
    device_row = active_device(shop)
    if device_row is not None and device_row.device_id != dev_in.device_id:
        device_row.is_active = False
        device_row = None
    if device_row is None:
        device_row = Device(shop_id=shop.id, device_id=dev_in.device_id, is_active=True)
        db.add(device_row)
        shop.devices.append(device_row)
        await audit(db, actor_type="shop", actor_id=str(shop.id), action="device.bound", target_type="device", target_id=dev_in.device_id, request=request)
    device_row.model = dev_in.model or device_row.model
    device_row.os = dev_in.os or device_row.os
    device_row.app_version = dev_in.app_version or device_row.app_version
    device_row.signature_sha256 = dev_in.signature_sha256 or device_row.signature_sha256
    device_row.last_seen_at = now
    device_row.locked = False
    device_row.lock_reason = None

    access, refresh_tok = await issue_tokens(db, shop, device_row.device_id)
    await audit(db, actor_type="shop", actor_id=str(shop.id), action=action, target_type="shop", target_id=str(shop.id), request=request,
                meta={"phone_suffix": phone_n[-4:], "files": sorted(files.keys()), "liveness_score": live["score"]})
    await db.commit()
    shop = await db.scalar(select(Shop).where(Shop.id == shop.id))
    return await _auth_response(db, shop, active_device(shop), access, refresh_tok)


@router.post("/refresh", response_model=AuthOut)
async def refresh(request: Request, body: RefreshIn, db: DB):
    invalid = HTTPException(status.HTTP_401_UNAUTHORIZED, {"code": "INVALID_REFRESH", "message": "আবার লগইন করুন"})
    payload = decode_token("app_refresh", body.refresh_token)
    if not payload:
        raise invalid
    row = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == sha256_hex(body.refresh_token)))
    if row is None:
        raise invalid
    if row.revoked or row.used_at is not None:
        # Reuse detected -> revoke the whole token family.
        await db.execute(update(RefreshToken).where(RefreshToken.family_id == row.family_id).values(revoked=True))
        await audit(db, actor_type="shop", actor_id=str(row.shop_id), action="refresh.reuse_detected", target_type="refresh_family",
                    target_id=str(row.family_id), request=request)
        await db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, {"code": "REFRESH_REUSED", "message": "নিরাপত্তার জন্য লগআউট করা হয়েছে, আবার লগইন করুন"})
    if row.expires_at < now_utc():
        raise invalid

    shop = await db.scalar(select(Shop).where(Shop.id == row.shop_id))
    if shop is None or shop.is_disabled:
        raise invalid
    device = active_device(shop)
    if device is None or device.device_id != row.device_id:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, {"code": "DEVICE_UNBOUND", "message": "ডিভাইস পরিবর্তিত, আবার লগইন করুন"})
    if device.locked:
        raise _locked_error(await get_open_request(db, shop.id, device.device_id))

    row.used_at = now_utc()
    device.last_seen_at = now_utc()
    access, new_refresh = await issue_tokens(db, shop, device.device_id, family_id=row.family_id)
    await db.commit()
    return await _auth_response(db, shop, device, access, new_refresh)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(request: Request, auth: CurrentShop, db: DB):
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.shop_id == auth.shop.id, RefreshToken.device_id == auth.device_id, RefreshToken.revoked.is_(False))
        .values(revoked=True)
    )
    await audit(db, actor_type="shop", actor_id=str(auth.shop.id), action="app.logout", request=request)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
