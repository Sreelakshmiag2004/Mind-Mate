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
"""

import uuid
from typing import Optional

from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, String
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
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    media_type: Mapped[str] = mapped_column(String(10), nullable=False)
    original_filename: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    object_key: Mapped[str] = mapped_column(String(500), unique=True, nullable=False)
    content_type: Mapped[str] = mapped_column(String(100), nullable=False)
    file_size: Mapped[int] = mapped_column(Integer, nullable=False)
    # Only meaningful for voice (and, in principle, video); client-supplied
    # at upload time since this backend does no audio/video processing —
    # see backend/README.md, "Design decisions", for why that's an
    # acceptable, explicitly-documented trust boundary for a display-only field.
    duration_seconds: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<MediaAsset id={self.id} user_id={self.user_id} media_type={self.media_type}>"
