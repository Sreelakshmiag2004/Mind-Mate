"""
Unlike journals/moods, a checklist "day" isn't one row — it's the join of
the fixed item catalog with whatever completion rows exist for that user
on that date (see app/models/checklist.py). `ChecklistDaySnapshot` is a
small internal value object for that composite result; it is not a DB
model or an API schema, it exists purely so this service can hand routes
one assembled object instead of two separate query results to merge.
"""

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from typing import List, Optional, Sequence

from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.models.checklist import ChecklistItem
from app.repositories import checklist_repository


@dataclass
class ChecklistItemState:
    item_id: uuid.UUID
    label: str
    sort_order: int
    completed: bool
    completed_at: Optional[datetime]


@dataclass
class ChecklistDaySnapshot:
    entry_date: date
    items: List[ChecklistItemState]
    completed_count: int
    total_count: int


def list_catalog(db: Session) -> Sequence[ChecklistItem]:
    return checklist_repository.list_active_items(db)


def get_day(db: Session, *, user_id: uuid.UUID, entry_date: date) -> ChecklistDaySnapshot:
    catalog = checklist_repository.list_active_items(db)
    completions = checklist_repository.get_completions_for_user_date(db, user_id=user_id, entry_date=entry_date)

    states: List[ChecklistItemState] = []
    completed_count = 0
    for item in catalog:
        completion = completions.get(item.id)
        completed = bool(completion and completion.completed)
        if completed:
            completed_count += 1
        states.append(
            ChecklistItemState(
                item_id=item.id,
                label=item.label,
                sort_order=item.sort_order,
                completed=completed,
                completed_at=completion.completed_at if completion else None,
            )
        )

    return ChecklistDaySnapshot(
        entry_date=entry_date, items=states, completed_count=completed_count, total_count=len(catalog)
    )


def update_day(
    db: Session, *, user_id: uuid.UUID, entry_date: date, completions: list[tuple[uuid.UUID, bool]]
) -> ChecklistDaySnapshot:
    valid_item_ids = {item.id for item in checklist_repository.list_active_items(db)}

    for item_id, _completed in completions:
        if item_id not in valid_item_ids:
            raise NotFoundError(f"Checklist item {item_id} does not exist")

    for item_id, completed in completions:
        checklist_repository.upsert_completion(
            db, user_id=user_id, checklist_item_id=item_id, entry_date=entry_date, completed=completed
        )

    db.commit()
    return get_day(db, user_id=user_id, entry_date=entry_date)
