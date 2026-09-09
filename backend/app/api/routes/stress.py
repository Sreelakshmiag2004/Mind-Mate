"""
The authenticated user's own view of their stress indicator — always the
full, explainable StressResult (see app/schemas/stress.py for why the
comfort-person-facing view in relationships.py is narrower).
"""

from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.dependencies.auth import get_current_active_user
from app.models.user import User
from app.schemas.stress import StressResult
from app.services import stress_service

router = APIRouter(prefix="/stress", tags=["stress"])

# Hard upper bound on /stress/history's `days` — this endpoint computes on
# demand (see stress_service's module docstring on why nothing is cached),
# so an unbounded range would mean an unbounded number of on-the-fly
# aggregate queries per request.
MAX_HISTORY_DAYS = 90


@router.get(
    "/today",
    response_model=StressResult,
    summary="Your own stress indicator for today",
    description=(
        "A deterministic, rule-based wellness indicator derived only from your recent mood check-ins "
        "and checklist completion — not AI, not a diagnosis. See `contributors` for exactly what fed "
        "the score, and `confidence`/`level: insufficient_data` for when there isn't enough recent "
        "activity to compute one meaningfully."
    ),
)
def get_my_stress_today(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> StressResult:
    return stress_service.compute_stress(db, user_id=current_user.id)


@router.get(
    "/history",
    response_model=list[StressResult],
    summary="Your stress indicator over recent days",
    description=f"One entry per day, most recent first, bounded to at most {MAX_HISTORY_DAYS} days.",
)
def get_my_stress_history(
    days: int = Query(default=7, ge=1, le=MAX_HISTORY_DAYS, description=f"1-{MAX_HISTORY_DAYS}"),
    end_date: date | None = Query(default=None, description="Defaults to today"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> list[StressResult]:
    return stress_service.compute_stress_history(db, user_id=current_user.id, days=days, end_date=end_date)
