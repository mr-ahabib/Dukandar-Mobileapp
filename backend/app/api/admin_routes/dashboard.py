from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.core.deps import DB, CurrentAdmin
from app.db.models import AuditLog, Device, Payment, PaymentClaim, Plan, Shop, UnlockRequest
from app.schemas.admin import AuditOut, DashboardOut, RevenueMonthOut
from app.services.settings_service import get_settings_snapshot
from app.services.subscription import status_sql

router = APIRouter(prefix="/dashboard", tags=["admin:dashboard"])


@router.get("", response_model=DashboardOut)
async def dashboard(auth: CurrentAdmin, db: DB):
    st = await get_settings_snapshot(db)
    now = datetime.now(UTC)
    status_col = status_sql(st.grace_days, now).label("st")
    # one grouped query: status x plan -> count (MRR derives from the active groups)
    grouped = (
        await db.execute(
            select(status_col, Plan.price_bdt, Plan.period_days, func.count(Shop.id))
            .select_from(Shop).outerjoin(Plan, Plan.id == Shop.plan_id)
            .group_by(status_col, Plan.price_bdt, Plan.period_days)
        )
    ).all()
    counts = {"trial": 0, "active": 0, "due": 0, "suspended": 0, "disabled": 0, "pending_verification": 0, "rejected": 0}
    mrr = 0
    for status, price, period, n in grouped:
        counts[status] = counts.get(status, 0) + n
        if status == "active" and price is not None:
            mrr += round(price * 30 / max(period or 30, 1)) * n
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    # the remaining scalars in a single round trip
    locked, revenue, pending, open_unlocks = (
        await db.execute(
            select(
                select(func.count()).select_from(Device).where(Device.locked.is_(True), Device.is_active.is_(True)).scalar_subquery(),
                select(func.coalesce(func.sum(Payment.amount_bdt), 0)).where(Payment.created_at >= month_start).scalar_subquery(),
                select(func.count()).select_from(PaymentClaim).where(PaymentClaim.status == "pending").scalar_subquery(),
                select(func.count()).select_from(UnlockRequest).where(UnlockRequest.status == "open").scalar_subquery(),
            )
        )
    ).one()
    recent = (await db.execute(select(AuditLog).order_by(AuditLog.created_at.desc()).limit(15))).scalars().all()
    return DashboardOut(
        total_shops=sum(counts.values()), pending_kyc=counts["pending_verification"],
        active=counts["active"], trial=counts["trial"], due=counts["due"], suspended=counts["suspended"],
        disabled=counts["disabled"], locked_devices=int(locked or 0), mrr_bdt=int(mrr), revenue_this_month_bdt=int(revenue or 0),
        pending_claims=int(pending or 0), open_unlock_requests=int(open_unlocks or 0), recent_activity=[AuditOut.model_validate(r) for r in recent],
    )


def _shift_month(d: datetime, months: int) -> datetime:
    y, m = divmod(d.month - 1 + months, 12)
    return d.replace(year=d.year + y, month=m + 1)


@router.get("/revenue", response_model=list[RevenueMonthOut])
async def revenue(auth: CurrentAdmin, db: DB, months: int = Query(6, ge=1, le=24)):
    """Revenue per calendar month (UTC) for the last `months` months, oldest first; months without payments are zero."""
    now = datetime.now(UTC)
    first = _shift_month(now.replace(day=1, hour=0, minute=0, second=0, microsecond=0), -(months - 1))
    rows = (await db.execute(select(Payment.created_at, Payment.amount_bdt).where(Payment.created_at >= first))).all()
    buckets: dict[str, list[int]] = {}
    for i in range(months):
        buckets[_shift_month(first, i).strftime("%Y-%m")] = [0, 0]
    for created_at, amount in rows:
        key = created_at.strftime("%Y-%m")
        if key in buckets:
            buckets[key][0] += amount
            buckets[key][1] += 1
    return [RevenueMonthOut(month=k, total_bdt=v[0], payments=v[1]) for k, v in buckets.items()]
