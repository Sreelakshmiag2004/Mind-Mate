"""create scheduler_entries

Revision ID: f6a7b8c9d0a1
Revises: e5f6a7b8c9d0
Create Date: 2026-09-12 00:00:00.000000

Phase 11A: scheduler_entries — the first backend-authoritative storage
for the Scheduler feature (see the PHASE11 Flutter-side audit report).
The existing app has never had any backend for this; it stores an
unscoped, date-only-keyed Hive box directly on-device, with a confirmed
silent-overwrite bug when two rows share a time. UNIQUE(user_id,
entry_date, scheduled_time) fixes that at the database level, per
PHASE11A product decision 2. See app/models/scheduler.py for why
scheduled_time is a plain "HH:MM" string rather than a Time column.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.models.base import GUID

# revision identifiers, used by Alembic.
revision: str = "f6a7b8c9d0a1"
down_revision: Union[str, None] = "e5f6a7b8c9d0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "scheduler_entries",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("entry_date", sa.Date(), nullable=False),
        sa.Column("scheduled_time", sa.String(length=5), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_scheduler_entries_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_scheduler_entries")),
        sa.UniqueConstraint(
            "user_id",
            "entry_date",
            "scheduled_time",
            name="uq_scheduler_entries_user_id_entry_date_scheduled_time",
        ),
    )
    op.create_index(op.f("ix_scheduler_entries_user_id"), "scheduler_entries", ["user_id"], unique=False)
    op.create_index(
        "ix_scheduler_entries_user_id_entry_date",
        "scheduler_entries",
        ["user_id", "entry_date"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_scheduler_entries_user_id_entry_date", table_name="scheduler_entries")
    op.drop_index(op.f("ix_scheduler_entries_user_id"), table_name="scheduler_entries")
    op.drop_table("scheduler_entries")
