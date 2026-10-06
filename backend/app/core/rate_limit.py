from __future__ import annotations

from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import get_settings


def _key(request: Request) -> str:
    if get_settings().trust_proxy_headers:
        xff = request.headers.get("x-forwarded-for")
        if xff:
            return xff.split(",")[0].strip()
    return get_remote_address(request)


limiter = Limiter(key_func=_key, headers_enabled=False)
LOGIN_LIMIT = "5/minute"
REGISTER_LIMIT = "10/hour"
