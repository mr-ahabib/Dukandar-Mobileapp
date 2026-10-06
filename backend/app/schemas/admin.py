from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import EmailStr, Field, field_validator

from app.core.security import validate_admin_password, validate_bd_phone, validate_shop_password
from app.schemas.common import OutModel, PlanPublic, StrictModel

Role = Literal["superadmin", "staff"]


class AdminOut(OutModel):
    id: uuid.UUID
    email: str
    role: str
    is_active: bool
    locked_until: datetime | None = None
    last_login_at: datetime | None = None
    created_at: datetime


class AdminLoginIn(StrictModel):
    email: EmailStr = Field(max_length=255)
    password: str = Field(min_length=1, max_length=128)
    totp: str | None = Field(default=None, max_length=8)


class AdminLoginOut(OutModel):
    csrf_token: str
    admin: AdminOut


class AdminMeOut(OutModel):
    admin: AdminOut
    csrf_token: str


class AdminCreateIn(StrictModel):
    email: EmailStr = Field(max_length=255)
    password: str = Field(max_length=128)
    role: Role = "staff"

    @field_validator("password")
    @classmethod
    def _pw(cls, v: str) -> str:
        validate_admin_password(v)
        return v


class AdminPatchIn(StrictModel):
    role: Role | None = None
    is_active: bool | None = None
    password: str | None = Field(default=None, max_length=128)
    unlock: bool | None = None

    @field_validator("password")
    @classmethod
    def _pw(cls, v: str | None) -> str | None:
        if v is not None:
            validate_admin_password(v)
        return v


class PlanCreateIn(StrictModel):
    name: str = Field(min_length=1, max_length=100)
    price_bdt: int = Field(ge=0, le=1_000_000)
    period_days: int = Field(ge=1, le=3650, default=30)
    is_active: bool = True


class PlanPatchIn(StrictModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    price_bdt: int | None = Field(default=None, ge=0, le=1_000_000)
    period_days: int | None = Field(default=None, ge=1, le=3650)
    is_active: bool | None = None


class PlanOut(PlanPublic):
    is_active: bool
    created_at: datetime


class ShopCreateIn(StrictModel):
    shop_name: str = Field(min_length=1, max_length=120)
    owner_name: str = Field(min_length=1, max_length=120)
    phone: str = Field(max_length=20)
    address: str | None = Field(default=None, max_length=255)
    plan_id: uuid.UUID | None = None
    password: str | None = Field(default=None, max_length=128, description="Omit to auto-generate a temp password")
    trial_days: int | None = Field(default=None, ge=0, le=365)
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        return validate_bd_phone(v)

    @field_validator("password")
    @classmethod
    def _pw(cls, v: str | None) -> str | None:
        if v is not None:
            validate_shop_password(v)
        return v


class ShopPatchIn(StrictModel):
    shop_name: str | None = Field(default=None, min_length=1, max_length=120)
    owner_name: str | None = Field(default=None, min_length=1, max_length=120)
    phone: str | None = Field(default=None, max_length=20)
    address: str | None = Field(default=None, max_length=255)
    plan_id: uuid.UUID | None = None
    trial_ends_at: datetime | None = None
    paid_until: datetime | None = None
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str | None) -> str | None:
        return validate_bd_phone(v) if v is not None else None


class DeviceOut(OutModel):
    id: uuid.UUID
    device_id: str
    model: str | None
    os: str | None
    app_version: str | None
    signature_sha256: str | None
    locked: bool
    lock_reason: str | None
    last_seen_at: datetime | None
    is_active: bool
    created_at: datetime


class ShopAdminOut(OutModel):
    id: uuid.UUID
    shop_name: str
    owner_name: str
    phone: str
    address: str | None
    plan: PlanPublic | None
    trial_ends_at: datetime | None
    paid_until: datetime | None
    is_disabled: bool
    notes: str | None
    status: str
    days_left: int
    grace_ends_at: datetime | None
    device: DeviceOut | None
    verification: str = "approved"
    verified_at: datetime | None = None
    rejection_reason_bn: str | None = None
    nid_number: str | None = None
    created_at: datetime
    updated_at: datetime


class ShopCreatedOut(OutModel):
    shop: ShopAdminOut
    temp_password: str


class TempPasswordOut(OutModel):
    temp_password: str


PaymentMethod = Literal["bkash", "nagad", "rocket", "cash", "bank", "other"]


class PaymentCreateIn(StrictModel):
    amount_bdt: int = Field(ge=0, le=1_000_000)
    method: PaymentMethod
    trx_id: str | None = Field(default=None, max_length=64)
    months: int = Field(ge=1, le=36, default=1)
    note: str | None = Field(default=None, max_length=500)


class PaymentOut(OutModel):
    id: uuid.UUID
    shop_id: uuid.UUID
    amount_bdt: int
    method: str
    trx_id: str | None
    months: int
    note: str | None
    recorded_by_admin_id: uuid.UUID | None
    paid_from: datetime
    paid_until: datetime
    created_at: datetime


class PaymentClaimAdminOut(OutModel):
    id: uuid.UUID
    shop_id: uuid.UUID
    shop_name: str | None = None
    phone: str | None = None
    amount: int
    method: str
    trx_id: str
    note: str | None
    status: str
    reviewed_by: uuid.UUID | None
    reviewed_at: datetime | None
    created_at: datetime


class ClaimApproveIn(StrictModel):
    months: int = Field(ge=1, le=36, default=1)
    note: str | None = Field(default=None, max_length=500)


class ClaimRejectIn(StrictModel):
    note: str | None = Field(default=None, max_length=500)


class UnlockRequestOut(OutModel):
    id: uuid.UUID
    shop_id: uuid.UUID
    shop_name: str | None = None
    phone: str | None = None
    device_id: str
    request_code: str
    unlock_code: str
    reason: str
    details: str | None
    app_version: str | None
    attempts: int
    status: str
    created_at: datetime
    used_at: datetime | None


class BroadcastIn(StrictModel):
    title_bn: str = Field(min_length=1, max_length=200)
    body_bn: str = Field(min_length=1, max_length=2000)
    kind: Literal["due", "info", "warning"] = "info"
    shop_ids: list[uuid.UUID] | None = Field(default=None, max_length=500)


class NotificationAdminOut(OutModel):
    id: uuid.UUID
    shop_id: uuid.UUID | None
    title_bn: str
    body_bn: str
    kind: str
    read_at: datetime | None
    created_at: datetime


class AuditOut(OutModel):
    id: uuid.UUID
    created_at: datetime
    actor_type: str
    actor_id: str | None
    action: str
    target_type: str | None
    target_id: str | None
    ip: str | None
    meta: dict[str, Any] | None


class SettingsOut(OutModel):
    bkash_number: str | None
    nagad_number: str | None
    instructions_bn: str | None
    grace_days: int
    trial_days: int
    reminder_days_before: int
    support_phone: str | None
    popup_every_minutes: int
    updated_at: datetime


class SettingsPatchIn(StrictModel):
    bkash_number: str | None = Field(default=None, max_length=15)
    nagad_number: str | None = Field(default=None, max_length=15)
    instructions_bn: str | None = Field(default=None, max_length=2000)
    grace_days: int | None = Field(default=None, ge=0, le=90)
    trial_days: int | None = Field(default=None, ge=0, le=365)
    reminder_days_before: int | None = Field(default=None, ge=0, le=30)
    support_phone: str | None = Field(default=None, max_length=15)
    popup_every_minutes: int | None = Field(default=None, ge=1, le=1440)


class KycRejectIn(StrictModel):
    reason_bn: str = Field(min_length=1, max_length=500)


class KycListItemOut(OutModel):
    shop: ShopAdminOut
    nid_number: str | None
    submitted_at: datetime | None
    liveness: dict[str, Any] | None
    files: list[str]
    decision: str | None = None
    reason_bn: str | None = None
    reviewed_at: datetime | None = None


class KycDetailOut(KycListItemOut):
    file_urls: dict[str, str]
    history: list[dict[str, Any]]


class RevenueMonthOut(OutModel):
    month: str  # YYYY-MM (UTC)
    total_bdt: int
    payments: int


class DashboardOut(OutModel):
    total_shops: int
    active: int
    trial: int
    due: int
    suspended: int
    disabled: int
    locked_devices: int
    mrr_bdt: int
    revenue_this_month_bdt: int
    pending_claims: int
    open_unlock_requests: int
    pending_kyc: int = 0
    recent_activity: list[AuditOut]
