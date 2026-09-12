"""
Backend for the Scheduler feature (PHASE11 Flutter-side audit + PHASE11A
product decisions) — the first backend support this feature has ever had;
the existing app stores this data only in a local, unscoped Hive box (see
the PHASE11 audit report). Deliberately a simple, date-scoped GET/PUT
pair, mirroring Checklist's `/checklists/{entry_date}` shape rather than
Journal's/Mood's per-entry CRUD — there is no "yesterday fallback" here by
design: per PHASE11A product decision 1, that stays entirely client-side,
so this API only ever answers "what's scheduled on this exact date."

No DELETE: whole-day PUT already deletes-by-omission — a row not included
in a PUT's `rows` is gone from that day after the call. See
app/services/scheduler_service.py.
"""

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import ConflictError, DuplicateScheduleTimeError
from app.dependencies.auth import get_current_active_user
from app.models.user import User
from app.schemas.scheduler import SchedulerDayRead, SchedulerDayUpdate, SchedulerEntryRead
from app.services import scheduler_service
from app.services.scheduler_service import SchedulerDaySnapshot

router = APIRouter(prefix="/scheduler", tags=["scheduler"])


def _to_response(snapshot: SchedulerDaySnapshot) -> SchedulerDayRead:
    return SchedulerDayRead(
        entry_date=snapshot.entry_date,
        items=[SchedulerEntryRead.model_validate(item) for item in snapshot.items],
    )


@router.get(
    "/{entry_date}",
    response_model=SchedulerDayRead,
    summary="Get your schedule for a date",
    description=(
        "Returns this user's scheduled rows for the date, ordered by time. An empty `items` list "
        "means nothing is scheduled — the client, not this API, is responsible for any "
        "'fall back to yesterday' display behavior."
    ),
)
def get_day(
    entry_date: date,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> SchedulerDayRead:
    snapshot = scheduler_service.get_day(db, user_id=current_user.id, entry_date=entry_date)
    return _to_response(snapshot)


@router.put(
    "/{entry_date}",
    response_model=SchedulerDayRead,
    summary="Replace your schedule for a date",
    description=(
        "Replaces this user's ENTIRE schedule for the date with `rows` in one call — matching the "
        "existing app's 'edit freely, save once' flow. A row from the previous save that isn't "
        "included here is deleted; `rows: []` clears the day. Two rows with the same "
        "scheduled_time in one request are rejected with 422 before anything is written."
    ),
)
def update_day(
    entry_date: date,
    payload: SchedulerDayUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> SchedulerDayRead:
    try:
        snapshot = scheduler_service.update_day(
            db, user_id=current_user.id, entry_date=entry_date, rows=payload.rows
        )
    except DuplicateScheduleTimeError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc))
    except ConflictError as exc:
        # The database's own UNIQUE(user_id, entry_date, scheduled_time)
        # constraint firing despite the duplicate-time check above already
        # passing — only reachable via a genuine concurrent-request race
        # (see scheduler_service.update_day's docstring). 409, not 422:
        # this single request was well-formed; a race against another
        # request is what failed.
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return _to_response(snapshot)
