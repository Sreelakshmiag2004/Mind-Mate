"""
CRUD for the weekly_reflections table — see app/models/reflection.py for
the schema and why only two statuses exist. `upsert` is the ONLY write
path; there is no separate `create`, because the table's whole point is
"at most one row per (user_id, week_start)" — see
app/services/reflection_service.py for when it's called with
force_regenerate vs. a first-time generation.
"""

import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.reflection import WeeklyReflection
from app.schemas.reflection import AIReflectionOutput


def get_by_user_and_week(db: Session, *, user_id: uuid.UUID, week_start: date) -> Optional[WeeklyReflection]:
    stmt = select(WeeklyReflection).where(
        WeeklyReflection.user_id == user_id, WeeklyReflection.week_start == week_start
    )
    return db.execute(stmt).scalar_one_or_none()


def get_latest_for_user(db: Session, *, user_id: uuid.UUID) -> Optional[WeeklyReflection]:
    stmt = (
        select(WeeklyReflection)
        .where(WeeklyReflection.user_id == user_id)
        .order_by(WeeklyReflection.week_start.desc())
        .limit(1)
    )
    return db.execute(stmt).scalar_one_or_none()


def upsert(
    db: Session,
    *,
    user_id: uuid.UUID,
    week_start: date,
    week_end: date,
    status: str,
    summary_version: str,
    summary_input: dict,
    reflection: Optional[AIReflectionOutput] = None,
    ai_provider: Optional[str] = None,
    ai_model: Optional[str] = None,
    generated_at: Optional[datetime] = None,
) -> WeeklyReflection:
    """
    Get-or-create keyed by (user_id, week_start) — matching the table's
    UNIQUE constraint — then overwrite in place rather than inserting a
    second row, so a regenerate call updates the same reflection instead
    of accumulating history.
    """
    row = get_by_user_and_week(db, user_id=user_id, week_start=week_start)
    if row is None:
        row = WeeklyReflection(user_id=user_id, week_start=week_start, week_end=week_end)

    row.status = status
    row.summary_version = summary_version
    row.summary_input = summary_input
    row.ai_provider = ai_provider
    row.ai_model = ai_model
    row.generated_at = generated_at

    if reflection is not None:
        row.reflection_summary = reflection.summary
        row.reflection_mood_insight = reflection.mood_insight
        row.reflection_habit_insight = reflection.habit_insight
        row.reflection_positive_highlights = list(reflection.positive_highlights)
        row.reflection_areas_to_reflect_on = list(reflection.areas_to_reflect_on)
        row.reflection_encouragement = reflection.encouragement
    else:
        # status == 'insufficient_data' — no AI content to store; clear
        # any stale content from a previous force_regenerate attempt that
        # (for example) later data made insufficient again.
        row.reflection_summary = None
        row.reflection_mood_insight = None
        row.reflection_habit_insight = None
        row.reflection_positive_highlights = None
        row.reflection_areas_to_reflect_on = None
        row.reflection_encouragement = None

    db.add(row)
    db.commit()
    db.refresh(row)
    return row
