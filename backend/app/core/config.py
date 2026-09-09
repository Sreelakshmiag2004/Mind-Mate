"""
Centralized, environment-driven configuration.

Every secret and every environment-specific value (DB URL, JWT secret,
token lifetimes, CORS origins) is read from the environment (or a local
`.env` file for development) — nothing is hard-coded. See `.env.example`
for the full list of variables and their meaning.
"""

from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- Environment ---
    environment: str = "development"

    # --- Database ---
    database_url: str

    # --- JWT ---
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    # --- Relationship invitations (Phase 4) ---
    # How long a shared invite link/token stays acceptable. Not driven by
    # anything in the old app (its "invite link" never expired at all —
    # see app/models/relationship_invitation.py) — a week is a reasonable,
    # explicit default for a link that's typically shared and opened
    # within minutes to days of being created.
    invitation_expire_days: int = 7

    # --- CORS ---
    # Stored as a raw comma-separated string in the environment; exposed
    # to the app as a parsed list via `cors_origins_list`.
    cors_origins: str = "http://localhost:3000"

    # --- Object storage (Phase 3: media/voice notes) ---
    # "s3" talks to any S3-compatible endpoint (MinIO locally, AWS S3 in
    # production) via the same boto3 client — only the endpoint/credentials
    # below change between them, so swapping providers later never touches
    # app/services/media_service.py. "memory" is used by the test suite
    # (see tests/conftest.py) so tests never depend on a running MinIO/S3
    # — see backend/README.md, "Object storage architecture".
    #
    # No default is given for the endpoint, credentials, or bucket name —
    # same treatment as `database_url`/`jwt_secret_key` above: these are
    # environment-specific and must come from `.env`/the environment, never
    # from a value baked into this file. Only `.env.example` shows example
    # values (MinIO's well-known local-dev defaults), never this class.
    storage_provider: str = "s3"
    s3_endpoint_url: str
    s3_access_key: str
    s3_secret_key: str
    s3_bucket_name: str
    s3_region: str = "us-east-1"
    max_upload_size_mb: int = 25

    @property
    def cors_origins_list(self) -> List[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def max_upload_size_bytes(self) -> int:
        return self.max_upload_size_mb * 1024 * 1024

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"


@lru_cache
def get_settings() -> Settings:
    """
    Cached settings accessor. Using a function (rather than a bare
    module-level instance) makes it trivial for tests to override
    settings by clearing the cache after monkeypatching environment
    variables.
    """
    return Settings()


settings = get_settings()
