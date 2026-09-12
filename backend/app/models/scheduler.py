"""
Backend for the Scheduler feature (see the PHASE11 Flutter-side audit
report) — the existing app currently has NO backend for this at all; it
stores a plain Hive box (`schedulerBox`, keyed by date only, with no
per-user scoping) directly on-device. This is the first
backend-authoritative representation of that data.

One row per (user, date, time) — the old Hive value was a `Map<String,
String>` keyed by a free-form time string, which meant two rows for the
same time silently overwrote one another (the audit's confirmed
"duplicate-time data loss" bug). `UNIQUE(user_id, entry_date,
scheduled_time)` makes that impossible at the database level instead of
merely unlikely, per PHASE11A product decision 2.

`scheduled_time` is stored as a plain, zero-padded `"HH:MM"` string, not a
SQL `Time`/`DateTime` column: the app has no concept of seconds or
timezone-aware scheduling — it is a 24-hour wall-clock label a user picks
via a time picker, on a specific calendar date, nothing more. A real
`Time` type would imply precision/comparison semantics (timezone handling,
seconds) this feature has never had; a `String` matches exactly what's
already validated (see app/schemas/scheduler.py) and persisted, with
`entry_date` (a real `Date` column) providing the only other axis that
actually matters.

Deliberately NOT a recurrence model. The old app's "today falls back to
yesterday" display behavior (PHASE11 audit report, Section 7) is a
client-side quirk, not an actual recurrence rule — per PHASE11A product
decision 1, that fallback stays entirely client-side; this backend only
ever answers "what's scheduled on this exact date."
"""

import uuid
from datetime import date as date_
from typing import Optional

from sqlalchemy import Date, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin


class SchedulerEntry(Base, TimestampMixin):
    __tablename__ = "scheduler_entries"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "entry_date",
            "scheduled_time",
            name="uq_scheduler_entries_user_id_entry_date_scheduled_time",
        ),
        # Supports "all of this user's scheduled rows for a date" reads
        # (every query this feature makes) without going through the
        # unique constraint's column order, same rationale as
        # ix_checklist_completions_user_id_entry_date.
        Index("ix_scheduler_entries_user_id_entry_date", "user_id", "entry_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    entry_date: Mapped[date_] = mapped_column(Date, nullable=False)
    # "HH:MM", 24-hour, zero-padded — see module docstring for why this is
    # a plain string rather than a SQL Time column. 5 chars exactly fits
    # "HH:MM"; validated by app/schemas/scheduler.py before it ever reaches
    # this model.
    scheduled_time: Mapped[str] = mapped_column(String(5), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<SchedulerEntry id={self.id} user_id={self.user_id} entry_date={self.entry_date} "
            f"time={self.scheduled_time!r}>"
        )
