from fastapi.testclient import TestClient

from tests.conftest import register_and_get_headers


def _put(client: TestClient, headers: dict, entry_date: str, rows: list):
    return client.put(f"/scheduler/{entry_date}", json={"rows": rows}, headers=headers)


def _get(client: TestClient, headers: dict, entry_date: str):
    return client.get(f"/scheduler/{entry_date}", headers=headers)


# --- Authentication ---


def test_unauthenticated_get_is_rejected(client: TestClient):
    assert _get(client, {}, "2025-01-05").status_code == 401


def test_unauthenticated_put_is_rejected(client: TestClient):
    response = client.put("/scheduler/2025-01-05", json={"rows": []})
    assert response.status_code == 401


# --- GET ---


def test_get_with_no_schedule_returns_empty_items(client: TestClient):
    headers = register_and_get_headers(client, "s1@example.com")

    response = _get(client, headers, "2025-01-05")

    assert response.status_code == 200
    body = response.json()
    assert body["entry_date"] == "2025-01-05"
    assert body["items"] == []


def test_get_returns_a_previously_saved_schedule(client: TestClient):
    headers = register_and_get_headers(client, "s2@example.com")
    _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Gym"}])

    response = _get(client, headers, "2025-01-05")

    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["scheduled_time"] == "09:00"
    assert body["items"][0]["description"] == "Gym"
    assert "id" in body["items"][0]


def test_get_orders_items_chronologically_by_time(client: TestClient):
    headers = register_and_get_headers(client, "s3@example.com")
    _put(
        client,
        headers,
        "2025-01-05",
        [
            {"scheduled_time": "18:30", "description": "Dinner"},
            {"scheduled_time": "07:00", "description": "Wake up"},
            {"scheduled_time": "12:00", "description": "Lunch"},
        ],
    )

    response = _get(client, headers, "2025-01-05")

    times = [item["scheduled_time"] for item in response.json()["items"]]
    assert times == ["07:00", "12:00", "18:30"]


def test_different_dates_are_independent(client: TestClient):
    headers = register_and_get_headers(client, "s4@example.com")
    _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Gym"}])

    other_day = _get(client, headers, "2025-01-06")

    assert other_day.json()["items"] == []


def test_different_users_are_isolated(client: TestClient):
    headers_a = register_and_get_headers(client, "s5a@example.com")
    headers_b = register_and_get_headers(client, "s5b@example.com")
    _put(client, headers_a, "2025-01-05", [{"scheduled_time": "09:00", "description": "A's gym"}])

    response_b = _get(client, headers_b, "2025-01-05")

    assert response_b.json()["items"] == []


def test_malformed_date_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s6@example.com")

    response = _get(client, headers, "not-a-date")

    assert response.status_code == 422


# --- PUT: create / replace / add / remove / clear ---


def test_put_creates_a_schedule(client: TestClient):
    headers = register_and_get_headers(client, "s7@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Gym"}])

    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["description"] == "Gym"


def test_put_replaces_an_existing_schedule_entirely(client: TestClient):
    headers = register_and_get_headers(client, "s8@example.com")
    _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Gym"}])

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Yoga"}])

    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["description"] == "Yoga"


def test_put_can_add_entries_to_an_existing_schedule(client: TestClient):
    headers = register_and_get_headers(client, "s9@example.com")
    _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Gym"}])

    response = _put(
        client,
        headers,
        "2025-01-05",
        [
            {"scheduled_time": "09:00", "description": "Gym"},
            {"scheduled_time": "14:00", "description": "Study"},
        ],
    )

    assert response.status_code == 200
    assert len(response.json()["items"]) == 2


def test_put_removes_entries_by_omission(client: TestClient):
    headers = register_and_get_headers(client, "s10@example.com")
    _put(
        client,
        headers,
        "2025-01-05",
        [
            {"scheduled_time": "09:00", "description": "Gym"},
            {"scheduled_time": "14:00", "description": "Study"},
        ],
    )

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Gym"}])

    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["scheduled_time"] == "09:00"


def test_put_with_empty_rows_clears_the_day(client: TestClient):
    headers = register_and_get_headers(client, "s11@example.com")
    _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Gym"}])

    response = _put(client, headers, "2025-01-05", [])

    assert response.status_code == 200
    assert response.json()["items"] == []
    # And a subsequent GET confirms the day is actually empty, not just the PUT response.
    assert _get(client, headers, "2025-01-05").json()["items"] == []


def test_put_accepts_multiple_entries_in_one_request(client: TestClient):
    headers = register_and_get_headers(client, "s12@example.com")

    response = _put(
        client,
        headers,
        "2025-01-05",
        [
            {"scheduled_time": "07:00", "description": "Wake up"},
            {"scheduled_time": "09:00", "description": "Gym"},
            {"scheduled_time": "12:00", "description": "Lunch"},
        ],
    )

    assert response.status_code == 200
    assert len(response.json()["items"]) == 3


def test_put_accepts_null_description(client: TestClient):
    headers = register_and_get_headers(client, "s13@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": None}])

    assert response.status_code == 200
    assert response.json()["items"][0]["description"] is None


