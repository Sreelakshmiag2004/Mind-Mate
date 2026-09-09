import uuid
from datetime import date
from typing import Optional, Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.mood import MoodEntry


def get_by_id_for_user(db: Session, *, mood_id: uuid.UUID, user_id: uuid.UUID) -> Optional[MoodEntry]:
    stmt = select(MoodEntry).where(MoodEntry.id == mood_id, MoodEntry.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def get_by_date_for_user(db: Session, *, user_id: uuid.UUID, entry_date: date) -> Optional[MoodEntry]:
    stmt = select(MoodEntry).where(MoodEntry.user_id == user_id, MoodEntry.entry_date == entry_date)
    return db.execute(stmt).scalar_one_or_none()


def list_for_user(
    db: Session,
    *,
    user_id: uuid.UUID,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    limit: int = 30,
    offset: int = 0,
) -> tuple[Sequence[MoodEntry], int]:
    filters = [MoodEntry.user_id == user_id]
    if start_date is not None:
        filters.append(MoodEntry.entry_date >= start_date)
    if end_date is not None:
        filters.append(MoodEntry.entry_date <= end_date)

    total = db.execute(select(func.count()).select_from(MoodEntry).where(*filters)).scalar_one()

    stmt = select(MoodEntry).where(*filters).order_by(MoodEntry.entry_date.desc()).limit(limit).offset(offset)
    items = db.execute(stmt).scalars().all()
    return items, total


def create(db: Session, *, user_id: uuid.UUID, entry_date: date, mood_value: int) -> MoodEntry:
    entry = MoodEntry(user_id=user_id, entry_date=entry_date, mood_value=mood_value)
    db.add(entry)
    db.flush()
    return entry
