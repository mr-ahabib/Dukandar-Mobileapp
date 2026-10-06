from fastapi import APIRouter

from app.api.app_routes import auth, me, notifications, payment_claim, tamper

router = APIRouter(prefix="/app")
for r in (auth.router, me.router, tamper.router, notifications.router, payment_claim.router):
    router.include_router(r)
