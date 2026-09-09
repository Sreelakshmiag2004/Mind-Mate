"""
Read-only aggregate queries the stress signal is computed from. Deliberately
its own module rather than reusing mood_repository/checklist_repository
directly from the service layer: those two modules return full ORM rows
sized for their own CRUD endpoints, while stress_service only ever needs
small aggregates over a date window — keeping that aggregation here means
app/services/stress_service.py never has to load (or accidentally expose)
a row it doesn't need, such as a MoodEntry's full column set.
"""

import uuid
from datetime import date
from typing import Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.checklist import ChecklistCompletion, ChecklistItem
from app.models.mood import MoodEntry


def get_mood_values_in_window(
    db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date
) -> Sequence[int]:
    stmt = select(MoodEntry.mood_value).where(
        MoodEntry.user_id == user_id, MoodEntry.entry_date >= start_date, MoodEntry.entry_date <= end_date
    )
    return db.execute(stmt).scalars().all()


def count_active_checklist_items(db: Session) -> int:
    stmt = select(func.count()).select_from(ChecklistItem).where(ChecklistItem.is_active.is_(True))
    return db.execute(stmt).scalar_one()


def count_checklist_rows_in_window(db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date) -> int:
    """
    Total completion *rows* touched in the window, completed or not.
    Distinct from count_completed_checklist_items_in_window below: a row
    existing at all means the user engaged with the checklist that day,
    which is what tells the score "there is checklist data to use here"
    versus "the user never touched the checklist" (zero rows) — those two
    cases must not both collapse to the same 0.
    """
    stmt = select(func.count()).select_from(ChecklistCompletion).where(
        ChecklistCompletion.user_id == user_id,
        ChecklistCompletion.entry_date >= start_date,
        ChecklistCompletion.entry_date <= end_date,
    )
    return db.execute(stmt).scalar_one()


def count_completed_checklist_items_in_window(
    db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date
) -> int:
    stmt = select(func.count()).select_from(ChecklistCompletion).where(
        ChecklistCompletion.user_id == user_id,
        ChecklistCompletion.entry_date >= start_date,
        ChecklistCompletion.entry_date <= end_date,
        ChecklistCompletion.completed.is_(True),
    )
    return db.execute(stmt).scalar_one()


def get_activity_dates_in_window(db: Session, *, user_id: uuid.UUID, start_date: date, end_date: date) -> set:
    """
    Every distinct calendar date in the window on which the user logged a
    mood OR touched their checklist (completed or not — a toggle still
    means they engaged with the app that day). Used only to gauge how much
    data the score is based on (see StressResult.confidence), never fed
    into the score itself.
    """
    mood_dates_stmt = select(MoodEntry.entry_date).where(
        MoodEntry.user_id == user_id, MoodEntry.entry_date >= start_date, MoodEntry.entry_date <= end_date
    )
    checklist_dates_stmt = select(ChecklistCompletion.entry_date).where(
        ChecklistCompletion.user_id == user_id,
        ChecklistCompletion.entry_date >= start_date,
        ChecklistCompletion.entry_date <= end_date,
    )
    mood_dates = db.execute(mood_dates_stmt).scalars().all()
    checklist_dates = db.execute(checklist_dates_stmt).scalars().all()
    return set(mood_dates) | set(checklist_dates)
