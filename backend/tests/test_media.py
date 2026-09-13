import hashlib
import io
import re
import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.exceptions import StorageError
from tests.conftest import register_and_get_headers


def _upload(client, headers, filename="note.png", content=b"fake-image-bytes", content_type="image/png", **extra):
    files = {"file": (filename, io.BytesIO(content), content_type)}
    return client.post("/media/upload", files=files, data=extra, headers=headers)


def test_authenticated_upload_succeeds(client: TestClient):
    headers = register_and_get_headers(client, "media1@example.com")

    response = _upload(client, headers)

    assert response.status_code == 201


def test_unauthenticated_upload_is_rejected(client: TestClient):
    files = {"file": ("note.png", io.BytesIO(b"data"), "image/png")}
    response = client.post("/media/upload", files=files)
    assert response.status_code == 401


def test_valid_voice_file_is_accepted(client: TestClient):
    headers = register_and_get_headers(client, "media2@example.com")

    response = _upload(
        client, headers, filename="recording.m4a", content=b"fake-audio-bytes", content_type="audio/mp4", duration_seconds=42
    )

    assert response.status_code == 201
    body = response.json()
    assert body["media_type"] == "voice"
    assert body["duration_seconds"] == 42


def test_valid_video_file_is_accepted(client: TestClient):
    headers = register_and_get_headers(client, "media3@example.com")

    response = _upload(client, headers, filename="clip.mp4", content=b"fake-video-bytes", content_type="video/mp4")

    assert response.status_code == 201
    assert response.json()["media_type"] == "video"


def test_invalid_content_type_is_rejected(client: TestClient):
    headers = register_and_get_headers(client, "media4@example.com")

    response = _upload(client, headers, filename="virus.exe", content=b"MZ", content_type="application/octet-stream")

    assert response.status_code == 415


def test_oversized_file_is_rejected(client: TestClient, monkeypatch):
    headers = register_and_get_headers(client, "media5@example.com")
    # Shrink the limit instead of generating a real 25MB+ payload.
    monkeypatch.setattr(settings, "max_upload_size_mb", 1)

    two_mb = b"x" * (2 * 1024 * 1024)
    response = _upload(client, headers, content=two_mb)

    assert response.status_code == 413


def test_empty_file_is_rejected(client: TestClient):
    headers = register_and_get_headers(client, "media6@example.com")
    response = _upload(client, headers, content=b"")
    assert response.status_code == 415


def test_metadata_is_created_correctly(client: TestClient):
    headers = register_and_get_headers(client, "media7@example.com")

    response = _upload(client, headers, filename="my photo.png", content=b"12345")

    body = response.json()
    assert body["original_filename"] == "my photo.png"
    assert body["content_type"] == "image/png"
    assert body["file_size"] == 5
    assert "id" in body
    assert "object_key" not in body  # never exposed to the client


def test_object_is_actually_stored(client: TestClient, storage):
    headers = register_and_get_headers(client, "media8@example.com")
    assert storage.count() == 0

    _upload(client, headers, content=b"some bytes")

    assert storage.count() == 1


def test_list_own_media(client: TestClient):
    headers = register_and_get_headers(client, "media9@example.com")
    _upload(client, headers, filename="a.png")
    _upload(client, headers, filename="b.png")

    response = client.get("/media", headers=headers)

    assert response.status_code == 200
    assert response.json()["total"] == 2


def test_list_filters_by_media_type(client: TestClient):
    headers = register_and_get_headers(client, "media10@example.com")
    _upload(client, headers, filename="a.png", content_type="image/png")
    _upload(client, headers, filename="a.m4a", content=b"audio", content_type="audio/mp4")

    response = client.get("/media", params={"media_type": "voice"}, headers=headers)

    assert response.json()["total"] == 1
    assert response.json()["items"][0]["media_type"] == "voice"


def test_list_does_not_include_another_users_media(client: TestClient):
    headers_a = register_and_get_headers(client, "media11a@example.com")
    headers_b = register_and_get_headers(client, "media11b@example.com")
    _upload(client, headers_a)

    response = client.get("/media", headers=headers_b)

    assert response.json()["total"] == 0


def test_retrieve_own_metadata_includes_download_url(client: TestClient):
    headers = register_and_get_headers(client, "media12@example.com")
    created = _upload(client, headers).json()

    response = client.get(f"/media/{created['id']}", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["download_url"].startswith("memory://")
    assert body["download_url_expires_in_seconds"] > 0


def test_unrelated_user_cannot_access_metadata(client: TestClient):
    owner_headers = register_and_get_headers(client, "media13owner@example.com")
    other_headers = register_and_get_headers(client, "media13other@example.com")
    created = _upload(client, owner_headers).json()

    response = client.get(f"/media/{created['id']}", headers=other_headers)

    assert response.status_code == 404


def test_unrelated_user_cannot_delete_media(client: TestClient, storage):
    owner_headers = register_and_get_headers(client, "media14owner@example.com")
    other_headers = register_and_get_headers(client, "media14other@example.com")
    created = _upload(client, owner_headers).json()

    response = client.delete(f"/media/{created['id']}", headers=other_headers)

    assert response.status_code == 404
    assert storage.count() == 1  # untouched
    assert client.get(f"/media/{created['id']}", headers=owner_headers).status_code == 200


def test_deletion_removes_both_metadata_and_object(client: TestClient, storage):
    headers = register_and_get_headers(client, "media15@example.com")
    created = _upload(client, headers).json()
    assert storage.count() == 1

    response = client.delete(f"/media/{created['id']}", headers=headers)

    assert response.status_code == 204
    assert storage.count() == 0
    assert client.get(f"/media/{created['id']}", headers=headers).status_code == 404


def test_failed_upload_does_not_leave_a_database_record(client: TestClient, storage, monkeypatch):
    headers = register_and_get_headers(client, "media16@example.com")

    def _always_fail(*args, **kwargs):
        raise StorageError("simulated storage outage")

    monkeypatch.setattr(storage, "upload", _always_fail)

    response = _upload(client, headers)

    assert response.status_code == 502
    assert storage.count() == 0
    assert client.get("/media", headers=headers).json()["total"] == 0


def test_invalid_uuid_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "media17@example.com")
    assert client.get("/media/not-a-uuid", headers=headers).status_code == 422


