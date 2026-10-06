"""Application settings (pydantic-settings). All secrets come from the environment / .env."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Dukandar API"
    env: str = Field(default="development", alias="ENV")
    debug: bool = False

    # Default: embedded SQLite (WAL, tuned pragmas in app/db/session.py). PostgreSQL remains supported:
    #   DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/dukandar
    database_url: str = Field(default="sqlite+aiosqlite:///./data/dukandar.db", alias="DATABASE_URL")

    # Cache-busting version appended to admin panel asset URLs (?v=...). Bump on every panel release.
    static_version: str = Field(default="2026.10.04", alias="STATIC_VERSION")

    # Separate secrets per token family
    jwt_app_access_secret: str = Field(default="change-me-app-access", alias="JWT_APP_ACCESS_SECRET")
    jwt_app_refresh_secret: str = Field(default="change-me-app-refresh", alias="JWT_APP_REFRESH_SECRET")
    jwt_admin_secret: str = Field(default="change-me-admin", alias="JWT_ADMIN_SECRET")

    app_access_ttl_minutes: int = 15
    app_refresh_ttl_days: int = 30
    admin_session_ttl_hours: int = 8

    admin_cookie_name: str = "admin_session"
    admin_cookie_secure: bool = Field(default=True, alias="ADMIN_COOKIE_SECURE")

    admin_max_failed_attempts: int = 8
    admin_lockout_minutes: int = 15

    cors_origins: str = Field(default="", alias="CORS_ORIGINS")
    trust_proxy_headers: bool = Field(default=False, alias="TRUST_PROXY_HEADERS")

    scheduler_enabled: bool = Field(default=True, alias="SCHEDULER_ENABLED")
    scheduler_timezone: str = "Asia/Dhaka"
    scheduler_hour: int = 9

    # Admin panel SPA location (absolute or relative to backend/). Served at /admin.
    admin_panel_dir: str = Field(default="../admin-panel", alias="ADMIN_PANEL_DIR")

    # Private data directory (SQLite db, KYC uploads under <data_dir>/kyc/<shop_id>/). Relative to backend/.
    data_dir: str = Field(default="./data", alias="DATA_DIR")

    # First-run bootstrap
    auto_migrate: bool = Field(default=True, alias="AUTO_MIGRATE")
    superadmin_email: str = Field(default="", alias="SUPERADMIN_EMAIL")
    superadmin_password: str = Field(default="", alias="SUPERADMIN_PASSWORD")

    # Defaults used when the settings row doesn't exist yet
    default_grace_days: int = 10
    default_trial_days: int = 14
    default_reminder_days_before: int = 3
    default_popup_every_minutes: int = 30

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, v: str) -> str:
        if v.startswith("postgresql://"):
            v = v.replace("postgresql://", "postgresql+asyncpg://", 1)
        if v.startswith("sqlite://") and "+aiosqlite" not in v:
            v = v.replace("sqlite://", "sqlite+aiosqlite://", 1)
        return v

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")

    @property
    def admin_panel_path(self) -> Path:
        p = Path(self.admin_panel_dir)
        if not p.is_absolute():
            p = Path(__file__).resolve().parents[2] / p
        return p.resolve()

    @property
    def data_path(self) -> Path:
        p = Path(self.data_dir)
        if not p.is_absolute():
            p = Path(__file__).resolve().parents[2] / p
        return p.resolve()

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.env.lower() in {"production", "prod"}


@lru_cache
def get_settings() -> Settings:
    return Settings()
