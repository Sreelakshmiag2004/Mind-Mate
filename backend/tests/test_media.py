import io
import uuid

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
