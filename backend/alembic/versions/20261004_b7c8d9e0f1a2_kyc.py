"""self-registration with KYC: shops.verification + kyc_submissions + settings.popup_every_minutes

Revision ID: b7c8d9e0f1a2
Revises: a1b2c3d4e5f6
Create Date: 2026-10-04
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = 'b7c8d9e0f1a2'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("shops") as b:
        # existing rows (admin-created) are already verified
        b.add_column(sa.Column("verification", sa.String(length=10), nullable=False, server_default="approved"))
        b.add_column(sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True))
        b.add_column(sa.Column("rejection_reason_bn", sa.Text(), nullable=True))
        b.add_column(sa.Column("nid_number", sa.String(length=20), nullable=True))
        b.create_index("ix_shops_verification", ["verification"], unique=False)
    with op.batch_alter_table("settings") as b:
        b.add_column(sa.Column("popup_every_minutes", sa.Integer(), nullable=False, server_default="30"))
    op.create_table(
        "kyc_submissions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("shop_id", sa.Uuid(), nullable=False),
        sa.Column("nid_number", sa.String(length=20), nullable=False),
        sa.Column("liveness_json", sa.JSON().with_variant(postgresql.JSONB(), "postgresql"), nullable=True),
        sa.Column("files_json", sa.JSON().with_variant(postgresql.JSONB(), "postgresql"), nullable=False),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("reviewed_by", sa.Uuid(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decision", sa.String(length=10), nullable=True),
        sa.Column("reason_bn", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["shop_id"], ["shops.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reviewed_by"], ["admins.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_kyc_submissions_shop_id", "kyc_submissions", ["shop_id"], unique=False)
    op.create_index("ix_kyc_submissions_shop_submitted", "kyc_submissions", ["shop_id", "submitted_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_kyc_submissions_shop_submitted", table_name="kyc_submissions")
    op.drop_index("ix_kyc_submissions_shop_id", table_name="kyc_submissions")
    op.drop_table("kyc_submissions")
    with op.batch_alter_table("settings") as b:
        b.drop_column("popup_every_minutes")
    with op.batch_alter_table("shops") as b:
        b.drop_index("ix_shops_verification")
        b.drop_column("nid_number")
        b.drop_column("rejection_reason_bn")
        b.drop_column("verified_at")
        b.drop_column("verification")
