"""
The single place that decides WHICH ObjectStorageService implementation
is live, based on `settings.storage_provider`. Everything else — routes,
services — depends on `get_storage_service` (a FastAPI dependency), never
on `S3StorageService` directly, so tests can override this one function
(see tests/conftest.py) and get the in-memory implementation everywhere
without touching route/service code.
"""

from functools import lru_cache

from app.core.config import settings
from app.services.storage.base import ObjectStorageService
from app.services.storage.s3_storage import S3StorageService


@lru_cache
def _s3_singleton() -> S3StorageService:
    # One boto3 client for the process lifetime — cheap to construct, but
    # no reason to rebuild it on every request.
    return S3StorageService(
        endpoint_url=settings.s3_endpoint_url,
        access_key=settings.s3_access_key,
        secret_key=settings.s3_secret_key,
        bucket_name=settings.s3_bucket_name,
        region=settings.s3_region,
    )


def get_storage_service() -> ObjectStorageService:
    if settings.storage_provider == "s3":
        return _s3_singleton()
    raise RuntimeError(
        f"Unknown STORAGE_PROVIDER {settings.storage_provider!r} — expected 's3' "
        "('memory' is test-only and is wired via a dependency override, never this setting)."
    )
