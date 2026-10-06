from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import Field, field_validator

from app.core.security import validate_bd_phone
from app.schemas.common import License, NotificationOut, OutModel, ShopPublic, StrictModel


class DeviceIn(StrictModel):
    device_id: str = Field(min_length=4, max_length=128)
    model: str | None = Field(default=None, max_length=120)
    os: str | None = Field(default=None, max_length=60)
    app_version: str | None = Field(default=None, max_length=30)
    signature_sha256: str | None = Field(default=None, max_length=64)


class LoginIn(StrictModel):
    phone: str = Field(max_length=20)
    password: str = Field(min_length=1, max_length=128)
    device: DeviceIn

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        return validate_bd_phone(v)


class RefreshIn(StrictModel):
    refresh_token: str = Field(min_length=10, max_length=2048)


class AuthOut(OutModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    shop: ShopPublic
    license: License


class MeOut(OutModel):
    shop: ShopPublic
    license: License
    notifications: list[NotificationOut]


TamperReason = Literal["ROOT_DETECTED", "SIGNATURE_MISMATCH", "DEBUGGER", "HOOKING_FRAMEWORK", "EMULATOR", "TAMPERED_BINARY"]


class TamperIn(StrictModel):
    phone: str = Field(max_length=20)
    device_id: str = Field(min_length=4, max_length=128)
    reason: TamperReason
    details: str | None = Field(default=None, max_length=2000)
    app_version: str | None = Field(default=None, max_length=30)

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        return validate_bd_phone(v)


class TamperOut(OutModel):
    locked: bool
    unlock_request_id: str
    message: str


class UnlockIn(StrictModel):
    phone: str = Field(max_length=20)
    device_id: str = Field(min_length=4, max_length=128)
    unlock_request_id: str = Field(min_length=9, max_length=12, pattern=r"^UL-[A-Z0-9]{6}$")
    unlock_code: str = Field(min_length=8, max_length=8, pattern=r"^\d{8}$")

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        return validate_bd_phone(v)


class UnlockOut(OutModel):
    unlocked: bool


PaymentMethod = Literal["bkash", "nagad", "rocket", "cash"]


class PaymentClaimIn(StrictModel):
    method: PaymentMethod
    trx_id: str = Field(min_length=3, max_length=64)
    amount: int = Field(gt=0, le=1_000_000)
    note: str | None = Field(default="", max_length=500)


class PaymentClaimOut(OutModel):
    id: uuid.UUID
    shop_id: uuid.UUID
    amount: int
    method: str
    trx_id: str
    note: str | None
    status: str
    reviewed_at: datetime | None = None
    created_at: datetime
