from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select

from app.api.admin_routes._common import PageParams, page_out, page_params, paginate
from app.core.audit import audit
from app.core.deps import DB, SuperAdmin, SuperAdminMutating, parse_uuid
from app.core.security import hash_password
from app.db.models import Admin
from app.schemas.admin import AdminCreateIn, AdminOut, AdminPatchIn
from app.schemas.common import Page

router = APIRouter(prefix="/admins", tags=["admin:admins"])


@router.get("", response_model=Page[AdminOut])
async def list_admins(auth: SuperAdmin, db: DB, p: PageParams = Depends(page_params)):
    stmt = select(Admin).order_by(Admin.created_at)
    if p.q:
        stmt = stmt.where(Admin.email.ilike(f"%{p.q}%"))
    rows, total = await paginate(db, stmt, p)
    return page_out([AdminOut.model_validate(r) for r in rows], total, p)


@router.post("", response_model=AdminOut, status_code=status.HTTP_201_CREATED)
async def create_admin(request: Request, body: AdminCreateIn, auth: SuperAdminMutating, db: DB):
    email = body.email.lower()
    if await db.scalar(select(Admin.id).where(Admin.email == email)):
        raise HTTPException(status.HTTP_409_CONFLICT, {"code": "EMAIL_EXISTS", "message": "Email already registered"})
    admin = Admin(email=email, password_hash=hash_password(body.password), role=body.role, is_active=True)
    db.add(admin)
    await db.flush()
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="admin.created", target_type="admin", target_id=str(admin.id),
                request=request, meta={"email": email, "role": body.role})
    await db.commit()
    await db.refresh(admin)
    return AdminOut.model_validate(admin)


@router.patch("/{admin_id}", response_model=AdminOut)
async def patch_admin(request: Request, admin_id: str, body: AdminPatchIn, auth: SuperAdminMutating, db: DB):
    admin = await db.scalar(select(Admin).where(Admin.id == parse_uuid(admin_id, "admin")))
    if admin is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "admin not found")
    data = body.model_dump(exclude_unset=True)
    if admin.id == auth.admin.id and (data.get("is_active") is False or (data.get("role") and data["role"] != "superadmin")):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, {"code": "SELF_DEMOTE", "message": "You cannot demote or deactivate yourself"})
    if "password" in data and data["password"]:
        admin.password_hash = hash_password(data.pop("password"))
    if data.pop("unlock", None):
        admin.locked_until = None
        admin.failed_attempts = 0
    for k, v in data.items():
        setattr(admin, k, v)
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="admin.updated", target_type="admin", target_id=str(admin.id),
                request=request, meta={"fields": sorted(body.model_dump(exclude_unset=True).keys())})
    await db.commit()
    await db.refresh(admin)
    return AdminOut.model_validate(admin)
