"""
Phase 5: one persisted row per (user, completed calendar week) — the
weekly reflection cache app/services/reflection_service.py reads before
ever calling an AI provider (see that module's docstring for the full
generate-or-return-cached flow). `UNIQUE(user_id, week_start)` is the
enforced "no duplicate reflections for the same user/week" rule; the
service layer's only write path is an upsert against that same key (see
app/repositories/reflection_repository.py), so regeneration overwrites
this row in place rather than appending a new one.

Only two statuses exist here: 'completed' and 'insufficient_data'. A
third, 'failed', was deliberately NOT added: an AI provider failure is
never persisted at all (see reflection_service.py's module docstring) —
if a row exists here, either a reflection was actually produced, or the
week was conclusively determined to be under-active, never "an attempt
happened and failed". This also sidesteps a real correctness question a
'failed' status would raise (does a failed regeneration attempt clobber a
previously-completed reflection?) by construction: nothing is ever
written on failure, so a prior completed row is simply left untouched.

What's deliberately NOT stored here:
  * The raw prompt text sent to the AI provider. `summary_input` already
    holds everything the prompt is deterministically built from (see
    app/services/ai/anthropic_provider.py) — storing the assembled
    prompt string too would be a redundant copy of the same information,
    not new data, and harder to reason about the privacy boundary of.
  * Any AI provider secret/API key — those live only in environment
    configuration (see app/core/config.py), never in a database row.
  * Raw journal/shoutout content. `summary_input` is a serialized
    app.schemas.reflection.WeeklySummary, which has no field capable of
    holding free text to begin with — there is nothing sensitive here to
    accidentally over-store.
"""

import uuid
from datetime import date as date_
from datetime import datetime
from typing import Optional

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Index, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin

REFLECTION_STATUSES = ("completed", "insufficient_data")


class WeeklyReflection(Base, TimestampMixin):
    __tablename__ = "weekly_reflections"
    __table_args__ = (
        UniqueConstraint("user_id", "week_start", name="uq_weekly_reflections_user_id_week_start"),
        CheckConstraint("status IN ('completed','insufficient_data')", name="ck_weekly_reflections_status"),
        # Backs both "does a row already exist for (user, week)" (the
        # cache-hit check every generate call makes) and "give me this
        # user's most recent reflection" (ORDER BY week_start DESC).
        Index("ix_weekly_reflections_user_id_week_start", "user_id", "week_start"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    week_start: Mapped[date_] = mapped_column(Date, nullable=False)
    week_end: Mapped[date_] = mapped_column(Date, nullable=False)

    status: Mapped[str] = mapped_column(String(20), nullable=False)

    # Schema version tag for `summary_input`'s shape (see
    # app.schemas.reflection.WeeklySummary) — so a future change to that
    # schema can tell old stored rows apart from new ones instead of
    # guessing from field presence.
    summary_version: Mapped[str] = mapped_column(String(20), nullable=False)
    summary_input: Mapped[dict] = mapped_column(JSON, nullable=False)

    # Populated only when status == 'completed'; left NULL for
    # 'insufficient_data' rather than storing empty strings.
    reflection_summary: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    reflection_mood_insight: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    reflection_habit_insight: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    reflection_positive_highlights: Mapped[Optional[list]] = mapped_column(JSON, nullable=True)
    reflection_areas_to_reflect_on: Mapped[Optional[list]] = mapped_column(JSON, nullable=True)
    reflection_encouragement: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    ai_provider: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    ai_model: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    generated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<WeeklyReflection id={self.id} user_id={self.user_id} week_start={self.week_start} status={self.status}>"
