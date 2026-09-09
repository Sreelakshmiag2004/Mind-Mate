"""
Phase 5: weekly reflections. Every test goes through the ordinary
synchronous TestClient — FastAPI's async routes (generate_weekly_reflection)
run fine under it, exactly like media.py's async upload route already does
in test_media.py, so no pytest-asyncio is needed anywhere here.

`ai_provider` (see tests/conftest.py) is the same MockAIReflectionProvider
instance the app is using: `.calls` records every WeeklySummary it was
actually asked to reflect on (used to prove aggregation correctness AND
that insufficient-data weeks / cache hits never reach the provider at
all), and `.next_error` lets a test make the next call fail in a chosen
way without any network access or real Anthropic credentials.
"""

from datetime import date, timedelta
from typing import Optional

from fastapi.testclient import TestClient

from app.core.exceptions import AIProviderError, AIProviderResponseError, AIProviderTimeoutError
from tests.conftest import register_and_get_headers

# A fixed, fully-completed Monday-Sunday week, far enough in the past that
# "is this week over yet" is never a concern for any test using it.
WEEK_START = date(2024, 1, 1)  # a Monday
WEEK_END = WEEK_START + timedelta(days=6)


def _d(offset: int) -> str:
    """ISO date string for WEEK_START + offset days (0=Mon ... 6=Sun)."""
    return str(WEEK_START + timedelta(days=offset))


def _log_mood(client: TestClient, headers: dict, entry_date: str, value: int):
    response = client.post("/moods", json={"entry_date": entry_date, "mood_value": value}, headers=headers)
    assert response.status_code == 201, response.text


def _toggle_checklist(client: TestClient, headers: dict, entry_date: str, completed: bool = True):
    items = client.get("/checklists/items", headers=headers)
    assert items.status_code == 200
    completions = [{"item_id": item["id"], "completed": completed} for item in items.json()]
    response = client.patch(f"/checklists/{entry_date}", json={"completions": completions}, headers=headers)
    assert response.status_code == 200, response.text


def _write_journal(client: TestClient, headers: dict, entry_date: str, content: str = "just a normal day"):
    response = client.post("/journals", json={"entry_date": entry_date, "content": content}, headers=headers)
    assert response.status_code == 201, response.text


def _write_shoutout(
    client: TestClient, headers: dict, entry_date: str, content: str = "venting", felt_better: Optional[bool] = None
):
    response = client.post("/shoutouts", json={"entry_date": entry_date, "content": content}, headers=headers)
    assert response.status_code == 201, response.text
    if felt_better is not None:
        shoutout_id = response.json()["id"]
        fb = client.post(f"/shoutouts/{shoutout_id}/feel-better", json={"felt_better": felt_better}, headers=headers)
        assert fb.status_code == 200, fb.text


def _generate(client: TestClient, headers: dict, week_start: Optional[str] = None, force_regenerate: bool = False):
    body = {}
    if week_start is not None:
        body["week_start"] = week_start
    if force_regenerate:
        body["force_regenerate"] = True
    return client.post("/reflections/weekly/generate", json=body, headers=headers)


# --- Aggregation ---


