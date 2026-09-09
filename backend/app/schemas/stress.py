"""
Schemas for the deterministic, rule-based "stress signal" — see
app/services/stress_service.py for the algorithm. Two response shapes
exist on purpose:

* `StressResult` — returned by the owner's own /stress/* endpoints. Full
  transparency: includes the per-signal breakdown (`contributors`) so the
  score is explainable, not a black box.
* `ComfortStressView` — returned by the comfort-person-facing endpoint.
  Deliberately narrower: score/level/confidence/window only, no
  contributor breakdown. The product only ever promised "view today's
  stress level" (favorite_page.dart) — a comfort person does not need, and
  is not given, the underlying mood-average/checklist-rate numbers that
  went into it, matching the Phase 4 "minimum necessary" consent brief.

Neither schema is ever built from raw journal/shoutout/media content —
see stress_service.py's module docstring for what feeds the score.
"""

from datetime import date, datetime
from typing import Literal, Optional

from pydantic import BaseModel

StressLevel = Literal["insufficient_data", "low", "moderate", "elevated"]
StressConfidence = Literal["none", "low", "medium", "high"]

DISCLAIMER = (
    "This is an automated wellness indicator derived from your recent MindMate activity "
    "(mood check-ins and daily checklist completion). It is not a medical or clinical "
    "assessment and should not be treated as one."
)


class StressContributors(BaseModel):
    """Explains *why* the score came out the way it did — see the module docstring."""

    mood_average: Optional[float]
    checklist_completion_rate: Optional[float]


class StressResult(BaseModel):
    score: Optional[int]
    level: StressLevel
    confidence: StressConfidence
    calculated_at: datetime
    data_window_start: date
    data_window_end: date
    contributors: StressContributors
    disclaimer: str = DISCLAIMER


class ComfortStressView(BaseModel):
    score: Optional[int]
    level: StressLevel
    confidence: StressConfidence
    calculated_at: datetime
    data_window_start: date
    data_window_end: date
    disclaimer: str = DISCLAIMER
