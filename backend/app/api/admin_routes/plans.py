from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select

from app.api.admin_routes._common import PageParams, page_out, page_params, paginate
from app.core.audit import audit
from app.core.deps import DB, CurrentAdmin, MutatingAdmin, parse_uuid
from app.db.models import Plan
from app.schemas.admin import PlanCreateIn, PlanOut, PlanPatchIn
from app.schemas.common import Page

router = APIRouter(prefix="/plans", tags=["admin:plans"])


@router.get("", response_model=Page[PlanOut])
async def list_plans(auth: CurrentAdmin, db: DB, p: PageParams = Depends(page_params)):
    stmt = select(Plan).order_by(Plan.created_at)
    if p.q:
        stmt = stmt.where(Plan.name.ilike(f"%{p.q}%"))
    rows, total = await paginate(db, stmt, p)
    return page_out([PlanOut.model_validate(r) for r in rows], total, p)


@router.post("", response_model=PlanOut, status_code=status.HTTP_201_CREATED)
async def create_plan(request: Request, body: PlanCreateIn, auth: MutatingAdmin, db: DB):
    plan = Plan(**body.model_dump())
    db.add(plan)
    await db.flush()
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="plan.created", target_type="plan", target_id=str(plan.id),
                request=request, meta=body.model_dump())
    await db.commit()
    await db.refresh(plan)
    return PlanOut.model_validate(plan)


@router.patch("/{plan_id}", response_model=PlanOut)
async def patch_plan(request: Request, plan_id: str, body: PlanPatchIn, auth: MutatingAdmin, db: DB):
    plan = await db.scalar(select(Plan).where(Plan.id == parse_uuid(plan_id, "plan")))
    if plan is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "plan not found")
    data = body.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(plan, k, v)
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="plan.updated", target_type="plan", target_id=str(plan.id),
                request=request, meta=data)
    await db.commit()
    await db.refresh(plan)
    return PlanOut.model_validate(plan)
