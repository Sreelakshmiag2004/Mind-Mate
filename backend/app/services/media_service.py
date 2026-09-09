"""
Upload/list/retrieve/delete for Vault media (voice notes, images, videos).

Allowed content types are taken directly from what `vault.dart` actually
accepts today, not invented:
  * Voice: `FilePicker.pickFiles(allowedExtensions: ['mp3','m4a','wav',
    'aac','opus','ogg'])` in the Voice Notes search bar, plus recordings
    (`record` package) which are always `.m4a`.
  * Video: only `.mp4` gets real handling anywhere in `vault.dart` —
    `VideoThumbnail.thumbnailData` and `VideoPlayerDialog` both only
    work correctly for it; the `FileType.video` file-picker filter is
    broader, but nothing else in the app actually plays another
    container. Kept to `.mp4` rather than guessing at the rest, per the
    instruction not to invent broad MIME-type support.
  * Images: `FileType.image` in file_picker doesn't enumerate an exact
    extension list in the Dart source (it delegates to the platform
    picker), so this uses the standard, universally-supported baseline
    (jpeg/png/gif/webp) instead of guessing at an exhaustive list.

Consistency between PostgreSQL and object storage (see backend/README.md,
"Upload/download/delete behavior", for the full write-up):
  * Upload: the object is written to storage FIRST; the metadata row is
    only inserted after that succeeds. If storage upload fails, no DB
    row is ever created — nothing to orphan.
  * If the object upload succeeds but the subsequent DB commit fails, the
    just-uploaded object IS now orphaned (metadata-less). This service
    makes a best-effort compensating delete of it before re-raising the
    original error — logged if that cleanup itself fails, never allowed
    to mask the real error. This is a best-effort compensation, not a
    distributed transaction; a periodic reconciliation job (comparing
    bucket contents against `media_assets` rows) would be needed to
    guarantee zero orphans, and is explicitly future work, not built here.
  * Delete: the object is deleted FIRST, then the metadata row. If the
    object delete fails, the row is kept (so the user can retry and the
    object/metadata never silently diverge). If the object delete
    succeeds but the row delete then fails, the row becomes a "ghost"
    pointing at a gone object — a narrower, more detectable failure than
    a fully untracked orphaned blob, which is why this ordering was
    chosen over deleting the row first.
"""

import logging
import uuid
from io import BytesIO
from typing import Optional, Sequence

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import FileTooLargeError, NotFoundError, StorageError, UnsupportedMediaTypeError
from app.models.media_asset import MediaAsset
from app.repositories import media_repository
from app.services.storage.base import ObjectStorageService

logger = logging.getLogger(__name__)

DOWNLOAD_URL_EXPIRES_IN_SECONDS = 15 * 60  # 15 minutes

# content_type -> (media_type, file extension used in the generated object key)
ALLOWED_CONTENT_TYPES: dict[str, tuple[str, str]] = {
    "audio/mp4": ("voice", ".m4a"),
    "audio/x-m4a": ("voice", ".m4a"),
    "audio/mpeg": ("voice", ".mp3"),
    "audio/wav": ("voice", ".wav"),
    "audio/x-wav": ("voice", ".wav"),
    "audio/aac": ("voice", ".aac"),
    "audio/opus": ("voice", ".opus"),
    "audio/ogg": ("voice", ".ogg"),
    "image/jpeg": ("image", ".jpg"),
    "image/png": ("image", ".png"),
    "image/gif": ("image", ".gif"),
    "image/webp": ("image", ".webp"),
    "video/mp4": ("video", ".mp4"),
}


def _validate_and_read(content_type: Optional[str], data: bytes) -> tuple[str, str]:
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise UnsupportedMediaTypeError(
            f"Content type {content_type!r} is not supported. Allowed: {sorted(ALLOWED_CONTENT_TYPES)}"
        )
    if len(data) == 0:
        raise UnsupportedMediaTypeError("Uploaded file is empty")
    if len(data) > settings.max_upload_size_bytes:
        raise FileTooLargeError(
            f"File is {len(data)} bytes, which exceeds the {settings.max_upload_size_mb}MB limit"
        )
    media_type, extension = ALLOWED_CONTENT_TYPES[content_type]
    return media_type, extension


def upload_media(
    db: Session,
    storage: ObjectStorageService,
    *,
    user_id: uuid.UUID,
    data: bytes,
    content_type: Optional[str],
    original_filename: Optional[str],
    duration_seconds: Optional[int],
) -> MediaAsset:
    media_type, extension = _validate_and_read(content_type, data)

    # Server-generated, UUID-based — never derived from `original_filename`,
    # so nothing about the client-supplied name (or path characters in it)
    # ever reaches the storage key. See module docstring for the full
    # consistency contract this upload sequence follows.
    object_key = f"{media_type}/{user_id}/{uuid.uuid4().hex}{extension}"

    storage.upload(object_key=object_key, fileobj=BytesIO(data), content_type=content_type)

    try:
        asset = media_repository.create(
            db,
            user_id=user_id,
            media_type=media_type,
            original_filename=original_filename,
            object_key=object_key,
            content_type=content_type,
            file_size=len(data),
            duration_seconds=duration_seconds,
        )
        db.commit()
        db.refresh(asset)
        return asset
    except SQLAlchemyError:
        db.rollback()
        try:
            storage.delete(object_key=object_key)
        except StorageError:
            logger.error(
                "Orphaned object after a failed metadata insert: object_key=%s could not be cleaned up",
                object_key,
            )
        raise


def get_media(db: Session, *, user_id: uuid.UUID, media_id: uuid.UUID) -> MediaAsset:
    asset = media_repository.get_by_id_for_user(db, media_id=media_id, user_id=user_id)
    if asset is None:
        raise NotFoundError("Media not found")
    return asset


def list_media(
    db: Session, *, user_id: uuid.UUID, media_type: Optional[str], limit: int, offset: int
) -> tuple[Sequence[MediaAsset], int]:
    return media_repository.list_for_user(db, user_id=user_id, media_type=media_type, limit=limit, offset=offset)


def build_download_url(storage: ObjectStorageService, asset: MediaAsset) -> str:
    return storage.generate_presigned_download_url(
        object_key=asset.object_key, expires_in_seconds=DOWNLOAD_URL_EXPIRES_IN_SECONDS
    )


def delete_media(db: Session, storage: ObjectStorageService, *, user_id: uuid.UUID, media_id: uuid.UUID) -> None:
    asset = media_repository.get_by_id_for_user(db, media_id=media_id, user_id=user_id)
    if asset is None:
        raise NotFoundError("Media not found")

    # Object first, row second — see module docstring for why this
    # ordering was chosen over the reverse.
    storage.delete(object_key=asset.object_key)

    media_repository.delete(db, asset)
    db.commit()
