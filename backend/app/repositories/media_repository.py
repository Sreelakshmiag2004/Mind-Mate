import uuid
from typing import Optional, Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.media_asset import MediaAsset


def get_by_id_for_user(db: Session, *, media_id: uuid.UUID, user_id: uuid.UUID) -> Optional[MediaAsset]:
    stmt = select(MediaAsset).where(MediaAsset.id == media_id, MediaAsset.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def list_for_user(
    db: Session,
    *,
    user_id: uuid.UUID,
    media_type: Optional[str] = None,
    limit: int = 30,
    offset: int = 0,
) -> tuple[Sequence[MediaAsset], int]:
    filters = [MediaAsset.user_id == user_id]
    if media_type is not None:
        filters.append(MediaAsset.media_type == media_type)

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
) -> MediaAsset:
    asset = MediaAsset(
        user_id=user_id,
        media_type=media_type,
        original_filename=original_filename,
        object_key=object_key,
        content_type=content_type,
        file_size=file_size,
        duration_seconds=duration_seconds,
    )
    db.add(asset)
    db.flush()
    return asset


def delete(db: Session, asset: MediaAsset) -> None:
    db.delete(asset)
