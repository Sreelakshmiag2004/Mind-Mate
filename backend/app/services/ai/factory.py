"""
The single place that decides WHICH AIReflectionProvider implementation
is live, based on settings.ai_provider — mirrors
app/services/storage/factory.py exactly. Routes/services depend on
get_ai_provider (a FastAPI dependency), never on
AnthropicReflectionProvider directly, so tests can override this one
function (see tests/conftest.py) and get MockAIReflectionProvider
everywhere without touching route/service code.
"""

from functools import lru_cache

from app.core.config import settings
from app.services.ai.anthropic_provider import AnthropicReflectionProvider
from app.services.ai.base import AIReflectionProvider


@lru_cache
def _anthropic_singleton() -> AnthropicReflectionProvider:
    # One client for the process lifetime — cheap to construct, but no
    # reason to rebuild it on every request.
    return AnthropicReflectionProvider(
        api_key=settings.ai_api_key,
        model=settings.ai_model,
        timeout_seconds=settings.ai_timeout_seconds,
    )


def get_ai_provider() -> AIReflectionProvider:
    if settings.ai_provider == "anthropic":
        return _anthropic_singleton()
    raise RuntimeError(
        f"Unknown AI_PROVIDER {settings.ai_provider!r} — expected 'anthropic' "
        "('mock' is test-only and is wired via a dependency override, never this setting)."
    )
