"""
Phase 4: relationships, invitation tokens, consent, and comfort-person
stress authorization. See app/services/relationship_service.py for the
rules under test here.
"""

import uuid
from datetime import datetime, timedelta, timezone

import jwt
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.security import hash_invitation_token
from tests.conftest import register_and_get_headers


def _register(client: TestClient, email: str, full_name: str | None = None) -> dict:
    response = client.post(
        "/auth/register", json={"email": email, "password": "correcthorse1", "full_name": full_name}
    )
    assert response.status_code == 201, response.text
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _invite(client: TestClient, owner_headers: dict, relationship_type: str = "mom", custom_label: str | None = None):
    payload = {"relationship_type": relationship_type}
    if custom_label is not None:
        payload["custom_relationship_label"] = custom_label
    return client.post("/relationships/invitations", json=payload, headers=owner_headers)


def _invite_and_accept(client: TestClient, owner_headers: dict, comfort_headers: dict, relationship_type="mom"):
    invite = _invite(client, owner_headers, relationship_type=relationship_type)
    assert invite.status_code == 201, invite.text
    token = invite.json()["token"]
    accept = client.post(f"/relationships/invitations/{token}/accept", headers=comfort_headers)
    assert accept.status_code == 200, accept.text
    return accept.json()


def _expire_invitation(db_session, token: str) -> None:
    from app.models.relationship_invitation import RelationshipInvitation

    row = db_session.query(RelationshipInvitation).filter_by(token_hash=hash_invitation_token(token)).one()
    row.expires_at = datetime.now(timezone.utc) - timedelta(days=1)
    db_session.add(row)
    db_session.commit()


# --- RELATIONSHIP TESTS ---


def test_create_invitation(client: TestClient):
    owner = _register(client, "r1-owner@example.com")

    response = _invite(client, owner, relationship_type="mom")

    assert response.status_code == 201
    body = response.json()
    assert body["relationship_type"] == "mom"
    assert body["status"] == "pending"
    assert "token" in body and len(body["token"]) > 20
    # The raw token must never be predictable/derivable from user data.
    assert "r1-owner" not in body["token"]


def test_create_invitation_other_requires_custom_label(client: TestClient):
    owner = _register(client, "r2-owner@example.com")

    missing_label = _invite(client, owner, relationship_type="other")
    assert missing_label.status_code == 422

    with_label = _invite(client, owner, relationship_type="other", custom_label="Neighbor")
    assert with_label.status_code == 201
    assert with_label.json()["custom_relationship_label"] == "Neighbor"


def test_valid_invitation_retrieval(client: TestClient):
    owner = _register(client, "r3-owner@example.com", full_name="Owner Person")
    comfort = _register(client, "r3-comfort@example.com")
    invite = _invite(client, owner, relationship_type="best_friend")
    token = invite.json()["token"]

    response = client.get(f"/relationships/invitations/{token}", headers=comfort)

    assert response.status_code == 200
    body = response.json()
    assert body["relationship_type"] == "best_friend"
    assert body["owner_display_name"] == "Owner Person"
    assert body["status"] == "pending"
    assert body["is_expired"] is False


def test_expired_invitation_rejected(client: TestClient, db_session):
    owner = _register(client, "r4-owner@example.com")
    comfort = _register(client, "r4-comfort@example.com")
    token = _invite(client, owner).json()["token"]
    _expire_invitation(db_session, token)

    accept = client.post(f"/relationships/invitations/{token}/accept", headers=comfort)
    assert accept.status_code == 404

    decline = client.post(f"/relationships/invitations/{token}/decline", headers=comfort)
    assert decline.status_code == 404


def test_expired_invitation_preview_shows_expired_flag_not_404(client: TestClient, db_session):
    """
    GET (preview) is a softer read than accept/decline: it still resolves a
    still-pending-but-expired token so the UI can render "this link has
    expired" instead of an opaque not-found.
    """
    owner = _register(client, "r4b-owner@example.com")
    comfort = _register(client, "r4b-comfort@example.com")
    token = _invite(client, owner).json()["token"]
    _expire_invitation(db_session, token)

    response = client.get(f"/relationships/invitations/{token}", headers=comfort)
    assert response.status_code == 200
    assert response.json()["is_expired"] is True


def test_invalid_invitation_rejected(client: TestClient):
    comfort = _register(client, "r5-comfort@example.com")

    response = client.get("/relationships/invitations/not-a-real-token", headers=comfort)

    assert response.status_code == 404


