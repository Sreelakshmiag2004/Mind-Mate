"""
Test configuration.

Tests exercise the exact same model/route/service code as production,
against a throwaway **SQLite** database instead of PostgreSQL. This is a
deliberate, documented trade-off for Phase 1 (see backend/README.md,
"Running tests"): this sandbox/CI environment cannot assume a live
PostgreSQL server is reachable, and the only PostgreSQL-specific type
used anywhere in the schema (`GUID`) was written specifically to be
dialect-portable for this reason (see app/models/base.py). Nothing else
in the schema is Postgres-specific for Phase 1.

`Base.metadata.create_all()` is used here — and ONLY here. Production
schema changes always go through Alembic (see backend/README.md).
"""

import os
import uuid

# Required settings must exist in the environment before `app.core.config`
# is ever imported (Pydantic Settings reads them at import time).
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_mindmate.db")
os.environ.setdefault("JWT_SECRET_KEY", f"test-secret-{uuid.uuid4()}")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "15")
os.environ.setdefault("REFRESH_TOKEN_EXPIRE_DAYS", "30")
os.environ.setdefault("CORS_ORIGINS", "http://localhost:3000")
# Required (no default in Settings — see app/core/config.py) but never
# actually dialed: tests always run with STORAGE_PROVIDER effectively
# overridden to the in-memory fake below via a dependency override, never
# a real S3/MinIO endpoint. These values exist purely so Settings()
# validates.
os.environ.setdefault("S3_ENDPOINT_URL", "http://unused.invalid:9000")
os.environ.setdefault("S3_ACCESS_KEY", "unused")
os.environ.setdefault("S3_SECRET_KEY", "unused")
os.environ.setdefault("S3_BUCKET_NAME", "unused-test-bucket")
# Same treatment as the S3_* block above: required by Settings (no
# default — see app/core/config.py) but never actually dialed. Tests
# always run with get_ai_provider overridden to MockAIReflectionProvider
# below, never a real Anthropic API call, so this value only needs to
# exist for Settings() to validate.
os.environ.setdefault("AI_API_KEY", "unused-test-key")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import get_db
from app.main import app
from app.models import Base
from app.models.checklist import ChecklistItem
from app.services.ai import get_ai_provider
from app.services.ai.mock_provider import MockAIReflectionProvider
from app.services.storage import get_storage_service
from app.services.storage.memory_storage import InMemoryStorageService

# In-memory SQLite, one connection shared across the whole test session
# via StaticPool so every request in a test sees the same schema/data.
_engine = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
_TestingSessionLocal = sessionmaker(bind=_engine, autoflush=False, autocommit=False, future=True)

# Mirrors the seed data in
# alembic/versions/b2c3d4e5f6a7_create_journals_moods_checklists.py.
# Duplicated here (rather than imported) because Alembic version files
# aren't meant to be imported as application modules — kept in sync
# manually; a drift here would only affect which fixture ids tests use,
# never production data. See backend/README.md, "Design decisions".
_TEST_CHECKLIST_ITEMS = [
    {"label": "Drank enough water 💧", "sort_order": 0},
    {"label": "Slept well last night 🛌", "sort_order": 1},
    {"label": "Did one thing just for me 😉", "sort_order": 2},
    {"label": "Got some fresh air and sunlight 🏝️", "sort_order": 3},
    {"label": "Exercised well 🧘‍♂️", "sort_order": 4},
]


def _override_get_db():
    db = _TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = _override_get_db

# One shared in-memory "bucket" for the whole test session — real enough to
# assert against ("was this object actually written / actually removed?")
# without any test ever depending on a running MinIO/S3. See
# app/services/storage/memory_storage.py and backend/README.md.
_test_storage = InMemoryStorageService()
app.dependency_overrides[get_storage_service] = lambda: _test_storage

# Same pattern for Phase 5: a shared MockAIReflectionProvider so tests can
# both assert on what it was asked to generate (`.calls`) and simulate a
# provider failure (`.next_error`) without ever depending on a real
# Anthropic API key or network access. See app/services/ai/mock_provider.py.
_test_ai_provider = MockAIReflectionProvider()
app.dependency_overrides[get_ai_provider] = lambda: _test_ai_provider


@pytest.fixture(autouse=True)
def _fresh_schema():
    """Recreate all tables — and empty the fake bucket/AI provider state — before every test so tests never leak state."""
    Base.metadata.drop_all(bind=_engine)
    Base.metadata.create_all(bind=_engine)
    _test_storage.clear()
    _test_ai_provider.reset()

    db = _TestingSessionLocal()
    try:
        for row in _TEST_CHECKLIST_ITEMS:
            db.add(ChecklistItem(label=row["label"], sort_order=row["sort_order"]))
        db.commit()
    finally:
        db.close()

    yield


@pytest.fixture()
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture()
def storage() -> InMemoryStorageService:
    """The same fake bucket the app is using, for tests to assert against directly."""
    return _test_storage


@pytest.fixture()
def ai_provider() -> MockAIReflectionProvider:
    """The same mock AI provider the app is using, for tests to assert against or configure `.next_error` on."""
    return _test_ai_provider


@pytest.fixture()
def db_session():
    """
    A raw session on the same test database, for the handful of tests that
    exercise a service function directly (e.g. simulating a DB failure
    mid-upload) rather than going through the HTTP API.
    """
    db = _TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


def register_and_get_headers(client: TestClient, email: str, password: str = "correcthorse1") -> dict:
    """
    Test helper, not a pytest fixture (it needs a per-call email) — used
    by test_journals.py/test_moods.py/test_checklists.py to get a ready
    `Authorization` header for a brand-new user in one line.
    """
    response = client.post("/auth/register", json={"email": email, "password": password})
    assert response.status_code == 201, response.text
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
