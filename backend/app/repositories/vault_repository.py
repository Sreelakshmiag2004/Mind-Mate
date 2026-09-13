import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.vault_lock import VaultLock


def get_by_user_id(db: Session, *, user_id: uuid.UUID) -> Optional[VaultLock]:
    stmt = select(VaultLock).where(VaultLock.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def create(db: Session, *, user_id: uuid.UUID, password_hash: str) -> VaultLock:
    lock = VaultLock(user_id=user_id, password_hash=password_hash)
    db.add(lock)
    db.flush()
    return lock
