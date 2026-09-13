import uuid
from datetime import datetime
from typing import Optional, Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.media_asset import MediaAsset


def get_by_id_for_user(db: Session, *, media_id: uuid.UUID, user_id: uuid.UUID) -> Optional[MediaAsset]:
    stmt = select(MediaAsset).where(MediaAsset.id == media_id, MediaAsset.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def get_by_user_and_legacy_source(
    db: Session, *, user_id: uuid.UUID, legacy_source: str
) -> Optional[MediaAsset]:
    """
    PHASE14I-B. The lookup this whole duplicate-safe-upload contract is
    built on — see app/services/media_service.py.upload_media, which
    calls this both as the pre-check (before ever touching storage) and
    again after losing an insert race, to resolve to the winner's row.
    Scoped by `user_id` in the same query as `legacy_source`, matching
    every other ownership-scoped lookup in this codebase (see
    app/repositories/journal_repository.py's get_by_id_for_user) — so a
    caller can never learn whether a *different* user already has that
    legacy_source.
    """
    stmt = select(MediaAsset).where(
        MediaAsset.user_id == user_id, MediaAsset.legacy_source == legacy_source
    )
    return db.execute(stmt).scalar_one_or_none()


def list_for_user(
    db: Session,
    *,
    user_id: uuid.UUID,
    media_type: Optional[str] = None,
    legacy_source: Optional[str] = None,
    limit: int = 30,
    offset: int = 0,
) -> tuple[Sequence[MediaAsset], int]:
    filters = [MediaAsset.user_id == user_id]
    if media_type is not None:
        filters.append(MediaAsset.media_type == media_type)
    if legacy_source is not None:
        # PHASE14I-B lookup filter — see app/api/routes/media.py's
        # `GET /media?legacy_source=...`. Exact match only; combined with
        # the `user_id` filter above in the same query, so a caller can
        # never learn whether another user's legacy_source exists.
        filters.append(MediaAsset.legacy_source == legacy_source)

    total = db.execute(select(func.count()).select_from(MediaAsset).where(*filters)).scalar_one()

    stmt = (
        select(MediaAsset)
        .where(*filters)
        .order_by(MediaAsset.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    items = db.execute(stmt).scalars().all()
    return items, total


def create(
    db: Session,
    *,
    user_id: uuid.UUID,
    media_type: str,
    original_filename: Optional[str],
    object_key: str,
    content_type: str,
    file_size: int,
    duration_seconds: Optional[int],
    legacy_source: Optional[str] = None,
    legacy_created_at: Optional[datetime] = None,
) -> MediaAsset:
    asset = MediaAsset(
        user_id=user_id,
        media_type=media_type,
        original_filename=original_filename,
        object_key=object_key,
        content_type=content_type,
        file_size=file_size,
        duration_seconds=duration_seconds,
        legacy_source=legacy_source,
        legacy_created_at=legacy_created_at,
    )
    db.add(asset)
    db.flush()
    return asset


def delete(db: Session, asset: MediaAsset) -> None:
    db.delete(asset)


def update_title(db: Session, asset: MediaAsset, *, title: str) -> MediaAsset:
    """PHASE14B: rename — updates ONLY `title`. Never touches object_key,
    media_type, duration_seconds, original_filename, or ownership."""
    asset.title = title
    db.add(asset)
    db.flush()
    return asset
