"""create journals, moods, checklists

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2025-01-02 00:00:00.000000

Phase 2: journal_entries, mood_entries, checklist_items, checklist_completions.

`checklist_items` is seeded with the app's current 5 fixed wellness tasks
(see app/models/checklist.py) using stable, hard-coded UUIDs — hard-coded
specifically so every environment that runs this migration ends up with
the same catalog row ids, rather than a fresh random id per deployment.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.models.base import GUID

# revision identifiers, used by Alembic.
revision: str = "b2c3d4e5f6a7"
down_revision: Union[str, None] = "a1b2c3d4e5f6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Stable seed ids for the 5 default checklist items — see docstring above.
# Labels are copied verbatim from `checklistItems` in lib/homepage.dart.
_CHECKLIST_ITEM_SEED = [
    {"id": "9d1a2b3c-0001-4a11-8b11-000000000001", "label": "Drank enough water 💧", "sort_order": 0},
    {"id": "9d1a2b3c-0002-4a11-8b11-000000000002", "label": "Slept well last night 🛌", "sort_order": 1},
    {"id": "9d1a2b3c-0003-4a11-8b11-000000000003", "label": "Did one thing just for me 😉", "sort_order": 2},
    {
        "id": "9d1a2b3c-0004-4a11-8b11-000000000004",
        "label": "Got some fresh air and sunlight 🏝️",
        "sort_order": 3,
    },
    {"id": "9d1a2b3c-0005-4a11-8b11-000000000005", "label": "Exercised well 🧘‍♂️", "sort_order": 4},
]


def upgrade() -> None:
    op.create_table(
        "journal_entries",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("entry_date", sa.Date(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=True),
        sa.Column("content", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_journal_entries_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_journal_entries")),
        sa.UniqueConstraint("user_id", "entry_date", name="uq_journal_entries_user_id_entry_date"),
    )
    op.create_index(op.f("ix_journal_entries_user_id"), "journal_entries", ["user_id"], unique=False)

    op.create_table(
        "mood_entries",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("entry_date", sa.Date(), nullable=False),
        sa.Column("mood_value", sa.SmallInteger(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("mood_value >= 0 AND mood_value <= 100", name=op.f("ck_mood_entries_mood_value_range")),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_mood_entries_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_mood_entries")),
        sa.UniqueConstraint("user_id", "entry_date", name="uq_mood_entries_user_id_entry_date"),
    )
    op.create_index(op.f("ix_mood_entries_user_id"), "mood_entries", ["user_id"], unique=False)

    op.create_table(
        "checklist_items",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("label", sa.String(length=200), nullable=False),
        sa.Column("sort_order", sa.SmallInteger(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_checklist_items")),
    )

    op.create_table(
        "checklist_completions",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("checklist_item_id", GUID(), nullable=False),
        sa.Column("entry_date", sa.Date(), nullable=False),
        sa.Column("completed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_checklist_completions_user_id_users"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["checklist_item_id"],
            ["checklist_items.id"],
            name=op.f("fk_checklist_completions_checklist_item_id_checklist_items"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_checklist_completions")),
        sa.UniqueConstraint(
            "user_id", "checklist_item_id", "entry_date", name="uq_checklist_completions_user_item_date"
        ),
    )
    op.create_index(
        op.f("ix_checklist_completions_user_id"), "checklist_completions", ["user_id"], unique=False
    )
    op.create_index(
        op.f("ix_checklist_completions_checklist_item_id"),
        "checklist_completions",
        ["checklist_item_id"],
        unique=False,
    )
    op.create_index(
        "ix_checklist_completions_user_id_entry_date",
        "checklist_completions",
        ["user_id", "entry_date"],
        unique=False,
    )

    # --- Seed the fixed checklist catalog (data migration, not schema) ---
    checklist_items_table = sa.table(
        "checklist_items",
        sa.column("id", GUID()),
        sa.column("label", sa.String()),
        sa.column("sort_order", sa.SmallInteger()),
        sa.column("is_active", sa.Boolean()),
    )
    op.bulk_insert(
        checklist_items_table,
        [
            {"id": row["id"], "label": row["label"], "sort_order": row["sort_order"], "is_active": True}
            for row in _CHECKLIST_ITEM_SEED
        ],
    )


def downgrade() -> None:
    op.drop_index("ix_checklist_completions_user_id_entry_date", table_name="checklist_completions")
    op.drop_index(op.f("ix_checklist_completions_checklist_item_id"), table_name="checklist_completions")
    op.drop_index(op.f("ix_checklist_completions_user_id"), table_name="checklist_completions")
    op.drop_table("checklist_completions")

    op.drop_table("checklist_items")

    op.drop_index(op.f("ix_mood_entries_user_id"), table_name="mood_entries")
    op.drop_table("mood_entries")

    op.drop_index(op.f("ix_journal_entries_user_id"), table_name="journal_entries")
    op.drop_table("journal_entries")
