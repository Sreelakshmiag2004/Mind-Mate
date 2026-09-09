"""
Deliberately NOT the generic `/checklists` + `/checklists/{checklist_id}`
CRUD shape suggested as a starting point — the existing app has no
"checklist resource" with its own id to create/delete; it has 5 fixed
tasks (see app/models/checklist.py) whose completion state is toggled per
calendar date. The API mirrors that reality: a day's state is read and
updated by date, and the (uncreatable, undeletable — matching the app,
which offers no way to add/remove items) task catalog is exposed
separately for the client to render.
"""

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import NotFoundError
from app.dependencies.auth import get_current_active_user
from app.models.user import User
from app.schemas.checklist import (
    ChecklistDayRead,
    ChecklistDayUpdate,
    ChecklistItemRead,
    ChecklistItemState,
)
from app.services import checklist_service
from app.services.checklist_service import ChecklistDaySnapshot

router = APIRouter(prefix="/checklists", tags=["checklists"])


def _to_response(snapshot: ChecklistDaySnapshot) -> ChecklistDayRead:
    return ChecklistDayRead(
        entry_date=snapshot.entry_date,
        items=[
            ChecklistItemState(
                item_id=i.item_id,
                label=i.label,
                sort_order=i.sort_order,
                completed=i.completed,
                completed_at=i.completed_at,
            )
            for i in snapshot.items
        ],
        completed_count=snapshot.completed_count,
        total_count=snapshot.total_count,
    )


@router.get(
    "/items",
    response_model=list[ChecklistItemRead],
    summary="List the checklist task catalog",
    description="The fixed set of daily wellness tasks every user shares. Not user-specific and not editable via this API.",
)
def list_items(db: Session = Depends(get_db), current_user: User = Depends(get_current_active_user)) -> list[ChecklistItemRead]:
    items = checklist_service.list_catalog(db)
    return [ChecklistItemRead.model_validate(item) for item in items]


@router.get(
    "/{entry_date}",
    response_model=ChecklistDayRead,
    summary="Get your checklist state for a date",
    description="Every catalog item plus whether you completed it on this date. Items never toggled default to not completed.",
)
def get_day(
    entry_date: date,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> ChecklistDayRead:
    snapshot = checklist_service.get_day(db, user_id=current_user.id, entry_date=entry_date)
    return _to_response(snapshot)


@router.patch(
    "/{entry_date}",
    response_model=ChecklistDayRead,
    summary="Update your checklist completions for a date",
    description="Toggle one or more items for this date. Returns the full day's state after the update.",
)
def update_day(
    entry_date: date,
    payload: ChecklistDayUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> ChecklistDayRead:
    try:
        snapshot = checklist_service.update_day(
            db,
            user_id=current_user.id,
            entry_date=entry_date,
            completions=[(c.item_id, c.completed) for c in payload.completions],
        )
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return _to_response(snapshot)
