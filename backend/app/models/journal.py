"""
Reproduces `journal_page.dart` / `journal_entry_page.dart`'s actual model —
one entry per calendar day (the old app wrote to a date-keyed Firestore
doc, `users/{u}/journals/{dateKey}`, so a second save on the same date
silently overwrote the first) — not an invented one. `UNIQUE(user_id,
entry_date)` makes that same one-entry-per-day rule an enforced database
constraint instead of an accidental side effect of the old doc-id scheme.

Field naming deviates from the old `title`/`description` Firestore fields
in one place: `description` is renamed `content` here (plain rename, same
meaning, no behavior change) for a clearer, more conventional name — noted
explicitly since the task calls for confirming every field against source.

The old app's per-entry `streak` field is intentionally NOT reproduced —
see backend/README.md, "Design decisions", for why it's deferred to a
computed analytics value rather than a stored column.
"""

import uuid
from datetime import date as date_
from typing import Optional

from sqlalchemy import Date, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin


class JournalEntry(Base, TimestampMixin):
    __tablename__ = "journal_entries"
    __table_args__ = (
        UniqueConstraint("user_id", "entry_date", name="uq_journal_entries_user_id_entry_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    entry_date: Mapped[date_] = mapped_column(Date, nullable=False)
    title: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    content: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<JournalEntry id={self.id} user_id={self.user_id} entry_date={self.entry_date}>"
