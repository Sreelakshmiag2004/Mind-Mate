"""add media_assets.title and vault_locks

Revision ID: a7b8c9d0e1f2
Revises: f6a7b8c9d0a1
Create Date: 2026-09-13 00:00:00.000000

PHASE14B: the backend contract/schema for the Vault migration (see the
PHASE14A audit report and the PHASE14B implementation report).

Two purely additive changes, fully isolated from every existing table:

1. `media_assets.title` — a new nullable column. Every existing row gets
   `title = NULL` (its natural "never renamed" default; see
   app/models/media_asset.py) — no backfill, no data transformation, no
   existing row's behavior changes. `original_filename` is untouched.

2. `vault_locks` — a brand-new table, deliberately NOT added to `users`,
   `profiles`, or `media_assets` (per PHASE14A's explicit isolation
   requirement). One row per user (`UNIQUE(user_id)`), `password_hash`
   always Argon2id (see app/core/security.py), `ON DELETE CASCADE` so a
   deleted user's Vault lock is cleaned up automatically, matching every
   other per-user child table in this schema (scheduler_entries,
   shoutouts, media_assets, ...).

Nothing in this migration touches, reads, or migrates the old Flutter
app's Firestore `vaultPasswordHash`/`vaultLastViewed`/
`vaultPrevLastViewed` fields — those are untouched and out of scope here;
see the PHASE14B implementation report, "Migration/legacy data safety".
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.models.base import GUID

# revision identifiers, used by Alembic.
revision: str = "a7b8c9d0e1f2"
down_revision: Union[str, None] = "f6a7b8c9d0a1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("media_assets", sa.Column("title", sa.String(length=200), nullable=True))

    op.create_table(
        "vault_locks",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("last_viewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("previous_viewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_vault_locks_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_vault_locks")),
        sa.UniqueConstraint("user_id", name="uq_vault_locks_user_id"),
    )


def downgrade() -> None:
    op.drop_table("vault_locks")
    op.drop_column("media_assets", "title")
