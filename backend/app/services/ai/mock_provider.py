"""
Deterministic, network-free AIReflectionProvider used ONLY by the test
suite — wired via a dependency override in tests/conftest.py, exactly
like app/services/storage/memory_storage.py's InMemoryStorageService.
Never selectable through settings.ai_provider (see
app/services/ai/factory.py); production always constructs
AnthropicReflectionProvider.
"""

from typing import List, Optional

from app.schemas.reflection import AIReflectionOutput, WeeklySummary
from app.services.ai.base import AIReflectionProvider


class MockAIReflectionProvider(AIReflectionProvider):
    """
    Returns a deterministic, summary-derived reflection by default, so
    tests can assert on it without depending on real model output. Set
    `.next_error` to an exception instance to make the *next* call raise
    it instead (then it's consumed, exactly once). `.calls` records every
    WeeklySummary this provider was actually asked to reflect on — tests
    use it to prove, e.g., that an insufficient-data week never reaches
    the provider at all, or that a cached result skips a second call.
    """

    def __init__(self) -> None:
        self.calls: List[WeeklySummary] = []
        self.next_error: Optional[Exception] = None

    @property
    def provider_name(self) -> str:
        return "mock"

    @property
    def model_name(self) -> str:
        return "mock-v1"

    async def generate_reflection(self, summary: WeeklySummary) -> AIReflectionOutput:
        self.calls.append(summary)

        if self.next_error is not None:
            error, self.next_error = self.next_error, None
            raise error

        return AIReflectionOutput(
            summary=f"This week you were active on {summary.active_days} day(s).",
            mood_insight=(
                f"Your average mood this week was {summary.mood_average}."
                if summary.mood_average is not None
                else "There wasn't enough mood data to describe a pattern this week."
            ),
            habit_insight=(
                f"Your checklist completion rate was {summary.checklist_completion_rate}."
                if summary.checklist_completion_rate is not None
                else "There wasn't enough checklist data to describe a pattern this week."
            ),
            positive_highlights=["You showed up for yourself this week."],
            areas_to_reflect_on=["Consider what made the harder days harder."],
            encouragement="Keep going — small steps add up.",
        )

    def reset(self) -> None:
        """Test-only helper — called from tests/conftest.py between tests so calls never leak."""
        self.calls.clear()
        self.next_error = None
