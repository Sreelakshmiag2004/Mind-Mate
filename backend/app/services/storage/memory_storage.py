"""
Used only by the test suite (`storage_provider="memory"`, wired in
tests/conftest.py) so tests never depend on a running MinIO/S3 — see the
task's own instruction not to make tests depend on an unavailable external
service. Stores bytes in a plain dict; a "presigned URL" is a fake,
deterministic string, never meant to be fetched.

This is also the concrete evidence for the storage abstraction actually
doing its job: `media_service.py` is written only against
`ObjectStorageService`, so swapping this in for `S3StorageService` in
tests requires touching zero business logic — only a dependency override.
"""

from typing import BinaryIO, Dict

from app.services.storage.base import ObjectStorageService


class InMemoryStorageService(ObjectStorageService):
    def __init__(self) -> None:
        self._objects: Dict[str, bytes] = {}

    def upload(self, *, object_key: str, fileobj: BinaryIO, content_type: str) -> None:
        self._objects[object_key] = fileobj.read()

    def delete(self, *, object_key: str) -> None:
        self._objects.pop(object_key, None)  # idempotent, matching ObjectStorageService's contract

    def generate_presigned_download_url(self, *, object_key: str, expires_in_seconds: int) -> str:
        return f"memory://{object_key}?expires_in={expires_in_seconds}"

    # Test-only inspection helpers — not part of the ObjectStorageService
    # interface, so production code can never call them.
    def object_exists(self, object_key: str) -> bool:
        return object_key in self._objects

    def get_object_bytes(self, object_key: str) -> bytes:
        return self._objects[object_key]

    def clear(self) -> None:
        """Reset between tests so objects never leak from one test into the next."""
        self._objects.clear()

    def count(self) -> int:
        return len(self._objects)
