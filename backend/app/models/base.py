"""
Declarative base, plus two small building blocks shared by every model:

`GUID` is a cross-dialect UUID column type: on PostgreSQL (the only
production target for this backend) it stores a native `UUID`; on any
other dialect it falls back to a 32-char hex string. Production and
Alembic only ever run against PostgreSQL — the fallback exists solely so
this exact model/migration code can also be exercised against SQLite in
automated tests without a running Postgres instance (see
`tests/conftest.py`). No application code branches on which dialect is
in use; only this type does.

`TimestampMixin` adds `created_at`/`updated_at` with server-side defaults,
so the timestamp is authoritative from the database's clock, not the
application server's.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, func
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import CHAR, TypeDecorator


class Base(DeclarativeBase):
    pass


class GUID(TypeDecorator):
    """Platform-independent UUID type. See module docstring."""

    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PG_UUID(as_uuid=True))
        return dialect.type_descriptor(CHAR(32))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        if dialect.name == "postgresql":
            return str(value)
        if not isinstance(value, uuid.UUID):
            value = uuid.UUID(str(value))
        return value.hex

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        if isinstance(value, uuid.UUID):
            return value
        return uuid.UUID(value)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
