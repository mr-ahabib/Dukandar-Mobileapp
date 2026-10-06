"""FastAPI application factory for Dukandar backend."""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from starlette.middleware.base import BaseHTTPMiddleware

from app.api.admin_routes import router as admin_router
from app.api.app_routes import router as app_router
from app.core.bootstrap import run_bootstrap
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.core.scheduler import start_scheduler, stop_scheduler

CSP = (
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
    "font-src 'self' https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; "
    "frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"
)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        h = response.headers
        h.setdefault("Content-Security-Policy", CSP)
        h.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        h.setdefault("X-Frame-Options", "DENY")
        h.setdefault("X-Content-Type-Options", "nosniff")
        h.setdefault("Referrer-Policy", "no-referrer")
        h.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        path = request.url.path
        if path.startswith(("/api", "/admin/api")):
            h.setdefault("Cache-Control", "no-store")
        elif path.startswith("/admin/") and "." in path.rsplit("/", 1)[-1]:
            # static asset: immutable when versioned (?v=...), otherwise revalidate
            h["Cache-Control"] = "public, max-age=31536000, immutable" if "v" in request.query_params else "public, max-age=0, must-revalidate"
        return response


class BodySizeLimitMiddleware(BaseHTTPMiddleware):
    MAX = 64 * 1024
    MAX_REGISTER = 14 * 1024 * 1024  # 3 jpeg x 3MB + 3 frames x 1MB + form fields
    REGISTER_PATH = "/api/v1/app/auth/register"

    async def dispatch(self, request: Request, call_next):
        cl = request.headers.get("content-length")
        limit = self.MAX_REGISTER if request.url.path == self.REGISTER_PATH else self.MAX
        if cl and cl.isdigit() and int(cl) > limit:
            return JSONResponse({"detail": "payload too large"}, status_code=413)
        return await call_next(request)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await run_bootstrap()
    start_scheduler()
    try:
        yield
    finally:
        stop_scheduler()


def create_app() -> FastAPI:
    s = get_settings()
    logging.basicConfig(level=logging.DEBUG if s.debug else logging.INFO)
    app = FastAPI(title=s.app_name, version="1.1.0", lifespan=lifespan,
                  docs_url="/api/docs" if not s.is_production else None, redoc_url=None,
                  openapi_url="/api/openapi.json" if not s.is_production else None)
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(BodySizeLimitMiddleware)

    if s.cors_origin_list:
        from fastapi.middleware.cors import CORSMiddleware

        app.add_middleware(CORSMiddleware, allow_origins=s.cors_origin_list, allow_credentials=True,
                           allow_methods=["GET", "POST", "PATCH", "DELETE"], allow_headers=["Authorization", "Content-Type", "X-CSRF-Token"])

    @app.exception_handler(RequestValidationError)
    async def validation_handler(request: Request, exc: RequestValidationError):
        errors = []
        for e in exc.errors():
            errors.append({"loc": [str(x) for x in e.get("loc", [])], "msg": e.get("msg", ""), "type": e.get("type", "")})
        return JSONResponse(status_code=422, content={"detail": {"code": "VALIDATION_ERROR", "errors": errors}})

    app.include_router(app_router, prefix="/api/v1")
    app.include_router(admin_router)

    @app.get("/healthz", include_in_schema=False)
    async def healthz():
        return {"status": "ok"}

    panel = s.admin_panel_path
    if (panel / "index.html").exists():
        # index.html is read once; "__V__" placeholders become the build version so assets are cached immutably.
        index_html = (panel / "index.html").read_text(encoding="utf-8").replace("__V__", s.static_version)

        @app.get("/admin", include_in_schema=False)
        @app.get("/admin/", include_in_schema=False)
        async def admin_index():
            return HTMLResponse(index_html, headers={"Cache-Control": "no-cache"})

        app.mount("/admin", StaticFiles(directory=str(panel), html=True), name="admin_panel")
    else:
        logging.getLogger("dukandar").warning("admin panel not found at %s (ADMIN_PANEL_DIR); /admin disabled", panel)
    return app


app = create_app()
