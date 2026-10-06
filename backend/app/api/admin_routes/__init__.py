from fastapi import APIRouter

from app.api.admin_routes import admins, audit, auth, dashboard, kyc, notifications, payment_claims, plans, settings, shops, unlock_requests

router = APIRouter(prefix="/admin/api")
for r in (auth.router, dashboard.router, shops.router, plans.router, payment_claims.router, unlock_requests.router,
          notifications.router, audit.router, admins.router, settings.router, kyc.router):
    router.include_router(r)
