"""
Reproduces what a "Shoutout" actually is in the current app — and it is
NOT an interpersonal message. Confirmed from source (`journal_page.dart`,
`shoutout_page.dart`): a Shoutout is a private, self-authored venting entry
("What's weighing on your mind?"), written by a user about themselves, for
themselves, exactly one per calendar day — read back only by the same
signed-in user via `users/{userId}/shoutouts/{dateKey}`. There is no
recipient anywhere: no screen lets a user choose another person, no
Firestore field references anyone but the author, and the only other place
in the app with a "who does this reach" concept — the comfort-person
circle in `favorite_page.dart` — has zero code connecting it to shoutouts.

This directly shapes the schema: a single `user_id` (author == sole
reader), not `sender_user_id`/`recipient_user_id`. See backend/README.md,
"Design decisions", for the full audit trail behind this call.

Two incompatible write shapes existed in the old app for the same
Firestore collection:
  * `journal_page.dart`'s inline `_saveShoutout()`: `.add({'problem':
    text, 'timestamp': ...})` — an auto-id doc, field name `problem`.
  * `shoutout_page.dart`'s `_saveShoutout()`: `.doc(dateKey).set({'title':
    ..., 'description': ..., 'timestamp': ...})` — a date-keyed doc.
Every READ path (`_loadTodayShoutout`, `_loadYesterdayShoutout`) expects
the second (date-keyed, title/description) shape — the first is
effectively orphaned, write-only data. This model adopts the
date-keyed/title+description shape as canonical, renaming `description`
to `content` for the same reason journals did (see app/models/journal.py).

`felt_better`/`felt_better_at` fix a genuine, verifiable bug rather than
inventing a feature: `_loadYesterdayShoutout()` reads `doc['feelBetter']`
expecting it to exist, but `_setYesterdayFeelBetter()` — the only code that
ever sets it — only calls `setState()` on local widget fields and never
writes to Firestore at all. The app's own read path already expects this
field to live on the same document as title/content, so it belongs here,
not in a separate table — see backend/README.md, "Follow-up interaction
decision", for the full reasoning.
"""

import uuid
from datetime import date as date_
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin


class Shoutout(Base, TimestampMixin):
    __tablename__ = "shoutouts"
    __table_args__ = (
        UniqueConstraint("user_id", "entry_date", name="uq_shoutouts_user_id_entry_date"),
        # Explicit, in addition to the unique constraint's index, because
        # that index leads with (user_id, entry_date) — this one supports
        # "list mine, newest first" ordered by created_at specifically,
        # which the unique constraint's column order doesn't serve as well.
        Index("ix_shoutouts_user_id_created_at", "user_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    entry_date: Mapped[date_] = mapped_column(Date, nullable=False)
    title: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    content: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    felt_better: Mapped[Optional[bool]] = mapped_column(Boolean, nullable=True)
    felt_better_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<Shoutout id={self.id} user_id={self.user_id} entry_date={self.entry_date}>"
