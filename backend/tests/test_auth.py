from fastapi.testclient import TestClient

VALID_PASSWORD = "correct-horse-1"


def _register(client: TestClient, email: str = "user@example.com", password: str = VALID_PASSWORD, **extra):
    return client.post("/auth/register", json={"email": email, "password": password, **extra})


def test_health_check_reports_database_connected(client: TestClient):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["database"] == "connected"


# --- Registration ---


def test_successful_registration_returns_tokens(client: TestClient):
    response = _register(client, full_name="Ada Lovelace")

    assert response.status_code == 201
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["expires_in"] > 0
    # The password (or any hash of it) must never appear in the response.
    assert "password" not in response.text
    assert "password_hash" not in response.text


def test_duplicate_email_is_rejected(client: TestClient):
    first = _register(client, email="dupe@example.com")
    assert first.status_code == 201

    second = _register(client, email="dupe@example.com")
    assert second.status_code == 409


def test_duplicate_email_is_case_insensitive(client: TestClient):
    _register(client, email="Case@Example.com")
    second = _register(client, email="case@example.com")
    assert second.status_code == 409


def test_too_short_password_is_rejected(client: TestClient):
    response = _register(client, password="short1")
    assert response.status_code == 422


def test_password_without_digit_is_rejected(client: TestClient):
    response = _register(client, password="onlyletters")
    assert response.status_code == 422


def test_invalid_email_is_rejected(client: TestClient):
    response = _register(client, email="not-an-email")
    assert response.status_code == 422


# --- Login ---


def test_successful_login(client: TestClient):
    _register(client, email="login@example.com")

    response = client.post("/auth/login", json={"email": "login@example.com", "password": VALID_PASSWORD})

    assert response.status_code == 200
    body = response.json()
    assert body["access_token"]
    assert body["refresh_token"]


def test_login_with_wrong_password_is_rejected(client: TestClient):
    _register(client, email="wrongpw@example.com")

    response = client.post("/auth/login", json={"email": "wrongpw@example.com", "password": "totally-wrong-1"})

    assert response.status_code == 401


def test_login_with_unknown_email_is_rejected(client: TestClient):
    response = client.post("/auth/login", json={"email": "nobody@example.com", "password": VALID_PASSWORD})
    assert response.status_code == 401


# --- /auth/me ---


def test_me_returns_user_and_profile_when_authenticated(client: TestClient):
    register_response = _register(client, email="me@example.com", full_name="Grace Hopper")
    access_token = register_response.json()["access_token"]

    response = client.get("/auth/me", headers={"Authorization": f"Bearer {access_token}"})

    assert response.status_code == 200
    body = response.json()
    assert body["user"]["email"] == "me@example.com"
    assert body["profile"]["full_name"] == "Grace Hopper"
    assert "password_hash" not in response.text


def test_me_without_token_is_rejected(client: TestClient):
    response = client.get("/auth/me")
    assert response.status_code == 401  # no Authorization header at all (HTTPBearer)


def test_me_with_garbage_token_is_rejected(client: TestClient):
    response = client.get("/auth/me", headers={"Authorization": "Bearer not-a-real-token"})
    assert response.status_code == 401


# --- Refresh ---


def test_refresh_token_rotation_issues_new_tokens(client: TestClient):
    register_response = _register(client, email="rotate@example.com")
    original_refresh = register_response.json()["refresh_token"]

    response = client.post("/auth/refresh", json={"refresh_token": original_refresh})

    assert response.status_code == 200
    body = response.json()
    assert body["refresh_token"] != original_refresh
    assert body["access_token"] != register_response.json()["access_token"]


def test_rotated_refresh_token_can_authenticate(client: TestClient):
    register_response = _register(client, email="rotate2@example.com")
    original_refresh = register_response.json()["refresh_token"]

    refreshed = client.post("/auth/refresh", json={"refresh_token": original_refresh})
    new_access_token = refreshed.json()["access_token"]

    me_response = client.get("/auth/me", headers={"Authorization": f"Bearer {new_access_token}"})
    assert me_response.status_code == 200


def test_reusing_a_rotated_refresh_token_is_rejected(client: TestClient):
    """Once a refresh token has been rotated, the OLD token must no longer work."""
    register_response = _register(client, email="reuse@example.com")
    original_refresh = register_response.json()["refresh_token"]

    client.post("/auth/refresh", json={"refresh_token": original_refresh})  # rotates it

    replay = client.post("/auth/refresh", json={"refresh_token": original_refresh})
    assert replay.status_code == 401


def test_unknown_refresh_token_is_rejected(client: TestClient):
    response = client.post("/auth/refresh", json={"refresh_token": "this-token-was-never-issued"})
    assert response.status_code == 401


# --- Logout ---


def test_logout_revokes_the_session(client: TestClient):
    register_response = _register(client, email="logout@example.com")
    access_token = register_response.json()["access_token"]
    refresh_token = register_response.json()["refresh_token"]

    logout_response = client.post(
        "/auth/logout",
        json={"refresh_token": refresh_token},
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert logout_response.status_code == 204

    reuse_response = client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert reuse_response.status_code == 401


def test_logout_requires_authentication(client: TestClient):
    register_response = _register(client, email="logout2@example.com")
    refresh_token = register_response.json()["refresh_token"]

    response = client.post("/auth/logout", json={"refresh_token": refresh_token})
    assert response.status_code == 401  # missing Authorization header


def test_logout_rejects_another_users_refresh_token(client: TestClient):
    victim = _register(client, email="victim@example.com")
    attacker = _register(client, email="attacker@example.com")

    response = client.post(
        "/auth/logout",
        json={"refresh_token": victim.json()["refresh_token"]},
        headers={"Authorization": f"Bearer {attacker.json()['access_token']}"},
    )
    assert response.status_code == 401