def test_put_accepts_empty_string_description_distinct_from_null(client: TestClient):
    headers = register_and_get_headers(client, "s14@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": ""}])

    assert response.status_code == 200
    assert response.json()["items"][0]["description"] == ""


def test_put_accepts_omitted_description_defaulting_to_null(client: TestClient):
    headers = register_and_get_headers(client, "s15@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00"}])

    assert response.status_code == 200
    assert response.json()["items"][0]["description"] is None


def test_put_replace_does_not_affect_other_dates(client: TestClient):
    headers = register_and_get_headers(client, "s16@example.com")
    _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00", "description": "Day 1"}])
    _put(client, headers, "2025-01-06", [{"scheduled_time": "09:00", "description": "Day 2"}])

    _put(client, headers, "2025-01-05", [])

    assert _get(client, headers, "2025-01-05").json()["items"] == []
    day2 = _get(client, headers, "2025-01-06").json()["items"]
    assert len(day2) == 1
    assert day2[0]["description"] == "Day 2"


# --- Validation ---


def test_invalid_time_format_missing_leading_zero_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s17@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "9:00", "description": "Gym"}])

    assert response.status_code == 422


def test_invalid_time_format_with_seconds_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s18@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:00:00", "description": "Gym"}])

    assert response.status_code == 422


def test_out_of_range_hour_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s19@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "24:00", "description": "Gym"}])

    assert response.status_code == 422


def test_out_of_range_minute_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s20@example.com")

    response = _put(client, headers, "2025-01-05", [{"scheduled_time": "09:60", "description": "Gym"}])

    assert response.status_code == 422


def test_malformed_date_on_put_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s21@example.com")

    response = _put(client, headers, "not-a-date", [{"scheduled_time": "09:00", "description": "Gym"}])

    assert response.status_code == 422


def test_duplicate_times_in_the_same_request_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s22@example.com")

    response = _put(
        client,
        headers,
        "2025-01-05",
        [
            {"scheduled_time": "09:00", "description": "Gym"},
            {"scheduled_time": "09:00", "description": "Study"},
        ],
    )

    assert response.status_code == 422


def test_duplicate_times_request_does_not_write_anything(client: TestClient):
    """A rejected duplicate-time PUT must not partially apply — the day stays exactly as it was."""
    headers = register_and_get_headers(client, "s23@example.com")
    _put(client, headers, "2025-01-05", [{"scheduled_time": "07:00", "description": "Original"}])

    rejected = _put(
        client,
        headers,
        "2025-01-05",
        [
            {"scheduled_time": "09:00", "description": "Gym"},
            {"scheduled_time": "09:00", "description": "Study"},
        ],
    )
    assert rejected.status_code == 422

    still_there = _get(client, headers, "2025-01-05").json()["items"]
    assert len(still_there) == 1
    assert still_there[0]["description"] == "Original"


def test_no_user_id_accepted_from_client(client: TestClient):
    """A client-supplied user_id in the body must be silently ignored, never used as the owner."""
    headers = register_and_get_headers(client, "s24@example.com")

    response = client.put(
        "/scheduler/2025-01-05",
        json={
            "rows": [{"scheduled_time": "09:00", "description": "Gym"}],
            "user_id": "00000000-0000-0000-0000-000000000000",
        },
        headers=headers,
    )

    assert response.status_code == 200
    # The entry is owned by the authenticated user (visible via their own
    # GET), not the spoofed id — there is no route to look it up by the
    # spoofed user_id at all, which is itself the proof it was ignored.
    assert len(_get(client, headers, "2025-01-05").json()["items"]) == 1


def test_database_unique_constraint_rejects_a_direct_duplicate_insert(client: TestClient, db_session):
    """
    The schema/service-layer duplicate check is bypassed here on purpose,
    exercising the database's own UNIQUE(user_id, entry_date,
    scheduled_time) constraint directly — the "final protection against
    races" the product decision calls for. Confirms the constraint exists
    and is enforced independently of the application-level check.

    Registers the user through the real API (rather than constructing a
    `User` row by hand) so this test can't silently drift from the actual
    `users` schema, then looks that same row up on `db_session` to attach
    `SchedulerEntry` rows directly.
    """
    from datetime import date

    from sqlalchemy.exc import IntegrityError

    from app.repositories import user_repository
    from app.models.scheduler import SchedulerEntry

    register_and_get_headers(client, "s25@example.com")
    user = user_repository.get_by_email(db_session, "s25@example.com")
    assert user is not None

    db_session.add(
        SchedulerEntry(user_id=user.id, entry_date=date(2025, 1, 5), scheduled_time="09:00", description="First")
    )
    db_session.commit()

    db_session.add(
        SchedulerEntry(user_id=user.id, entry_date=date(2025, 1, 5), scheduled_time="09:00", description="Second")
    )
    try:
        db_session.commit()
        raised = False
    except IntegrityError:
        db_session.rollback()
        raised = True

    assert raised, "UNIQUE(user_id, entry_date, scheduled_time) did not reject a direct duplicate insert"


def test_unknown_but_well_formed_date_get_is_not_an_error(client: TestClient):
    headers = register_and_get_headers(client, "s26@example.com")
    response = _get(client, headers, "2099-12-31")
    assert response.status_code == 200
    assert response.json()["items"] == []
