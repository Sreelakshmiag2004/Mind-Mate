"""
Structurally identical to journal_service.py — one entry per user per
calendar day, same conflict/ownership rules — because a Shoutout IS the
same shape of resource as a Journal entry (private, dated, freeform text
authored and read by exactly one user). See app/models/shoutout.py for the
source evidence behind that call.

`answer_feel_better` is a separate action, not folded into `update_shoutout`
via PATCH, because it's a distinct interaction in the real UI (a one-time
Yes/No prompt, not a text edit) and the old app's own behavior treats it
as one-shot: once answered, the UI shows a static outcome message with no
way back. `ConflictError` here is reused from the same generic exception
Phase 2 uses for "a uniqueness rule was violated" — answering twice is
exactly that kind of conflict, not a new category of error.
"""

import uuid
from datetime import date, datetime, timezone
from typing import Optional, Sequence

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.shoutout import Shoutout
from app.repositories import shoutout_repository
from app.schemas.shoutout import ShoutoutCreate, ShoutoutUpdate


def create_shoutout(db: Session, *, user_id: uuid.UUID, payload: ShoutoutCreate) -> Shoutout:
    if shoutout_repository.get_by_date_for_user(db, user_id=user_id, entry_date=payload.entry_date) is not None:
        raise ConflictError(f"A shoutout for {payload.entry_date} already exists")

    entry = shoutout_repository.create(
        db, user_id=user_id, entry_date=payload.entry_date, title=payload.title, content=payload.content
    )
    db.commit()
    db.refresh(entry)
    return entry


def get_shoutout(db: Session, *, user_id: uuid.UUID, shoutout_id: uuid.UUID) -> Shoutout:
    entry = shoutout_repository.get_by_id_for_user(db, shoutout_id=shoutout_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Shoutout not found")
    return entry


def list_shoutouts(
    db: Session,
    *,
    user_id: uuid.UUID,
    start_date: Optional[date],
    end_date: Optional[date],
    limit: int,
    offset: int,
) -> tuple[Sequence[Shoutout], int]:
    return shoutout_repository.list_for_user(
        db, user_id=user_id, start_date=start_date, end_date=end_date, limit=limit, offset=offset
    )


def update_shoutout(
    db: Session, *, user_id: uuid.UUID, shoutout_id: uuid.UUID, payload: ShoutoutUpdate
) -> Shoutout:
    entry = shoutout_repository.get_by_id_for_user(db, shoutout_id=shoutout_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Shoutout not found")

    if payload.entry_date is not None and payload.entry_date != entry.entry_date:
        existing = shoutout_repository.get_by_date_for_user(db, user_id=user_id, entry_date=payload.entry_date)
        if existing is not None and existing.id != entry.id:
            raise ConflictError(f"A shoutout for {payload.entry_date} already exists")
        entry.entry_date = payload.entry_date

    if payload.title is not None:
        entry.title = payload.title
    if payload.content is not None:
        entry.content = payload.content

    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


def delete_shoutout(db: Session, *, user_id: uuid.UUID, shoutout_id: uuid.UUID) -> None:
    entry = shoutout_repository.get_by_id_for_user(db, shoutout_id=shoutout_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Shoutout not found")

    shoutout_repository.delete(db, entry)
    db.commit()


def answer_feel_better(db: Session, *, user_id: uuid.UUID, shoutout_id: uuid.UUID, felt_better: bool) -> Shoutout:
    entry = shoutout_repository.get_by_id_for_user(db, shoutout_id=shoutout_id, user_id=user_id)
    if entry is None:
        raise NotFoundError("Shoutout not found")

    if entry.felt_better is not None:
        raise ConflictError("This shoutout's follow-up has already been answered")

    entry.felt_better = felt_better
    entry.felt_better_at = datetime.now(timezone.utc)
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry
