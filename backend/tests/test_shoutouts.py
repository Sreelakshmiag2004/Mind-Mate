import uuid

from fastapi.testclient import TestClient

from tests.conftest import register_and_get_headers


def _create(client: TestClient, headers: dict, entry_date: str, title: str = "Weighing on me", content: str = "A problem."):
    return client.post("/shoutouts", json={"entry_date": entry_date, "title": title, "content": content}, headers=headers)


def test_authenticated_user_can_create_shoutout(client: TestClient):
    headers = register_and_get_headers(client, "s1@example.com")

    response = _create(client, headers, "2025-01-05", title="Work stress", content="Deadline is tomorrow.")

    assert response.status_code == 201
    body = response.json()
    assert body["entry_date"] == "2025-01-05"
    assert body["title"] == "Work stress"
    assert body["felt_better"] is None
    assert body["felt_better_at"] is None


def test_sender_identity_comes_from_jwt_not_the_request_body(client: TestClient):
    """user_id must never be settable by the client — it isn't even a field ShoutoutCreate accepts."""
    headers = register_and_get_headers(client, "s2@example.com")

    response = client.post(
        "/shoutouts",
        json={"entry_date": "2025-01-05", "title": "x", "user_id": str(uuid.uuid4())},
        headers=headers,
    )

    assert response.status_code == 201
    # the extra field is silently ignored; the id returned is the real caller's
    me = client.get("/auth/me", headers=headers).json()
    assert response.json()["user_id"] == me["user"]["id"]


def test_cannot_create_two_shoutouts_on_the_same_date(client: TestClient):
    headers = register_and_get_headers(client, "s3@example.com")
    _create(client, headers, "2025-01-05")

    response = _create(client, headers, "2025-01-05")

    assert response.status_code == 409


def test_list_own_shoutouts(client: TestClient):
    headers = register_and_get_headers(client, "s4@example.com")
    _create(client, headers, "2025-01-01")
    _create(client, headers, "2025-01-02")

    response = client.get("/shoutouts", headers=headers)

    assert response.status_code == 200
    assert response.json()["total"] == 2


def test_list_does_not_include_another_users_shoutouts(client: TestClient):
    headers_a = register_and_get_headers(client, "s5a@example.com")
    headers_b = register_and_get_headers(client, "s5b@example.com")
    _create(client, headers_a, "2025-01-01")
    _create(client, headers_b, "2025-01-01")

    response = client.get("/shoutouts", headers=headers_a)

    assert response.json()["total"] == 1


def test_ordering_is_newest_first(client: TestClient):
    headers = register_and_get_headers(client, "s6@example.com")
    _create(client, headers, "2025-01-01")
    _create(client, headers, "2025-01-15")
    _create(client, headers, "2025-01-08")

    response = client.get("/shoutouts", headers=headers)

    dates = [item["entry_date"] for item in response.json()["items"]]
    assert dates == ["2025-01-15", "2025-01-08", "2025-01-01"]


def test_pagination(client: TestClient):
    headers = register_and_get_headers(client, "s7@example.com")
    for day in range(1, 6):
        _create(client, headers, f"2025-01-{day:02d}")

    page1 = client.get("/shoutouts", params={"limit": 2, "offset": 0}, headers=headers)
    page2 = client.get("/shoutouts", params={"limit": 2, "offset": 2}, headers=headers)

    assert len(page1.json()["items"]) == 2
    assert len(page2.json()["items"]) == 2
    assert page1.json()["items"] != page2.json()["items"]


def test_date_filtering(client: TestClient):
    headers = register_and_get_headers(client, "s8@example.com")
    _create(client, headers, "2025-01-01")
    _create(client, headers, "2025-01-10")
    _create(client, headers, "2025-01-20")

    response = client.get("/shoutouts", params={"start_date": "2025-01-05", "end_date": "2025-01-15"}, headers=headers)

    assert response.json()["total"] == 1
    assert response.json()["items"][0]["entry_date"] == "2025-01-10"


def test_retrieve_authorized_shoutout(client: TestClient):
    headers = register_and_get_headers(client, "s9@example.com")
    created = _create(client, headers, "2025-01-05").json()

    response = client.get(f"/shoutouts/{created['id']}", headers=headers)

    assert response.status_code == 200
    assert response.json()["id"] == created["id"]


