"""ORM models. The server stores ONLY accounts, subscriptions, devices, licensing — no business data."""
from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import Uuid

from app.db.base import Base, JSONType, TimestampMixin, TZDateTime, UUIDMixin


class Admin(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "admins"

    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False, default="staff")  # superadmin|staff
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    failed_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)
    totp_secret: Mapped[str | None] = mapped_column(String(64), nullable=True)
    last_login_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)


class Plan(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "plans"

    name: Mapped[str] = mapped_column(String(100), nullable=False)
    price_bdt: Mapped[int] = mapped_column(Integer, nullable=False)
    period_days: Mapped[int] = mapped_column(Integer, nullable=False, default=30)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class Shop(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "shops"

    shop_name: Mapped[str] = mapped_column(String(120), nullable=False)
    owner_name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone: Mapped[str] = mapped_column(String(11), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    address: Mapped[str | None] = mapped_column(String(255), nullable=True)
    plan_id: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("plans.id", ondelete="SET NULL"), nullable=True)
    trial_ends_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)
    paid_until: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)
    is_disabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_status: Mapped[str | None] = mapped_column(String(20), nullable=True)  # for transition audit
    # KYC: admin-created shops are 'approved'; self-registered start 'pending'
    verification: Mapped[str] = mapped_column(String(10), nullable=False, default="approved", server_default="approved", index=True)
    verified_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)
    rejection_reason_bn: Mapped[str | None] = mapped_column(Text, nullable=True)
    nid_number: Mapped[str | None] = mapped_column(String(20), nullable=True)

    plan: Mapped[Plan | None] = relationship(Plan, lazy="joined")
    devices: Mapped[list[Device]] = relationship("Device", back_populates="shop", lazy="selectin")


class KycSubmission(Base, UUIDMixin):
    """One KYC bundle per self-registration attempt (re-registration after rejection creates a new row)."""

    __tablename__ = "kyc_submissions"
    __table_args__ = (Index("ix_kyc_submissions_shop_submitted", "shop_id", "submitted_at"),)

    shop_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True)
    nid_number: Mapped[str] = mapped_column(String(20), nullable=False)
    liveness_json: Mapped[dict[str, Any] | None] = mapped_column(JSONType, nullable=True)
    files_json: Mapped[dict[str, Any]] = mapped_column(JSONType, nullable=False, default=dict)  # {kind: relative path}
    submitted_at: Mapped[datetime] = mapped_column(TZDateTime(), nullable=False)
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("admins.id", ondelete="SET NULL"), nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)
    decision: Mapped[str | None] = mapped_column(String(10), nullable=True)  # approved|rejected
    reason_bn: Mapped[str | None] = mapped_column(Text, nullable=True)

    shop: Mapped[Shop] = relationship(Shop, lazy="joined")


class Device(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "devices"
    __table_args__ = (
        Index("ix_devices_shop_device", "shop_id", "device_id"),
        Index("ix_devices_shop_active", "shop_id", "is_active"),
        # one ACTIVE device per shop (partial unique index; also enforced in code)
        Index("uq_devices_one_active_per_shop", "shop_id", unique=True, postgresql_where=text("is_active"), sqlite_where=text("is_active")),
    )

    shop_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    model: Mapped[str | None] = mapped_column(String(120), nullable=True)
    os: Mapped[str | None] = mapped_column(String(60), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(30), nullable=True)
    signature_sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    locked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    lock_reason: Mapped[str | None] = mapped_column(String(60), nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    shop: Mapped[Shop] = relationship(Shop, back_populates="devices")


class Payment(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "payments"
    __table_args__ = (Index("ix_payments_shop_created", "shop_id", "created_at"), Index("ix_payments_created_at", "created_at"))

    shop_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True)
    amount_bdt: Mapped[int] = mapped_column(Integer, nullable=False)
    method: Mapped[str] = mapped_column(String(20), nullable=False)
    trx_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    months: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    recorded_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("admins.id", ondelete="SET NULL"), nullable=True)
    paid_from: Mapped[datetime] = mapped_column(TZDateTime(), nullable=False)
    paid_until: Mapped[datetime] = mapped_column(TZDateTime(), nullable=False)


class PaymentClaim(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "payment_claims"
    __table_args__ = (Index("ix_payment_claims_status_created", "status", "created_at"),)

    shop_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    method: Mapped[str] = mapped_column(String(20), nullable=False)
    trx_id: Mapped[str] = mapped_column(String(64), nullable=False)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending", index=True)  # pending|approved|rejected
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("admins.id", ondelete="SET NULL"), nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)

    shop: Mapped[Shop] = relationship(Shop, lazy="joined")


class UnlockRequest(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "unlock_requests"
    __table_args__ = (
        UniqueConstraint("request_code", name="uq_unlock_requests_request_code"),
        Index("ix_unlock_requests_status_created", "status", "created_at"),
    )

    shop_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True)
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    request_code: Mapped[str] = mapped_column(String(12), nullable=False)
    unlock_code_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    # Product requirement: admins must be able to read the code in the panel.
    unlock_code: Mapped[str] = mapped_column(String(8), nullable=False)
    reason: Mapped[str] = mapped_column(String(40), nullable=False)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(30), nullable=True)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="open", index=True)  # open|used|burned|closed
    used_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)

    shop: Mapped[Shop] = relationship(Shop, lazy="joined")


class Notification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "notifications"
    __table_args__ = (Index("ix_notifications_shop_created", "shop_id", "created_at"),)

    shop_id: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), nullable=True, index=True)
    title_bn: Mapped[str] = mapped_column(String(200), nullable=False)
    body_bn: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(String(10), nullable=False, default="info")  # due|info|warning
    read_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)
    dedupe_key: Mapped[str | None] = mapped_column(String(80), nullable=True, index=True)


class NotificationRead(Base):
    """Read marks for broadcast notifications (shop_id NULL rows)."""

    __tablename__ = "notification_reads"
    notification_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("notifications.id", ondelete="CASCADE"), primary_key=True)
    shop_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), primary_key=True)
    read_at: Mapped[datetime] = mapped_column(TZDateTime(), nullable=False)


class RefreshToken(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "refresh_tokens"

    shop_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True)
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), nullable=False, index=True)
    expires_at: Mapped[datetime] = mapped_column(TZDateTime(), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    used_at: Mapped[datetime | None] = mapped_column(TZDateTime(), nullable=True)


class AuditLog(Base, UUIDMixin):
    __tablename__ = "audit_logs"

    created_at: Mapped[datetime] = mapped_column(TZDateTime(), nullable=False, index=True)
    actor_type: Mapped[str] = mapped_column(String(10), nullable=False)  # admin|shop|system
    actor_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    action: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    target_type: Mapped[str | None] = mapped_column(String(30), nullable=True)
    target_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    ip: Mapped[str | None] = mapped_column(String(45), nullable=True)
    meta: Mapped[dict[str, Any] | None] = mapped_column(JSONType, nullable=True)


class AppSettings(Base, TimestampMixin):
    __tablename__ = "settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    bkash_number: Mapped[str | None] = mapped_column(String(15), nullable=True)
    nagad_number: Mapped[str | None] = mapped_column(String(15), nullable=True)
    instructions_bn: Mapped[str | None] = mapped_column(Text, nullable=True)
    grace_days: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    trial_days: Mapped[int] = mapped_column(Integer, nullable=False, default=14)
    reminder_days_before: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    support_phone: Mapped[str | None] = mapped_column(String(15), nullable=True)
    popup_every_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=30, server_default="30")
