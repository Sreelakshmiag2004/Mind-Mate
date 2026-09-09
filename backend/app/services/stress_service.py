"""
The "stress signal": a transparent, deterministic, rule-based wellness
indicator — explicitly NOT an AI/ML feature (see backend/README.md's
Phase 4 section and the Phase 4 brief this module was built against). It
exists to give real backend substance to the one thing the old UI already
promises but never implements: the "View today's stress level" button in
`favorite_page.dart`, currently wired to `// TODO: Implement stress level
view`.

## What feeds the score, and what deliberately does not

Two signals only, both already-existing MindMate features with their own
dedicated screens:

  * Recent mood check-ins (`mood_entries.mood_value`, the app's existing
    0-100 mood percentage — see app/models/mood.py).
  * Recent daily wellness checklist completion (`checklist_completions`
    — see app/models/checklist.py).

Journal activity/content is deliberately NOT a scoring input, even though
the Phase 4 brief allows it as an optional signal. Whether someone wrote a
journal entry on a given day is a weak, easily-misread proxy for stress —
treating "didn't journal" as evidence of stress would punish a person
having a perfectly fine, unremarkable day, and using journal *content*
would require reading private text this endpoint must never expose (see
"Never exposed" below). Shoutouts and media are excluded for the same
"never exposed" reason, not because they were considered and weighted.

## The formula

Over a trailing 7-day window ending on the reference date:

  * `mood_component` = 100 − average(mood_value in window). Mood is
    recorded on the app's own 0-100 "good day" scale, so inverting it is
    the simplest, most literal reading of "low mood score → higher stress
    contribution" available without inventing a second scale.
  * `checklist_component` = 100 × (1 − completed / possible), where
    `possible` = (active checklist item count) × (days in the window the
    user could actually have used the app, i.e. not before their account
    existed). Lower completion → higher stress contribution.
  * `score` = round(0.6 × mood_component + 0.4 × checklist_component),
    clamped to [0, 100]. Mood is weighted higher because it is the app's
    only direct self-report of how someone feels; the checklist is a
    behavioral proxy. If only one signal has any data in the window, the
    score is that signal alone (weights renormalized to 1.0), not zeroed
    out for the missing one.

`score` is deliberately `None` — not 0, not a guess — when the window has
no mood entries AND no checklist activity at all; see `_level_and_score`.
A missing signal is never treated as "0 stress" or "100 stress".

## Never exposed here

This module only ever reads aggregate numbers (an average, a count) via
app/repositories/stress_repository.py — it never loads, returns, or logs
a JournalEntry's title/content, a Shoutout's title/content, or any
MediaAsset. See app/schemas/stress.py for the two response shapes and why
the comfort-person-facing one is narrower still.

## Stored or computed?

Computed fresh on every call from source rows, never persisted. The data
volume this ever aggregates over is small (at most 7 days × a handful of
mood/checklist rows) and nothing in the product needs a stress score to
survive independently of the data it was derived from — persisting a
snapshot would just be a second, potentially-stale copy of a cheap
query's result. See backend/README.md, Phase 4 section, for the full
"why no stress_snapshots table" reasoning.
"""

import uuid
from dataclasses import dataclass
from datetime import date as date_
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.repositories import stress_repository, user_repository
from app.schemas.stress import StressContributors, StressResult

WINDOW_DAYS = 7
MOOD_WEIGHT = 0.6
CHECKLIST_WEIGHT = 0.4


@dataclass
class _RawSignals:
    mood_average: Optional[float]
    checklist_rate: Optional[float]
    data_points: int


def _level_for_score(score: int) -> str:
    if score <= 33:
        return "low"
    if score <= 66:
        return "moderate"
    return "elevated"


def _confidence_for_data_points(data_points: int) -> str:
    if data_points == 0:
        return "none"
    if data_points < 3:
        return "low"
    if data_points < 5:
        return "medium"
    return "high"


def _gather_signals(
    db: Session, *, user_id: uuid.UUID, window_start: date_, window_end: date_
) -> _RawSignals:
    mood_values = stress_repository.get_mood_values_in_window(
        db, user_id=user_id, start_date=window_start, end_date=window_end
    )
    mood_average = (sum(mood_values) / len(mood_values)) if mood_values else None

    checklist_rows = stress_repository.count_checklist_rows_in_window(
        db, user_id=user_id, start_date=window_start, end_date=window_end
    )
    checklist_rate: Optional[float] = None
    if checklist_rows > 0:
        active_item_count = stress_repository.count_active_checklist_items(db)
        user = user_repository.get_by_id(db, user_id)
        effective_start = window_start
        if user is not None:
            created_date = user.created_at.date() if hasattr(user.created_at, "date") else user.created_at
            if created_date > effective_start:
                effective_start = created_date
        days_elapsed = max((window_end - effective_start).days + 1, 1)
        possible_slots = active_item_count * days_elapsed
        if possible_slots > 0:
            completed_count = stress_repository.count_completed_checklist_items_in_window(
                db, user_id=user_id, start_date=window_start, end_date=window_end
            )
            checklist_rate = min(completed_count / possible_slots, 1.0)

    activity_dates = stress_repository.get_activity_dates_in_window(
        db, user_id=user_id, start_date=window_start, end_date=window_end
    )
    return _RawSignals(mood_average=mood_average, checklist_rate=checklist_rate, data_points=len(activity_dates))


def compute_stress(
    db: Session, *, user_id: uuid.UUID, reference_date: Optional[date_] = None
) -> StressResult:
    if reference_date is None:
        reference_date = datetime.now(timezone.utc).date()
    window_start = reference_date - timedelta(days=WINDOW_DAYS - 1)
    window_end = reference_date

    signals = _gather_signals(db, user_id=user_id, window_start=window_start, window_end=window_end)

    mood_component = 100 - signals.mood_average if signals.mood_average is not None else None
    checklist_component = 100 * (1 - signals.checklist_rate) if signals.checklist_rate is not None else None

    score: Optional[int]
    if mood_component is None and checklist_component is None:
        score = None
        level = "insufficient_data"
    else:
        if mood_component is not None and checklist_component is not None:
            raw = MOOD_WEIGHT * mood_component + CHECKLIST_WEIGHT * checklist_component
        elif mood_component is not None:
            raw = mood_component
        else:
            raw = checklist_component
        score = max(0, min(100, round(raw)))
        level = _level_for_score(score)

    return StressResult(
        score=score,
        level=level,
        confidence=_confidence_for_data_points(signals.data_points),
        calculated_at=datetime.now(timezone.utc),
        data_window_start=window_start,
        data_window_end=window_end,
        contributors=StressContributors(
            mood_average=round(signals.mood_average, 1) if signals.mood_average is not None else None,
            checklist_completion_rate=(
                round(signals.checklist_rate, 3) if signals.checklist_rate is not None else None
            ),
        ),
    )


def compute_stress_history(
    db: Session, *, user_id: uuid.UUID, days: int, end_date: Optional[date_] = None
) -> list[StressResult]:
    """
    One StressResult per day over `days` calendar days ending at `end_date`
    (default today), each computed with its own trailing WINDOW_DAYS-day
    window — a rolling history, not a stored log. Bounded by the route
    layer (see app/api/routes/stress.py) so this can never be asked to
    materialize an unbounded range.
    """
    if end_date is None:
        end_date = datetime.now(timezone.utc).date()
    return [compute_stress(db, user_id=user_id, reference_date=end_date - timedelta(days=offset)) for offset in range(days)]
