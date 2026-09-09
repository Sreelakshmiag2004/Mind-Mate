import uuid
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import ConflictError, NotFoundError
from app.dependencies.auth import get_current_active_user
from app.dependencies.pagination import PaginationParams, pagination_params
from app.models.user import User
from app.schemas.common import Page
from app.schemas.mood import MoodCreate, MoodRead, MoodUpdate
from app.services import mood_service

router = APIRouter(prefix="/moods", tags=["moods"])


@router.post(
    "",
    response_model=MoodRead,
    status_code=status.HTTP_201_CREATED,
    summary="Log a mood entry",
    description=(
        "Records a 0-100 mood percentage for the given date, matching the existing app's "
        "mood calendar. One entry per date — a second entry for a date that already has "
        "one is rejected with 409; use PATCH to change that day's value instead."
    ),
)
def create_mood(
    payload: MoodCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> MoodRead:
    try:
        entry = mood_service.create_mood(db, user_id=current_user.id, payload=payload)
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return MoodRead.model_validate(entry)


@router.get(
    "",
    response_model=Page[MoodRead],
    summary="List your mood entries",
    description="Returns only the authenticated user's own entries, optionally filtered by date range.",
)
def list_moods(
    start_date: Optional[date] = Query(default=None, description="Inclusive lower bound on entry_date"),
    end_date: Optional[date] = Query(default=None, description="Inclusive upper bound on entry_date"),
    pagination: PaginationParams = Depends(pagination_params),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Page[MoodRead]:
    items, total = mood_service.list_moods(
        db,
        user_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
        limit=pagination.limit,
        offset=pagination.offset,
    )
    return Page[MoodRead](
        items=[MoodRead.model_validate(item) for item in items],
        total=total,
        limit=pagination.limit,
        offset=pagination.offset,
    )


@router.get(
    "/{mood_id}",
    response_model=MoodRead,
    summary="Retrieve one mood entry",
    description="404 if the entry doesn't exist OR doesn't belong to you — the two are indistinguishable by design.",
)
def get_mood(
    mood_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> MoodRead:
    try:
        entry = mood_service.get_mood(db, user_id=current_user.id, mood_id=mood_id)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return MoodRead.model_validate(entry)


@router.patch(
    "/{mood_id}",
    response_model=MoodRead,
    summary="Update a mood entry",
    description="Matches the app's existing edit flow (re-tapping a day to change its value). Only provided fields change.",
)
def update_mood(
    mood_id: uuid.UUID,
    payload: MoodUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> MoodRead:
    try:
        entry = mood_service.update_mood(db, user_id=current_user.id, mood_id=mood_id, payload=payload)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return MoodRead.model_validate(entry)
