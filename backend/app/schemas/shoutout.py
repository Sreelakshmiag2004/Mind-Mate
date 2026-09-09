import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class ShoutoutCreate(BaseModel):
    entry_date: date
    title: Optional[str] = Field(default=None, max_length=200)
    content: Optional[str] = Field(default=None, max_length=20_000)


class ShoutoutUpdate(BaseModel):
    """PATCH semantics — only provided fields change. Does not touch felt_better; see ShoutoutFeelBetterRequest."""

    entry_date: Optional[date] = None
    title: Optional[str] = Field(default=None, max_length=200)
    content: Optional[str] = Field(default=None, max_length=20_000)


class ShoutoutFeelBetterRequest(BaseModel):
    felt_better: bool


class ShoutoutRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    entry_date: date
    title: Optional[str] = None
    content: Optional[str] = None
    felt_better: Optional[bool] = None
    felt_better_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
