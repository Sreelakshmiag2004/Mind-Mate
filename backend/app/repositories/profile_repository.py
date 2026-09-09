import uuid
from typing import Optional

from sqlalchemy.orm import Session

from app.models.profile import Profile


def get_by_user_id(db: Session, user_id: uuid.UUID) -> Optional[Profile]:
    return db.get(Profile, user_id)


def create_for_user(db: Session, *, user_id: uuid.UUID, full_name: Optional[str] = None) -> Profile:
    profile = Profile(user_id=user_id, full_name=full_name)
    db.add(profile)
    db.flush()
    return profile
