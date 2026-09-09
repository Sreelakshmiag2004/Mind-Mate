"""
Schemas for Phase 5's weekly reflection feature. Three distinct shapes,
deliberately kept separate rather than one growing model:

* `WeeklySummary` — the privacy-controlled, structured intermediate
  representation built by app/services/weekly_aggregation_service.py.
  This is the ONLY thing that ever reaches an AIReflectionProvider (see
  app/services/ai/base.py) — every field here is a count, an average, a
  min/max, or an enum. There is no field anywhere in this class capable
  of holding a journal/shoutout title or body, on purpose: the privacy
  boundary described in backend/README.md ("Privacy boundary") is
  enforced by this class's shape, not by a runtime check elsewhere that
  could be forgotten.
* `AIReflectionOutput` — the AI provider's structured response, validated
  by Pydantic before it is ever persisted or returned to a client (see
  app/core/exceptions.py's AIProviderResponseError for what happens when
  it doesn't validate). Every string/list field is length-bounded, both
  to keep the response supportive-and-brief rather than an unbounded
  essay, and as a concrete guard against a runaway or malicious provider
  response.
* `WeeklyReflectionRead` / `WeeklyReflectionGenerateRequest` — the HTTP
  API shapes (see app/api/routes/reflections.py).
"""

import uuid
from datetime import date, datetime
from typing import Annotated, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

MoodTrend = Literal["improving", "declining", "stable", "insufficient_data"]
StressTrend = Literal["improving", "worsening", "stable", "insufficient_data"]
ReflectionStatus = Literal["completed", "insufficient_data"]

_Highlight = Annotated[str, Field(max_length=200)]


class WeeklySummary(BaseModel):
    """
    See the module docstring — this is the complete, privacy-controlled
    input an AIReflectionProvider ever receives. Field-by-field:

    * `mood_*` / `checklist_*` come from the exact same aggregate queries
      app/services/stress_service.py already uses (see
      app/repositories/stress_repository.py) — reused, not recomputed a
      second way, so the two features can never silently disagree about
      what "this week's mood average" means.
    * `journal_entry_count` / `shoutout_count` are counts of entries that
      exist in the window — never their title/content. `shoutout_
      positive_feel_better_count` is the one piece of shoutout *content*
      that ever leaves the database for this feature, and it's a
      boolean, not text (see app/models/shoutout.py).
    * `stress_score_start`/`stress_score_end` reuse
      app/services/stress_service.py's own compute_stress() rather than
      a second stress formula (Phase 5 must not add a new one) — see
      app/services/weekly_aggregation_service.py for exactly which
      reference dates are used and why.
    """

    week_start: date
    week_end: date

    active_days: int = Field(description="Distinct calendar dates in the week with any mood, checklist, journal, or shoutout activity")

    mood_entry_count: int
    mood_average: Optional[float] = None
    mood_min: Optional[int] = None
    mood_max: Optional[int] = None
    mood_trend: MoodTrend

    checklist_days_tracked: int
    checklist_completion_rate: Optional[float] = Field(default=None, description="0-1, or null if the checklist was never touched this week")

    journal_entry_count: int
    shoutout_count: int
    shoutout_positive_feel_better_count: int

    stress_score_start: Optional[int] = Field(default=None, description="Stress score computed as of week_start — see weekly_aggregation_service")
    stress_score_end: Optional[int] = Field(default=None, description="Stress score computed as of week_end — covers this week's own data")
    stress_trend: StressTrend

    has_sufficient_data: bool
    insufficient_data_reason: Optional[str] = None


class AIReflectionOutput(BaseModel):
    """
    The AI provider's structured response. Every field is required and
    length-bounded — see app/services/ai/anthropic_provider.py's system
    prompt for the safety/tone rules (non-clinical, no diagnosis, hedged
    language) this content must follow; this schema only enforces shape
    and size, not tone, which is why the prompt-level rules matter too.
    """

    summary: str = Field(max_length=700)
    mood_insight: str = Field(max_length=400)
    habit_insight: str = Field(max_length=400)
    positive_highlights: List[_Highlight] = Field(max_length=5)
    areas_to_reflect_on: List[_Highlight] = Field(max_length=5)
    encouragement: str = Field(max_length=300)


class WeeklyReflectionGenerateRequest(BaseModel):
    week_start: Optional[date] = Field(
        default=None,
        description="Must be a Monday and refer to a fully completed week. Defaults to the most recently completed week.",
    )
    force_regenerate: bool = Field(
        default=False,
        description="Re-run aggregation and call the AI provider again even if a completed reflection already exists for this week.",
    )


class WeeklyReflectionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    week_start: date
    week_end: date
    status: ReflectionStatus
    reflection: Optional[AIReflectionOutput] = None
    insufficient_data_reason: Optional[str] = None
    ai_provider: Optional[str] = None
    ai_model: Optional[str] = None
    generated_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
