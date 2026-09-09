"""
Phase 5: the top-level orchestrator for weekly reflections — the only
module that decides "is a stored reflection good enough to return as-is,
or do we need to aggregate and call the AI provider". Mirrors
media_service.py's role (the one place that coordinates a DB write with a
possibly-failing external dependency), except the external dependency
here is an AIReflectionProvider instead of ObjectStorageService — see
app/services/ai/base.py.

Flow (see backend/README.md, "Weekly reflection architecture"):

    FastAPI route (app/api/routes/reflections.py)
      -> generate_weekly_reflection() [this module]
          -> reflection_repository.get_by_user_and_week()  [cache check]
          -> weekly_aggregation_service.build_weekly_summary()
          -> (insufficient data? persist+return : provider.generate_reflection())
          -> reflection_repository.upsert()

## Caching / regeneration policy

`force_regenerate=False` (the default): if any row already exists for
(user, week) — 'completed' or 'insufficient_data' — it is returned as-is.
No aggregation, no AI call. This is the whole cost-control story for this
feature (see the module docstring's caching rule): a given user/week pair
calls the AI provider at most once, ever, unless a caller explicitly asks
to redo it.

`force_regenerate=True`: aggregation and (if the data is sufficient) the
AI provider are always invoked again, and the result overwrites the
existing row (see app/repositories/reflection_repository.py's upsert).

## Why an AI provider failure is never persisted

If `provider.generate_reflection()` raises (timeout, provider error, or
an unvalidatable response), this function lets that exception propagate —
app/api/routes/reflections.py maps it to a 502 — and writes NOTHING to
the database. Two deliberate consequences:

  * A failed attempt is always transparently retryable: the next
    `POST /generate` call for that same week sees no existing row (or
    the same old one, if this was a force_regenerate attempt on top of a
    previously 'completed' week) and simply tries again — no separate
    "the last attempt failed, allow a retry without force_regenerate"
    special case is needed anywhere.
  * A `force_regenerate=True` call that fails can never destroy a
    previously-'completed' reflection. Since nothing is written on
    failure, the prior row (if any) is left exactly as it was — this
    sidesteps, by construction, the harder question of whether a failed
    regeneration attempt should be allowed to clobber good data.
"""

import logging
import uuid
from datetime import date as date_
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.core.exceptions import AIProviderError, NotFoundError
from app.models.reflection import WeeklyReflection
from app.repositories import reflection_repository
from app.schemas.reflection import AIReflectionOutput
from app.services import weekly_aggregation_service
from app.services.ai.base import AIReflectionProvider

logger = logging.getLogger(__name__)

# Tags the shape of `summary_input` — see app/models/reflection.py.
SUMMARY_SCHEMA_VERSION = "v1"


def _most_recently_completed_week_start(today: date_) -> date_:
    this_monday = today - timedelta(days=today.weekday())
    return this_monday - timedelta(days=7)


def resolve_week_start(requested: Optional[date_]) -> date_:
    """
    Defaults to the most recently completed Monday-Sunday week (UTC).
    Raises ValueError — mapped to HTTP 400 by the route — for an explicit
    `requested` that isn't a Monday, or that refers to a week not yet
    fully over: reflecting on a week makes the most sense once it's
    actually finished, and a partial week's "trend" would be noisy and
    potentially misleading (see PART 6/7 of the Phase 5 brief on hedged,
    non-misleading language).
    """
    today = datetime.now(timezone.utc).date()
    if requested is None:
        return _most_recently_completed_week_start(today)

    if requested.weekday() != 0:
        raise ValueError("week_start must be a Monday")

    week_end = requested + timedelta(days=6)
    if week_end >= today:
        raise ValueError("week_start must refer to a fully completed week")

    return requested


async def generate_weekly_reflection(
    db: Session,
    provider: AIReflectionProvider,
    *,
    user_id: uuid.UUID,
    week_start: Optional[date_],
    force_regenerate: bool,
) -> WeeklyReflection:
    resolved_week_start = resolve_week_start(week_start)
    week_end = resolved_week_start + timedelta(days=6)

    existing = reflection_repository.get_by_user_and_week(db, user_id=user_id, week_start=resolved_week_start)
    if existing is not None and not force_regenerate:
        return existing

    summary = weekly_aggregation_service.build_weekly_summary(
        db, user_id=user_id, week_start=resolved_week_start, week_end=week_end
    )

    if not summary.has_sufficient_data:
        return reflection_repository.upsert(
            db,
            user_id=user_id,
            week_start=resolved_week_start,
            week_end=week_end,
            status="insufficient_data",
            summary_version=SUMMARY_SCHEMA_VERSION,
            summary_input=summary.model_dump(mode="json"),
        )

    try:
        output: AIReflectionOutput = await provider.generate_reflection(summary)
    except AIProviderError as exc:
        # Safe to log: user_id, the week, the provider/model, and the
        # failure category — never the summary content or any exception
        # text that might echo provider-side detail. See PART 13.
        logger.warning(
            "weekly_reflection_generation_failed user_id=%s week_start=%s provider=%s category=%s",
            user_id,
            resolved_week_start,
            provider.provider_name,
            type(exc).__name__,
        )
        raise

    return reflection_repository.upsert(
        db,
        user_id=user_id,
        week_start=resolved_week_start,
        week_end=week_end,
        status="completed",
        summary_version=SUMMARY_SCHEMA_VERSION,
        summary_input=summary.model_dump(mode="json"),
        reflection=output,
        ai_provider=provider.provider_name,
        ai_model=provider.model_name,
        generated_at=datetime.now(timezone.utc),
    )


def get_latest_reflection(db: Session, *, user_id: uuid.UUID) -> Optional[WeeklyReflection]:
    return reflection_repository.get_latest_for_user(db, user_id=user_id)


def get_reflection_for_week(db: Session, *, user_id: uuid.UUID, week_start: date_) -> WeeklyReflection:
    row = reflection_repository.get_by_user_and_week(db, user_id=user_id, week_start=week_start)
    if row is None:
        raise NotFoundError("No weekly reflection found for that week")
    return row


def to_reflection_read_dict(row: WeeklyReflection) -> dict:
    """
    Shapes one WeeklyReflection row into the dict
    app.schemas.reflection.WeeklyReflectionRead expects — the row's
    columns are flat, the API response nests the AI fields under
    `reflection` and reads `insufficient_data_reason` back out of the
    stored `summary_input` rather than a duplicate column (see
    app/models/reflection.py). Mirrors relationship_service.py's
    to_relationship_read_dict for the same "ORM shape != API shape"
    reason.
    """
    reflection = None
    if row.status == "completed":
        reflection = AIReflectionOutput(
            summary=row.reflection_summary,
            mood_insight=row.reflection_mood_insight,
            habit_insight=row.reflection_habit_insight,
            positive_highlights=row.reflection_positive_highlights or [],
            areas_to_reflect_on=row.reflection_areas_to_reflect_on or [],
            encouragement=row.reflection_encouragement,
        )

    return {
        "id": row.id,
        "user_id": row.user_id,
        "week_start": row.week_start,
        "week_end": row.week_end,
        "status": row.status,
        "reflection": reflection,
        "insufficient_data_reason": (row.summary_input or {}).get("insufficient_data_reason"),
        "ai_provider": row.ai_provider,
        "ai_model": row.ai_model,
        "generated_at": row.generated_at,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }
