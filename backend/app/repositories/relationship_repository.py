import uuid
from typing import Optional, Sequence

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.models.relationship import Relationship


def get_by_id(db: Session, relationship_id: uuid.UUID) -> Optional[Relationship]:
    return db.get(Relationship, relationship_id)


def get_by_id_for_party(db: Session, *, relationship_id: uuid.UUID, user_id: uuid.UUID) -> Optional[Relationship]:
    """
    Loads a relationship only if `user_id` is one of its two parties
    (owner or comfort person) — the same "filter by ownership in the same
    query as the id" pattern journal_repository/mood_repository use, so a
    relationship that exists but belongs to someone else is
    indistinguishable from one that doesn't exist at all (IDOR-by-response
    prevention).
    """
    stmt = select(Relationship).where(
        Relationship.id == relationship_id,
        or_(Relationship.owner_user_id == user_id, Relationship.comfort_user_id == user_id),
    )
    return db.execute(stmt).scalar_one_or_none()


def get_active_pair(db: Session, *, owner_user_id: uuid.UUID, comfort_user_id: uuid.UUID) -> Optional[Relationship]:
    stmt = select(Relationship).where(
        Relationship.owner_user_id == owner_user_id,
        Relationship.comfort_user_id == comfort_user_id,
        Relationship.status == "accepted",
    )
    return db.execute(stmt).scalar_one_or_none()


def list_for_owner(
    db: Session, *, owner_user_id: uuid.UUID, limit: int = 30, offset: int = 0
) -> tuple[Sequence[Relationship], int]:
    filters = [Relationship.owner_user_id == owner_user_id]
    total = db.execute(select(func.count()).select_from(Relationship).where(*filters)).scalar_one()
    stmt = (
        select(Relationship).where(*filters).order_by(Relationship.created_at.desc()).limit(limit).offset(offset)
    )
    items = db.execute(stmt).scalars().all()
    return items, total


def list_for_comfort_user(
    db: Session, *, comfort_user_id: uuid.UUID, limit: int = 30, offset: int = 0
) -> tuple[Sequence[Relationship], int]:
    filters = [Relationship.comfort_user_id == comfort_user_id]
    total = db.execute(select(func.count()).select_from(Relationship).where(*filters)).scalar_one()
    stmt = (
        select(Relationship).where(*filters).order_by(Relationship.created_at.desc()).limit(limit).offset(offset)
    )
    items = db.execute(stmt).scalars().all()
    return items, total


def create(
    db: Session,
    *,
    owner_user_id: uuid.UUID,
    comfort_user_id: uuid.UUID,
    relationship_type: str,
    custom_relationship_label: Optional[str],
    accepted_at,
) -> Relationship:
    row = Relationship(
        owner_user_id=owner_user_id,
        comfort_user_id=comfort_user_id,
        relationship_type=relationship_type,
        custom_relationship_label=custom_relationship_label,
        status="accepted",
        accepted_at=accepted_at,
    )
    db.add(row)
    db.flush()
    return row