def test_unrelated_user_gets_404_on_retrieve(client: TestClient):
    owner_headers = register_and_get_headers(client, "s10owner@example.com")
    other_headers = register_and_get_headers(client, "s10other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    response = client.get(f"/shoutouts/{created['id']}", headers=other_headers)

    assert response.status_code == 404


def test_unauthorized_modification_rejected(client: TestClient):
    owner_headers = register_and_get_headers(client, "s11owner@example.com")
    other_headers = register_and_get_headers(client, "s11other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    response = client.patch(f"/shoutouts/{created['id']}", json={"title": "Hijacked"}, headers=other_headers)

    assert response.status_code == 404
    still_owned = client.get(f"/shoutouts/{created['id']}", headers=owner_headers)
    assert still_owned.json()["title"] != "Hijacked"


def test_unauthorized_deletion_rejected(client: TestClient):
    owner_headers = register_and_get_headers(client, "s12owner@example.com")
    other_headers = register_and_get_headers(client, "s12other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    response = client.delete(f"/shoutouts/{created['id']}", headers=other_headers)

    assert response.status_code == 404
    still_there = client.get(f"/shoutouts/{created['id']}", headers=owner_headers)
    assert still_there.status_code == 200


def test_owner_can_update_and_delete(client: TestClient):
    headers = register_and_get_headers(client, "s13@example.com")
    created = _create(client, headers, "2025-01-05", title="Old").json()

    updated = client.patch(f"/shoutouts/{created['id']}", json={"title": "New"}, headers=headers)
    assert updated.status_code == 200
    assert updated.json()["title"] == "New"

    deleted = client.delete(f"/shoutouts/{created['id']}", headers=headers)
    assert deleted.status_code == 204
    assert client.get(f"/shoutouts/{created['id']}", headers=headers).status_code == 404


def test_unauthenticated_access_is_rejected(client: TestClient):
    assert client.get("/shoutouts").status_code == 401
    assert client.post("/shoutouts", json={"entry_date": "2025-01-01"}).status_code == 401


def test_invalid_uuid_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s14@example.com")
    assert client.get("/shoutouts/not-a-uuid", headers=headers).status_code == 422


def test_missing_entry_date_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "s15@example.com")
    response = client.post("/shoutouts", json={"title": "No date"}, headers=headers)
    assert response.status_code == 422


# --- "Did you feel better?" follow-up ---


def test_feel_better_follow_up_persists(client: TestClient):
    """This is the bug fix: the old app never actually saved this answer."""
    headers = register_and_get_headers(client, "s16@example.com")
    created = _create(client, headers, "2025-01-05").json()

    response = client.post(f"/shoutouts/{created['id']}/feel-better", json={"felt_better": True}, headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["felt_better"] is True
    assert body["felt_better_at"] is not None

    # and it really persisted — a fresh GET (not just the response body) confirms it
    refetched = client.get(f"/shoutouts/{created['id']}", headers=headers)
    assert refetched.json()["felt_better"] is True


def test_feel_better_can_be_answered_no(client: TestClient):
    headers = register_and_get_headers(client, "s17@example.com")
    created = _create(client, headers, "2025-01-05").json()

    response = client.post(f"/shoutouts/{created['id']}/feel-better", json={"felt_better": False}, headers=headers)

    assert response.json()["felt_better"] is False


def test_feel_better_cannot_be_answered_twice(client: TestClient):
    headers = register_and_get_headers(client, "s18@example.com")
    created = _create(client, headers, "2025-01-05").json()
    client.post(f"/shoutouts/{created['id']}/feel-better", json={"felt_better": True}, headers=headers)

    response = client.post(f"/shoutouts/{created['id']}/feel-better", json={"felt_better": False}, headers=headers)

    assert response.status_code == 409


def test_feel_better_on_another_users_shoutout_is_rejected(client: TestClient):
    owner_headers = register_and_get_headers(client, "s19owner@example.com")
    other_headers = register_and_get_headers(client, "s19other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    response = client.post(f"/shoutouts/{created['id']}/feel-better", json={"felt_better": True}, headers=other_headers)

    assert response.status_code == 404


def test_feel_better_requires_authentication(client: TestClient):
    headers = register_and_get_headers(client, "s20@example.com")
    created = _create(client, headers, "2025-01-05").json()

    response = client.post(f"/shoutouts/{created['id']}/feel-better", json={"felt_better": True})

    assert response.status_code == 401
