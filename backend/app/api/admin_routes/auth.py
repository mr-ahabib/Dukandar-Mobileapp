from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, HTTPException, Request, Response, status
from sqlalchemy import select

from app.core.audit import audit
from app.core.config import get_settings
from app.core.deps import DB, CurrentAdmin, MutatingAdmin
from app.core.rate_limit import LOGIN_LIMIT, limiter
from app.core.security import create_token, generate_csrf_token, now_utc, verify_password
from app.db.models import Admin
from app.schemas.admin import AdminLoginIn, AdminLoginOut, AdminMeOut, AdminOut

router = APIRouter(prefix="/auth", tags=["admin:auth"])
INVALID = {"code": "INVALID_CREDENTIALS", "message": "ইমেইল বা পাসওয়ার্ড ভুল"}


def set_session_cookie(response: Response, token: str) -> None:
    s = get_settings()
    response.set_cookie(
        key=s.admin_cookie_name,
        value=token,
        max_age=s.admin_session_ttl_hours * 3600,
        httponly=True,
        secure=s.admin_cookie_secure,
        samesite="strict",
        path="/admin",
    )


@router.post("/login", response_model=AdminLoginOut)
@limiter.limit(LOGIN_LIMIT)
async def login(request: Request, response: Response, body: AdminLoginIn, db: DB):
    s = get_settings()
    admin = await db.scalar(select(Admin).where(Admin.email == body.email.lower()))
    now = now_utc()
    if admin and admin.locked_until and admin.locked_until > now:
        verify_password(body.password, None)
        raise HTTPException(status.HTTP_423_LOCKED, {"code": "ACCOUNT_LOCKED", "message": "অনেকবার ভুল চেষ্টা। ১৫ মিনিট পর আবার চেষ্টা করুন।"})
    ok = verify_password(body.password, admin.password_hash if admin else None)
    if not admin or not ok or not admin.is_active:
        if admin and admin.is_active:
            admin.failed_attempts += 1
            if admin.failed_attempts >= s.admin_max_failed_attempts:
                admin.locked_until = now + timedelta(minutes=s.admin_lockout_minutes)
                admin.failed_attempts = 0
                await audit(db, actor_type="system", actor_id=None, action="admin.locked_out", target_type="admin", target_id=str(admin.id), request=request)
        await audit(db, actor_type="admin", actor_id=str(admin.id) if admin else None, action="admin.login_failed", request=request,
                    meta={"email": body.email.lower()})
        await db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, INVALID)
    admin.failed_attempts = 0
    admin.locked_until = None
    admin.last_login_at = now
    csrf = generate_csrf_token()
    token = create_token("admin_session", str(admin.id), {"csrf": csrf, "role": admin.role})
    set_session_cookie(response, token)
    await audit(db, actor_type="admin", actor_id=str(admin.id), action="admin.login", request=request)
    await db.commit()
    return AdminLoginOut(csrf_token=csrf, admin=AdminOut.model_validate(admin))


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(request: Request, response: Response, auth: MutatingAdmin, db: DB):
    s = get_settings()
    response.delete_cookie(s.admin_cookie_name, path="/admin")
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="admin.logout", request=request)
    await db.commit()
    response.status_code = status.HTTP_204_NO_CONTENT
    return response


@router.get("/me", response_model=AdminMeOut)
async def me(auth: CurrentAdmin):
    return AdminMeOut(admin=AdminOut.model_validate(auth.admin), csrf_token=auth.csrf)
