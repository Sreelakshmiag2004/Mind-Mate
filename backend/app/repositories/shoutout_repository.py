import uuid
from datetime import date
from typing import Optional, Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.shoutout import Shoutout


def get_by_id_for_user(db: Session, *, shoutout_id: uuid.UUID, user_id: uuid.UUID) -> Optional[Shoutout]:
    stmt = select(Shoutout).where(Shoutout.id == shoutout_id, Shoutout.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def get_by_date_for_user(db: Session, *, user_id: uuid.UUID, entry_date: date) -> Optional[Shoutout]:
    stmt = select(Shoutout).where(Shoutout.user_id == user_id, Shoutout.entry_date == entry_date)
    return db.execute(stmt).scalar_one_or_none()


def list_for_user(
    db: Session,
    *,
    user_id: uuid.UUID,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    limit: int = 30,
    offset: int = 0,
) -> tuple[Sequence[Shoutout], int]:
    filters = [Shoutout.user_id == user_id]
    if start_date is not None:
        filters.append(Shoutout.entry_date >= start_date)
    if end_date is not None:
        filters.append(Shoutout.entry_date <= end_date)

    total = db.execute(select(func.count()).select_from(Shoutout).where(*filters)).scalar_one()

    stmt = select(Shoutout).where(*filters).order_by(Shoutout.entry_date.desc()).limit(limit).offset(offset)
    items = db.execute(stmt).scalars().all()
    return items, total


def create(db: Session, *, user_id: uuid.UUID, entry_date: date, title: Optional[str], content: Optional[str]) -> Shoutout:
    entry = Shoutout(user_id=user_id, entry_date=entry_date, title=title, content=content)
    db.add(entry)
    db.flush()
    return entry


def delete(db: Session, entry: Shoutout) -> None:
    db.delete(entry)
