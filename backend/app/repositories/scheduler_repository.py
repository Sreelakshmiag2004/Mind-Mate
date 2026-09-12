import uuid
from datetime import date
from typing import List, Optional, Sequence, Tuple

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.scheduler import SchedulerEntry


def list_for_user_date(db: Session, *, user_id: uuid.UUID, entry_date: date) -> Sequence[SchedulerEntry]:
    """
    Every lookup in this module takes `user_id` and filters by it in the
    SAME query as the date — never "fetch by date, then check owner in
    Python" — matching every other Phase 2+ resource's IDOR-resistance
    convention. Ordered by `scheduled_time` (a string, so this is a plain
    lexicographic sort — safe only because every value is validated
    zero-padded "HH:MM" by app/schemas/scheduler.py before it's ever
    stored, so lexicographic order and chronological order coincide).
    """
    stmt = (
        select(SchedulerEntry)
        .where(SchedulerEntry.user_id == user_id, SchedulerEntry.entry_date == entry_date)
        .order_by(SchedulerEntry.scheduled_time)
    )
    return db.execute(stmt).scalars().all()


def replace_for_user_date(
    db: Session,
    *,
    user_id: uuid.UUID,
    entry_date: date,
    rows: List[Tuple[str, Optional[str]]],
) -> None:
    """
    Deletes every existing row for (user_id, entry_date) and inserts
    `rows` in their place, all within the caller's own transaction — no
    commit here. The service commits exactly once after this returns (see
    app/services/scheduler_service.py), so if anything raises before that
    single commit (including a duplicate-time IntegrityError the schema
    layer's own validation didn't catch — e.g. a concurrent-request race),
    nothing from this call is left partially applied: closing the session
    without committing discards the whole delete-then-insert as one unit,
    matching every other Phase 2+ write path's transaction shape.
    """
    existing_stmt = select(SchedulerEntry).where(
        SchedulerEntry.user_id == user_id, SchedulerEntry.entry_date == entry_date
    )
    for entry in db.execute(existing_stmt).scalars().all():
        db.delete(entry)
    db.flush()

    for scheduled_time, description in rows:
        db.add(
            SchedulerEntry(
                user_id=user_id,
                entry_date=entry_date,
                scheduled_time=scheduled_time,
                description=description,
            )
        )
    db.flush()
