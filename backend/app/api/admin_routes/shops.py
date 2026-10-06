from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.api.admin_routes._common import PageParams, page_out, page_params, paginate
from app.core.audit import audit
from app.core.deps import DB, CurrentAdmin, MutatingAdmin, parse_uuid
from app.core.security import generate_temp_password, hash_password, now_utc
from app.db.models import AuditLog, Device, Payment, Plan, RefreshToken, Shop, UnlockRequest
from app.schemas.admin import (
    AuditOut,
    DeviceOut,
    PaymentCreateIn,
    PaymentOut,
    ShopAdminOut,
    ShopCreatedOut,
    ShopCreateIn,
    ShopPatchIn,
    TempPasswordOut,
)
from app.schemas.common import Page, PlanPublic
from app.services.notifications import create_notification
from app.services.settings_service import SettingsSnapshot, get_settings_snapshot
from app.services.subscription import compute_status, extend_paid_until, status_sql

router = APIRouter(prefix="/shops", tags=["admin:shops"])


async def shop_out(db: AsyncSession, shop: Shop, st: SettingsSnapshot | None = None) -> ShopAdminOut:
    st = st or await get_settings_snapshot(db)
    info = compute_status(shop, st.grace_days)
    dev = next((d for d in shop.devices if d.is_active), None)
    return ShopAdminOut(
        id=shop.id, shop_name=shop.shop_name, owner_name=shop.owner_name, phone=shop.phone, address=shop.address,
        plan=PlanPublic.model_validate(shop.plan) if shop.plan else None,
        trial_ends_at=shop.trial_ends_at, paid_until=shop.paid_until, is_disabled=shop.is_disabled, notes=shop.notes,
        status=info.status, days_left=info.days_left, grace_ends_at=info.grace_ends_at,
        device=DeviceOut.model_validate(dev) if dev else None, verification=shop.verification, verified_at=shop.verified_at,
        rejection_reason_bn=shop.rejection_reason_bn, nid_number=shop.nid_number, created_at=shop.created_at, updated_at=shop.updated_at,
    )


async def get_shop_or_404(db: AsyncSession, shop_id: str) -> Shop:
    shop = await db.scalar(select(Shop).where(Shop.id == parse_uuid(shop_id, "shop")))
    if shop is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "shop not found")
    return shop


@router.get("", response_model=Page[ShopAdminOut])
async def list_shops(auth: CurrentAdmin, db: DB, p: PageParams = Depends(page_params), status_filter: str | None = None):
    st = await get_settings_snapshot(db)
    stmt = select(Shop).order_by(Shop.created_at.desc())
    if p.q:
        like = f"%{p.q}%"
        stmt = stmt.where(or_(Shop.shop_name.ilike(like), Shop.owner_name.ilike(like), Shop.phone.ilike(like)))
    if status_filter:
        stmt = stmt.where(status_sql(st.grace_days) == status_filter)
    # plan is lazy="joined" on the model; load only the ACTIVE device in the same query (no selectin round trip)
    stmt = stmt.options(joinedload(Shop.devices.and_(Device.is_active.is_(True))))
    rows, total = await paginate(db, stmt, p)
    return page_out([await shop_out(db, s, st) for s in rows], total, p)


@router.post("", response_model=ShopCreatedOut, status_code=status.HTTP_201_CREATED)
async def create_shop(request: Request, body: ShopCreateIn, auth: MutatingAdmin, db: DB):
    if await db.scalar(select(Shop.id).where(Shop.phone == body.phone)):
        raise HTTPException(status.HTTP_409_CONFLICT, {"code": "PHONE_EXISTS", "message": "এই নম্বরে আগেই অ্যাকাউন্ট আছে"})
    st = await get_settings_snapshot(db)
    plan_id = body.plan_id
    if plan_id is None:
        plan_id = await db.scalar(select(Plan.id).where(Plan.is_active.is_(True)).order_by(Plan.created_at).limit(1))
    elif not await db.scalar(select(Plan.id).where(Plan.id == plan_id)):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "plan not found")
    temp = body.password or generate_temp_password()
    trial_days = body.trial_days if body.trial_days is not None else st.trial_days
    shop = Shop(
        shop_name=body.shop_name, owner_name=body.owner_name, phone=body.phone, password_hash=hash_password(temp),
        address=body.address, plan_id=plan_id, trial_ends_at=now_utc() + timedelta(days=trial_days), notes=body.notes,
    )
    db.add(shop)
    await db.flush()
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="shop.created", target_type="shop", target_id=str(shop.id),
                request=request, meta={"phone": shop.phone, "trial_days": trial_days})
    await db.commit()
    shop = await get_shop_or_404(db, str(shop.id))
    return ShopCreatedOut(shop=await shop_out(db, shop), temp_password=temp)


@router.get("/{shop_id}", response_model=ShopAdminOut)
async def get_shop(shop_id: str, auth: CurrentAdmin, db: DB):
    return await shop_out(db, await get_shop_or_404(db, shop_id))


@router.patch("/{shop_id}", response_model=ShopAdminOut)
async def patch_shop(request: Request, shop_id: str, body: ShopPatchIn, auth: MutatingAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    data = body.model_dump(exclude_unset=True)
    if "phone" in data and data["phone"] != shop.phone:
        if await db.scalar(select(Shop.id).where(Shop.phone == data["phone"], Shop.id != shop.id)):
            raise HTTPException(status.HTTP_409_CONFLICT, {"code": "PHONE_EXISTS", "message": "এই নম্বরে আগেই অ্যাকাউন্ট আছে"})
    if "plan_id" in data and data["plan_id"] is not None and not await db.scalar(select(Plan.id).where(Plan.id == data["plan_id"])):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "plan not found")
    for k, v in data.items():
        setattr(shop, k, v)
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="shop.updated", target_type="shop", target_id=str(shop.id),
                request=request, meta={"fields": sorted(data.keys())})
    await db.commit()
    await db.refresh(shop)
    return await shop_out(db, shop)


