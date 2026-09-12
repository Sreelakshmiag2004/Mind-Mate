"""
Request/response shapes for `/scheduler/{entry_date}` — see
app/models/scheduler.py for why `scheduled_time` is a plain `"HH:MM"`
string rather than a `time`/`datetime` field, and app/services/
scheduler_service.py for where cross-row duplicate-time detection actually
lives (deliberately the service layer, not a validator here — see that
module's docstring).
"""

import re
import uuid
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

# Exactly HH:MM, 24-hour: hour 00-23, minute 00-59. Anchored on both ends
# so "9:00" (missing leading zero), "09:00:00", or trailing/leading
# whitespace are all rejected rather than silently accepted.
_TIME_PATTERN = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


class SchedulerEntryInput(BaseModel):
    """One row of a PUT /scheduler/{entry_date} request body."""

    scheduled_time: str = Field(description="24-hour wall-clock time, exactly HH:MM (e.g. '09:00', '23:45')")
    description: Optional[str] = Field(default=None, max_length=500)

    @field_validator("scheduled_time")
    @classmethod
    def _validate_time_format(cls, value: str) -> str:
        if not _TIME_PATTERN.match(value):
            raise ValueError("scheduled_time must be exactly HH:MM in 24-hour format (e.g. '09:00', '23:45')")
        return value


class SchedulerEntryRead(BaseModel):
    """One saved row, as returned inside a SchedulerDayRead."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entry_date: date
    scheduled_time: str
    description: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class SchedulerDayRead(BaseModel):
    """
    The full response of both GET and PUT /scheduler/{entry_date} — every
    row currently saved for that date, ordered by scheduled_time (see
    app/repositories/scheduler_repository.py). An empty `items` list means
    nothing is scheduled for that date; it is never an error.
    """

    entry_date: date
    items: List[SchedulerEntryRead]


class SchedulerDayUpdate(BaseModel):
    """
    PUT /scheduler/{entry_date} request body — `rows` is this user's
    COMPLETE schedule for that date after the call: whole-day replacement,
    not a per-row patch (see app/services/scheduler_service.py). A row
    from the previous save that isn't included here is deleted; `rows: []`
    clears the day entirely. `rows` is required (not optional/defaulted)
    so a caller must explicitly say "clear this day" rather than that
    happening as a side effect of omitting the field.
    """

    rows: List[SchedulerEntryInput]
