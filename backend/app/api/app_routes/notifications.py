from __future__ import annotations

from fastapi import APIRouter, HTTPException, Response, status

from app.core.deps import DB, CurrentShop, parse_uuid
from app.services.notifications import mark_read

router = APIRouter(prefix="/notifications", tags=["app:notifications"])


@router.post("/{notification_id}/read", status_code=status.HTTP_204_NO_CONTENT)
async def read_notification(notification_id: str, auth: CurrentShop, db: DB):
    nid = parse_uuid(notification_id, "notification")
    if not await mark_read(db, auth.shop.id, nid):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "notification not found")
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
