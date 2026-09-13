"""add media_assets legacy_source tracking

Revision ID: b8c9d0e1f2a3
Revises: a7b8c9d0e1f2
Create Date: 2026-09-13 12:00:00.000000

PHASE14I-B: the backend contract for safe, duplicate-proof legacy Hive
media tracking ahead of the eventual one-time Flutter Vault migration
(see the PHASE14I-B implementation report for the full design). This
migration performs NO data migration itself — it only adds schema
support two purely additive, nullable columns plus one partial unique
index, fully isolated from every existing row:

1. `media_assets.legacy_source` — nullable `VARCHAR(300)`. Every existing
   row gets `NULL` (its natural "not a migrated row" default; see
   app/models/media_asset.py) — no backfill, no data transformation, no
   existing row's behavior changes.

2. `media_assets.legacy_created_at` — nullable, timezone-aware
   `TIMESTAMP`, matching every other datetime column in this schema (see
   app/models/base.py's TimestampMixin). Every existing row gets `NULL`.
   Deliberately independent of `created_at`, whose meaning is unchanged.

3. `uq_media_assets_user_id_legacy_source` — a PARTIAL unique index on
   `(user_id, legacy_source)`, restricted to `WHERE legacy_source IS NOT
   NULL`. This is the database-level, final-backstop guarantee that the
   same legacy_source can never produce two rows for one user, even
   under a concurrent retry (see app/services/media_service.py). It is
   partial specifically so that the (very large, and growing) set of
   ordinary uploads with `legacy_source IS NULL` is entirely unaffected
   — a plain `UniqueConstraint("user_id", "legacy_source")` would risk
   depending on the database's NULL-handling in unique constraints
   instead of a rule this schema states explicitly.

Nothing in this migration touches any other table, and no existing
media_assets row's `legacy_source`/`legacy_created_at` becomes anything
other than NULL — this migration adds capability, it does not migrate
data.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "b8c9d0e1f2a3"
down_revision: Union[str, None] = "a7b8c9d0e1f2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("media_assets", sa.Column("legacy_source", sa.String(length=300), nullable=True))
    op.add_column(
        "media_assets", sa.Column("legacy_created_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.create_index(
        "uq_media_assets_user_id_legacy_source",
        "media_assets",
        ["user_id", "legacy_source"],
        unique=True,
        postgresql_where=sa.text("legacy_source IS NOT NULL"),
        sqlite_where=sa.text("legacy_source IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_media_assets_user_id_legacy_source", table_name="media_assets")
    op.drop_column("media_assets", "legacy_created_at")
    op.drop_column("media_assets", "legacy_source")
