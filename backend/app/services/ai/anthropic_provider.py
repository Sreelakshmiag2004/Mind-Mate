"""
First (and, as of Phase 5, only) real AIReflectionProvider implementation:
Anthropic's Claude, via the official `anthropic` Python SDK's
`messages.parse()` structured-output helper — it validates the model's
JSON response against AIReflectionOutput server-side (constrained
decoding) and hands back an already-parsed, already-validated Pydantic
instance, which is exactly the guarantee app/core/exceptions.py's
AIProviderResponseError exists to enforce if it's ever NOT met (a safety
refusal, or a response the SDK couldn't parse at all).

Why Claude for this first implementation: this backend is being built by
Claude Code, so the Anthropic Python SDK's official structured-output
support (`messages.parse`, `output_format=<PydanticModel>`) was already
the best-documented, most directly verifiable integration available
while writing this phase — not a claim that no other provider could work
here. Nothing about app/services/reflection_service.py or
app/services/weekly_aggregation_service.py depends on Claude specifically
(see app/services/ai/base.py) — a second provider is a second file here
plus one line in factory.py.

The model defaults to `claude-opus-5` (settings.ai_model) but is fully
configurable via the AI_MODEL environment variable — see
backend/README.md, "AI provider abstraction", for the cost/quality
tradeoff of pointing it at a smaller model instead. This is a
low-request-volume, non-interactive background feature (at most one real
generation per user per completed week — see
app/services/reflection_service.py's caching policy), so the default
favors output quality over the lowest possible per-call cost.
"""

import anthropic

from app.core.exceptions import AIProviderError, AIProviderResponseError, AIProviderTimeoutError
from app.schemas.reflection import AIReflectionOutput, WeeklySummary
from app.services.ai.base import AIReflectionProvider

# Five short, bounded fields (see AIReflectionOutput's own Field max_length
# values) — comfortably fits in far fewer tokens than this; the headroom
# is deliberate so a slightly verbose response doesn't get cut off
# mid-JSON, which would itself surface as an AIProviderResponseError.
MAX_OUTPUT_TOKENS = 1024

SYSTEM_PROMPT = """You are writing a short, supportive weekly reflection for a user of \
MindMate, a personal wellness app. You will be given a structured, \
numbers-only summary of that user's activity for one week (mood \
check-ins, daily checklist completion, journal/shoutout activity counts, \
and a derived stress indicator). You have NOT been given — and must never \
assume, invent, or refer to — the content of any journal entry or \
shoutout; you only know that they happened, not what they said.

Follow these rules strictly:
1. Base every statement only on the structured data provided. Never \
invent facts, events, or feelings not implied by the data.
2. Do not diagnose depression, anxiety, or any mental illness. Do not use \
clinical or diagnostic language.
3. Do not give medical advice or suggest treatment, medication, or therapy.
4. Never claim certainty about the user's mental state. Describe \
observable patterns ("your logged mood was lower in the first half of \
the week") rather than facts about how the user feels or felt.
5. Use warm, plain, encouraging language — like a supportive friend \
noticing patterns, not a clinician writing a report.
6. If the data is mixed or shows a difficult period, acknowledge it \
honestly but gently, and pair it with something concrete and observable \
that went well, if the data supports one.
7. Never mention another person, and never suggest the user contact \
emergency services or a crisis line — if the data suggests real distress, \
simply reflect that gently and encourage self-compassion; escalation is \
handled elsewhere in the product, not by this response.
8. Respond ONLY with the structured fields you are asked for. Do not add \
headings, disclaimers, or any text outside those fields — the product \
adds its own disclaimer separately."""


def _build_user_prompt(summary: WeeklySummary) -> str:
    # `summary` is the entire input — see WeeklySummary's own docstring
    # for why it structurally cannot carry journal/shoutout text.
    return (
        "Here is one user's structured weekly activity summary from MindMate. "
        "Write their weekly reflection now, following your instructions exactly.\n\n"
        f"{summary.model_dump_json(indent=2)}"
    )


class AnthropicReflectionProvider(AIReflectionProvider):
    def __init__(self, *, api_key: str, model: str, timeout_seconds: float) -> None:
        self._model = model
        # max_retries=1 (not the SDK default of 2): a timeout here should
        # fail fast into a clean 502 for the caller's current request
        # (which can simply be retried by the client) rather than
        # multiplying the worst-case wall-clock time of a single request —
        # the same reasoning app/services/storage/s3_storage.py applies to
        # its own boto3 client.
        self._client = anthropic.AsyncAnthropic(api_key=api_key, timeout=timeout_seconds, max_retries=1)

    @property
    def provider_name(self) -> str:
        return "anthropic"

    @property
    def model_name(self) -> str:
        return self._model

    async def generate_reflection(self, summary: WeeklySummary) -> AIReflectionOutput:
        try:
            response = await self._client.messages.parse(
                model=self._model,
                max_tokens=MAX_OUTPUT_TOKENS,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": _build_user_prompt(summary)}],
                output_format=AIReflectionOutput,
            )
        except anthropic.APITimeoutError as exc:
            raise AIProviderTimeoutError("The AI provider did not respond in time") from exc
        except (anthropic.APIStatusError, anthropic.APIConnectionError) as exc:
            raise AIProviderError(f"The AI provider request failed ({type(exc).__name__})") from exc
        except Exception as exc:  # noqa: BLE001 - see AIReflectionProvider's contract: never let anything else escape
            raise AIProviderError(f"Unexpected AI provider failure ({type(exc).__name__})") from exc

        if getattr(response, "stop_reason", None) == "refusal":
            raise AIProviderResponseError("The AI provider declined to generate a reflection for this request")

        if response.parsed_output is None:
            raise AIProviderResponseError("The AI provider's response did not match the expected reflection schema")

        return response.parsed_output
