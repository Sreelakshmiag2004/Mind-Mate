import uuid

from fastapi.testclient import TestClient

from tests.conftest import register_and_get_headers


def test_list_catalog_returns_the_five_fixed_items(client: TestClient):
    headers = register_and_get_headers(client, "c1@example.com")

    response = client.get("/checklists/items", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert len(body) == 5
    assert [item["sort_order"] for item in body] == [0, 1, 2, 3, 4]
    assert "Drank enough water" in body[0]["label"]


def test_get_day_defaults_to_all_incomplete(client: TestClient):
    headers = register_and_get_headers(client, "c2@example.com")

    response = client.get("/checklists/2025-01-05", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["entry_date"] == "2025-01-05"
    assert body["total_count"] == 5
    assert body["completed_count"] == 0
    assert all(item["completed"] is False for item in body["items"])


def test_create_checklist_completion_state(client: TestClient):
    headers = register_and_get_headers(client, "c3@example.com")
    items = client.get("/checklists/items", headers=headers).json()
    first_item_id = items[0]["id"]

    response = client.patch(
        "/checklists/2025-01-05",
        json={"completions": [{"item_id": first_item_id, "completed": True}]},
        headers=headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["completed_count"] == 1
    completed_items = [i for i in body["items"] if i["completed"]]
    assert len(completed_items) == 1
    assert completed_items[0]["item_id"] == first_item_id
    assert completed_items[0]["completed_at"] is not None


def test_update_completion_state_can_toggle_back_off(client: TestClient):
    headers = register_and_get_headers(client, "c4@example.com")
    item_id = client.get("/checklists/items", headers=headers).json()[0]["id"]
    client.patch("/checklists/2025-01-05", json={"completions": [{"item_id": item_id, "completed": True}]}, headers=headers)

    response = client.patch(
        "/checklists/2025-01-05", json={"completions": [{"item_id": item_id, "completed": False}]}, headers=headers
    )

    assert response.status_code == 200
    assert response.json()["completed_count"] == 0


def test_multiple_items_can_be_updated_in_one_request(client: TestClient):
    headers = register_and_get_headers(client, "c5@example.com")
    items = client.get("/checklists/items", headers=headers).json()

    response = client.patch(
        "/checklists/2025-01-05",
        json={"completions": [{"item_id": items[0]["id"], "completed": True}, {"item_id": items[1]["id"], "completed": True}]},
        headers=headers,
    )

    assert response.json()["completed_count"] == 2


def test_retrieve_own_checklist_day(client: TestClient):
    headers = register_and_get_headers(client, "c6@example.com")
    item_id = client.get("/checklists/items", headers=headers).json()[0]["id"]
    client.patch("/checklists/2025-01-05", json={"completions": [{"item_id": item_id, "completed": True}]}, headers=headers)

    response = client.get("/checklists/2025-01-05", headers=headers)

    assert response.status_code == 200
    assert response.json()["completed_count"] == 1


def test_a_different_date_is_independent(client: TestClient):
    headers = register_and_get_headers(client, "c7@example.com")
    item_id = client.get("/checklists/items", headers=headers).json()[0]["id"]
    client.patch("/checklists/2025-01-05", json={"completions": [{"item_id": item_id, "completed": True}]}, headers=headers)

    other_day = client.get("/checklists/2025-01-06", headers=headers)

    assert other_day.json()["completed_count"] == 0


def test_cross_user_checklists_are_independent(client: TestClient):
    headers_a = register_and_get_headers(client, "c8a@example.com")
    headers_b = register_and_get_headers(client, "c8b@example.com")
    item_id = client.get("/checklists/items", headers=headers_a).json()[0]["id"]

    client.patch("/checklists/2025-01-05", json={"completions": [{"item_id": item_id, "completed": True}]}, headers=headers_a)

    response_b = client.get("/checklists/2025-01-05", headers=headers_b)

    assert response_b.json()["completed_count"] == 0  # user B's own state, unaffected by user A


def test_updating_an_unknown_item_id_returns_404(client: TestClient):
    headers = register_and_get_headers(client, "c9@example.com")

    response = client.patch(
        "/checklists/2025-01-05", json={"completions": [{"item_id": str(uuid.uuid4()), "completed": True}]}, headers=headers
    )

    assert response.status_code == 404


def test_empty_completions_list_is_rejected(client: TestClient):
    headers = register_and_get_headers(client, "c10@example.com")
    response = client.patch("/checklists/2025-01-05", json={"completions": []}, headers=headers)
    assert response.status_code == 422


def test_unauthenticated_access_is_rejected(client: TestClient):
    assert client.get("/checklists/items").status_code == 401
    assert client.get("/checklists/2025-01-05").status_code == 401
    assert client.patch("/checklists/2025-01-05", json={"completions": []}).status_code == 401


def test_invalid_date_format_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "c11@example.com")
    response = client.get("/checklists/not-a-date", headers=headers)
    assert response.status_code == 422
