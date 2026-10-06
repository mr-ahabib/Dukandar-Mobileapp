"""performance indexes for SQLite/PostgreSQL hot paths

Revision ID: a1b2c3d4e5f6
Revises: 994bdb2f5db6
Create Date: 2026-10-04
"""
from alembic import op

revision = 'a1b2c3d4e5f6'
down_revision = '994bdb2f5db6'
branch_labels = None
depends_on = None

INDEXES = [
    ("ix_devices_shop_active", "devices", ["shop_id", "is_active"]),
    ("ix_payments_shop_created", "payments", ["shop_id", "created_at"]),
    ("ix_payments_created_at", "payments", ["created_at"]),
    ("ix_notifications_shop_created", "notifications", ["shop_id", "created_at"]),
    ("ix_payment_claims_status_created", "payment_claims", ["status", "created_at"]),
    ("ix_unlock_requests_status_created", "unlock_requests", ["status", "created_at"]),
]


def upgrade() -> None:
    # Already present from the initial schema: shops.phone (unique), audit_logs.created_at, unlock_requests.status,
    # payment_claims.status, refresh_tokens.token_hash (unique).
    for name, table, cols in INDEXES:
        with op.batch_alter_table(table) as batch_op:
            batch_op.create_index(name, cols, unique=False)


def downgrade() -> None:
    for name, table, _cols in reversed(INDEXES):
        with op.batch_alter_table(table) as batch_op:
            batch_op.drop_index(name)
