"""
Transforms one user's raw activity for one calendar week into a
WeeklySummary — the ONLY thing that ever reaches an AI provider for
weekly reflection generation (see app/services/ai/base.py and
backend/README.md, "Privacy boundary"). This module reads exclusively via
app/repositories/stress_repository.py (mood/checklist aggregates) and
app/repositories/weekly_aggregation_repository.py (journal/shoutout
DATES and one boolean) — it never imports JournalEntry/Shoutout content
columns, so there is no raw free text anywhere in this module for a later
change to accidentally leak into a reflection.

A "week" is always Monday-Sunday — see
app/services/reflection_service.resolve_week_start for where week_start
is validated/defaulted before this function is ever called; this module
trusts that `week_start`/`week_end` already form exactly such a 7-day
range and does no validation of its own.

## Trend calculations

`mood_trend` compares the first three days of the week (Mon-Wed) against
the last three (Fri-Sun), skipping Thursday as a deliberate gap between
the two halves rather than splitting down the middle — this keeps the
comparison to two clearly-separated windows instead of one day doing
double duty. `insufficient_data` if either half has zero mood entries;
otherwise "improving"/"declining" if the average moved by at least
MOOD_TREND_THRESHOLD points, else "stable".

`stress_trend` reuses app/services/stress_service.py's own
compute_stress() at two reference dates — it does NOT add a second stress
formula (Phase 5 must not). `compute_stress(reference_date=week_end)`
covers a trailing 7-day window that is exactly this week (window_start ==
week_start), so `stress_score_end` reflects this week's own data.
`compute_stress(reference_date=week_start)` covers the 7 days *ending* on
week_start — i.e. mostly the week before this one — so `stress_score_start`
is a "before this week" baseline, not a data point drawn from inside the
week being reflected on. `insufficient_data` if either score is None
(the stress indicator itself had insufficient data for that reference
date); otherwise "improving" (stress went down) / "worsening" (stress
went up) if the score moved by at least STRESS_TREND_THRESHOLD points,
else "stable".
"""

import uuid
from datetime import date as date_
from datetime import timedelta
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from app.repositories import stress_repository, weekly_aggregation_repository
from app.schemas.reflection import MoodTrend, StressTrend, WeeklySummary
from app.services import stress_service

# A week with fewer than this many distinct active days is never sent to
# the AI provider — see reflection_service.py. Two, not one: a single
# active day out of seven has nothing to describe a "pattern" over, and
# generating a confident-sounding reflection from one data point would
# violate the "acknowledge uncertainty" safety rule more than declining to
# generate one at all.
MIN_ACTIVE_DAYS_FOR_REFLECTION = 2

MOOD_TREND_THRESHOLD = 5
STRESS_TREND_THRESHOLD = 5


def _mood_trend(db: Session, *, user_id: uuid.UUID, week_start: date_, week_end: date_) -> MoodTrend:
    first_half_end = week_start + timedelta(days=2)  # Mon-Wed
    second_half_start = week_start + timedelta(days=4)  # Fri-Sun
    first_half = stress_repository.get_mood_values_in_window(
        db, user_id=user_id, start_date=week_start, end_date=first_half_end
    )
    second_half = stress_repository.get_mood_values_in_window(
        db, user_id=user_id, start_date=second_half_start, end_date=week_end
    )
    if not first_half or not second_half:
        return "insufficient_data"

    diff = (sum(second_half) / len(second_half)) - (sum(first_half) / len(first_half))
    if diff >= MOOD_TREND_THRESHOLD:
        return "improving"
    if diff <= -MOOD_TREND_THRESHOLD:
        return "declining"
    return "stable"


def _stress_trend(
    db: Session, *, user_id: uuid.UUID, week_start: date_, week_end: date_
) -> Tuple[Optional[int], Optional[int], StressTrend]:
    start_result = stress_service.compute_stress(db, user_id=user_id, reference_date=week_start)
    end_result = stress_service.compute_stress(db, user_id=user_id, reference_date=week_end)

    if start_result.score is None or end_result.score is None:
        return start_result.score, end_result.score, "insufficient_data"

    diff = end_result.score - start_result.score
    if diff <= -STRESS_TREND_THRESHOLD:
        trend: StressTrend = "improving"
    elif diff >= STRESS_TREND_THRESHOLD:
        trend = "worsening"
    else:
        trend = "stable"
    return start_result.score, end_result.score, trend


def build_weekly_summary(db: Session, *, user_id: uuid.UUID, week_start: date_, week_end: date_) -> WeeklySummary:
    mood_values = stress_repository.get_mood_values_in_window(db, user_id=user_id, start_date=week_start, end_date=week_end)
    mood_average = round(sum(mood_values) / len(mood_values), 1) if mood_values else None
    mood_min = min(mood_values) if mood_values else None
    mood_max = max(mood_values) if mood_values else None
    mood_trend = _mood_trend(db, user_id=user_id, week_start=week_start, week_end=week_end)

    checklist_dates = weekly_aggregation_repository.get_checklist_active_dates_in_window(
        db, user_id=user_id, start_date=week_start, end_date=week_end
    )
    checklist_completion_rate: Optional[float] = None
    if checklist_dates:
        active_items = stress_repository.count_active_checklist_items(db)
        completed = stress_repository.count_completed_checklist_items_in_window(
            db, user_id=user_id, start_date=week_start, end_date=week_end
        )
        possible = active_items * 7  # the full calendar week, not clipped to account-creation date
        if possible > 0:
            checklist_completion_rate = round(min(completed / possible, 1.0), 3)

    journal_dates = weekly_aggregation_repository.get_journal_entry_dates_in_window(
        db, user_id=user_id, start_date=week_start, end_date=week_end
    )
    shoutout_dates = weekly_aggregation_repository.get_shoutout_dates_in_window(
        db, user_id=user_id, start_date=week_start, end_date=week_end
    )
    shoutout_positive_feel_better_count = weekly_aggregation_repository.count_shoutouts_with_positive_feel_better_in_window(
        db, user_id=user_id, start_date=week_start, end_date=week_end
    )

    stress_score_start, stress_score_end, stress_trend = _stress_trend(
        db, user_id=user_id, week_start=week_start, week_end=week_end
    )

    mood_or_checklist_dates = stress_repository.get_activity_dates_in_window(
        db, user_id=user_id, start_date=week_start, end_date=week_end
    )
    active_days = len(mood_or_checklist_dates | journal_dates | shoutout_dates)

    has_sufficient_data = active_days >= MIN_ACTIVE_DAYS_FOR_REFLECTION
    insufficient_data_reason: Optional[str] = None
    if not has_sufficient_data:
        if active_days == 0:
            insufficient_data_reason = "No activity was recorded during this week."
        else:
            insufficient_data_reason = (
                f"Only {active_days} day of activity was recorded this week — "
                "not enough to identify a meaningful weekly pattern."
            )

    return WeeklySummary(
        week_start=week_start,
        week_end=week_end,
        active_days=active_days,
        mood_entry_count=len(mood_values),
        mood_average=mood_average,
        mood_min=mood_min,
        mood_max=mood_max,
        mood_trend=mood_trend,
        checklist_days_tracked=len(checklist_dates),
        checklist_completion_rate=checklist_completion_rate,
        journal_entry_count=len(journal_dates),
        shoutout_count=len(shoutout_dates),
        shoutout_positive_feel_better_count=shoutout_positive_feel_better_count,
        stress_score_start=stress_score_start,
        stress_score_end=stress_score_end,
        stress_trend=stress_trend,
        has_sufficient_data=has_sufficient_data,
        insufficient_data_reason=insufficient_data_reason,
    )
