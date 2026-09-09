"""
Read-only aggregate queries specific to assembling a WeeklySummary (see
app/services/weekly_aggregation_service.py) — journal/shoutout activity by
DATE only, never title/content. Every function here reads at most an
`entry_date` column or a boolean (`felt_better`); none of them ever
selects `title`/`content` from JournalEntry or Shoutout, which is what
makes it structurally impossible for this module to leak journal/shoutout
text into a weekly reflection.

Mood and checklist aggregates are deliberately NOT duplicated here —
they're read from app/repositories/stress_repository.py instead. Weekly
reflection and the stress indicator need the exact same mood/checklist
window aggregates, so reusing that module keeps both callers backed by
one set of queries rather than two independently-maintained ones that
could silently drift apart on what "this week's mood average" means.
"""

import uuid
from datetime import date
from typing import Set

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.checklist import ChecklistCompletion
from app.models.journal import JournalEntry
from app.models.shoutout import Shoutout


def get_checklist_active_dates_in_window(
    db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date
) -> Set[date]:
    """Distinct dates the checklist was touched at all (completed or not) — used for checklist_days_tracked."""
    stmt = (
        select(ChecklistCompletion.entry_date)
        .where(
            ChecklistCompletion.user_id == user_id,
            ChecklistCompletion.entry_date >= start_date,
            ChecklistCompletion.entry_date <= end_date,
        )
        .distinct()
    )
    return set(db.execute(stmt).scalars().all())


def get_journal_entry_dates_in_window(db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date) -> Set[date]:
    stmt = select(JournalEntry.entry_date).where(
        JournalEntry.user_id == user_id, JournalEntry.entry_date >= start_date, JournalEntry.entry_date <= end_date
    )
    return set(db.execute(stmt).scalars().all())


def get_shoutout_dates_in_window(db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date) -> Set[date]:
    stmt = select(Shoutout.entry_date).where(
        Shoutout.user_id == user_id, Shoutout.entry_date >= start_date, Shoutout.entry_date <= end_date
    )
    return set(db.execute(stmt).scalars().all())


def count_shoutouts_with_positive_feel_better_in_window(
    db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date
) -> int:
    """
    The one piece of shoutout *content* that ever leaves the database for
    weekly reflection — a boolean, never title/content text.
    """
    stmt = select(func.count()).select_from(Shoutout).where(
        Shoutout.user_id == user_id,
        Shoutout.entry_date >= start_date,
        Shoutout.entry_date <= end_date,
        Shoutout.felt_better.is_(True),
    )
    return db.execute(stmt).scalar_one()
