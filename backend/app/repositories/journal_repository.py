import uuid
from datetime import date
from typing import Optional, Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.journal import JournalEntry


def get_by_id_for_user(db: Session, *, journal_id: uuid.UUID, user_id: uuid.UUID) -> Optional[JournalEntry]:
    """
    Every lookup in this module takes `user_id` and filters by it in the
    SAME query as the id — never "fetch by id, then check owner in
    Python" — so a mismatched owner and a nonexistent id are
    indistinguishable at the database level too, not just in the HTTP
    response built on top of this.
    """
    stmt = select(JournalEntry).where(JournalEntry.id == journal_id, JournalEntry.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def get_by_date_for_user(db: Session, *, user_id: uuid.UUID, entry_date: date) -> Optional[JournalEntry]:
    stmt = select(JournalEntry).where(JournalEntry.user_id == user_id, JournalEntry.entry_date == entry_date)
    return db.execute(stmt).scalar_one_or_none()


def list_for_user(
    db: Session,
    *,
    user_id: uuid.UUID,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    limit: int = 30,
    offset: int = 0,
) -> tuple[Sequence[JournalEntry], int]:
    filters = [JournalEntry.user_id == user_id]
    if start_date is not None:
        filters.append(JournalEntry.entry_date >= start_date)
    if end_date is not None:
        filters.append(JournalEntry.entry_date <= end_date)

    total = db.execute(select(func.count()).select_from(JournalEntry).where(*filters)).scalar_one()

    stmt = (
        select(JournalEntry)
        .where(*filters)
        .order_by(JournalEntry.entry_date.desc())
        .limit(limit)
        .offset(offset)
    )
    items = db.execute(stmt).scalars().all()
    return items, total


def create(db: Session, *, user_id: uuid.UUID, entry_date: date, title: Optional[str], content: Optional[str]) -> JournalEntry:
    entry = JournalEntry(user_id=user_id, entry_date=entry_date, title=title, content=content)
    db.add(entry)
    db.flush()
    return entry


def delete(db: Session, entry: JournalEntry) -> None:
    db.delete(entry)
