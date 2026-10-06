"""Password hashing (argon2id), JWT helpers, CSRF tokens, password policy, phone validation."""
from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import string
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt
from argon2 import PasswordHasher, Type
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from app.core.config import get_settings

_ph = PasswordHasher(time_cost=2, memory_cost=65536, parallelism=2, hash_len=32, salt_len=16, type=Type.ID)

# A real argon2 hash of a random secret; used to keep verification time constant for unknown users.
_DUMMY_HASH = _ph.hash(secrets.token_hex(16))

BD_PHONE_RE = re.compile(r"^01[3-9]\d{8}$")
SHOP_PASSWORD_MIN = 6
ADMIN_PASSWORD_MIN = 10


def now_utc() -> datetime:
    return datetime.now(UTC)


# ---- passwords -------------------------------------------------------------
def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    """Always runs an argon2 verify (even when no hash exists) so timing doesn't leak existence."""
    target = password_hash or _DUMMY_HASH
    try:
        ok = _ph.verify(target, password)
    except (VerifyMismatchError, InvalidHashError):
        ok = False
    return ok and password_hash is not None


def needs_rehash(password_hash: str) -> bool:
    try:
        return _ph.check_needs_rehash(password_hash)
    except Exception:  # pragma: no cover
        return False


def constant_time_equals(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))


def validate_shop_password(pw: str) -> None:
    if len(pw) < SHOP_PASSWORD_MIN or len(pw) > 128:
        raise ValueError(f"পাসওয়ার্ড কমপক্ষে {SHOP_PASSWORD_MIN} অক্ষরের হতে হবে")


def validate_admin_password(pw: str) -> None:
    if len(pw) < ADMIN_PASSWORD_MIN or len(pw) > 128:
        raise ValueError(f"Admin password must be at least {ADMIN_PASSWORD_MIN} characters")
    if pw.lower() == pw or not any(c.isdigit() for c in pw):
        raise ValueError("Admin password must contain an uppercase letter and a digit")


def validate_bd_phone(phone: str) -> str:
    p = phone.strip().replace(" ", "").replace("-", "")
    if p.startswith("+88"):
        p = p[3:]
    elif p.startswith("88") and len(p) == 13:
        p = p[2:]
    if not BD_PHONE_RE.match(p):
        raise ValueError("সঠিক বাংলাদেশি মোবাইল নম্বর দিন (01XXXXXXXXX)")
    return p


def generate_temp_password(length: int = 8) -> str:
    alphabet = string.ascii_uppercase.replace("O", "").replace("I", "") + string.digits.replace("0", "")
    return "".join(secrets.choice(alphabet) for _ in range(length))


def generate_unlock_code() -> str:
    return f"{secrets.randbelow(10**8):08d}"


def generate_request_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "UL-" + "".join(secrets.choice(alphabet) for _ in range(6))


def generate_csrf_token() -> str:
    return secrets.token_urlsafe(32)


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


# ---- JWT --------------------------------------------------------------------
TokenKind = Literal["app_access", "app_refresh", "admin_session"]


def _secret_for(kind: TokenKind) -> str:
    s = get_settings()
    return {
        "app_access": s.jwt_app_access_secret,
        "app_refresh": s.jwt_app_refresh_secret,
        "admin_session": s.jwt_admin_secret,
    }[kind]


def _ttl_for(kind: TokenKind) -> timedelta:
    s = get_settings()
    return {
        "app_access": timedelta(minutes=s.app_access_ttl_minutes),
        "app_refresh": timedelta(days=s.app_refresh_ttl_days),
        "admin_session": timedelta(hours=s.admin_session_ttl_hours),
    }[kind]


def create_token(kind: TokenKind, subject: str, extra: dict[str, Any] | None = None, ttl: timedelta | None = None) -> str:
    now = now_utc()
    payload: dict[str, Any] = {
        "sub": subject,
        "kind": kind,
        "iat": int(now.timestamp()),
        "exp": int((now + (ttl or _ttl_for(kind))).timestamp()),
        "jti": uuid.uuid4().hex,
    }
    if extra:
        payload.update(extra)
    return jwt.encode(payload, _secret_for(kind), algorithm="HS256")


def decode_token(kind: TokenKind, token: str) -> dict[str, Any] | None:
    try:
        payload = jwt.decode(token, _secret_for(kind), algorithms=["HS256"], options={"require": ["exp", "sub", "kind"]})
    except jwt.PyJWTError:
        return None
    if payload.get("kind") != kind:
        return None
    return payload
