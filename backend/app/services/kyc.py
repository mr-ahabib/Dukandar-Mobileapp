"""KYC file storage + validation. Files live under <data_dir>/kyc/<shop_id>/<kind>.jpg (0600), never served publicly."""
from __future__ import annotations

import json
import os
import re
import uuid
from pathlib import Path
from typing import Any

from fastapi import HTTPException, UploadFile, status

from app.core.config import get_settings

MAX_IMAGE = 3 * 1024 * 1024
MAX_FRAME = 1 * 1024 * 1024
MAX_FRAMES = 3
REQUIRED_KINDS = ("nid_front", "nid_back", "selfie")
FRAME_KINDS = tuple(f"frame_{i}" for i in range(MAX_FRAMES))
ALL_KINDS = REQUIRED_KINDS + FRAME_KINDS
NID_RE = re.compile(r"^\d{10}$|^\d{13}$|^\d{17}$")
LIVENESS_CHALLENGES = {"blink", "turn_left", "turn_right", "smile", "nod", "open_mouth"}

_JPEG = b"\xff\xd8\xff"
_PNG = b"\x89PNG\r\n\x1a\n"


def _err(code: int, detail: Any) -> HTTPException:
    return HTTPException(code, detail)


def _verr(loc: list[str], msg: str) -> HTTPException:
    return _err(status.HTTP_422_UNPROCESSABLE_CONTENT, {"code": "VALIDATION_ERROR", "errors": [{"loc": loc, "msg": msg, "type": "value_error"}]})


def kyc_root() -> Path:
    return get_settings().data_path / "kyc"


def shop_dir(shop_id: uuid.UUID) -> Path:
    return kyc_root() / str(shop_id)


def validate_nid(nid: str) -> str:
    nid = (nid or "").strip().replace(" ", "")
    if not NID_RE.match(nid):
        raise _verr(["nid_number"], "NID নম্বর ১০, ১৩ বা ১৭ অঙ্কের হতে হবে")
    return nid


def parse_json_field(name: str, raw: str) -> dict[str, Any]:
    try:
        v = json.loads(raw)
    except (TypeError, ValueError):
        raise _verr([name], "JSON ভুল") from None
    if not isinstance(v, dict):
        raise _verr([name], "object প্রয়োজন")
    return v


def validate_liveness(v: dict[str, Any]) -> dict[str, Any]:
    errors = []
    if v.get("passed") is not True:
        errors.append({"loc": ["liveness", "passed"], "msg": "লাইভনেস পাস হয়নি", "type": "value_error"})
    ch = v.get("challenges")
    if not isinstance(ch, list) or not ch or not all(isinstance(c, str) and c in LIVENESS_CHALLENGES for c in ch):
        errors.append({"loc": ["liveness", "challenges"], "msg": "অবৈধ চ্যালেঞ্জ তালিকা", "type": "value_error"})
    score = v.get("score")
    if not isinstance(score, int | float) or isinstance(score, bool) or not 0.0 <= float(score) <= 1.0:
        errors.append({"loc": ["liveness", "score"], "msg": "score 0.0–1.0 হতে হবে", "type": "value_error"})
    if errors:
        raise _err(status.HTTP_422_UNPROCESSABLE_CONTENT, {"code": "VALIDATION_ERROR", "errors": errors})
    return {"passed": True, "challenges": ch, "score": float(score), "captured_at": v.get("captured_at")}


async def read_image(upload: UploadFile, kind: str, limit: int) -> bytes:
    """Read an upload fully, enforcing size (413) and JPEG/PNG magic bytes (422)."""
    data = await upload.read(limit + 1)
    if len(data) > limit:
        raise _err(status.HTTP_413_CONTENT_TOO_LARGE, {"code": "FILE_TOO_LARGE", "field": kind, "max_bytes": limit, "message": "ছবির সাইজ বেশি বড়"})
    if not (data.startswith(_JPEG) or data.startswith(_PNG)):
        raise _err(status.HTTP_422_UNPROCESSABLE_CONTENT, {"code": "BAD_IMAGE", "field": kind, "message": "শুধু JPEG/PNG ছবি গ্রহণযোগ্য"})
    return data


def store_files(shop_id: uuid.UUID, blobs: dict[str, bytes]) -> dict[str, str]:
    """Write blobs to <data_dir>/kyc/<shop_id>/<kind>.jpg with 0600 perms; wipes any previous bundle. Returns {kind: relpath}."""
    d = shop_dir(shop_id)
    d.mkdir(parents=True, exist_ok=True)
    os.chmod(d, 0o700)
    for old in d.glob("*"):
        if old.is_file():
            old.unlink()
    out: dict[str, str] = {}
    for kind, data in blobs.items():
        if kind not in ALL_KINDS:
            continue
        path = d / f"{kind}.jpg"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(path, 0o600)
        out[kind] = str(path.relative_to(kyc_root()))
    return out


def resolve_file(shop_id: uuid.UUID, files_json: dict[str, Any], kind: str) -> Path | None:
    """Return the absolute path for a stored kind, refusing anything outside the shop's directory."""
    rel = files_json.get(kind)
    if not rel or kind not in ALL_KINDS:
        return None
    root = kyc_root().resolve()
    p = (root / rel).resolve()
    if not str(p).startswith(str((root / str(shop_id)).resolve()) + os.sep) or not p.is_file():
        return None
    return p


def sniff_media_type(data: bytes) -> str:
    return "image/png" if data.startswith(_PNG) else "image/jpeg"
