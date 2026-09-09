import uuid
from typing import Optional, Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.relationship_permission import RelationshipPermission


def get(db: Session, *, relationship_id: uuid.UUID, permission_type: str) -> Optional[RelationshipPermission]:
    stmt = select(RelationshipPermission).where(
        RelationshipPermission.relationship_id == relationship_id,
        RelationshipPermission.permission_type == permission_type,
    )
    return db.execute(stmt).scalar_one_or_none()


def list_for_relationship(db: Session, *, relationship_id: uuid.UUID) -> Sequence[RelationshipPermission]:
    stmt = select(RelationshipPermission).where(RelationshipPermission.relationship_id == relationship_id)
    return db.execute(stmt).scalars().all()


def create(
    db: Session, *, relationship_id: uuid.UUID, permission_type: str, granted: bool, granted_at
) -> RelationshipPermission:
    row = RelationshipPermission(
        relationship_id=relationship_id,
        permission_type=permission_type,
        granted=granted,
        granted_at=granted_at if granted else None,
        revoked_at=None if granted else granted_at,
    )
    db.add(row)
    db.flush()
    return row
