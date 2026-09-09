import uuid
from datetime import date, datetime, timezone
from typing import Dict, Optional, Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.checklist import ChecklistCompletion, ChecklistItem


def list_active_items(db: Session) -> Sequence[ChecklistItem]:
    stmt = select(ChecklistItem).where(ChecklistItem.is_active.is_(True)).order_by(ChecklistItem.sort_order)
    return db.execute(stmt).scalars().all()


def get_item_by_id(db: Session, item_id: uuid.UUID) -> Optional[ChecklistItem]:
    return db.get(ChecklistItem, item_id)


def get_completions_for_user_date(
    db: Session, *, user_id: uuid.UUID, entry_date: date
) -> Dict[uuid.UUID, ChecklistCompletion]:
    """Keyed by checklist_item_id for O(1) lookup while assembling a day's response."""
    stmt = select(ChecklistCompletion).where(
        ChecklistCompletion.user_id == user_id, ChecklistCompletion.entry_date == entry_date
    )
    rows = db.execute(stmt).scalars().all()
    return {row.checklist_item_id: row for row in rows}


def get_completion_for_user(
    db: Session, *, completion_id: uuid.UUID, user_id: uuid.UUID
) -> Optional[ChecklistCompletion]:
    stmt = select(ChecklistCompletion).where(
        ChecklistCompletion.id == completion_id, ChecklistCompletion.user_id == user_id
    )
    return db.execute(stmt).scalar_one_or_none()


def upsert_completion(
    db: Session, *, user_id: uuid.UUID, checklist_item_id: uuid.UUID, entry_date: date, completed: bool
) -> ChecklistCompletion:
    stmt = select(ChecklistCompletion).where(
        ChecklistCompletion.user_id == user_id,
        ChecklistCompletion.checklist_item_id == checklist_item_id,
        ChecklistCompletion.entry_date == entry_date,
    )
    row = db.execute(stmt).scalar_one_or_none()

    if row is None:
        row = ChecklistCompletion(
            user_id=user_id,
            checklist_item_id=checklist_item_id,
            entry_date=entry_date,
            completed=completed,
            completed_at=datetime.now(timezone.utc) if completed else None,
        )
        db.add(row)
    else:
        row.completed = completed
        row.completed_at = datetime.now(timezone.utc) if completed else None
        db.add(row)

    db.flush()
    return row


def delete_completion(db: Session, completion: ChecklistCompletion) -> None:
    db.delete(completion)
