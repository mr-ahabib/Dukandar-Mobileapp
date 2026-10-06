from __future__ import annotations

import uuid
from datetime import datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict

T = TypeVar("T")


class StrictModel(BaseModel):
    """Reject unknown fields everywhere: the server must never accept business data."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class OutModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Page(BaseModel, Generic[T]):
    items: list[T]
    page: int
    page_size: int
    total: int


class PlanPublic(OutModel):
    id: uuid.UUID
    name: str
    price_bdt: int
    period_days: int


class ShopPublic(OutModel):
    id: uuid.UUID
    shop_name: str
    owner_name: str
    phone: str
    address: str | None = None
    plan: PlanPublic | None = None
    created_at: datetime


class PaymentInfo(BaseModel):
    bkash: str | None = None
    nagad: str | None = None
    instructions_bn: str | None = None
    support_phone: str | None = None


class PaymentPopup(BaseModel):
    show: bool
    every_minutes: int
    title_bn: str
    body_bn: str


class License(BaseModel):
    status: str
    verification: str = "approved"
    rejection_reason_bn: str | None = None
    verified_at: datetime | None = None
    payment_popup: PaymentPopup | None = None
    plan_name: str | None = None
    price_bdt: int | None = None
    trial_ends_at: datetime | None = None
    paid_until: datetime | None = None
    grace_ends_at: datetime | None = None
    next_due_at: datetime | None = None
    days_left: int
    grace_days: int
    message_bn: str
    server_time: datetime
    device_locked: bool
    features: list[str]
    payment_info: PaymentInfo


class NotificationOut(BaseModel):
    id: uuid.UUID
    title_bn: str
    body_bn: str
    kind: str
    created_at: datetime
    read: bool
