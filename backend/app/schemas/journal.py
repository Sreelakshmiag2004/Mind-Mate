import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class JournalCreate(BaseModel):
    entry_date: date
    title: Optional[str] = Field(default=None, max_length=200)
    content: Optional[str] = Field(default=None, max_length=20_000)


class JournalUpdate(BaseModel):
    """All fields optional — PATCH semantics; only provided fields change."""

    entry_date: Optional[date] = None
    title: Optional[str] = Field(default=None, max_length=200)
    content: Optional[str] = Field(default=None, max_length=20_000)


class JournalRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    entry_date: date
    title: Optional[str] = None
    content: Optional[str] = None
    created_at: datetime
    updated_at: datetime
