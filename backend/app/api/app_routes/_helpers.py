from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Device, Shop
from app.schemas.common import ShopPublic
from app.services.settings_service import get_settings_snapshot
from app.services.subscription import build_license


async def shop_by_phone(db: AsyncSession, phone: str) -> Shop | None:
    return await db.scalar(select(Shop).where(Shop.phone == phone))


def active_device(shop: Shop) -> Device | None:
    return next((d for d in shop.devices if d.is_active), None)


async def license_payload(db: AsyncSession, shop: Shop, device: Device | None) -> dict:
    settings_row = await get_settings_snapshot(db)
    return build_license(shop, settings_row, device_locked=bool(device and device.locked))


def shop_public(shop: Shop) -> ShopPublic:
    return ShopPublic.model_validate(shop)
