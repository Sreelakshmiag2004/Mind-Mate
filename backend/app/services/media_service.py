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

PHASE14I-B — duplicate-safe legacy upload (see the PHASE14I-B
implementation report for the full contract this section implements):

`upload_media` now accepts optional `legacy_source`/`legacy_created_at`
for the eventual one-time Flutter Vault -> backend legacy Hive media
migration. When `legacy_source` is given, this function guarantees that
the same `(user_id, legacy_source)` can never end up as two `MediaAsset`
rows or two storage objects, even across a lost-response retry or a true
concurrent race:

  1. Pre-check: before touching storage at all, look up an existing row
     for this exact `(user_id, legacy_source)`. If one exists, return it
     immediately — no new object is uploaded, no new row is created. This
     alone handles the common non-concurrent case (client uploaded
     successfully, the response was lost — e.g. a flaky mobile network —
     and the same request is retried).
  2. This pre-check cannot close a true concurrent race (two requests can
     both pass it before either has inserted). The
     `uq_media_assets_user_id_legacy_source` partial unique index (see
     app/models/media_asset.py) is the mandatory final backstop: it lets
     at most one of two racing inserts succeed. The losing request's
     insert raises `IntegrityError`; this function catches specifically
     that (not the broader `SQLAlchemyError` catch-all below, which
     covers everything else — e.g. a lost DB connection), deletes its own
     now-orphaned storage object as compensation, then re-resolves via
     the same lookup as step 1 to return the *winning* request's row.
     Both requests therefore resolve to the same logical `MediaAsset`,
     matching the contract's preferred behavior over surfacing a 409 to
     a client that will just retry anyway.

Limitation (also called out in the implementation report): step 2's
`IntegrityError` handling assumes that when `legacy_source` is set,
`uq_media_assets_user_id_legacy_source` is the only unique constraint an
`upload_media` insert could violate — true today (it is the only
per-user uniqueness rule this table has), but if a future change adds
another unique constraint reachable from this same insert, this handler
would need to distinguish which constraint fired (e.g. by inspecting the
driver error) rather than assuming. True concurrent-insert behavior is
also not exercised by an automated test here: this project's test suite
runs against a single-threaded, single-connection SQLite database (see
tests/conftest.py), which cannot actually run two DB transactions in
parallel. The two-sequential-requests "lost response, retried" scenario
*is* covered directly; genuine concurrency is instead handled by relying
on the database constraint (proven correct at the schema level, since it
is a real, always-enforced uniqueness rule) rather than on a
would-be-approximate test.
"""

import logging
import uuid
from datetime import datetime
from io import BytesIO
from typing import Optional, Sequence

from sqlalchemy.exc import IntegrityError, SQLAlchemyError
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
    legacy_source: Optional[str] = None,
    legacy_created_at: Optional[datetime] = None,
) -> MediaAsset:
    # PHASE14I-B duplicate-safe pre-check — see module docstring, point 1.
    # Deliberately BEFORE any storage I/O: a lost-response retry for an
    # already-migrated legacy_source should never upload a second object.
    if legacy_source is not None:
        existing = media_repository.get_by_user_and_legacy_source(
            db, user_id=user_id, legacy_source=legacy_source
        )
        if existing is not None:
            return existing

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
            legacy_source=legacy_source,
            legacy_created_at=legacy_created_at,
        )
        db.commit()
        db.refresh(asset)
        return asset
    except IntegrityError:
        # PHASE14I-B race backstop — see module docstring, point 2. Only
        # ever expected here when legacy_source is set: the
        # (user_id, legacy_source) partial unique index is the only
        # per-user uniqueness rule this table has, so a concurrent
        # request for the exact same legacy_source is the only thing this
        # insert could lose a race against.
        db.rollback()
        try:
            storage.delete(object_key=object_key)  # this request's object is now orphaned
        except StorageError:
            logger.error(
                "Orphaned object after losing a legacy_source insert race: object_key=%s could not be cleaned up",
                object_key,
            )

        if legacy_source is not None:
            winner = media_repository.get_by_user_and_legacy_source(
                db, user_id=user_id, legacy_source=legacy_source
            )
            if winner is not None:
                return winner
        raise
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
    db: Session,
    *,
    user_id: uuid.UUID,
    media_type: Optional[str],
    limit: int,
    offset: int,
    legacy_source: Optional[str] = None,
) -> tuple[Sequence[MediaAsset], int]:
    return media_repository.list_for_user(
        db, user_id=user_id, media_type=media_type, legacy_source=legacy_source, limit=limit, offset=offset
    )


def build_download_url(storage: ObjectStorageService, asset: MediaAsset) -> str:
    return storage.generate_presigned_download_url(
        object_key=asset.object_key, expires_in_seconds=DOWNLOAD_URL_EXPIRES_IN_SECONDS
    )


def update_media_title(db: Session, *, user_id: uuid.UUID, media_id: uuid.UUID, title: str) -> MediaAsset:
    """
    PHASE14B rename. Ownership is enforced the exact same way as every
    other media operation (`get_by_id_for_user`, 404 if missing/not
    theirs) — this never touches object storage at all: the object itself
    is never renamed, only this row's `title` column.
    """
    asset = media_repository.get_by_id_for_user(db, media_id=media_id, user_id=user_id)
    if asset is None:
        raise NotFoundError("Media not found")

    media_repository.update_title(db, asset, title=title)
    db.commit()
    db.refresh(asset)
    return asset


def delete_media(db: Session, storage: ObjectStorageService, *, user_id: uuid.UUID, media_id: uuid.UUID) -> None:
    asset = media_repository.get_by_id_for_user(db, media_id=media_id, user_id=user_id)
    if asset is None:
        raise NotFoundError("Media not found")

    # Object first, row second — see module docstring for why this
    # ordering was chosen over the reverse.
    storage.delete(object_key=asset.object_key)

    media_repository.delete(db, asset)
    db.commit()