def test_invitation_single_use(client: TestClient):
    owner = _register(client, "r6-owner@example.com")
    comfort = _register(client, "r6-comfort@example.com")
    other = _register(client, "r6-other@example.com")
    invite = _invite(client, owner)
    token = invite.json()["token"]

    first_accept = client.post(f"/relationships/invitations/{token}/accept", headers=comfort)
    assert first_accept.status_code == 200

    second_accept = client.post(f"/relationships/invitations/{token}/accept", headers=other)
    assert second_accept.status_code == 404


def test_duplicate_relationship_prevented(client: TestClient):
    owner = _register(client, "r7-owner@example.com")
    comfort = _register(client, "r7-comfort@example.com")
    _invite_and_accept(client, owner, comfort)

    second_invite = _invite(client, owner)
    token = second_invite.json()["token"]
    response = client.post(f"/relationships/invitations/{token}/accept", headers=comfort)

    assert response.status_code == 409


def test_accept_invitation(client: TestClient):
    owner = _register(client, "r8-owner@example.com")
    comfort = _register(client, "r8-comfort@example.com", full_name="Comfort Person")

    relationship = _invite_and_accept(client, owner, comfort, relationship_type="love")

    assert relationship["status"] == "accepted"
    assert relationship["relationship_type"] == "love"
    assert relationship["my_role"] == "comfort_person"
    assert relationship["revoked_at"] is None


def test_decline_invitation(client: TestClient):
    owner = _register(client, "r9-owner@example.com")
    comfort = _register(client, "r9-comfort@example.com")
    token = _invite(client, owner).json()["token"]

    decline = client.post(f"/relationships/invitations/{token}/decline", headers=comfort)
    assert decline.status_code == 200
    assert decline.json()["status"] == "declined"

    # A declined token is now dead — cannot be accepted afterward.
    accept = client.post(f"/relationships/invitations/{token}/accept", headers=comfort)
    assert accept.status_code == 404


