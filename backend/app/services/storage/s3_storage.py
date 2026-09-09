"""
The only file in this codebase that imports boto3. Works unchanged
against MinIO (set S3_ENDPOINT_URL to MinIO's address) or real AWS S3
(leave S3_ENDPOINT_URL pointed at AWS, or unset it) — boto3's S3 client is
the same client either way; only `.env` changes.
"""

from typing import BinaryIO

import boto3
from botocore.client import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.core.exceptions import StorageError
from app.services.storage.base import ObjectStorageService


class S3StorageService(ObjectStorageService):
    def __init__(self, *, endpoint_url: str, access_key: str, secret_key: str, bucket_name: str, region: str):
        self._bucket = bucket_name
        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=region,
            # MinIO requires SigV4; explicit so this doesn't silently
            # depend on whatever boto3 happens to default to. Timeouts are
            # bounded and retries disabled so a MinIO/S3 outage surfaces as
            # a prompt 502 (via StorageError) instead of the request
            # hanging for botocore's much longer defaults — found during
            # this phase's own live verification (see backend/README.md,
            # "Problems encountered").
            config=Config(signature_version="s3v4", connect_timeout=5, read_timeout=10, retries={"max_attempts": 1}),
        )

    def upload(self, *, object_key: str, fileobj: BinaryIO, content_type: str) -> None:
        try:
            self._client.upload_fileobj(
                fileobj, self._bucket, object_key, ExtraArgs={"ContentType": content_type}
            )
        except (BotoCoreError, ClientError) as exc:
            raise StorageError(f"Failed to upload object {object_key!r}: {exc}") from exc

    def delete(self, *, object_key: str) -> None:
        try:
            # S3's DeleteObject is itself idempotent (no error on a
            # missing key), which is exactly the semantic base.py requires.
            self._client.delete_object(Bucket=self._bucket, Key=object_key)
        except (BotoCoreError, ClientError) as exc:
            raise StorageError(f"Failed to delete object {object_key!r}: {exc}") from exc

    def generate_presigned_download_url(self, *, object_key: str, expires_in_seconds: int) -> str:
        try:
            return self._client.generate_presigned_url(
                "get_object",
                Params={"Bucket": self._bucket, "Key": object_key},
                ExpiresIn=expires_in_seconds,
            )
        except (BotoCoreError, ClientError) as exc:
            raise StorageError(f"Failed to sign a download URL for {object_key!r}: {exc}") from exc
