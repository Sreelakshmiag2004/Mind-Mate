import uuid
from datetime import date
from typing import Optional, Sequence

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.mood import MoodEntry
from app.repositories import mood_repository
from app.schemas.mood import MoodCreate, MoodUpdate


def create_mood(db: Session, *, user_id: uuid.UUID, payload: MoodCreate) -> MoodEntry:
    if mood_repository.get_by_date_for_user(db, user_id=user_id, entry_date=payload.entry_date) is not None:
        raise ConflictError(f"A mood entry for {payload.entry_date} already exists")

    entry = mood_repository.create(
        db, user_id=user_id, entry_date=payload.entry_date, mood_value=payload.mood_value
    )
    db.commit()
    db.refresh(entry)
    return entry


def get_mood(db: Session, *, user_id: uuid.UUID, mood_id: uuid.UUID) -> MoodEntry:
    entry = mood_repository.get_by_id_for_user(db, mood_id=mood_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Mood entry not found")
    return entry


def list_moods(
    db: Session,
    *,
    user_id: uuid.UUID,
    start_date: Optional[date],
    end_date: Optional[date],
    limit: int,
    offset: int,
) -> tuple[Sequence[MoodEntry], int]:
    return mood_repository.list_for_user(
        db, user_id=user_id, start_date=start_date, end_date=end_date, limit=limit, offset=offset
    )


def update_mood(db: Session, *, user_id: uuid.UUID, mood_id: uuid.UUID, payload: MoodUpdate) -> MoodEntry:
    entry = mood_repository.get_by_id_for_user(db, mood_id=mood_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Mood entry not found")

    if payload.entry_date is not None and payload.entry_date != entry.entry_date:
        existing = mood_repository.get_by_date_for_user(db, user_id=user_id, entry_date=payload.entry_date)
        if existing is not None and existing.id != entry.id:
            raise ConflictError(f"A mood entry for {payload.entry_date} already exists")
        entry.entry_date = payload.entry_date

    if payload.mood_value is not None:
        entry.mood_value = payload.mood_value

    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry
