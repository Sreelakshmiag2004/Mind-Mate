import uuid

from fastapi.testclient import TestClient

from app.core.security import verify_password
from app.repositories import vault_repository
from tests.conftest import register_and_get_headers


def _me_user_id(client: TestClient, headers: dict) -> uuid.UUID:
    return uuid.UUID(client.get("/auth/me", headers=headers).json()["user"]["id"])


def test_create_lock_succeeds(client: TestClient):
    headers = register_and_get_headers(client, "vault1@example.com")

    response = client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    assert response.status_code == 201
    assert response.json()["configured"] is True
    assert response.json()["last_viewed_at"] is None


def test_password_is_never_returned_on_create(client: TestClient):
    headers = register_and_get_headers(client, "vault2@example.com")

    response = client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    body = response.json()
    assert "password" not in body
    assert "password_hash" not in body
    assert set(body.keys()) == {"configured", "last_viewed_at", "previous_viewed_at"}


def test_password_hash_is_never_returned_anywhere_including_raw_response_text(client: TestClient):
    headers = register_and_get_headers(client, "vault3@example.com")

    response = client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    # Belt-and-braces: check the raw response body text, not just the
    # parsed JSON keys, so a hash smuggled into e.g. a stray debug field
    # would still be caught.
    assert "password_hash" not in response.text
    assert "correcthorse" not in response.text


def test_stored_password_is_argon2_not_sha256(client: TestClient, db_session):
    headers = register_and_get_headers(client, "vault4@example.com")
    user_id = _me_user_id(client, headers)
    client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    lock = vault_repository.get_by_user_id(db_session, user_id=user_id)

    # Not asserting an exact hash string (Argon2 is salted — every hash
    # differs even for the same password) — instead: the stored value has
    # the Argon2 PHC string format, is NOT a bare 64-char hex SHA-256
    # digest (the old app's scheme), and actually verifies via the same
    # utility the app itself uses to check it.
    assert lock.password_hash.startswith("$argon2")
    assert not all(c in "0123456789abcdef" for c in lock.password_hash)  # not a raw hex digest
    assert verify_password("correcthorse", lock.password_hash) is True
    assert verify_password("wrong-password", lock.password_hash) is False


def test_duplicate_create_returns_409(client: TestClient):
    headers = register_and_get_headers(client, "vault5@example.com")
    client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    response = client.post("/vault/lock", json={"password": "anotherpassword"}, headers=headers)

    assert response.status_code == 409


def test_get_unconfigured_state(client: TestClient):
    headers = register_and_get_headers(client, "vault6@example.com")

    response = client.get("/vault/lock", headers=headers)

    assert response.status_code == 200
    assert response.json() == {"configured": False, "last_viewed_at": None, "previous_viewed_at": None}


def test_get_configured_state(client: TestClient):
    headers = register_and_get_headers(client, "vault7@example.com")
    client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    response = client.get("/vault/lock", headers=headers)

    assert response.status_code == 200
    assert response.json()["configured"] is True


def test_correct_password_unlocks(client: TestClient):
    headers = register_and_get_headers(client, "vault8@example.com")
    client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    response = client.post("/vault/unlock", json={"password": "correcthorse"}, headers=headers)

    assert response.status_code == 200
    assert response.json()["configured"] is True


def test_incorrect_password_returns_401(client: TestClient):
    headers = register_and_get_headers(client, "vault9@example.com")
    client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    response = client.post("/vault/unlock", json={"password": "wrong-password"}, headers=headers)

    assert response.status_code == 401
    assert "password_hash" not in response.text


def test_unlock_before_any_lock_is_created_also_returns_401_not_404(client: TestClient):
    """Never reveals 'you haven't set one up' vs 'you got it wrong' via a different status code."""
    headers = register_and_get_headers(client, "vault10@example.com")

    response = client.post("/vault/unlock", json={"password": "anything"}, headers=headers)

    assert response.status_code == 401


def test_successful_unlock_updates_last_viewed_at(client: TestClient):
    headers = register_and_get_headers(client, "vault11@example.com")
    client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    response = client.post("/vault/unlock", json={"password": "correcthorse"}, headers=headers)

    assert response.json()["last_viewed_at"] is not None


def test_previous_last_viewed_at_is_shifted_correctly_across_two_unlocks(client: TestClient):
    headers = register_and_get_headers(client, "vault12@example.com")
    client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    first = client.post("/vault/unlock", json={"password": "correcthorse"}, headers=headers).json()
    assert first["previous_viewed_at"] is None  # nothing to shift on the very first unlock

    second = client.post("/vault/unlock", json={"password": "correcthorse"}, headers=headers).json()

    assert second["previous_viewed_at"] == first["last_viewed_at"]
    assert second["last_viewed_at"] != first["last_viewed_at"]


def test_unauthenticated_get_is_rejected(client: TestClient):
    assert client.get("/vault/lock").status_code == 401


def test_unauthenticated_create_is_rejected(client: TestClient):
    assert client.post("/vault/lock", json={"password": "correcthorse"}).status_code == 401


def test_unauthenticated_unlock_is_rejected(client: TestClient):
    assert client.post("/vault/unlock", json={"password": "correcthorse"}).status_code == 401


def test_user_a_cannot_see_or_unlock_user_bs_vault_lock(client: TestClient):
    """
    There is no id-addressed Vault-lock route at all (unlike /media/{id})
    — every route resolves strictly to the caller's own JWT-derived
    user_id, so there is no request shape through which one user could
    even name another user's lock. This test confirms the practical
    consequence: two users' Vault locks never interfere with each other.
    """
    headers_a = register_and_get_headers(client, "vault13a@example.com")
    headers_b = register_and_get_headers(client, "vault13b@example.com")
    client.post("/vault/lock", json={"password": "a-password"}, headers=headers_a)

    # B still sees their own (unconfigured) state, not A's.
    b_state = client.get("/vault/lock", headers=headers_b).json()
    assert b_state["configured"] is False

    # B guessing A's password against B's own /vault/unlock can't possibly
    # unlock A's — it's checked against B's own (nonexistent) lock.
    response = client.post("/vault/unlock", json={"password": "a-password"}, headers=headers_b)
    assert response.status_code == 401


def test_lock_data_is_isolated_from_profile_and_media_assets(client: TestClient):
    """
    Structural isolation check (PHASE14A/PHASE14B requirement): the Vault
    lock response never carries, and the table is never joined against,
    Profile or media_assets fields.
    """
    headers = register_and_get_headers(client, "vault14@example.com")

    response = client.post("/vault/lock", json={"password": "correcthorse"}, headers=headers)

    body = response.json()
    for forbidden_field in ("full_name", "age_group", "phone", "city", "country", "media_type", "object_key"):
        assert forbidden_field not in body


def test_empty_password_on_create_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "vault15@example.com")
    response = client.post("/vault/lock", json={"password": ""}, headers=headers)
    assert response.status_code == 422


def test_too_short_password_on_create_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "vault16@example.com")
    response = client.post("/vault/lock", json={"password": "abc"}, headers=headers)
    assert response.status_code == 422


def test_whitespace_only_password_on_create_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "vault17@example.com")
    response = client.post("/vault/lock", json={"password": "      "}, headers=headers)
    assert response.status_code == 422
