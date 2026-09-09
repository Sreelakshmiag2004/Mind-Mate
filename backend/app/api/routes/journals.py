import uuid
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import ConflictError, NotFoundError
from app.dependencies.auth import get_current_active_user
from app.dependencies.pagination import PaginationParams, pagination_params
from app.models.user import User
from app.schemas.common import Page
from app.schemas.journal import JournalCreate, JournalRead, JournalUpdate
from app.services import journal_service

router = APIRouter(prefix="/journals", tags=["journals"])


@router.post(
    "",
    response_model=JournalRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a journal entry",
    description=(
        "Creates one journal entry for the given date. Matches the existing app's "
        "one-entry-per-day rule: a second entry for a date that already has one is "
        "rejected with 409 — use PATCH to edit that day's entry instead."
    ),
)
def create_journal(
    payload: JournalCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> JournalRead:
    try:
        entry = journal_service.create_journal(db, user_id=current_user.id, payload=payload)
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return JournalRead.model_validate(entry)


@router.get(
    "",
    response_model=Page[JournalRead],
    summary="List your journal entries",
    description="Returns only the authenticated user's own entries, optionally filtered by date range.",
)
def list_journals(
    start_date: Optional[date] = Query(default=None, description="Inclusive lower bound on entry_date"),
    end_date: Optional[date] = Query(default=None, description="Inclusive upper bound on entry_date"),
    pagination: PaginationParams = Depends(pagination_params),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Page[JournalRead]:
    items, total = journal_service.list_journals(
        db,
        user_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
        limit=pagination.limit,
        offset=pagination.offset,
    )
    return Page[JournalRead](
        items=[JournalRead.model_validate(item) for item in items],
        total=total,
        limit=pagination.limit,
        offset=pagination.offset,
    )


@router.get(
    "/{journal_id}",
    response_model=JournalRead,
    summary="Retrieve one journal entry",
    description="404 if the entry doesn't exist OR doesn't belong to you — the two are indistinguishable by design.",
)
def get_journal(
    journal_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> JournalRead:
    try:
        entry = journal_service.get_journal(db, user_id=current_user.id, journal_id=journal_id)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return JournalRead.model_validate(entry)


@router.patch(
    "/{journal_id}",
    response_model=JournalRead,
    summary="Update a journal entry",
    description="Only the fields provided are changed. 404 for another user's entry; 409 if moving to a date you already have an entry for.",
)
def update_journal(
    journal_id: uuid.UUID,
    payload: JournalUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> JournalRead:
    try:
        entry = journal_service.update_journal(db, user_id=current_user.id, journal_id=journal_id, payload=payload)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return JournalRead.model_validate(entry)


@router.delete(
    "/{journal_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a journal entry",
)
def delete_journal(
    journal_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Response:
    try:
        journal_service.delete_journal(db, user_id=current_user.id, journal_id=journal_id)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return Response(status_code=status.HTTP_204_NO_CONTENT)
