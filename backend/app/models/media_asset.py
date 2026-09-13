"""
Metadata-only record for one uploaded file — the binary itself lives in
S3-compatible object storage (MinIO locally), never in PostgreSQL; this
row only points at it via `object_key`.

Media types are confirmed from `vault.dart`'s three Hive models
(`VoiceNote`, `ImageNote`, `VideoNote`) rather than invented: voice
recordings/imports, images, and videos are the only three kinds of media
the app's Vault ever handles. `media_type` is a discriminator over one
table instead of three near-identical tables (the three old Hive models
differ only in whether they carry a `duration`), matching the migration
audit's original recommendation.

`object_key` is fully server-generated (`{media_type}/{user_id}/{uuid4
hex}{extension}`) — never derived from the client-supplied filename, so
nothing about the original name, its extension, or path characters ever
reaches the storage key. `original_filename` is kept purely for display
and is never trusted for anything else (see app/services/media_service.py).

PHASE14B adds `title`: a separate, nullable, user-editable display name
(Vault's rename feature — `note.title = ...; note.save()` in
`vault.dart`/`viewall_images.dart`/`viewall_videos.dart`). Deliberately a
new column rather than repurposing `original_filename` for it:
`original_filename` is documented above as set once at upload time and
"never trusted for anything else" — overloading it as a mutable rename
target would silently break that contract for every existing caller.
Every row defaults to `title = NULL` (nothing has been renamed yet); a
`NULL` title is not an error state anywhere in this API — see
app/schemas/media.py/app/api/routes/media.py's `PATCH /media/{media_id}`.

PHASE14I-B adds two more additive, nullable columns for the eventual
one-time Flutter Vault → backend legacy Hive media migration (see
app/services/media_service.py's module docstring and the PHASE14I-B
implementation report for the full contract; nothing here performs any
actual migration, and no Flutter/Hive code is touched by this phase):

* `legacy_source` — an opaque `"<image|voice|video>:<legacy-hive-id>"`
  string identifying which old Hive record a migrated row came from.
  `NULL` for every normal upload (the overwhelming majority of rows,
  forever). The `(user_id, legacy_source)` partial unique index below is
  what makes upload retries duplicate-safe: it, not application logic
  alone, is the final guarantee that the same Hive item can never produce
  two `MediaAsset` rows for one user, even under a concurrent retry.
* `legacy_created_at` — the original Hive `DateTime` the migrated file
  was created at, preserved verbatim for display purposes. Deliberately
  separate from `created_at`: `TimestampMixin.created_at` is a
  server-assigned, `server_default=func.now()` column recording when
  *this row* was inserted (i.e., migration time, not the note's real
  history) and that meaning must never change for any existing or new
  row — see app/services/media_service.py for exactly how the two are
  populated and app/schemas/media.py for how a client should choose
  between them for display.
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin

MEDIA_TYPES = ("voice", "image", "video")


class MediaAsset(Base, TimestampMixin):
    __tablename__ = "media_assets"
    __table_args__ = (
        CheckConstraint("media_type IN ('voice', 'image', 'video')", name="ck_media_assets_media_type"),
        CheckConstraint("file_size > 0", name="ck_media_assets_file_size_positive"),
        # Supports "my media, newest first" and "my voice notes only" /
        # "my images only" listings without a full-table scan per user.
        Index("ix_media_assets_user_id_created_at", "user_id", "created_at"),
        # PHASE14I-B: enforces "the same legacy_source can never create two
        # rows for one user" at the database level — the mandatory final
        # backstop against a concurrent-retry race (see
        # app/services/media_service.py.upload_media), not merely an
        # application-level check-then-insert. Deliberately a PARTIAL
        # index (`WHERE legacy_source IS NOT NULL`, supplied per-dialect
        # since plain SQL has no portable spelling for it) rather than a
        # plain `UniqueConstraint("user_id", "legacy_source")`: the latter
        # would treat every pair of NULLs as equal-or-not depending on the
        # database's NULL-handling in unique constraints, which is not a
        # rule this schema wants to depend on. A partial index sidesteps
        # that entirely — it simply never indexes a NULL `legacy_source`
        # row, so any number of ordinary (non-legacy) uploads with
        # `legacy_source IS NULL` remain unaffected and mutually valid.
        Index(
            "uq_media_assets_user_id_legacy_source",
            "user_id",
            "legacy_source",
            unique=True,
            postgresql_where=text("legacy_source IS NOT NULL"),
            sqlite_where=text("legacy_source IS NOT NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    media_type: Mapped[str] = mapped_column(String(10), nullable=False)
    original_filename: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    # PHASE14B: the Vault rename target — see the module docstring. Kept
    # deliberately separate from original_filename, both in column and in
    # meaning; NULL until a caller PATCHes it.
    title: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    object_key: Mapped[str] = mapped_column(String(500), unique=True, nullable=False)
    content_type: Mapped[str] = mapped_column(String(100), nullable=False)
    file_size: Mapped[int] = mapped_column(Integer, nullable=False)
    # Only meaningful for voice (and, in principle, video); client-supplied
    # at upload time since this backend does no audio/video processing —
    # see backend/README.md, "Design decisions", for why that's an
    # acceptable, explicitly-documented trust boundary for a display-only field.
    duration_seconds: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    # PHASE14I-B — see module docstring for the full contract. Both NULL
    # for every normal upload; both set together for a migrated legacy row.
    legacy_source: Mapped[Optional[str]] = mapped_column(String(300), nullable=True)
    # Always stored timezone-aware UTC, matching every other DateTime
    # column in this schema (see app/models/base.py's TimestampMixin) —
    # see app/schemas/media.py for how a naive client-supplied value is
    # normalized before it ever reaches this column.
    legacy_created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<MediaAsset id={self.id} user_id={self.user_id} media_type={self.media_type}>"
