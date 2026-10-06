"""FastAPI dependencies: DB session, shop (bearer) auth, admin (cookie + CSRF) auth, RBAC."""
from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import constant_time_equals, decode_token
from app.db.models import Admin, Shop
from app.db.session import get_db

DB = Annotated[AsyncSession, Depends(get_db)]


class ShopAuth:
    def __init__(self, shop: Shop, device_id: str):
        self.shop = shop
        self.device_id = device_id


async def get_current_shop(db: DB, authorization: Annotated[str | None, Header()] = None) -> ShopAuth:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated", headers={"WWW-Authenticate": "Bearer"})
    payload = decode_token("app_access", authorization[7:].strip())
    if not payload:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token", headers={"WWW-Authenticate": "Bearer"})
    try:
        shop_id = uuid.UUID(payload["sub"])
    except (ValueError, KeyError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token") from None
    shop = await db.scalar(select(Shop).where(Shop.id == shop_id))
    if shop is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    if shop.is_disabled:
        raise HTTPException(status.HTTP_403_FORBIDDEN, {"code": "ACCOUNT_DISABLED", "message": "অ্যাকাউন্ট বন্ধ করা হয়েছে"})
    device_id = payload.get("dev", "")
    active = next((d for d in shop.devices if d.is_active), None)
    if active is None or active.device_id != device_id:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, {"code": "DEVICE_UNBOUND", "message": "ডিভাইস আর যুক্ত নেই, আবার লগইন করুন"})
    return ShopAuth(shop, device_id)


CurrentShop = Annotated[ShopAuth, Depends(get_current_shop)]


class AdminAuth:
    def __init__(self, admin: Admin, csrf: str):
        self.admin = admin
        self.csrf = csrf


async def _admin_from_cookie(request: Request, db: AsyncSession) -> AdminAuth:
    s = get_settings()
    token = request.cookies.get(s.admin_cookie_name)
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    payload = decode_token("admin_session", token)
    if not payload:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired")
    try:
        admin_id = uuid.UUID(payload["sub"])
    except (ValueError, KeyError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid session") from None
    admin = await db.scalar(select(Admin).where(Admin.id == admin_id))
    if admin is None or not admin.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid session")
    return AdminAuth(admin, payload.get("csrf", ""))


async def get_current_admin(request: Request, db: DB) -> AdminAuth:
    """Read-only admin dependency (GET)."""
    return await _admin_from_cookie(request, db)


async def get_admin_mutating(request: Request, db: DB, x_csrf_token: Annotated[str | None, Header()] = None) -> AdminAuth:
    """Mutating admin dependency: cookie session + CSRF double submit."""
    auth = await _admin_from_cookie(request, db)
    if not x_csrf_token or not auth.csrf or not constant_time_equals(x_csrf_token, auth.csrf):
        raise HTTPException(status.HTTP_403_FORBIDDEN, {"code": "CSRF_INVALID", "message": "Missing or invalid CSRF token"})
    return auth


CurrentAdmin = Annotated[AdminAuth, Depends(get_current_admin)]
MutatingAdmin = Annotated[AdminAuth, Depends(get_admin_mutating)]


def require_superadmin(auth: AdminAuth) -> None:
    if auth.admin.role != "superadmin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, {"code": "FORBIDDEN", "message": "Superadmin only"})


async def get_superadmin(auth: CurrentAdmin) -> AdminAuth:
    require_superadmin(auth)
    return auth


async def get_superadmin_mutating(auth: MutatingAdmin) -> AdminAuth:
    require_superadmin(auth)
    return auth


SuperAdmin = Annotated[AdminAuth, Depends(get_superadmin)]
SuperAdminMutating = Annotated[AdminAuth, Depends(get_superadmin_mutating)]


def parse_uuid(value: str, what: str = "id") -> uuid.UUID:
    try:
        return uuid.UUID(value)
    except ValueError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"{what} not found") from None