# --- PHASE14B: media rename (title) ---


def test_authenticated_rename_succeeds(client: TestClient):
    headers = register_and_get_headers(client, "rename1@example.com")
    created = _upload(client, headers).json()

    response = client.patch(f"/media/{created['id']}", json={"title": "Beach trip"}, headers=headers)

    assert response.status_code == 200


def test_returned_title_is_correct(client: TestClient):
    headers = register_and_get_headers(client, "rename2@example.com")
    created = _upload(client, headers).json()
    assert created["title"] is None  # never renamed yet

    response = client.patch(f"/media/{created['id']}", json={"title": "Beach trip"}, headers=headers)

    assert response.json()["title"] == "Beach trip"


def test_title_persists_after_get(client: TestClient):
    headers = register_and_get_headers(client, "rename3@example.com")
    created = _upload(client, headers).json()
    client.patch(f"/media/{created['id']}", json={"title": "Beach trip"}, headers=headers)

    response = client.get(f"/media/{created['id']}", headers=headers)

    assert response.json()["title"] == "Beach trip"


def test_title_persists_after_list(client: TestClient):
    headers = register_and_get_headers(client, "rename4@example.com")
    created = _upload(client, headers).json()
    client.patch(f"/media/{created['id']}", json={"title": "Beach trip"}, headers=headers)

    response = client.get("/media", headers=headers)

    assert response.json()["items"][0]["title"] == "Beach trip"


def test_null_title_remains_valid_for_a_never_renamed_item(client: TestClient):
    headers = register_and_get_headers(client, "rename5@example.com")
    created = _upload(client, headers).json()

    get_response = client.get(f"/media/{created['id']}", headers=headers)
    list_response = client.get("/media", headers=headers)

    assert created["title"] is None
    assert get_response.json()["title"] is None
    assert list_response.json()["items"][0]["title"] is None


def test_maximum_valid_length_title_is_accepted(client: TestClient):
    headers = register_and_get_headers(client, "rename6@example.com")
    created = _upload(client, headers).json()
    title_200 = "x" * 200

    response = client.patch(f"/media/{created['id']}", json={"title": title_200}, headers=headers)

    assert response.status_code == 200
    assert response.json()["title"] == title_200


def test_over_limit_title_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "rename7@example.com")
    created = _upload(client, headers).json()
    title_201 = "x" * 201

    response = client.patch(f"/media/{created['id']}", json={"title": title_201}, headers=headers)

    assert response.status_code == 422


def test_empty_string_title_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "rename8@example.com")
    created = _upload(client, headers).json()

    response = client.patch(f"/media/{created['id']}", json={"title": ""}, headers=headers)

    assert response.status_code == 422


def test_whitespace_only_title_returns_422(client: TestClient):
    headers = register_and_get_headers(client, "rename9@example.com")
    created = _upload(client, headers).json()

    response = client.patch(f"/media/{created['id']}", json={"title": "   "}, headers=headers)

    assert response.status_code == 422


def test_rename_nonexistent_media_returns_404(client: TestClient):
    headers = register_and_get_headers(client, "rename10@example.com")

    response = client.patch(f"/media/{uuid.uuid4()}", json={"title": "x"}, headers=headers)

    assert response.status_code == 404


def test_rename_another_users_media_returns_404(client: TestClient):
    owner_headers = register_and_get_headers(client, "rename11owner@example.com")
    other_headers = register_and_get_headers(client, "rename11other@example.com")
    created = _upload(client, owner_headers).json()

    response = client.patch(f"/media/{created['id']}", json={"title": "Hijacked"}, headers=other_headers)

    assert response.status_code == 404
    still_owned = client.get(f"/media/{created['id']}", headers=owner_headers)
    assert still_owned.json()["title"] != "Hijacked"


def test_unauthenticated_rename_is_rejected(client: TestClient):
    response = client.patch(f"/media/{uuid.uuid4()}", json={"title": "x"})
    assert response.status_code == 401


def test_rename_does_not_change_the_stored_object_key(client: TestClient):
    """object_key is never exposed directly, but the presigned download URL embeds it (memory://<object_key>?...),
    so an unchanged prefix is direct evidence the object itself was never renamed/moved."""
    headers = register_and_get_headers(client, "rename12@example.com")
    created = _upload(client, headers).json()
    before_url = client.get(f"/media/{created['id']}", headers=headers).json()["download_url"]
    before_key = before_url.split("?", 1)[0]

    client.patch(f"/media/{created['id']}", json={"title": "Renamed"}, headers=headers)

    after_url = client.get(f"/media/{created['id']}", headers=headers).json()["download_url"]
    after_key = after_url.split("?", 1)[0]
    assert after_key == before_key