def test_correct_date_range_excludes_entries_outside_the_week(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref1@example.com")
    _log_mood(client, headers, _d(0), 80)  # inside the week
    _write_journal(client, headers, _d(1))  # a second active day, so the week clears has_sufficient_data
    _log_mood(client, headers, str(WEEK_START - timedelta(days=10)), 10)  # well before the week
    _log_mood(client, headers, str(WEEK_END + timedelta(days=10)), 10)  # well after the week

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200, response.text

    summary = ai_provider.calls[-1]
    assert summary.mood_entry_count == 1
    assert summary.mood_average == 80.0


def test_mood_statistics_average_min_max(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref2@example.com")
    _log_mood(client, headers, _d(0), 20)
    _log_mood(client, headers, _d(1), 60)
    _log_mood(client, headers, _d(2), 100)
    _write_journal(client, headers, _d(3))  # bump active_days so this week is "sufficient" on its own terms

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200

    summary = ai_provider.calls[-1]
    assert summary.mood_entry_count == 3
    assert summary.mood_average == 60.0
    assert summary.mood_min == 20
    assert summary.mood_max == 100


def test_mood_trend_improving(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref3@example.com")
    _log_mood(client, headers, _d(0), 10)  # first half (Mon-Wed)
    _log_mood(client, headers, _d(5), 90)  # second half (Fri-Sun)

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200
    assert ai_provider.calls[-1].mood_trend == "improving"


def test_mood_trend_declining(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref4@example.com")
    _log_mood(client, headers, _d(0), 90)
    _log_mood(client, headers, _d(5), 10)

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200
    assert ai_provider.calls[-1].mood_trend == "declining"


def test_mood_trend_insufficient_data_when_only_one_half_has_entries(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref5@example.com")
    _log_mood(client, headers, _d(0), 50)
    _write_journal(client, headers, _d(1))  # sufficient overall, but still only one mood half

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200
    assert ai_provider.calls[-1].mood_trend == "insufficient_data"


def test_checklist_completion_rate_and_days_tracked(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref6@example.com")
    _toggle_checklist(client, headers, _d(0), completed=True)
    _toggle_checklist(client, headers, _d(1), completed=False)

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200

    summary = ai_provider.calls[-1]
    assert summary.checklist_days_tracked == 2
    assert summary.checklist_completion_rate is not None
    assert 0 <= summary.checklist_completion_rate <= 1


def test_journal_and_shoutout_counts(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref7@example.com")
    _write_journal(client, headers, _d(0))
    _write_journal(client, headers, _d(1))
    _write_shoutout(client, headers, _d(2), felt_better=True)
    _write_shoutout(client, headers, _d(3), felt_better=False)
    _write_shoutout(client, headers, _d(4))  # never answered

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200

    summary = ai_provider.calls[-1]
    assert summary.journal_entry_count == 2
    assert summary.shoutout_count == 3
    assert summary.shoutout_positive_feel_better_count == 1


def test_journal_and_shoutout_content_never_reaches_the_summary_or_response(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref8@example.com")
    secret_journal = "a very private journal thought"
    secret_shoutout = "a very private shoutout vent"
    _write_journal(client, headers, _d(0), content=secret_journal)
    _write_shoutout(client, headers, _d(1), content=secret_shoutout)

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200
    assert secret_journal not in response.text
    assert secret_shoutout not in response.text

    summary = ai_provider.calls[-1]
    assert secret_journal not in summary.model_dump_json()
    assert secret_shoutout not in summary.model_dump_json()
    # Structural guarantee, not just "didn't happen to appear this time":
    # WeeklySummary has no field capable of holding entry text at all.
    assert "content" not in type(summary).model_fields
    assert "title" not in type(summary).model_fields


def test_stress_trend_present_when_data_spans_the_boundary(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref9@example.com")
    # Data before the week (feeds stress_score_start's trailing window)
    # and within the week (feeds stress_score_end's).
    for offset in range(1, 8):
        _log_mood(client, headers, str(WEEK_START - timedelta(days=offset)), 20)
    for offset in range(7):
        _log_mood(client, headers, _d(offset), 90)

    response = _generate(client, headers, week_start=str(WEEK_START))
    assert response.status_code == 200

    summary = ai_provider.calls[-1]
    assert summary.stress_score_start is not None
    assert summary.stress_score_end is not None
    assert summary.stress_trend in ("improving", "worsening", "stable")


def test_multiple_weeks_are_independent(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref10@example.com")
    week2_start = WEEK_START + timedelta(days=7)
    _log_mood(client, headers, _d(0), 30)
    _write_journal(client, headers, _d(1))
    _log_mood(client, headers, str(week2_start), 90)
    _write_journal(client, headers, str(week2_start + timedelta(days=1)))

    r1 = _generate(client, headers, week_start=str(WEEK_START))
    r2 = _generate(client, headers, week_start=str(week2_start))
    assert r1.status_code == 200 and r2.status_code == 200
    assert r1.json()["week_start"] != r2.json()["week_start"]

    week1_summary, week2_summary = ai_provider.calls[0], ai_provider.calls[1]
    assert week1_summary.mood_average == 30.0
    assert week2_summary.mood_average == 90.0


def test_aggregation_does_not_mix_two_users_data(client: TestClient, ai_provider):
    headers_a = register_and_get_headers(client, "ref11a@example.com")
    headers_b = register_and_get_headers(client, "ref11b@example.com")
    _log_mood(client, headers_a, _d(0), 10)
    _write_journal(client, headers_a, _d(1))
    _log_mood(client, headers_b, _d(0), 90)
    _write_journal(client, headers_b, _d(1))

    _generate(client, headers_a, week_start=str(WEEK_START))
    _generate(client, headers_b, week_start=str(WEEK_START))

    summary_a, summary_b = ai_provider.calls[0], ai_provider.calls[1]
    assert summary_a.mood_average == 10.0
    assert summary_b.mood_average == 90.0


# --- AI provider / insufficient data ---


def test_insufficient_data_never_calls_the_provider(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref12@example.com")
    _log_mood(client, headers, _d(0), 50)  # exactly one active day — below the minimum

    response = _generate(client, headers, week_start=str(WEEK_START))

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "insufficient_data"
    assert body["reflection"] is None
    assert body["insufficient_data_reason"] is not None
    assert ai_provider.calls == []


def test_zero_activity_week_is_insufficient_data(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref13@example.com")

    response = _generate(client, headers, week_start=str(WEEK_START))

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "insufficient_data"
    assert "No activity" in body["insufficient_data_reason"]
    assert ai_provider.calls == []


def test_successful_generation_returns_full_structured_reflection(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref14@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))

    response = _generate(client, headers, week_start=str(WEEK_START))

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "completed"
    assert body["insufficient_data_reason"] is None
    reflection = body["reflection"]
    for field in ("summary", "mood_insight", "habit_insight", "positive_highlights", "areas_to_reflect_on", "encouragement"):
        assert field in reflection
    assert body["ai_provider"] == "mock"
    assert body["ai_model"] == "mock-v1"
    assert body["generated_at"] is not None


def test_provider_timeout_returns_502(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref15@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))
    ai_provider.next_error = AIProviderTimeoutError("simulated timeout")

    response = _generate(client, headers, week_start=str(WEEK_START))

    assert response.status_code == 502


def test_provider_malformed_response_returns_502(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref16@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))
    ai_provider.next_error = AIProviderResponseError("simulated malformed output")

    response = _generate(client, headers, week_start=str(WEEK_START))

    assert response.status_code == 502


def test_provider_generic_error_returns_502(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref17@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))
    ai_provider.next_error = AIProviderError("simulated provider outage")

    response = _generate(client, headers, week_start=str(WEEK_START))

    assert response.status_code == 502


def test_failed_generation_does_not_persist_anything(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref18@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))
    ai_provider.next_error = AIProviderError("simulated outage")

    failed = _generate(client, headers, week_start=str(WEEK_START))
    assert failed.status_code == 502

    # Nothing was written — GET for that week 404s, exactly as if
    # generation had never been attempted at all.
    lookup = client.get(f"/reflections/weekly/{WEEK_START}", headers=headers)
    assert lookup.status_code == 404


def test_failed_regeneration_leaves_previous_completed_reflection_untouched(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref19@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))

    first = _generate(client, headers, week_start=str(WEEK_START))
    assert first.status_code == 200
    original_summary_text = first.json()["reflection"]["summary"]

    ai_provider.next_error = AIProviderError("simulated outage during regenerate")
    second = _generate(client, headers, week_start=str(WEEK_START), force_regenerate=True)
    assert second.status_code == 502

    lookup = client.get(f"/reflections/weekly/{WEEK_START}", headers=headers)
    assert lookup.status_code == 200
    assert lookup.json()["status"] == "completed"
    assert lookup.json()["reflection"]["summary"] == original_summary_text


# --- Reflection service: caching / regeneration / duplicates ---


def test_generate_twice_returns_cached_result_without_calling_provider_again(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref20@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))

    first = _generate(client, headers, week_start=str(WEEK_START))
    second = _generate(client, headers, week_start=str(WEEK_START))

    assert first.status_code == 200 and second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert len(ai_provider.calls) == 1


def test_force_regenerate_calls_the_provider_again(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref21@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))

    _generate(client, headers, week_start=str(WEEK_START))
    second = _generate(client, headers, week_start=str(WEEK_START), force_regenerate=True)

    assert second.status_code == 200
    assert len(ai_provider.calls) == 2


def test_duplicate_generate_calls_never_create_a_second_row(client: TestClient, ai_provider, db_session):
    from sqlalchemy import select

    from app.models.reflection import WeeklyReflection

    headers = register_and_get_headers(client, "ref22@example.com")
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))

    _generate(client, headers, week_start=str(WEEK_START))
    _generate(client, headers, week_start=str(WEEK_START))
    _generate(client, headers, week_start=str(WEEK_START), force_regenerate=True)

    rows = db_session.execute(select(WeeklyReflection)).scalars().all()
    assert len(rows) == 1


def test_insufficient_data_result_is_also_cached(client: TestClient, ai_provider):
    headers = register_and_get_headers(client, "ref23@example.com")
    _log_mood(client, headers, _d(0), 50)  # one active day only

    first = _generate(client, headers, week_start=str(WEEK_START))
    second = _generate(client, headers, week_start=str(WEEK_START))

    assert first.status_code == 200 and second.status_code == 200
    assert first.json()["status"] == second.json()["status"] == "insufficient_data"
    assert ai_provider.calls == []  # never called, on either attempt


# --- API: auth, ownership, validation ---


def test_generate_requires_authentication(client: TestClient):
    assert _generate(client, headers={}, week_start=str(WEEK_START)).status_code in (401, 403)


def test_get_latest_requires_authentication(client: TestClient):
    assert client.get("/reflections/weekly").status_code in (401, 403)


def test_get_week_requires_authentication(client: TestClient):
    assert client.get(f"/reflections/weekly/{WEEK_START}").status_code in (401, 403)


def test_get_latest_returns_404_when_nothing_generated_yet(client: TestClient):
    headers = register_and_get_headers(client, "ref24@example.com")
    response = client.get("/reflections/weekly", headers=headers)
    assert response.status_code == 404


def test_get_week_returns_404_for_a_week_never_generated(client: TestClient):
    headers = register_and_get_headers(client, "ref25@example.com")
    response = client.get(f"/reflections/weekly/{WEEK_START}", headers=headers)
    assert response.status_code == 404


def test_user_cannot_retrieve_another_users_reflection(client: TestClient):
    headers_a = register_and_get_headers(client, "ref26a@example.com")
    headers_b = register_and_get_headers(client, "ref26b@example.com")
    _log_mood(client, headers_a, _d(0), 60)
    _write_journal(client, headers_a, _d(1))
    _generate(client, headers_a, week_start=str(WEEK_START))

    response = client.get(f"/reflections/weekly/{WEEK_START}", headers=headers_b)
    assert response.status_code == 404

    latest = client.get("/reflections/weekly", headers=headers_b)
    assert latest.status_code == 404


def test_get_latest_returns_the_most_recent_week(client: TestClient):
    headers = register_and_get_headers(client, "ref27@example.com")
    week2_start = WEEK_START + timedelta(days=7)
    _log_mood(client, headers, _d(0), 60)
    _write_journal(client, headers, _d(1))
    _log_mood(client, headers, str(week2_start), 60)
    _write_journal(client, headers, str(week2_start + timedelta(days=1)))

    _generate(client, headers, week_start=str(WEEK_START))
    _generate(client, headers, week_start=str(week2_start))

    latest = client.get("/reflections/weekly", headers=headers)
    assert latest.status_code == 200
    assert latest.json()["week_start"] == str(week2_start)


def test_generate_rejects_non_monday_week_start(client: TestClient):
    headers = register_and_get_headers(client, "ref28@example.com")
    non_monday = str(WEEK_START + timedelta(days=1))  # a Tuesday
    response = _generate(client, headers, week_start=non_monday)
    assert response.status_code == 400


def test_generate_rejects_a_week_that_is_not_yet_complete(client: TestClient):
    headers = register_and_get_headers(client, "ref29@example.com")
    today = date.today()
    this_monday = str(today - timedelta(days=today.weekday()))
    response = _generate(client, headers, week_start=this_monday)
    assert response.status_code == 400


def test_generate_defaults_to_the_most_recently_completed_week(client: TestClient):
    headers = register_and_get_headers(client, "ref30@example.com")
    today = date.today()
    this_monday = today - timedelta(days=today.weekday())
    expected_week_start = this_monday - timedelta(days=7)

    response = _generate(client, headers)  # no week_start given

    assert response.status_code == 200
    assert response.json()["week_start"] == str(expected_week_start)


def test_invalid_week_start_path_param_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "ref31@example.com")
    response = client.get("/reflections/weekly/not-a-date", headers=headers)
    assert response.status_code == 422


# --- AI output schema validation (no DB, no HTTP) ---


def test_ai_reflection_output_rejects_oversized_summary():
    import pytest as _pytest
    from pydantic import ValidationError

    from app.schemas.reflection import AIReflectionOutput

    with _pytest.raises(ValidationError):
        AIReflectionOutput(
            summary="x" * 10_000,
            mood_insight="fine",
            habit_insight="fine",
            positive_highlights=[],
            areas_to_reflect_on=[],
            encouragement="fine",
        )


def test_ai_reflection_output_rejects_too_many_highlights():
    import pytest as _pytest
    from pydantic import ValidationError

    from app.schemas.reflection import AIReflectionOutput

    with _pytest.raises(ValidationError):
        AIReflectionOutput(
            summary="fine",
            mood_insight="fine",
            habit_insight="fine",
            positive_highlights=["a"] * 50,
            areas_to_reflect_on=[],
            encouragement="fine",
        )
