import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


class MoodCreate(BaseModel):
    entry_date: date
    mood_value: int = Field(ge=0, le=100, description="0-100, matching the app's existing percent scale")


class MoodUpdate(BaseModel):
    entry_date: date | None = None
    mood_value: int | None = Field(default=None, ge=0, le=100)


class MoodRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    entry_date: date
    mood_value: int
    created_at: datetime
    updated_at: datetime
