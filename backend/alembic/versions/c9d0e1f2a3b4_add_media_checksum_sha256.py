"""add media_assets checksum_sha256

Revision ID: c9d0e1f2a3b4
Revises: b8c9d0e1f2a3
Create Date: 2026-09-13 18:00:00.000000

PHASE14I-G.1: the backend content-integrity foundation for a future,
still-unbuilt verify-before-delete step (see the PHASE14I-G audit report
and the PHASE14I-G.1 implementation report for the full design). This
migration performs NO data migration, backfill, or object-storage access
of any kind — it only adds one purely additive, nullable column plus one
new (also additive) check constraint, fully isolated from every existing
row and every existing constraint:

1. `media_assets.checksum_sha256` — nullable `VARCHAR(64)`. Every
   existing row gets `NULL` (there is no code path in this migration, or
   anywhere else in this phase, that reads back a historical object from
   S3/MinIO to compute one — see app/models/media_asset.py's module
   docstring and the PHASE14I-G.1 implementation report,
   "Historical-row behavior", for why that is explicitly out of scope
   here). Only a NEWLY uploaded row (via the updated
   app/services/media_service.py.upload_media, from this revision
   onward) ever gets a non-NULL value.

2. `ck_media_assets_checksum_sha256_length` — a new CHECK constraint
   requiring `checksum_sha256` to be either NULL or exactly 64 characters
   (a SHA-256 hex digest's fixed length). Deliberately a length-only
   check, not a full `[0-9a-f]{64}` character-class check: SQLite has no
   portable equivalent to PostgreSQL's `~` regex operator, and this
   project's test suite runs against SQLite (tests/conftest.py) — see
   app/models/media_asset.py's own comment on this same constraint for
   the full reasoning. The hex-only guarantee is an application-level
   one instead: the sole writer of this column only ever stores
   `hashlib.sha256(data).hexdigest()`'s direct output.

Both changes are made inside a single `op.batch_alter_table(...)` block:
SQLite (this project's test-suite dialect — tests/conftest.py) has no
`ALTER TABLE ... ADD CONSTRAINT`/`DROP CONSTRAINT` support at all
(confirmed directly: `op.create_check_constraint`/`op.drop_constraint`
raise `NotImplementedError` against it outside batch mode) — Alembic's
batch mode is the standard, documented way to add a CHECK constraint
portably; on SQLite it transparently recreates the table with the new
constraint included, and on PostgreSQL (the only real production target
— see app/models/base.py) it emits the exact same plain `ALTER TABLE`
statements `add_column`/`create_check_constraint` would have anyway, so
production behavior is unchanged.

Nothing in this migration touches any other table or column, no existing
CHECK constraint or index is modified, and no existing media_assets row's
`checksum_sha256` becomes anything other than NULL — this migration adds
capability, it does not touch data.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "c9d0e1f2a3b4"
down_revision: Union[str, None] = "b8c9d0e1f2a3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("media_assets") as batch_op:
        batch_op.add_column(sa.Column("checksum_sha256", sa.String(length=64), nullable=True))
        batch_op.create_check_constraint(
            "ck_media_assets_checksum_sha256_length",
            "checksum_sha256 IS NULL OR length(checksum_sha256) = 64",
        )


def downgrade() -> None:
    with op.batch_alter_table("media_assets") as batch_op:
        batch_op.drop_constraint("ck_media_assets_checksum_sha256_length", type_="check")
        batch_op.drop_column("checksum_sha256")
