"""
Deliberately NOT a sender/recipient messaging API. The audit (see
app/models/shoutout.py) found a Shoutout is a private, self-authored
entry with no recipient anywhere in the current app — so this mirrors
/journals exactly: one owner, one entry per calendar date, no "sent" vs
"received" split, because that split doesn't exist in the real feature.
"""

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
from app.schemas.shoutout import ShoutoutCreate, ShoutoutFeelBetterRequest, ShoutoutRead, ShoutoutUpdate
from app.services import shoutout_service

router = APIRouter(prefix="/shoutouts", tags=["shoutouts"])


@router.post(
    "",
    response_model=ShoutoutRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a shoutout",
    description="One per date, like /journals — 409 if that date already has one; use PATCH to edit it instead.",
)
def create_shoutout(
    payload: ShoutoutCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> ShoutoutRead:
    try:
        entry = shoutout_service.create_shoutout(db, user_id=current_user.id, payload=payload)
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return ShoutoutRead.model_validate(entry)


@router.get(
    "",
    response_model=Page[ShoutoutRead],
    summary="List your shoutouts",
    description="Only the authenticated user's own entries — there is no 'sent'/'received' split; see the model docstring for why.",
)
def list_shoutouts(
    start_date: Optional[date] = Query(default=None),
    end_date: Optional[date] = Query(default=None),
    pagination: PaginationParams = Depends(pagination_params),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Page[ShoutoutRead]:
    items, total = shoutout_service.list_shoutouts(
        db,
        user_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
        limit=pagination.limit,
        offset=pagination.offset,
    )
    return Page[ShoutoutRead](
        items=[ShoutoutRead.model_validate(item) for item in items],
        total=total,
        limit=pagination.limit,
        offset=pagination.offset,
    )


@router.get(
    "/{shoutout_id}",
    response_model=ShoutoutRead,
    summary="Retrieve one shoutout",
    description="404 if it doesn't exist OR isn't yours — the two are indistinguishable by design.",
)
def get_shoutout(
    shoutout_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> ShoutoutRead:
    try:
        entry = shoutout_service.get_shoutout(db, user_id=current_user.id, shoutout_id=shoutout_id)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return ShoutoutRead.model_validate(entry)


@router.patch(
    "/{shoutout_id}",
    response_model=ShoutoutRead,
    summary="Update a shoutout",
    description="Only provided fields change. Does not answer the feel-better follow-up — use the dedicated endpoint below.",
)
def update_shoutout(
    shoutout_id: uuid.UUID,
    payload: ShoutoutUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> ShoutoutRead:
    try:
        entry = shoutout_service.update_shoutout(db, user_id=current_user.id, shoutout_id=shoutout_id, payload=payload)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return ShoutoutRead.model_validate(entry)


@router.delete(
    "/{shoutout_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a shoutout",
)
def delete_shoutout(
    shoutout_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Response:
    try:
        shoutout_service.delete_shoutout(db, user_id=current_user.id, shoutout_id=shoutout_id)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{shoutout_id}/feel-better",
    response_model=ShoutoutRead,
    summary="Answer the 'did you feel better?' follow-up",
    description=(
        "Fixes a real bug found in the old app: it reads this answer back but never actually persisted it. "
        "One-shot — answering an already-answered shoutout returns 409."
    ),
)
def answer_feel_better(
    shoutout_id: uuid.UUID,
    payload: ShoutoutFeelBetterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> ShoutoutRead:
    try:
        entry = shoutout_service.answer_feel_better(
            db, user_id=current_user.id, shoutout_id=shoutout_id, felt_better=payload.felt_better
        )
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return ShoutoutRead.model_validate(entry)
