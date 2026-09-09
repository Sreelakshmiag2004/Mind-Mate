import uuid
from datetime import datetime
from typing import Optional, Sequence

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.relationship_invitation import RelationshipInvitation


def get_by_token_hash(db: Session, token_hash: str) -> Optional[RelationshipInvitation]:
    stmt = select(RelationshipInvitation).where(RelationshipInvitation.token_hash == token_hash)
    return db.execute(stmt).scalar_one_or_none()


def get_by_id_for_owner(
    db: Session, *, invitation_id: uuid.UUID, owner_user_id: uuid.UUID
) -> Optional[RelationshipInvitation]:
    stmt = select(RelationshipInvitation).where(
        RelationshipInvitation.id == invitation_id, RelationshipInvitation.owner_user_id == owner_user_id
    )
    return db.execute(stmt).scalar_one_or_none()


def list_for_owner(
    db: Session, *, owner_user_id: uuid.UUID, limit: int = 30, offset: int = 0
) -> tuple[Sequence[RelationshipInvitation], int]:
    filters = [RelationshipInvitation.owner_user_id == owner_user_id]
    total = db.execute(select(func.count()).select_from(RelationshipInvitation).where(*filters)).scalar_one()
    stmt = (
        select(RelationshipInvitation)
        .where(*filters)
        .order_by(RelationshipInvitation.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    items = db.execute(stmt).scalars().all()
    return items, total


def create(
    db: Session,
    *,
    owner_user_id: uuid.UUID,
    relationship_type: str,
    custom_relationship_label: Optional[str],
    token_hash: str,
    expires_at: datetime,
) -> RelationshipInvitation:
    row = RelationshipInvitation(
        owner_user_id=owner_user_id,
        relationship_type=relationship_type,
        custom_relationship_label=custom_relationship_label,
        token_hash=token_hash,
        status="pending",
        expires_at=expires_at,
    )
    db.add(row)
    db.flush()
    return row
