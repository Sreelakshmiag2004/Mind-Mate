"""
The one interface `media_service.py` is written against. Nothing outside
`app/services/storage/` ever imports boto3 (or any other provider SDK)
directly — that's what makes "replace MinIO with AWS S3, or something
else entirely, without rewriting business logic" true rather than
aspirational: the business logic only ever calls these three methods.
"""

from abc import ABC, abstractmethod
from typing import BinaryIO


class ObjectStorageService(ABC):
    @abstractmethod
    def upload(self, *, object_key: str, fileobj: BinaryIO, content_type: str) -> None:
        """Upload `fileobj`'s contents to `object_key`. Raises StorageError on failure."""

    @abstractmethod
    def delete(self, *, object_key: str) -> None:
        """
        Delete the object at `object_key`. Deleting a key that doesn't
        exist is NOT an error (idempotent) — a retried delete, or a delete
        following a previous partial failure, must not itself fail.
        """

    @abstractmethod
    def generate_presigned_download_url(self, *, object_key: str, expires_in_seconds: int) -> str:
        """A time-limited URL the client can use to fetch the object directly, bypassing this API."""
