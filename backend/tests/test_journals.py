import uuid

from fastapi.testclient import TestClient

from tests.conftest import register_and_get_headers


def _create(client: TestClient, headers: dict, entry_date: str, title: str = "Title", content: str = "Content"):
    return client.post("/journals", json={"entry_date": entry_date, "title": title, "content": content}, headers=headers)


def test_create_journal(client: TestClient):
    headers = register_and_get_headers(client, "j1@example.com")

    response = _create(client, headers, "2025-01-05", title="A good day", content="Went for a walk.")

    assert response.status_code == 201
    body = response.json()
    assert body["entry_date"] == "2025-01-05"
    assert body["title"] == "A good day"
    assert body["content"] == "Went for a walk."
    assert body["user_id"]
    assert "id" in body


def test_cannot_create_two_journals_on_the_same_date(client: TestClient):
    headers = register_and_get_headers(client, "j2@example.com")
    _create(client, headers, "2025-01-05")

    response = _create(client, headers, "2025-01-05")

    assert response.status_code == 409


def test_two_different_users_can_each_have_an_entry_on_the_same_date(client: TestClient):
    headers_a = register_and_get_headers(client, "j3a@example.com")
    headers_b = register_and_get_headers(client, "j3b@example.com")

    assert _create(client, headers_a, "2025-01-05").status_code == 201
    assert _create(client, headers_b, "2025-01-05").status_code == 201


def test_list_own_journals(client: TestClient):
    headers = register_and_get_headers(client, "j4@example.com")
    _create(client, headers, "2025-01-01")
    _create(client, headers, "2025-01-02")
    _create(client, headers, "2025-01-03")

    response = client.get("/journals", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert len(body["items"]) == 3
    # newest first
    assert body["items"][0]["entry_date"] == "2025-01-03"


def test_list_does_not_include_another_users_journals(client: TestClient):
    headers_a = register_and_get_headers(client, "j5a@example.com")
    headers_b = register_and_get_headers(client, "j5b@example.com")
    _create(client, headers_a, "2025-01-01")
    _create(client, headers_b, "2025-01-01")
    _create(client, headers_b, "2025-01-02")

    response = client.get("/journals", headers=headers_a)

    assert response.status_code == 200
    assert response.json()["total"] == 1


def test_date_filtering(client: TestClient):
    headers = register_and_get_headers(client, "j6@example.com")
    _create(client, headers, "2025-01-01")
    _create(client, headers, "2025-01-10")
    _create(client, headers, "2025-01-20")

    response = client.get("/journals", params={"start_date": "2025-01-05", "end_date": "2025-01-15"}, headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["entry_date"] == "2025-01-10"


def test_pagination(client: TestClient):
    headers = register_and_get_headers(client, "j7@example.com")
    for day in range(1, 6):
        _create(client, headers, f"2025-01-{day:02d}")

    page1 = client.get("/journals", params={"limit": 2, "offset": 0}, headers=headers)
    page2 = client.get("/journals", params={"limit": 2, "offset": 2}, headers=headers)

    assert page1.json()["total"] == 5
    assert len(page1.json()["items"]) == 2
    assert len(page2.json()["items"]) == 2
    assert page1.json()["items"] != page2.json()["items"]


def test_retrieve_own_journal(client: TestClient):
    headers = register_and_get_headers(client, "j8@example.com")
    created = _create(client, headers, "2025-01-05").json()

    response = client.get(f"/journals/{created['id']}", headers=headers)

    assert response.status_code == 200
    assert response.json()["id"] == created["id"]


def test_update_own_journal(client: TestClient):
    headers = register_and_get_headers(client, "j9@example.com")
    created = _create(client, headers, "2025-01-05", title="Old title").json()

    response = client.patch(f"/journals/{created['id']}", json={"title": "New title"}, headers=headers)

    assert response.status_code == 200
    assert response.json()["title"] == "New title"
    assert response.json()["content"] == "Content"  # untouched


def test_update_journal_to_a_date_already_taken_is_rejected(client: TestClient):
    headers = register_and_get_headers(client, "j10@example.com")
    _create(client, headers, "2025-01-01")
    second = _create(client, headers, "2025-01-02").json()

    response = client.patch(f"/journals/{second['id']}", json={"entry_date": "2025-01-01"}, headers=headers)

    assert response.status_code == 409


def test_delete_own_journal(client: TestClient):
    headers = register_and_get_headers(client, "j11@example.com")
    created = _create(client, headers, "2025-01-05").json()

    delete_response = client.delete(f"/journals/{created['id']}", headers=headers)
    assert delete_response.status_code == 204

    get_response = client.get(f"/journals/{created['id']}", headers=headers)
    assert get_response.status_code == 404


def test_unauthenticated_access_is_rejected(client: TestClient):
    assert client.get("/journals").status_code == 401
    assert client.post("/journals", json={"entry_date": "2025-01-01"}).status_code == 401


def test_user_cannot_access_another_users_journal(client: TestClient):
    owner_headers = register_and_get_headers(client, "j12owner@example.com")
    other_headers = register_and_get_headers(client, "j12other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    response = client.get(f"/journals/{created['id']}", headers=other_headers)

    assert response.status_code == 404  # not 403 — existence is not revealed


def test_user_cannot_modify_another_users_journal(client: TestClient):
    owner_headers = register_and_get_headers(client, "j13owner@example.com")
    other_headers = register_and_get_headers(client, "j13other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    response = client.patch(f"/journals/{created['id']}", json={"title": "Hijacked"}, headers=other_headers)

    assert response.status_code == 404
    # and the owner's data is provably untouched
    still_owned = client.get(f"/journals/{created['id']}", headers=owner_headers)
    assert still_owned.json()["title"] != "Hijacked"


def test_user_cannot_delete_another_users_journal(client: TestClient):
    owner_headers = register_and_get_headers(client, "j14owner@example.com")
    other_headers = register_and_get_headers(client, "j14other@example.com")
    created = _create(client, owner_headers, "2025-01-05").json()

    response = client.delete(f"/journals/{created['id']}", headers=other_headers)

    assert response.status_code == 404
    still_there = client.get(f"/journals/{created['id']}", headers=owner_headers)
    assert still_there.status_code == 200


def test_invalid_uuid_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "j15@example.com")
    response = client.get("/journals/not-a-uuid", headers=headers)
    assert response.status_code == 422


def test_unknown_but_well_formed_uuid_returns_404(client: TestClient):
    headers = register_and_get_headers(client, "j16@example.com")
    response = client.get(f"/journals/{uuid.uuid4()}", headers=headers)
    assert response.status_code == 404


def test_invalid_payload_missing_entry_date_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "j17@example.com")
    response = client.post("/journals", json={"title": "No date"}, headers=headers)
    assert response.status_code == 422
