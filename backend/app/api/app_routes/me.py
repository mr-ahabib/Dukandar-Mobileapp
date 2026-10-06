from __future__ import annotations

from fastapi import APIRouter

from app.api.app_routes._helpers import active_device, license_payload, shop_public
from app.core.deps import DB, CurrentShop
from app.core.security import now_utc
from app.schemas.app import MeOut
from app.schemas.common import License
from app.services.notifications import list_for_shop

router = APIRouter(tags=["app:me"])


@router.get("/me", response_model=MeOut)
async def me(auth: CurrentShop, db: DB):
    device = active_device(auth.shop)
    if device:
        device.last_seen_at = now_utc()
    lic = await license_payload(db, auth.shop, device)
    notes = await list_for_shop(db, auth.shop.id)
    await db.commit()
    return MeOut(shop=shop_public(auth.shop), license=lic, notifications=notes)


@router.get("/license", response_model=License)
async def license_(auth: CurrentShop, db: DB):
    device = active_device(auth.shop)
    if device:
        device.last_seen_at = now_utc()
    lic = await license_payload(db, auth.shop, device)
    await db.commit()
    return lic