def test_rename_does_not_change_media_type(client: TestClient):
    headers = register_and_get_headers(client, "rename13@example.com")
    created = _upload(client, headers, filename="clip.mp4", content=b"video-bytes", content_type="video/mp4").json()

    response = client.patch(f"/media/{created['id']}", json={"title": "Renamed"}, headers=headers)

    assert response.json()["media_type"] == "video"


def test_rename_does_not_change_duration(client: TestClient):
    headers = register_and_get_headers(client, "rename14@example.com")
    created = _upload(
        client, headers, filename="a.m4a", content=b"audio-bytes", content_type="audio/mp4", duration_seconds=99
    ).json()

    response = client.patch(f"/media/{created['id']}", json={"title": "Renamed"}, headers=headers)

    assert response.json()["duration_seconds"] == 99


def test_rename_does_not_change_original_filename(client: TestClient):
    headers = register_and_get_headers(client, "rename15@example.com")
    created = _upload(client, headers, filename="original name.png").json()

    response = client.patch(f"/media/{created['id']}", json={"title": "Renamed"}, headers=headers)

    assert response.json()["original_filename"] == "original name.png"


def test_upload_media_cleans_up_orphaned_object_on_db_failure(db_session, storage, monkeypatch):
    """
    Service-level test (not through the API): simulates a DB commit
    failure AFTER a successful storage upload, and asserts the just-
    uploaded object is cleaned up rather than left orphaned — see
    app/services/media_service.py's module docstring.
    """
    from sqlalchemy.exc import SQLAlchemyError

    from app.repositories import media_repository
    from app.services import media_service

    def _always_fail(*args, **kwargs):
        raise SQLAlchemyError("simulated DB outage")

    monkeypatch.setattr(media_repository, "create", _always_fail)

    with pytest.raises(SQLAlchemyError):
        media_service.upload_media(
            db_session,
            storage,
            user_id=uuid.uuid4(),
            data=b"some bytes",
            content_type="image/png",
            original_filename="x.png",
            duration_seconds=None,
        )

    assert storage.count() == 0  # cleaned up, not orphaned


# --- PHASE14I-B: legacy Hive media migration duplicate-safe tracking ---


def test_normal_upload_has_null_legacy_fields(client: TestClient):
    headers = register_and_get_headers(client, "legacy1@example.com")

    response = _upload(client, headers)

    assert response.status_code == 201
    body = response.json()
    assert body["legacy_source"] is None
    assert body["legacy_created_at"] is None


def test_normal_upload_with_legacy_created_at_omitted_succeeds(client: TestClient):
    """A legacy_source with no legacy_created_at is a valid, independent combination."""
    headers = register_and_get_headers(client, "legacy2@example.com")

    response = _upload(client, headers, legacy_source="image:no-date")

    assert response.status_code == 201
    body = response.json()
    assert body["legacy_source"] == "image:no-date"
    assert body["legacy_created_at"] is None


def test_legacy_upload_with_valid_legacy_source_succeeds(client: TestClient):
    headers = register_and_get_headers(client, "legacy3@example.com")

    response = _upload(client, headers, legacy_source="image:abc")

    assert response.status_code == 201
    assert response.json()["legacy_source"] == "image:abc"


def test_legacy_upload_with_valid_legacy_created_at_round_trips_as_utc(client: TestClient):
    headers = register_and_get_headers(client, "legacy4@example.com")

    response = _upload(
        client, headers, legacy_source="image:legacy-date", legacy_created_at="2020-06-15T10:30:00+05:30"
    )

    assert response.status_code == 201
    # The service layer normalizes to a tz-AWARE UTC datetime before this
    # ever reaches the database (see MediaUploadLegacyFields._normalize_to_utc
    # and app/models/media_asset.py) — what's asserted below (the naive
    # wall-clock value) is what actually round-trips back out through the
    # test suite's SQLite fallback, which does not preserve a `tzinfo` on
    # read-back the way PostgreSQL's real timestamptz does (see
    # tests/conftest.py's documented Phase 1 SQLite-vs-PostgreSQL
    # trade-off). Comparing wall-clock value here still proves the +05:30
    # offset was correctly converted to UTC before storage.
    returned = datetime.fromisoformat(response.json()["legacy_created_at"])
    assert returned.replace(tzinfo=None) == datetime(2020, 6, 15, 5, 0, 0)  # +05:30 normalized to UTC


def test_legacy_created_at_naive_value_is_assumed_utc(client: TestClient):
    """See MediaUploadLegacyFields._normalize_to_utc's docstring: a value with no offset is stamped UTC, not rejected."""
    headers = register_and_get_headers(client, "legacy4b@example.com")

    response = _upload(client, headers, legacy_source="image:naive-date", legacy_created_at="2020-06-15T10:30:00")

    assert response.status_code == 201
    returned = datetime.fromisoformat(response.json()["legacy_created_at"])
    assert returned.replace(tzinfo=None) == datetime(2020, 6, 15, 10, 30, 0)


