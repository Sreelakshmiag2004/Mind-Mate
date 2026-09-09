"""create shoutouts and media_assets

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2025-01-03 00:00:00.000000

Phase 3: shoutouts (one private entry per user per date, same shape as
journal_entries — see app/models/shoutout.py for why there is no
sender/recipient split) and media_assets (metadata only; binaries live in
S3-compatible object storage, never in this database).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.models.base import GUID

# revision identifiers, used by Alembic.
revision: str = "c3d4e5f6a7b8"
down_revision: Union[str, None] = "b2c3d4e5f6a7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "shoutouts",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("entry_date", sa.Date(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=True),
        sa.Column("content", sa.Text(), nullable=True),
        sa.Column("felt_better", sa.Boolean(), nullable=True),
        sa.Column("felt_better_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_shoutouts_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_shoutouts")),
        sa.UniqueConstraint("user_id", "entry_date", name="uq_shoutouts_user_id_entry_date"),
    )
    op.create_index(op.f("ix_shoutouts_user_id"), "shoutouts", ["user_id"], unique=False)
    op.create_index("ix_shoutouts_user_id_created_at", "shoutouts", ["user_id", "created_at"], unique=False)

    op.create_table(
        "media_assets",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("media_type", sa.String(length=10), nullable=False),
        sa.Column("original_filename", sa.String(length=255), nullable=True),
        sa.Column("object_key", sa.String(length=500), nullable=False),
        sa.Column("content_type", sa.String(length=100), nullable=False),
        sa.Column("file_size", sa.Integer(), nullable=False),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("media_type IN ('voice', 'image', 'video')", name=op.f("ck_media_assets_media_type")),
        sa.CheckConstraint("file_size > 0", name=op.f("ck_media_assets_file_size_positive")),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_media_assets_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_media_assets")),
        sa.UniqueConstraint("object_key", name="uq_media_assets_object_key"),
    )
    op.create_index(op.f("ix_media_assets_user_id"), "media_assets", ["user_id"], unique=False)
    op.create_index("ix_media_assets_user_id_created_at", "media_assets", ["user_id", "created_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_media_assets_user_id_created_at", table_name="media_assets")
    op.drop_index(op.f("ix_media_assets_user_id"), table_name="media_assets")
    op.drop_table("media_assets")

    op.drop_index("ix_shoutouts_user_id_created_at", table_name="shoutouts")
    op.drop_index(op.f("ix_shoutouts_user_id"), table_name="shoutouts")
    op.drop_table("shoutouts")
