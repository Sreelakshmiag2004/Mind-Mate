import uuid
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class ChecklistItemRead(BaseModel):
    """One row of the global task catalog (today: the 5 fixed wellness items)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    label: str
    sort_order: int


class ChecklistItemState(BaseModel):
    """One item's completion state on a specific date."""

    item_id: uuid.UUID
    label: str
    sort_order: int
    completed: bool
    completed_at: Optional[datetime] = None


class ChecklistDayRead(BaseModel):
    """
    The full day's checklist — every catalog item plus its completion
    state, defaulting to `completed=False` for items that have never been
    toggled on that date (see app/models/checklist.py: rows are only
    created on first toggle, not pre-materialized).
    """

    entry_date: date
    items: List[ChecklistItemState]
    completed_count: int
    total_count: int


class ChecklistCompletionInput(BaseModel):
    item_id: uuid.UUID
    completed: bool


class ChecklistDayUpdate(BaseModel):
    completions: List[ChecklistCompletionInput] = Field(min_length=1)