def test_duplicate_legacy_source_returns_existing_asset(client: TestClient):
    headers = register_and_get_headers(client, "legacy5@example.com")
    first = _upload(client, headers, legacy_source="image:dup").json()

    second = _upload(client, headers, filename="different.png", content=b"other bytes", legacy_source="image:dup")

    assert second.status_code == 201
    assert second.json()["id"] == first["id"]


def test_duplicate_legacy_source_does_not_create_second_db_row(client: TestClient):
    headers = register_and_get_headers(client, "legacy6@example.com")
    _upload(client, headers, legacy_source="image:dup2")

    _upload(client, headers, legacy_source="image:dup2")

    assert client.get("/media", headers=headers).json()["total"] == 1


def test_duplicate_legacy_source_does_not_create_second_storage_object(client: TestClient, storage):
    headers = register_and_get_headers(client, "legacy7@example.com")
    _upload(client, headers, legacy_source="image:dup3")
    assert storage.count() == 1

    _upload(client, headers, legacy_source="image:dup3")

    assert storage.count() == 1


def test_different_legacy_source_creates_different_assets(client: TestClient):
    headers = register_and_get_headers(client, "legacy8@example.com")
    first = _upload(client, headers, legacy_source="image:one").json()

    second = _upload(client, headers, legacy_source="image:two").json()

    assert first["id"] != second["id"]
    assert client.get("/media", headers=headers).json()["total"] == 2


def test_same_legacy_source_allowed_for_different_users(client: TestClient):
    headers_a = register_and_get_headers(client, "legacy9a@example.com")
    headers_b = register_and_get_headers(client, "legacy9b@example.com")

    response_a = _upload(client, headers_a, legacy_source="image:shared")
    response_b = _upload(client, headers_b, legacy_source="image:shared")

    assert response_a.status_code == 201
    assert response_b.status_code == 201
    assert response_a.json()["id"] != response_b.json()["id"]


def test_user_cannot_query_another_users_legacy_source(client: TestClient):
    owner_headers = register_and_get_headers(client, "legacy10owner@example.com")
    other_headers = register_and_get_headers(client, "legacy10other@example.com")
    _upload(client, owner_headers, legacy_source="image:owned")

    response = client.get("/media", params={"legacy_source": "image:owned"}, headers=other_headers)

    assert response.status_code == 200
    assert response.json()["total"] == 0


def test_owner_can_query_own_legacy_source(client: TestClient):
    headers = register_and_get_headers(client, "legacy11@example.com")
    created = _upload(client, headers, legacy_source="image:findme").json()

    response = client.get("/media", params={"legacy_source": "image:findme"}, headers=headers)

    assert response.json()["total"] == 1
    assert response.json()["items"][0]["id"] == created["id"]


def test_query_for_absent_legacy_source_returns_empty(client: TestClient):
    headers = register_and_get_headers(client, "legacy12@example.com")

    response = client.get("/media", params={"legacy_source": "image:never-uploaded"}, headers=headers)

    assert response.status_code == 200
    assert response.json()["total"] == 0


def test_blank_legacy_source_rejected(client: TestClient):
    headers = register_and_get_headers(client, "legacy13@example.com")

    response = _upload(client, headers, legacy_source="")

    assert response.status_code == 422


def test_malformed_legacy_source_missing_colon_rejected(client: TestClient):
    headers = register_and_get_headers(client, "legacy14@example.com")

    response = _upload(client, headers, legacy_source="not-a-valid-format")

    assert response.status_code == 422


def test_malformed_legacy_source_wrong_prefix_rejected(client: TestClient):
    headers = register_and_get_headers(client, "legacy14b@example.com")

    response = _upload(client, headers, legacy_source="document:abc")

    assert response.status_code == 422


def test_invalid_legacy_created_at_rejected(client: TestClient):
    headers = register_and_get_headers(client, "legacy15@example.com")

    response = _upload(client, headers, legacy_source="image:baddate", legacy_created_at="not-a-date")

    assert response.status_code == 422


def test_rename_still_works_for_legacy_media(client: TestClient):
    headers = register_and_get_headers(client, "legacy16@example.com")
    created = _upload(client, headers, legacy_source="image:rename-me").json()

    response = client.patch(f"/media/{created['id']}", json={"title": "Migrated photo"}, headers=headers)

    assert response.status_code == 200
    assert response.json()["title"] == "Migrated photo"
    assert response.json()["legacy_source"] == "image:rename-me"  # untouched by rename


def test_delete_still_works_for_legacy_media(client: TestClient, storage):
    headers = register_and_get_headers(client, "legacy17@example.com")
    created = _upload(client, headers, legacy_source="image:delete-me").json()

    response = client.delete(f"/media/{created['id']}", headers=headers)

    assert response.status_code == 204
    assert storage.count() == 0
    assert client.get(f"/media/{created['id']}", headers=headers).status_code == 404


def test_get_media_list_still_works_alongside_legacy_fields(client: TestClient):
    headers = register_and_get_headers(client, "legacy18@example.com")
    _upload(client, headers, filename="a.png")
    _upload(client, headers, filename="b.png", legacy_source="image:b")

    response = client.get("/media", headers=headers)

    assert response.status_code == 200
    assert response.json()["total"] == 2