def test_revoke_relationship(client: TestClient):
    owner = _register(client, "r10-owner@example.com")
    comfort = _register(client, "r10-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.post(f"/relationships/{relationship['id']}/revoke", headers=owner)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "revoked"
    assert body["revoked_at"] is not None


def test_revoke_relationship_by_comfort_person(client: TestClient):
    """Either party may end the relationship, not just the owner."""
    owner = _register(client, "r10b-owner@example.com")
    comfort = _register(client, "r10b-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.post(f"/relationships/{relationship['id']}/revoke", headers=comfort)

    assert response.status_code == 200
    assert response.json()["status"] == "revoked"


def test_self_relationship_rejected(client: TestClient):
    owner = _register(client, "r11-owner@example.com")
    token = _invite(client, owner).json()["token"]

    accept = client.post(f"/relationships/invitations/{token}/accept", headers=owner)
    assert accept.status_code == 400

    token2 = _invite(client, owner).json()["token"]
    decline = client.post(f"/relationships/invitations/{token2}/decline", headers=owner)
    assert decline.status_code == 400


def test_relationship_listing(client: TestClient):
    owner = _register(client, "r12-owner@example.com")
    comfort = _register(client, "r12-comfort@example.com")
    _invite_and_accept(client, owner, comfort)

    owner_view = client.get("/relationships?role=owner", headers=owner)
    assert owner_view.status_code == 200
    assert owner_view.json()["total"] == 1
    assert owner_view.json()["items"][0]["my_role"] == "owner"

    comfort_view = client.get("/relationships?role=comfort_person", headers=comfort)
    assert comfort_view.status_code == 200
    assert comfort_view.json()["total"] == 1
    assert comfort_view.json()["items"][0]["my_role"] == "comfort_person"

    # Each side sees nothing under the other role.
    assert client.get("/relationships?role=comfort_person", headers=owner).json()["total"] == 0
    assert client.get("/relationships?role=owner", headers=comfort).json()["total"] == 0


def test_unauthorized_relationship_access_rejected(client: TestClient):
    owner = _register(client, "r13-owner@example.com")
    comfort = _register(client, "r13-comfort@example.com")
    outsider = _register(client, "r13-outsider@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    rel_id = relationship["id"]

    assert client.get(f"/relationships/{rel_id}/permissions", headers=outsider).status_code == 404
    assert client.post(f"/relationships/{rel_id}/revoke", headers=outsider).status_code == 404
    assert client.get(f"/relationships/{rel_id}/stress/today", headers=outsider).status_code == 404


# --- CONSENT TESTS ---


def test_permission_granted_on_accept(client: TestClient):
    owner = _register(client, "c1-owner@example.com")
    comfort = _register(client, "c1-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.get(f"/relationships/{relationship['id']}/permissions", headers=owner)

    assert response.status_code == 200
    perms = response.json()
    assert len(perms) == 1
    assert perms[0]["permission_type"] == "stress_level"
    assert perms[0]["granted"] is True
    assert perms[0]["granted_at"] is not None


def test_permission_revoked(client: TestClient):
    owner = _register(client, "c2-owner@example.com")
    comfort = _register(client, "c2-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    rel_id = relationship["id"]

    response = client.post(f"/relationships/{rel_id}/permissions/stress_level/revoke", headers=owner)

    assert response.status_code == 200
    body = response.json()
    assert body["granted"] is False
    assert body["revoked_at"] is not None


def test_only_owner_can_manage_consent(client: TestClient):
    owner = _register(client, "c3-owner@example.com")
    comfort = _register(client, "c3-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    rel_id = relationship["id"]

    response = client.post(f"/relationships/{rel_id}/permissions/stress_level/revoke", headers=comfort)

    assert response.status_code == 403


def test_access_blocked_without_permission(client: TestClient):
    owner = _register(client, "c4-owner@example.com")
    comfort = _register(client, "c4-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    rel_id = relationship["id"]
    client.post(f"/relationships/{rel_id}/permissions/stress_level/revoke", headers=owner)

    response = client.get(f"/relationships/{rel_id}/stress/today", headers=comfort)

    assert response.status_code == 403


def test_access_immediately_blocked_after_revocation(client: TestClient):
    owner = _register(client, "c5-owner@example.com")
    comfort = _register(client, "c5-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    rel_id = relationship["id"]

    # Works while granted (accept auto-grants it).
    assert client.get(f"/relationships/{rel_id}/stress/today", headers=comfort).status_code == 200

    client.post(f"/relationships/{rel_id}/permissions/stress_level/revoke", headers=owner)

    # Blocked on the very next call — no caching/staleness.
    assert client.get(f"/relationships/{rel_id}/stress/today", headers=comfort).status_code == 403


def test_relationship_revocation_removes_effective_access(client: TestClient):
    owner = _register(client, "c6-owner@example.com")
    comfort = _register(client, "c6-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    rel_id = relationship["id"]
    assert client.get(f"/relationships/{rel_id}/stress/today", headers=comfort).status_code == 200

    client.post(f"/relationships/{rel_id}/revoke", headers=owner)

    assert client.get(f"/relationships/{rel_id}/stress/today", headers=comfort).status_code == 403
    # The permission row itself is stamped revoked too, not just orphaned.
    perms = client.get(f"/relationships/{rel_id}/permissions", headers=owner).json()
    assert perms[0]["granted"] is False


# --- COMFORT PERSON ACCESS TESTS ---


def test_authorized_comfort_person_can_view_permitted_stress(client: TestClient):
    owner = _register(client, "cp1-owner@example.com")
    comfort = _register(client, "cp1-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=comfort)

    assert response.status_code == 200
    body = response.json()
    assert set(body.keys()) == {
        "score",
        "level",
        "confidence",
        "calculated_at",
        "data_window_start",
        "data_window_end",
        "disclaimer",
    }
    assert body["level"] == "insufficient_data"  # no mood/checklist data logged yet


def test_unrelated_user_gets_404(client: TestClient):
    owner = _register(client, "cp2-owner@example.com")
    comfort = _register(client, "cp2-comfort@example.com")
    stranger = _register(client, "cp2-stranger@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=stranger)

    assert response.status_code == 404


def test_owner_cannot_use_comfort_stress_endpoint_for_own_relationship(client: TestClient):
    """The relationship owner is the data subject, not the viewer, on this endpoint — use /stress/today instead."""
    owner = _register(client, "cp3-owner@example.com")
    comfort = _register(client, "cp3-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=owner)

    assert response.status_code == 403


def test_raw_journal_content_not_returned_by_comfort_stress_endpoint(client: TestClient):
    owner = _register(client, "cp4-owner@example.com")
    comfort = _register(client, "cp4-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    secret_text = "This is a private journal entry nobody else should see."
    journal = client.post(
        "/journals", json={"entry_date": "2025-01-05", "title": "Private", "content": secret_text}, headers=owner
    )
    assert journal.status_code == 201

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=comfort)

    assert response.status_code == 200
    assert secret_text not in response.text
    assert "Private" not in response.text
    assert "journal" not in response.text.lower()


def test_shoutout_content_not_returned_by_comfort_stress_endpoint(client: TestClient):
    owner = _register(client, "cp5-owner@example.com")
    comfort = _register(client, "cp5-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    secret_text = "Venting about something deeply personal."
    shoutout = client.post(
        "/shoutouts", json={"entry_date": "2025-01-05", "content": secret_text}, headers=owner
    )
    assert shoutout.status_code == 201

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=comfort)

    assert response.status_code == 200
    assert secret_text not in response.text


def test_media_not_returned_by_comfort_stress_endpoint(client: TestClient):
    owner = _register(client, "cp6-owner@example.com")
    comfort = _register(client, "cp6-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=comfort)

    assert response.status_code == 200
    assert "object_key" not in response.text
    assert "media" not in response.text.lower()


def test_revoked_relationship_cannot_access_stress(client: TestClient):
    owner = _register(client, "cp7-owner@example.com")
    comfort = _register(client, "cp7-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    client.post(f"/relationships/{relationship['id']}/revoke", headers=owner)

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=comfort)

    assert response.status_code == 403


def test_revoked_consent_cannot_access_stress(client: TestClient):
    owner = _register(client, "cp8-owner@example.com")
    comfort = _register(client, "cp8-comfort@example.com")
    relationship = _invite_and_accept(client, owner, comfort)
    client.post(f"/relationships/{relationship['id']}/permissions/stress_level/revoke", headers=owner)

    response = client.get(f"/relationships/{relationship['id']}/stress/today", headers=comfort)

    assert response.status_code == 403


def test_no_relationship_means_no_stress_access(client: TestClient):
    """
    There is no 'pending relationship' state in this model — a relationship
    row is only ever created at acceptance (see app/models/relationship.py)
    — so the equivalent guarantee is: before acceptance, no relationship id
    exists to query at all, and a fabricated one is rejected exactly like
    any other IDOR attempt.
    """
    comfort = _register(client, "cp9-comfort@example.com")

    response = client.get(f"/relationships/{uuid.uuid4()}/stress/today", headers=comfort)

    assert response.status_code == 404


# --- SECURITY TESTS ---


def test_cross_user_idor_on_permissions(client: TestClient):
    owner = _register(client, "s1-owner@example.com")
    comfort = _register(client, "s1-comfort@example.com")
    outsider = _register(client, "s1-outsider@example.com")
    relationship = _invite_and_accept(client, owner, comfort)

    response = client.post(
        f"/relationships/{relationship['id']}/permissions/stress_level/grant", headers=outsider
    )

    assert response.status_code == 404


def test_invalid_uuid_relationship_id(client: TestClient):
    comfort = _register(client, "s2-comfort@example.com")

    response = client.get("/relationships/not-a-uuid/stress/today", headers=comfort)

    assert response.status_code == 422


def test_missing_jwt(client: TestClient):
    response = client.post("/relationships/invitations", json={"relationship_type": "mom"})
    assert response.status_code == 401 or response.status_code == 403


def test_expired_jwt(client: TestClient):
    _register(client, "s3-user@example.com")
    expired_payload = {
        "sub": str(uuid.uuid4()),
        "type": "access",
        "iat": int((datetime.now(timezone.utc) - timedelta(minutes=30)).timestamp()),
        "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
        "jti": uuid.uuid4().hex,
    }
    expired_token = jwt.encode(expired_payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)

    response = client.get("/relationships?role=owner", headers={"Authorization": f"Bearer {expired_token}"})

    assert response.status_code == 401


def test_malformed_invitation_token(client: TestClient):
    comfort = _register(client, "s4-comfort@example.com")

    for bad_token in ["", "a", "%%%not-url-safe%%%", "a" * 500]:
        response = client.get(f"/relationships/invitations/{bad_token or 'blank'}", headers=comfort)
        assert response.status_code in (404, 422)


def test_replayed_invitation_token_after_accept(client: TestClient):
    owner = _register(client, "s5-owner@example.com")
    comfort = _register(client, "s5-comfort@example.com")
    attacker = _register(client, "s5-attacker@example.com")
    token = _invite(client, owner).json()["token"]
    accept = client.post(f"/relationships/invitations/{token}/accept", headers=comfort)
    assert accept.status_code == 200

    # An attacker who somehow observed the already-used token cannot replay it.
    replay = client.post(f"/relationships/invitations/{token}/accept", headers=attacker)
    assert replay.status_code == 404
    preview = client.get(f"/relationships/invitations/{token}", headers=attacker)
    assert preview.status_code == 404
