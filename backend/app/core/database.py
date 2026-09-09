"""
SQLAlchemy engine/session wiring.

This module intentionally exposes only `engine`, `SessionLocal`, and the
`get_db` FastAPI dependency. Schema creation is NOT performed here —
production schema management is Alembic's job (see `alembic/`). Tests
build their own throwaway schema against SQLite (see `tests/conftest.py`)
using the same models, without touching this module's engine.
"""

from typing import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

# `pool_pre_ping` avoids handing out dead connections after the DB
# restarts or an idle connection is dropped by a proxy/firewall.
engine = create_engine(settings.database_url, pool_pre_ping=True, future=True)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency yielding a request-scoped DB session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