def test_get_media_detail_still_works_alongside_legacy_fields(client: TestClient):
    headers = register_and_get_headers(client, "legacy19@example.com")
    created = _upload(client, headers, legacy_source="image:detail").json()

    response = client.get(f"/media/{created['id']}", headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["legacy_source"] == "image:detail"
    assert "download_url" in body


def test_upload_response_contains_agreed_legacy_fields(client: TestClient):
    headers = register_and_get_headers(client, "legacy20@example.com")

    response = _upload(client, headers)

    body = response.json()
    assert "legacy_source" in body
    assert "legacy_created_at" in body


def test_upload_success_then_lost_response_retry_resolves_to_same_asset(client: TestClient, storage):
    """
    The exact scenario named in the PHASE14I-B contract: the first request
    succeeds server-side, but the client never receives the response (a
    dropped connection, a timeout, ...) and retries the identical request.
    The retry must resolve to the SAME MediaAsset and must not create a
    second object or a second row.
    """
    headers = register_and_get_headers(client, "legacy21@example.com")

    first_response = _upload(client, headers, legacy_source="image:lost-response")
    assert first_response.status_code == 201
    first_id = first_response.json()["id"]
    assert storage.count() == 1

    # Simulated retry: the client never saw `first_response`, so it
    # resends the exact same multipart request.
    retry_response = _upload(client, headers, legacy_source="image:lost-response")

    assert retry_response.status_code == 201
    assert retry_response.json()["id"] == first_id
    assert storage.count() == 1  # no second object
    assert client.get("/media", headers=headers).json()["total"] == 1  # no second row


def test_race_backstop_resolves_to_winning_row_and_cleans_up_orphan(db_session, storage, monkeypatch):
    """
    Service-level test for the TRUE concurrent-race backstop (module
    docstring, point 2) — not the simpler lost-response retry above,
    which the pre-check alone already resolves. This simulates the
    narrower window a real race opens: two requests both pass the
    pre-check (because neither row exists yet when either checks), both
    upload their own storage object, and then race to insert; the
    database's unique index lets exactly one win.

    tests/conftest.py's SQLite test database uses one shared connection
    (StaticPool) for the whole process, so an actual multi-threaded
    concurrent transaction can't be driven through the HTTP layer here —
    see app/services/media_service.py's module docstring for that
    documented limitation. This test instead drives the same code path
    deterministically: the pre-check is made to report "no row yet" once
    (simulating the race window), the second request's INSERT is made to
    raise the same IntegrityError the real unique index would raise for a
    genuine concurrent duplicate, and a "winning" row — standing in for
    what a concurrent request would have already committed — is resolved
    to and returned, while this request's own now-orphaned object is
    cleaned up.
    """
    from sqlalchemy.exc import IntegrityError

    from app.repositories import media_repository
    from app.services import media_service

    user_id = uuid.uuid4()

    winning_asset = media_repository.create(
        db_session,
        user_id=user_id,
        media_type="image",
        original_filename="winner.png",
        object_key="image/winner/already-committed.png",
        content_type="image/png",
        file_size=5,
        duration_seconds=None,
        legacy_source="image:race",
        legacy_created_at=None,
    )
    db_session.commit()

    real_lookup = media_repository.get_by_user_and_legacy_source
    lookup_calls = {"count": 0}

    def _pre_check_misses_then_finds_winner(db, *, user_id, legacy_source):
        lookup_calls["count"] += 1
        if lookup_calls["count"] == 1:
            return None  # the pre-check: simulates the race window (no row yet)
        return real_lookup(db, user_id=user_id, legacy_source=legacy_source)

    monkeypatch.setattr(media_repository, "get_by_user_and_legacy_source", _pre_check_misses_then_finds_winner)

    def _insert_loses_the_race(*args, **kwargs):
        raise IntegrityError("insert", {}, Exception("UNIQUE constraint failed: media_assets.user_id, media_assets.legacy_source"))

    monkeypatch.setattr(media_repository, "create", _insert_loses_the_race)

    result = media_service.upload_media(
        db_session,
        storage,
        user_id=user_id,
        data=b"loser bytes",
        content_type="image/png",
        original_filename="loser.png",
        duration_seconds=None,
        legacy_source="image:race",
        legacy_created_at=None,
    )

    assert result.id == winning_asset.id  # resolved to the winner, not a 409/500
    # the loser's own uploaded object was compensated away; the winner's
    # object_key was never actually written to this fake bucket by this
    # test, so zero remaining objects is direct evidence of that cleanup.
    assert storage.count() == 0


def test_migration_upgrade_and_downgrade_add_legacy_source(tmp_path, monkeypatch):
    """
    Test 22: runs the ACTUAL Alembic migration chain (not
    Base.metadata.create_all(), which every other test in this suite uses
    per tests/conftest.py's documented Phase 1 trade-off) against a
    throwaway SQLite file, verifying this migration's upgrade() adds
    exactly the expected column/index shape — including that the partial
    unique index really does allow multiple NULLs and really does reject
    a duplicate non-null legacy_source — and that downgrade() removes
    everything it added, cleanly.
    """
    from pathlib import Path

    from alembic import command
    from alembic.config import Config
    from sqlalchemy import create_engine, inspect, text

    from app.core.config import settings

    db_path = tmp_path / "phase14ib_migration_test.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setattr(settings, "database_url", db_url)

    backend_dir = Path(__file__).resolve().parent.parent
    alembic_cfg = Config(str(backend_dir / "alembic.ini"))
    alembic_cfg.set_main_option("script_location", str(backend_dir / "alembic"))

    command.upgrade(alembic_cfg, "head")

    engine = create_engine(db_url)
    inspector = inspect(engine)
    columns = {c["name"] for c in inspector.get_columns("media_assets")}
    assert "legacy_source" in columns
    assert "legacy_created_at" in columns
    assert any(
        ix["name"] == "uq_media_assets_user_id_legacy_source" and ix["unique"]
        for ix in inspector.get_indexes("media_assets")
    )

    # Multiple NULLs must remain valid; a duplicate non-null legacy_source
    # for the same user must be rejected at the database level.
    with engine.begin() as conn:
        user_id = uuid.uuid4().hex
        base_cols = "id, user_id, media_type, object_key, content_type, file_size, legacy_source"
        conn.execute(
            text(f"INSERT INTO media_assets ({base_cols}) VALUES (:id, :uid, 'image', :key, 'image/png', 1, NULL)"),
            {"id": uuid.uuid4().hex, "uid": user_id, "key": "k1"},
        )
        conn.execute(
            text(f"INSERT INTO media_assets ({base_cols}) VALUES (:id, :uid, 'image', :key, 'image/png', 1, NULL)"),
            {"id": uuid.uuid4().hex, "uid": user_id, "key": "k2"},
        )
        conn.execute(
            text(
                f"INSERT INTO media_assets ({base_cols}) VALUES (:id, :uid, 'image', :key, 'image/png', 1, 'image:mig')"
            ),
            {"id": uuid.uuid4().hex, "uid": user_id, "key": "k3"},
        )
        with pytest.raises(Exception):
            conn.execute(
                text(
                    f"INSERT INTO media_assets ({base_cols}) VALUES (:id, :uid, 'image', :key, 'image/png', 1, 'image:mig')"
                ),
                {"id": uuid.uuid4().hex, "uid": user_id, "key": "k4"},
            )
    engine.dispose()

    # Targets this migration's own revision explicitly rather than a
    # relative "-1" — PHASE14I-G.1 added a new migration on top of this
    # one, so "-1" from head no longer lands here; an explicit target
    # keeps this test correct regardless of how many migrations are later
    # stacked on top of the one it actually exercises.
    command.downgrade(alembic_cfg, "a7b8c9d0e1f2")

    engine = create_engine(db_url)
    inspector = inspect(engine)
    columns_after_downgrade = {c["name"] for c in inspector.get_columns("media_assets")}
    assert "legacy_source" not in columns_after_downgrade
    assert "legacy_created_at" not in columns_after_downgrade
    engine.dispose()


# --- PHASE14I-G.1: SHA-256 content-integrity checksum ---

_SHA256_HEX_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def test_checksum_is_calculated_from_exact_uploaded_bytes(client: TestClient):
    content = b"the exact bytes this test uploads"
    headers = register_and_get_headers(client, "checksum1@example.com")

    response = _upload(client, headers, content=content)

    assert response.status_code == 201
    assert response.json()["checksum_sha256"] == hashlib.sha256(content).hexdigest()


def test_known_byte_sequence_produces_expected_sha256(client: TestClient):
    # A fixed, hand-verifiable input/output pair rather than only comparing
    # against hashlib's own output (which test_checksum_is_calculated_from_
    # exact_uploaded_bytes already does) — this pins the exact algorithm.
    content = b"hello world"
    expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
    assert hashlib.sha256(content).hexdigest() == expected  # sanity: the pin itself is correct

    headers = register_and_get_headers(client, "checksum2@example.com")
    response = _upload(client, headers, content=content)

    assert response.json()["checksum_sha256"] == expected


def test_stored_db_checksum_equals_expected_sha256(client: TestClient, db_session):
    from app.models.media_asset import MediaAsset

    content = b"verify the actual database row, not just the response"
    headers = register_and_get_headers(client, "checksum3@example.com")
    created_id = _upload(client, headers, content=content).json()["id"]

    row = db_session.get(MediaAsset, uuid.UUID(created_id))
    assert row.checksum_sha256 == hashlib.sha256(content).hexdigest()


def test_upload_response_contains_checksum_sha256(client: TestClient):
    headers = register_and_get_headers(client, "checksum4@example.com")

    response = _upload(client, headers)

    assert "checksum_sha256" in response.json()


def test_list_media_returns_checksum_sha256(client: TestClient):
    content = b"listed item bytes"
    headers = register_and_get_headers(client, "checksum5@example.com")
    _upload(client, headers, content=content)

    response = client.get("/media", headers=headers)

    assert response.json()["items"][0]["checksum_sha256"] == hashlib.sha256(content).hexdigest()


def test_get_media_detail_returns_checksum_sha256(client: TestClient):
    content = b"detail item bytes"
    headers = register_and_get_headers(client, "checksum6@example.com")
    created = _upload(client, headers, content=content).json()

    response = client.get(f"/media/{created['id']}", headers=headers)

    assert response.json()["checksum_sha256"] == hashlib.sha256(content).hexdigest()


def test_two_different_files_produce_different_checksums(client: TestClient):
    headers = register_and_get_headers(client, "checksum7@example.com")

    first = _upload(client, headers, content=b"file one contents").json()
    second = _upload(client, headers, content=b"file two contents, different").json()

    assert first["checksum_sha256"] != second["checksum_sha256"]


def test_same_bytes_produce_the_same_checksum(client: TestClient):
    content = b"identical bytes uploaded twice, as two separate normal uploads"
    headers = register_and_get_headers(client, "checksum8@example.com")

    first = _upload(client, headers, filename="a.png", content=content).json()
    second = _upload(client, headers, filename="b.png", content=content).json()

    assert first["id"] != second["id"]  # two distinct, unrelated uploads
    assert first["checksum_sha256"] == second["checksum_sha256"]


def test_empty_file_behaves_per_existing_validation_with_no_checksum_side_effect(
    client: TestClient, storage
):
    headers = register_and_get_headers(client, "checksum9@example.com")

    response = _upload(client, headers, content=b"")

    assert response.status_code == 415  # unchanged from existing behavior (test_empty_file_is_rejected)
    assert storage.count() == 0
    assert client.get("/media", headers=headers).json()["total"] == 0


def test_existing_row_with_null_checksum_remains_readable(client: TestClient, db_session):
    """
    Simulates a row created before PHASE14I-G.1 (checksum_sha256 always
    NULL for those, by design — see the implementation report's
    "Historical-row behavior") by inserting one directly, bypassing the
    upload path entirely, then confirming the read endpoints still work.
    """
    from app.models.media_asset import MediaAsset
    from app.repositories import user_repository

    headers = register_and_get_headers(client, "checksum10@example.com")
    user = user_repository.get_by_email(db_session, "checksum10@example.com")

    pre_existing = MediaAsset(
        user_id=user.id,
        media_type="image",
        object_key="image/pre-existing/legacy.png",
        content_type="image/png",
        file_size=10,
        checksum_sha256=None,
    )
    db_session.add(pre_existing)
    db_session.commit()

    list_response = client.get("/media", headers=headers)
    assert list_response.status_code == 200
    assert list_response.json()["items"][0]["checksum_sha256"] is None

    detail_response = client.get(f"/media/{pre_existing.id}", headers=headers)
    assert detail_response.status_code == 200
    assert detail_response.json()["checksum_sha256"] is None


def test_legacy_source_duplicate_prevention_still_works_with_checksum_added(client: TestClient, storage):
    headers = register_and_get_headers(client, "checksum11@example.com")

    first = _upload(client, headers, legacy_source="image:checksum-dup").json()
    second = _upload(client, headers, legacy_source="image:checksum-dup").json()

    assert first["id"] == second["id"]
    assert storage.count() == 1
    assert client.get("/media", headers=headers).json()["total"] == 1


def test_upload_storage_failure_creates_no_row_and_no_checksum(client: TestClient, storage, monkeypatch):
    headers = register_and_get_headers(client, "checksum12@example.com")

    def _always_fail(*args, **kwargs):
        raise StorageError("simulated storage outage")

    monkeypatch.setattr(storage, "upload", _always_fail)

    response = _upload(client, headers)

    assert response.status_code == 502
    assert storage.count() == 0
    assert client.get("/media", headers=headers).json()["total"] == 0


def test_db_failure_after_storage_upload_still_compensates_with_checksum_present(
    db_session, storage, monkeypatch
):
    """
    Re-verifies the existing orphan-cleanup compensation (see
    test_upload_media_cleans_up_orphaned_object_on_db_failure) is not
    weakened by this phase's addition of a new `checksum_sha256` keyword
    argument to media_repository.create.
    """
    from app.repositories import media_repository
    from app.services import media_service
    from sqlalchemy.exc import SQLAlchemyError

    def _always_fail(*args, **kwargs):
        raise SQLAlchemyError("simulated DB outage")

    monkeypatch.setattr(media_repository, "create", _always_fail)

    with pytest.raises(SQLAlchemyError):
        media_service.upload_media(
            db_session,
            storage,
            user_id=uuid.uuid4(),
            data=b"some bytes",
            content_type="image/png",
            original_filename="x.png",
            duration_seconds=None,
        )

    assert storage.count() == 0  # the object was compensated away, not left orphaned


def test_jwt_ownership_still_enforced_for_checksum_bearing_media(client: TestClient):
    owner_headers = register_and_get_headers(client, "checksum13owner@example.com")
    other_headers = register_and_get_headers(client, "checksum13other@example.com")
    created = _upload(client, owner_headers, content=b"owner-only bytes").json()

    response = client.get(f"/media/{created['id']}", headers=other_headers)

    assert response.status_code == 404  # same IDOR-resistant 404, unaffected by the new field


def test_object_key_not_exposed_alongside_checksum(client: TestClient):
    headers = register_and_get_headers(client, "checksum14@example.com")
    created = _upload(client, headers).json()

    detail = client.get(f"/media/{created['id']}", headers=headers).json()

    assert "checksum_sha256" in created
    assert "object_key" not in created
    assert "checksum_sha256" in detail
    assert "object_key" not in detail


def test_no_filesystem_path_exposed_in_upload_or_detail_response(client: TestClient):
    headers = register_and_get_headers(client, "checksum15@example.com")
    created = _upload(client, headers, filename="my_photo.png").json()

    detail = client.get(f"/media/{created['id']}", headers=headers).json()

    for body in (created, detail):
        for key, value in body.items():
            if isinstance(value, str):
                assert not value.startswith("/"), f"{key!r} looks like a filesystem path: {value!r}"
                assert "\\" not in value, f"{key!r} looks like a Windows filesystem path: {value!r}"


def test_checksum_is_exactly_64_lowercase_hex_characters(client: TestClient):
    headers = register_and_get_headers(client, "checksum16@example.com")

    response = _upload(client, headers)

    checksum = response.json()["checksum_sha256"]
    assert _SHA256_HEX_PATTERN.match(checksum), f"not a 64-char lowercase hex string: {checksum!r}"


def test_checksum_is_not_derived_from_filename_or_title(client: TestClient):
    content = b"identical bytes, wildly different filenames and titles"
    headers = register_and_get_headers(client, "checksum17@example.com")

    first = _upload(client, headers, filename="alpha.png", content=content).json()
    second = _upload(client, headers, filename="totally-different-name.png", content=content).json()
    client.patch(f"/media/{second['id']}", json={"title": "A completely different title"}, headers=headers)
    second_after_rename = client.get(f"/media/{second['id']}", headers=headers).json()

    assert first["checksum_sha256"] == second["checksum_sha256"] == second_after_rename["checksum_sha256"]


def test_checksum_calculated_before_storage_persistence_from_exact_captured_bytes(db_session, storage):
    """
    Wraps the storage fake's own `upload` to capture exactly the bytes
    handed to it, proving the persisted `checksum_sha256` is the SHA-256
    of THOSE bytes — not of the multipart wrapper, metadata, or anything
    reconstructed after the fact. `BytesIO.getvalue()` doesn't disturb the
    stream's read position, so the real (wrapped) upload still receives
    the identical, unconsumed fileobj afterward.
    """
    from app.services import media_service

    captured: dict = {}
    original_upload = storage.upload

    def _capturing_upload(*, object_key, fileobj, content_type):
        captured["bytes"] = fileobj.getvalue()
        return original_upload(object_key=object_key, fileobj=fileobj, content_type=content_type)

    storage.upload = _capturing_upload

    content = b"the precise bytes that must reach both storage and the checksum"
    asset = media_service.upload_media(
        db_session,
        storage,
        user_id=uuid.uuid4(),
        data=content,
        content_type="image/png",
        original_filename="a.png",
        duration_seconds=None,
    )

    assert captured["bytes"] == content
    expected = hashlib.sha256(captured["bytes"]).hexdigest()
    assert asset.checksum_sha256 == expected
    assert hashlib.sha256(content).hexdigest() == expected  # the checksum matches the ORIGINAL bytes too


def test_migration_upgrade_and_downgrade_add_checksum_sha256(tmp_path, monkeypatch):
    """
    Runs the ACTUAL Alembic migration chain (see
    test_migration_upgrade_and_downgrade_add_legacy_source's own doc for
    why this suite does that instead of relying on
    Base.metadata.create_all() here) against a throwaway SQLite file,
    verifying this migration's upgrade() adds `checksum_sha256` and its
    length CHECK constraint, that the constraint actually rejects a
    too-short value while allowing NULL and a genuine 64-character one,
    and that downgrade() removes everything it added — including that
    batch-mode's SQLite table-recreate strategy preserves existing rows.
    """
    from pathlib import Path

    from alembic import command
    from alembic.config import Config
    from sqlalchemy import create_engine, inspect, text

    from app.core.config import settings

    db_path = tmp_path / "phase14ig1_migration_test.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setattr(settings, "database_url", db_url)

    backend_dir = Path(__file__).resolve().parent.parent
    alembic_cfg = Config(str(backend_dir / "alembic.ini"))
    alembic_cfg.set_main_option("script_location", str(backend_dir / "alembic"))

    command.upgrade(alembic_cfg, "head")

    engine = create_engine(db_url)
    inspector = inspect(engine)
    columns = {c["name"] for c in inspector.get_columns("media_assets")}
    assert "checksum_sha256" in columns

    user_id = uuid.uuid4().hex
    base_cols = "id, user_id, media_type, object_key, content_type, file_size, checksum_sha256"
    with engine.begin() as conn:
        conn.execute(
            text(f"INSERT INTO media_assets ({base_cols}) VALUES (:id, :uid, 'image', :key, 'image/png', 1, NULL)"),
            {"id": uuid.uuid4().hex, "uid": user_id, "key": "k1"},
        )
        conn.execute(
            text(
                f"INSERT INTO media_assets ({base_cols}) VALUES (:id, :uid, 'image', :key, 'image/png', 1, :sum)"
            ),
            {"id": uuid.uuid4().hex, "uid": user_id, "key": "k2", "sum": "a" * 64},
        )
        with pytest.raises(Exception):
            conn.execute(
                text(
                    f"INSERT INTO media_assets ({base_cols}) VALUES (:id, :uid, 'image', :key, 'image/png', 1, :sum)"
                ),
                {"id": uuid.uuid4().hex, "uid": user_id, "key": "k3", "sum": "too-short"},
            )
    engine.dispose()

    # Explicit target, not a relative "-1" — see the same reasoning in
    # test_migration_upgrade_and_downgrade_add_legacy_source, now applied
    # to this migration's own down_revision.
    command.downgrade(alembic_cfg, "b8c9d0e1f2a3")

    engine = create_engine(db_url)
    inspector = inspect(engine)
    columns_after_downgrade = {c["name"] for c in inspector.get_columns("media_assets")}
    assert "checksum_sha256" not in columns_after_downgrade
    with engine.connect() as conn:
        # batch-mode's recreate-table strategy must preserve existing rows.
        assert conn.execute(text("SELECT COUNT(*) FROM media_assets")).scalar_one() == 2
    engine.dispose()
