import uuid

from fastapi.testclient import TestClient

from tests.conftest import register_and_get_headers


def _create(client: TestClient, headers: dict, entry_date: str, mood_value: int = 70):
    return client.post("/moods", json={"entry_date": entry_date, "mood_value": mood_value}, headers=headers)


def test_create_mood(client: TestClient):
    headers = register_and_get_headers(client, "m1@example.com")

    response = _create(client, headers, "2025-01-05", mood_value=85)

    assert response.status_code == 201
    body = response.json()
    assert body["entry_date"] == "2025-01-05"
    assert body["mood_value"] == 85


def test_cannot_create_two_moods_on_the_same_date(client: TestClient):
    headers = register_and_get_headers(client, "m2@example.com")
    _create(client, headers, "2025-01-05")

    response = _create(client, headers, "2025-01-05")

    assert response.status_code == 409


def test_mood_value_above_100_is_rejected(client: TestClient):
    headers = register_and_get_headers(client, "m3@example.com")
    response = _create(client, headers, "2025-01-05", mood_value=101)
    assert response.status_code == 422


def test_mood_value_below_0_is_rejected(client: TestClient):
    headers = register_and_get_headers(client, "m4@example.com")
    response = _create(client, headers, "2025-01-05", mood_value=-1)
    assert response.status_code == 422


def test_mood_value_must_be_an_integer(client: TestClient):
    headers = register_and_get_headers(client, "m5@example.com")
    response = client.post("/moods", json={"entry_date": "2025-01-05", "mood_value": "high"}, headers=headers)
    assert response.status_code == 422


def test_list_own_moods(client: TestClient):
    headers = register_and_get_headers(client, "m6@example.com")
    _create(client, headers, "2025-01-01", 10)
    _create(client, headers, "2025-01-02", 90)

    response = client.get("/moods", headers=headers)

    assert response.status_code == 200
    assert response.json()["total"] == 2


def test_list_does_not_include_another_users_moods(client: TestClient):
    headers_a = register_and_get_headers(client, "m7a@example.com")
    headers_b = register_and_get_headers(client, "m7b@example.com")
    _create(client, headers_a, "2025-01-01")
    _create(client, headers_b, "2025-01-01")

    response = client.get("/moods", headers=headers_a)

    assert response.json()["total"] == 1


def test_date_range_filtering(client: TestClient):
    headers = register_and_get_headers(client, "m8@example.com")
    _create(client, headers, "2025-01-01", 20)
    _create(client, headers, "2025-01-10", 50)
    _create(client, headers, "2025-01-20", 80)

    response = client.get("/moods", params={"start_date": "2025-01-05", "end_date": "2025-01-15"}, headers=headers)

    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["mood_value"] == 50


def test_retrieve_own_mood(client: TestClient):
    headers = register_and_get_headers(client, "m9@example.com")
    created = _create(client, headers, "2025-01-05", 60).json()

    response = client.get(f"/moods/{created['id']}", headers=headers)

    assert response.status_code == 200
    assert response.json()["mood_value"] == 60


def test_update_own_mood(client: TestClient):
    headers = register_and_get_headers(client, "m10@example.com")
    created = _create(client, headers, "2025-01-05", 40).json()

    response = client.patch(f"/moods/{created['id']}", json={"mood_value": 95}, headers=headers)

    assert response.status_code == 200
    assert response.json()["mood_value"] == 95


def test_cross_user_access_is_rejected_for_get_and_patch(client: TestClient):
    owner_headers = register_and_get_headers(client, "m11owner@example.com")
    other_headers = register_and_get_headers(client, "m11other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    assert client.get(f"/moods/{created['id']}", headers=other_headers).status_code == 404
    assert client.patch(f"/moods/{created['id']}", json={"mood_value": 1}, headers=other_headers).status_code == 404


def test_unauthenticated_access_is_rejected(client: TestClient):
    assert client.get("/moods").status_code == 401
    assert client.post("/moods", json={"entry_date": "2025-01-01", "mood_value": 50}).status_code == 401


def test_unknown_mood_id_returns_404(client: TestClient):
    headers = register_and_get_headers(client, "m12@example.com")
    response = client.get(f"/moods/{uuid.uuid4()}", headers=headers)
    assert response.status_code == 404


def test_invalid_uuid_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "m13@example.com")
    response = client.get("/moods/not-a-uuid", headers=headers)
    assert response.status_code == 422
