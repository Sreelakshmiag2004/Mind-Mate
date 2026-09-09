import uuid
from datetime import date
from typing import Optional, Sequence

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.journal import JournalEntry
from app.repositories import journal_repository
from app.schemas.journal import JournalCreate, JournalUpdate


def create_journal(db: Session, *, user_id: uuid.UUID, payload: JournalCreate) -> JournalEntry:
    if journal_repository.get_by_date_for_user(db, user_id=user_id, entry_date=payload.entry_date) is not None:
        raise ConflictError(f"A journal entry for {payload.entry_date} already exists")

    entry = journal_repository.create(
        db, user_id=user_id, entry_date=payload.entry_date, title=payload.title, content=payload.content
    )
    db.commit()
    db.refresh(entry)
    return entry


def get_journal(db: Session, *, user_id: uuid.UUID, journal_id: uuid.UUID) -> JournalEntry:
    entry = journal_repository.get_by_id_for_user(db, journal_id=journal_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Journal entry not found")
    return entry


def list_journals(
    db: Session,
    *,
    user_id: uuid.UUID,
    start_date: Optional[date],
    end_date: Optional[date],
    limit: int,
    offset: int,
) -> tuple[Sequence[JournalEntry], int]:
    return journal_repository.list_for_user(
        db, user_id=user_id, start_date=start_date, end_date=end_date, limit=limit, offset=offset
    )


def update_journal(
    db: Session, *, user_id: uuid.UUID, journal_id: uuid.UUID, payload: JournalUpdate
) -> JournalEntry:
    entry = journal_repository.get_by_id_for_user(db, journal_id=journal_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Journal entry not found")

    if payload.entry_date is not None and payload.entry_date != entry.entry_date:
        existing = journal_repository.get_by_date_for_user(db, user_id=user_id, entry_date=payload.entry_date)
        if existing is not None and existing.id != entry.id:
            raise ConflictError(f"A journal entry for {payload.entry_date} already exists")
        entry.entry_date = payload.entry_date

    if payload.title is not None:
        entry.title = payload.title
    if payload.content is not None:
        entry.content = payload.content

    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


def delete_journal(db: Session, *, user_id: uuid.UUID, journal_id: uuid.UUID) -> None:
    entry = journal_repository.get_by_id_for_user(db, journal_id=journal_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Journal entry not found")

    journal_repository.delete(db, entry)
    db.commit()
