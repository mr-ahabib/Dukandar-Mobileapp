from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status

from app.core.audit import audit
from app.core.deps import DB, CurrentAdmin, SuperAdminMutating
from app.core.security import validate_bd_phone
from app.schemas.admin import SettingsOut, SettingsPatchIn
from app.services.settings_service import get_app_settings, invalidate_settings_cache

router = APIRouter(prefix="/settings", tags=["admin:settings"])


@router.get("", response_model=SettingsOut)
async def get_settings_(auth: CurrentAdmin, db: DB):
    row = await get_app_settings(db)
    await db.commit()
    return SettingsOut.model_validate(row)


@router.patch("", response_model=SettingsOut)
async def patch_settings(request: Request, body: SettingsPatchIn, auth: SuperAdminMutating, db: DB):
    row = await get_app_settings(db)
    data = body.model_dump(exclude_unset=True)
    for key in ("bkash_number", "nagad_number", "support_phone"):
        if data.get(key):
            try:
                data[key] = validate_bd_phone(data[key])
            except ValueError as e:
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from None
    for k, v in data.items():
        setattr(row, k, v)
    await audit(db, actor_type="admin", actor_id=str(auth.admin.id), action="settings.updated", target_type="settings", target_id="1",
                request=request, meta={"fields": sorted(data.keys())})
    await db.commit()
    await db.refresh(row)
    invalidate_settings_cache()
    return SettingsOut.model_validate(row)
