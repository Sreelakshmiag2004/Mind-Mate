"""
Phase 4: the deterministic, rule-based stress indicator. See
app/services/stress_service.py for the algorithm under test here.
"""

from datetime import date, timedelta

from fastapi.testclient import TestClient

from tests.conftest import register_and_get_headers


def _log_mood(client: TestClient, headers: dict, entry_date: str, value: int):
    response = client.post("/moods", json={"entry_date": entry_date, "mood_value": value}, headers=headers)
    assert response.status_code == 201, response.text


def _complete_all_checklist_items(client: TestClient, headers: dict, entry_date: str, completed: bool = True):
    items = client.get("/checklists/items", headers=headers)
    assert items.status_code == 200
    completions = [{"item_id": item["id"], "completed": completed} for item in items.json()]
    response = client.patch(f"/checklists/{entry_date}", json={"completions": completions}, headers=headers)
    assert response.status_code == 200, response.text


def test_own_stress_endpoint_insufficient_data_for_new_user(client: TestClient):
    headers = register_and_get_headers(client, "st1@example.com")

    response = client.get("/stress/today", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["score"] is None
    assert body["level"] == "insufficient_data"
    assert body["confidence"] == "none"
    assert body["contributors"]["mood_average"] is None
    assert body["contributors"]["checklist_completion_rate"] is None
    assert "not a medical" in body["disclaimer"].lower()


def test_deterministic_calculation(client: TestClient):
    headers = register_and_get_headers(client, "st2@example.com")
    _log_mood(client, headers, "2025-06-10", 40)

    first = client.get("/stress/today", headers=headers).json()
    second = client.get("/stress/today", headers=headers).json()

    assert first["score"] == second["score"]
    assert first["level"] == second["level"]


def test_bounded_score_at_extremes(client: TestClient):
    headers = register_and_get_headers(client, "st3@example.com")
    today = date.today()
    for offset in range(4):
        _log_mood(client, headers, str(today - timedelta(days=offset)), 0)
        _complete_all_checklist_items(client, headers, str(today - timedelta(days=offset)), completed=False)

    body = client.get("/stress/today", headers=headers).json()

    assert body["score"] is not None
    assert 0 <= body["score"] <= 100

    headers2 = register_and_get_headers(client, "st3b@example.com")
    for offset in range(4):
        _log_mood(client, headers2, str(today - timedelta(days=offset)), 100)
        _complete_all_checklist_items(client, headers2, str(today - timedelta(days=offset)), completed=True)

    body2 = client.get("/stress/today", headers=headers2).json()
    assert 0 <= body2["score"] <= 100
    assert body2["score"] < body["score"]  # happy, fully-completed days score lower stress than the opposite


def test_mood_contribution(client: TestClient):
    headers = register_and_get_headers(client, "st4@example.com")
    today = date.today()
    _log_mood(client, headers, str(today), 20)
    _log_mood(client, headers, str(today - timedelta(days=1)), 40)

    body = client.get("/stress/today", headers=headers).json()

    assert body["contributors"]["mood_average"] == 30.0
    # Mood-only signal (no checklist data at all): score == 100 - avg mood.
    assert body["score"] == 70
    assert body["level"] == "elevated"


def test_checklist_contribution(client: TestClient):
    headers = register_and_get_headers(client, "st5@example.com")
    today = str(date.today())
    _complete_all_checklist_items(client, headers, today, completed=True)

    body = client.get("/stress/today", headers=headers).json()

    assert body["contributors"]["checklist_completion_rate"] is not None
    assert body["contributors"]["mood_average"] is None
    # Checklist-only signal: fully completed today lowers stress (but the
    # window is 7 days and only 1 day has data, so the rate is well below 1.0).
    assert 0 <= body["contributors"]["checklist_completion_rate"] <= 1


def test_checklist_completion_lowers_score_vs_no_completion(client: TestClient):
    today = str(date.today())

    completed_headers = register_and_get_headers(client, "st6-completed@example.com")
    _complete_all_checklist_items(client, completed_headers, today, completed=True)

    uncompleted_headers = register_and_get_headers(client, "st6-uncompleted@example.com")
    _complete_all_checklist_items(client, uncompleted_headers, today, completed=False)

    completed_score = client.get("/stress/today", headers=completed_headers).json()["score"]
    uncompleted_score = client.get("/stress/today", headers=uncompleted_headers).json()["score"]

    assert completed_score < uncompleted_score


def test_date_window_correctness_excludes_old_entries(client: TestClient):
    headers = register_and_get_headers(client, "st7@example.com")
    today = date.today()
    # Well outside the 7-day trailing window.
    _log_mood(client, headers, str(today - timedelta(days=30)), 0)

    body = client.get("/stress/today", headers=headers).json()

    assert body["score"] is None
    assert body["level"] == "insufficient_data"
    assert body["data_window_start"] == str(today - timedelta(days=6))
    assert body["data_window_end"] == str(today)


def test_date_window_includes_entry_at_window_boundary(client: TestClient):
    headers = register_and_get_headers(client, "st8@example.com")
    today = date.today()
    _log_mood(client, headers, str(today - timedelta(days=6)), 50)  # exactly the oldest in-window day

    body = client.get("/stress/today", headers=headers).json()

    assert body["contributors"]["mood_average"] == 50.0


def test_history_endpoint_bounded_and_ordered(client: TestClient):
    headers = register_and_get_headers(client, "st9@example.com")
    today = date.today()
    _log_mood(client, headers, str(today), 10)

    response = client.get("/stress/history?days=3", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert len(body) == 3
    assert body[0]["data_window_end"] == str(today)
    assert body[1]["data_window_end"] == str(today - timedelta(days=1))
    assert body[2]["data_window_end"] == str(today - timedelta(days=2))


def test_history_days_out_of_range_rejected(client: TestClient):
    headers = register_and_get_headers(client, "st10@example.com")

    too_many = client.get("/stress/history?days=91", headers=headers)
    assert too_many.status_code == 422

    zero = client.get("/stress/history?days=0", headers=headers)
    assert zero.status_code == 422


def test_stress_endpoints_require_authentication(client: TestClient):
    assert client.get("/stress/today").status_code in (401, 403)
    assert client.get("/stress/history").status_code in (401, 403)


def test_stress_never_exposes_journal_or_shoutout_content(client: TestClient):
    headers = register_and_get_headers(client, "st11@example.com")
    secret = "very private journal text"
    client.post("/journals", json={"entry_date": str(date.today()), "content": secret}, headers=headers)
    _log_mood(client, headers, str(date.today()), 50)

    response = client.get("/stress/today", headers=headers)

    assert secret not in response.text
