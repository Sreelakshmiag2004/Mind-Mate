"""
Unlike journals/moods (one row per date) or checklists (a join of a fixed
catalog with per-date completions), a Scheduler "day" is simply every
`SchedulerEntry` row for (user, date) — there's no catalog to join
against. `SchedulerDaySnapshot` is a small internal value object for that
result, matching the shape `checklist_service.ChecklistDaySnapshot`
already established; it is not a DB model or an API schema.

PHASE11A product decisions this module implements:

1. The old app's "today falls back to yesterday" display behavior stays
   entirely client-side (see the PHASE11 Flutter audit report, Section 7)
   — this service, and the API it backs, only ever answers "what's on
   this exact date," never "or the most recent prior date with something
   on it." No fallback logic exists here on purpose.
2. Two rows for the same (user, date, scheduled_time) can never coexist.
   `update_day` rejects a request containing the same scheduled_time
   twice via `DuplicateScheduleTimeError` (mapped to 422 by the route)
   BEFORE touching the database at all — this is deliberately a service
   responsibility, not a schema validator, so it can inspect the full set
   of rows as a whole rather than one field at a time. The
   UNIQUE(user_id, entry_date, scheduled_time) database constraint (see
   app/models/scheduler.py) is the final backstop against a
   concurrent-request race slipping past that in-process check — caught
   here as an IntegrityError and re-raised as ConflictError (409),
   distinct from the 422 a single self-contradictory request gets.
"""

import uuid
from dataclasses import dataclass
from datetime import date
from typing import List, Sequence

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, DuplicateScheduleTimeError
from app.models.scheduler import SchedulerEntry
from app.repositories import scheduler_repository
from app.schemas.scheduler import SchedulerEntryInput


@dataclass
class SchedulerDaySnapshot:
    entry_date: date
    items: Sequence[SchedulerEntry]


def get_day(db: Session, *, user_id: uuid.UUID, entry_date: date) -> SchedulerDaySnapshot:
    items = scheduler_repository.list_for_user_date(db, user_id=user_id, entry_date=entry_date)
    return SchedulerDaySnapshot(entry_date=entry_date, items=items)


def update_day(
    db: Session, *, user_id: uuid.UUID, entry_date: date, rows: List[SchedulerEntryInput]
) -> SchedulerDaySnapshot:
    _reject_duplicate_times(rows)

    try:
        scheduler_repository.replace_for_user_date(
            db,
            user_id=user_id,
            entry_date=entry_date,
            rows=[(row.scheduled_time, row.description) for row in rows],
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ConflictError(
            f"Could not save the schedule for {entry_date} due to a conflicting concurrent update; please retry"
        )

    # Re-fetch fresh from the database rather than tracking/refreshing the
    # objects `replace_for_user_date` created in-place — matches
    # checklist_service.update_day's exact pattern for the same reason:
    # this is a multi-row "day" result, not a single entity to refresh.
    return get_day(db, user_id=user_id, entry_date=entry_date)


def _reject_duplicate_times(rows: List[SchedulerEntryInput]) -> None:
    seen: set = set()
    for row in rows:
        if row.scheduled_time in seen:
            raise DuplicateScheduleTimeError(
                f"scheduled_time '{row.scheduled_time}' appears more than once in the same request"
            )
        seen.add(row.scheduled_time)
