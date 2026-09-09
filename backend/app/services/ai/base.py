"""
The one interface reflection_service.py is written against — mirrors
app/services/storage/base.py's ObjectStorageService pattern exactly.
Nothing outside app/services/ai/ ever imports the Anthropic SDK (or any
other provider SDK) directly, so swapping providers later means changing
app/services/ai/factory.py and adding one new implementation file, never
touching app/services/reflection_service.py or any route.
"""

from abc import ABC, abstractmethod

from app.schemas.reflection import AIReflectionOutput, WeeklySummary


class AIReflectionProvider(ABC):
    @property
    @abstractmethod
    def provider_name(self) -> str:
        """A short, stable identifier (e.g. 'anthropic', 'mock') — stored on WeeklyReflection.ai_provider."""

    @property
    @abstractmethod
    def model_name(self) -> str:
        """The specific model used — stored on WeeklyReflection.ai_model."""

    @abstractmethod
    async def generate_reflection(self, summary: WeeklySummary) -> AIReflectionOutput:
        """
        Generate a structured reflection from `summary` — a
        privacy-controlled aggregate (see
        app/services/weekly_aggregation_service.py), never raw journal/
        shoutout content; `summary`'s own type makes that impossible to
        get wrong here.

        Must return an AIReflectionOutput that has already passed Pydantic
        validation, or raise exactly one of:
          * AIProviderTimeoutError — the provider did not respond within
            the configured timeout.
          * AIProviderResponseError — the provider responded, but its
            output could not be validated against AIReflectionOutput
            (malformed JSON, a missing/oversized field, a safety refusal).
          * AIProviderError — any other provider-side failure.

        Implementations must never let any other exception type escape —
        see app/core/exceptions.py.
        """
