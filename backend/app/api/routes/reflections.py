"""
Weekly reflections (Phase 5) — see app/services/reflection_service.py for
the full generate-or-return-cached flow and
app/services/weekly_aggregation_service.py for what actually goes into a
summary. Every endpoint here is scoped to the authenticated caller's own
user_id, the same way every Phase 1-4 resource is: no route (and no
service function) can return one user's reflection to another user —
`GET /{week_start}` reuses NotFoundError for "doesn't exist OR isn't
yours", the same IDOR-resistance pattern journals/moods/shoutouts/media/
relationships already rely on.
"""

from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import AIProviderError, NotFoundError
from app.dependencies.auth import get_current_active_user
from app.models.user import User
from app.schemas.reflection import WeeklyReflectionGenerateRequest, WeeklyReflectionRead
from app.services import reflection_service
from app.services.ai import AIReflectionProvider, get_ai_provider

router = APIRouter(prefix="/reflections/weekly", tags=["reflections"])


@router.post(
    "/generate",
    response_model=WeeklyReflectionRead,
    summary="Generate (or return the cached) weekly reflection",
    description=(
        "Defaults to the most recently completed Monday-Sunday week. Returns the existing stored "
        "reflection without calling the AI provider again unless force_regenerate=true (see "
        "backend/README.md, 'Caching / regeneration'). 400 if week_start isn't a Monday or refers to "
        "a week that isn't over yet. 502 if the AI provider fails — nothing is written to storage in "
        "that case, so a prior completed reflection for that week (if any) is left untouched."
    ),
)
async def generate_weekly_reflection(
    payload: Optional[WeeklyReflectionGenerateRequest] = None,
    db: Session = Depends(get_db),
    provider: AIReflectionProvider = Depends(get_ai_provider),
    current_user: User = Depends(get_current_active_user),
) -> WeeklyReflectionRead:
    body = payload or WeeklyReflectionGenerateRequest()
    try:
        row = await reflection_service.generate_weekly_reflection(
            db,
            provider,
            user_id=current_user.id,
            week_start=body.week_start,
            force_regenerate=body.force_regenerate,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except AIProviderError:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="The reflection could not be generated right now. Please try again later.",
        )
    return WeeklyReflectionRead(**reflection_service.to_reflection_read_dict(row))


@router.get(
    "",
    response_model=WeeklyReflectionRead,
    summary="Your most recent weekly reflection",
    description="Read-only — never triggers generation or calls the AI provider. 404 if none has been generated yet.",
)
def get_latest_weekly_reflection(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> WeeklyReflectionRead:
    row = reflection_service.get_latest_reflection(db, user_id=current_user.id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No weekly reflection has been generated yet")
    return WeeklyReflectionRead(**reflection_service.to_reflection_read_dict(row))


@router.get(
    "/{week_start}",
    response_model=WeeklyReflectionRead,
    summary="Retrieve one week's reflection",
    description="404 if that week doesn't exist OR doesn't belong to you — the two are indistinguishable by design.",
)
def get_weekly_reflection(
    week_start: date,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> WeeklyReflectionRead:
    try:
        row = reflection_service.get_reflection_for_week(db, user_id=current_user.id, week_start=week_start)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return WeeklyReflectionRead(**reflection_service.to_reflection_read_dict(row))
