"""create weekly_reflections

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-09-09 00:00:00.000000

Phase 5: one persisted row per (user, completed calendar week) — the
weekly-reflection cache app/services/reflection_service.py reads before
ever calling an AI provider. See app/models/reflection.py for the full
reasoning behind only two statuses ('completed'/'insufficient_data', no
'failed' row is ever persisted) and why `summary_input` — a serialized
WeeklySummary, never raw journal/shoutout content — is the only "input"
this migration stores.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.models.base import GUID

# revision identifiers, used by Alembic.
revision: str = "e5f6a7b8c9d0"
down_revision: Union[str, None] = "d4e5f6a7b8c9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "weekly_reflections",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("week_start", sa.Date(), nullable=False),
        sa.Column("week_end", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("summary_version", sa.String(length=20), nullable=False),
        sa.Column("summary_input", sa.JSON(), nullable=False),
        sa.Column("reflection_summary", sa.Text(), nullable=True),
        sa.Column("reflection_mood_insight", sa.Text(), nullable=True),
        sa.Column("reflection_habit_insight", sa.Text(), nullable=True),
        sa.Column("reflection_positive_highlights", sa.JSON(), nullable=True),
        sa.Column("reflection_areas_to_reflect_on", sa.JSON(), nullable=True),
        sa.Column("reflection_encouragement", sa.Text(), nullable=True),
        sa.Column("ai_provider", sa.String(length=50), nullable=True),
        sa.Column("ai_model", sa.String(length=100), nullable=True),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("status IN ('completed','insufficient_data')", name=op.f("ck_weekly_reflections_status")),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_weekly_reflections_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_weekly_reflections")),
        sa.UniqueConstraint("user_id", "week_start", name=op.f("uq_weekly_reflections_user_id_week_start")),
    )
    op.create_index("ix_weekly_reflections_user_id", "weekly_reflections", ["user_id"], unique=False)
    op.create_index(
        "ix_weekly_reflections_user_id_week_start", "weekly_reflections", ["user_id", "week_start"], unique=False
    )


def downgrade() -> None:
    op.drop_index("ix_weekly_reflections_user_id_week_start", table_name="weekly_reflections")
    op.drop_index("ix_weekly_reflections_user_id", table_name="weekly_reflections")
    op.drop_table("weekly_reflections")
