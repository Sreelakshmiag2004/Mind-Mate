"""
Reproduces `homepage.dart`'s actual mood model: a single 0-100 integer
percentage, one per user per calendar day (`users/{u}/moods/{dateKey}`
in the old app — also date-keyed, same one-per-day semantic as journals).

Deliberately NOT reproduced:
  * A stored mood "label"/emoji. `getEmojiForPercent()` in homepage.dart
    derives an emoji from the percent via a fixed range table purely for
    display — it is never written to Firestore. Storing it here would be
    inventing a field the app doesn't actually have; a future UI can
    recompute it client-side from `mood_value`, exactly like today.
  * The old app's redundant nested-map Firestore shape, which the Phase 1
    audit flagged as a bug (`saveMoodForDate` wrote a map that could only
    ever contain its own key) — `mood_value` here is a plain column.
  * The old app's client-side rule limiting edits to "today or yesterday"
    (`canEdit` in homepage.dart) — that's UI policy, not a data
    constraint; see backend/README.md, "Design decisions".
"""

import uuid
from datetime import date as date_

from sqlalchemy import CheckConstraint, Date, ForeignKey, SmallInteger, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin


class MoodEntry(Base, TimestampMixin):
    __tablename__ = "mood_entries"
    __table_args__ = (
        UniqueConstraint("user_id", "entry_date", name="uq_mood_entries_user_id_entry_date"),
        CheckConstraint("mood_value >= 0 AND mood_value <= 100", name="ck_mood_entries_mood_value_range"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    entry_date: Mapped[date_] = mapped_column(Date, nullable=False)
    mood_value: Mapped[int] = mapped_column(SmallInteger, nullable=False)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<MoodEntry id={self.id} user_id={self.user_id} entry_date={self.entry_date} value={self.mood_value}>"