@router.post("/{shop_id}/reset-password", response_model=TempPasswordOut)
async def reset_password(request: Request, shop_id: str, auth: MutatingAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    temp = generate_temp_password()
    shop.password_hash = hash_password(temp)
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="shop.password_reset", target_type="shop", target_id=str(shop.id), request=request)
    await db.commit()
    return TempPasswordOut(temp_password=temp)


async def _set_disabled(request: Request, shop_id: str, auth, db: AsyncSession, disabled: bool) -> ShopAdminOut:
    shop = await get_shop_or_404(db, shop_id)
    shop.is_disabled = disabled
    if disabled:
        from sqlalchemy import update

        await db.execute(update(RefreshToken).where(RefreshToken.shop_id == shop.id).values(revoked=True))
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="shop.disabled" if disabled else "shop.enabled",
                target_type="shop", target_id=str(shop.id), request=request)
    await db.commit()
    await db.refresh(shop)
    return await shop_out(db, shop)


@router.post("/{shop_id}/disable", response_model=ShopAdminOut)
async def disable_shop(request: Request, shop_id: str, auth: MutatingAdmin, db: DB):
    return await _set_disabled(request, shop_id, auth, db, True)


@router.post("/{shop_id}/enable", response_model=ShopAdminOut)
async def enable_shop(request: Request, shop_id: str, auth: MutatingAdmin, db: DB):
    return await _set_disabled(request, shop_id, auth, db, False)


@router.post("/{shop_id}/reset-device", response_model=ShopAdminOut)
async def reset_device(request: Request, shop_id: str, auth: MutatingAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    from sqlalchemy import update

    unbound = []
    for d in shop.devices:
        if d.is_active:
            d.is_active = False
            d.locked = False
            d.lock_reason = None
            unbound.append(d.device_id)
    await db.execute(update(RefreshToken).where(RefreshToken.shop_id == shop.id).values(revoked=True))
    await db.execute(update(UnlockRequest).where(UnlockRequest.shop_id == shop.id, UnlockRequest.status == "open").values(status="closed"))
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="shop.device_reset", target_type="shop", target_id=str(shop.id),
                request=request, meta={"unbound": unbound})
    await db.commit()
    shop = await get_shop_or_404(db, shop_id)
    return await shop_out(db, shop)


@router.get("/{shop_id}/devices", response_model=list[DeviceOut])
async def list_devices(shop_id: str, auth: CurrentAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    rows = (await db.execute(select(Device).where(Device.shop_id == shop.id).order_by(Device.created_at.desc()))).scalars().all()
    return [DeviceOut.model_validate(d) for d in rows]


@router.get("/{shop_id}/payments", response_model=list[PaymentOut])
async def list_payments(shop_id: str, auth: CurrentAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    rows = (await db.execute(select(Payment).where(Payment.shop_id == shop.id).order_by(Payment.created_at.desc()))).scalars().all()
    return [PaymentOut.model_validate(r) for r in rows]


async def record_payment(db: AsyncSession, request: Request, admin_id, shop: Shop, *, amount_bdt: int, method: str, trx_id: str | None,
                         months: int, note: str | None, source: str = "manual") -> Payment:
    period = shop.plan.period_days if shop.plan else 30
    paid_from, paid_until = extend_paid_until(shop, period, months)
    pay = Payment(shop_id=shop.id, amount_bdt=amount_bdt, method=method, trx_id=trx_id, months=months, note=note,
                  recorded_by_admin_id=admin_id, paid_from=paid_from, paid_until=paid_until)
    db.add(pay)
    await db.flush()
    await create_notification(
        db, shop_id=shop.id, kind="info", title_bn="পেমেন্ট গৃহীত হয়েছে",
        body_bn=f"ধন্যবাদ! {amount_bdt} টাকার পেমেন্ট গ্রহণ করা হয়েছে। আপনার সাবস্ক্রিপশন {paid_until.strftime('%d-%m-%Y')} পর্যন্ত সক্রিয়।",
    )
    await audit(db, actor_type="admin", actor_id=str(admin_id), action="payment.recorded", target_type="shop", target_id=str(shop.id),
                request=request, meta={"amount_bdt": amount_bdt, "method": method, "months": months, "trx_id": trx_id,
                                       "paid_until": paid_until.isoformat(), "source": source})
    return pay


@router.post("/{shop_id}/payments", response_model=PaymentOut, status_code=status.HTTP_201_CREATED)
async def create_payment(request: Request, shop_id: str, body: PaymentCreateIn, auth: MutatingAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    pay = await record_payment(db, request, auth.admin.id, shop, amount_bdt=body.amount_bdt, method=body.method, trx_id=body.trx_id,
                               months=body.months, note=body.note)
    await db.commit()
    await db.refresh(pay)
    return PaymentOut.model_validate(pay)


@router.get("/{shop_id}/audit", response_model=list[AuditOut])
async def shop_audit(shop_id: str, auth: CurrentAdmin, db: DB):
    shop = await get_shop_or_404(db, shop_id)
    sid = str(shop.id)
    rows = (
        await db.execute(
            select(AuditLog).where(or_(AuditLog.target_id == sid, AuditLog.actor_id == sid)).order_by(AuditLog.created_at.desc()).limit(200)
        )
    ).scalars().all()
    return [AuditOut.model_validate(r) for r in rows]
