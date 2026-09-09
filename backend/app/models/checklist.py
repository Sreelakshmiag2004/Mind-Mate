"""
Reproduces `homepage.dart`'s actual checklist model, normalized instead
of copied as a JSON blob.

The old app stores `users/{u}/checklist/{dateKey} = {items: [bool, bool,
bool, bool, bool]}` — a positional boolean array matching 5 HARD-CODED
items defined once in Dart (`checklistItems` in `homepage.dart`):
"Drank enough water", "Slept well last night", "Did one thing just for
me", "Got some fresh air and sunlight", "Exercised well". Confirmed from
source: there are no categories, no user-created items, no recurrence
rules, and no per-user customization anywhere in the app today — every
user sees the same 5 items in the same order.

That reality maps to two tables, not one:

  * `checklist_items` — the catalog of tasks. Global (no `user_id`), since
    nothing in the app personalizes it today. Seeded with exactly today's
    5 items, in their current order, by the Phase 2 migration's data step
    — adding a 6th item later is a data change, not a schema change.
  * `checklist_completions` — one row per (user, item, date) once that
    item has been toggled on that date. A day with no rows yet simply
    means "nothing completed" — rows are created on first toggle, not
    pre-materialized for every day, which keeps the table's growth
    proportional to actual use rather than to the number of days that
    have merely passed.

This shape is what makes the completion-rate / trend analytics called for
in "Weekly Reflection readiness" a simple aggregate query instead of a
JSON-parsing exercise: `COUNT(*) ... GROUP BY entry_date` directly answers
"how many items were completed on each day".
"""

import uuid
from datetime import date as date_
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, SmallInteger, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin


class ChecklistItem(Base, TimestampMixin):
    """The global catalog of daily wellness tasks (currently: 5, fixed)."""

    __tablename__ = "checklist_items"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    label: Mapped[str] = mapped_column(String(200), nullable=False)
    sort_order: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    def __repr__(self) -> str:  # pragma: no cover
        return f"<ChecklistItem id={self.id} label={self.label!r}>"


class ChecklistCompletion(Base, TimestampMixin):
    """Whether one item was completed, for one user, on one date."""

    __tablename__ = "checklist_completions"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "checklist_item_id", "entry_date", name="uq_checklist_completions_user_item_date"
        ),
        # Supports "all of this user's completions in a date range" scans
        # (the shape every Weekly Reflection / trend query needs) without
        # having to go through the item_id column first — the unique
        # constraint above leads with user_id+item_id, which is the wrong
        # column order for a date-range scan across all items.
        Index("ix_checklist_completions_user_id_entry_date", "user_id", "entry_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    checklist_item_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("checklist_items.id", ondelete="CASCADE"), nullable=False, index=True
    )

    entry_date: Mapped[date_] = mapped_column(Date, nullable=False)
    completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821
    item: Mapped["ChecklistItem"] = relationship()

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<ChecklistCompletion user_id={self.user_id} item_id={self.checklist_item_id} "
            f"date={self.entry_date} completed={self.completed}>"
        )
