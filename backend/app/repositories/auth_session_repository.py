import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.auth_session import AuthSession


def create(
    db: Session,
    *,
    user_id: uuid.UUID,
    refresh_token_hash: str,
    expires_at: datetime,
    user_agent: Optional[str] = None,
    ip_address: Optional[str] = None,
) -> AuthSession:
    session = AuthSession(
        user_id=user_id,
        refresh_token_hash=refresh_token_hash,
        issued_at=datetime.now(timezone.utc),
        expires_at=expires_at,
        user_agent=user_agent,
        ip_address=ip_address,
    )
    db.add(session)
    db.flush()
    return session


def get_by_token_hash(db: Session, refresh_token_hash: str) -> Optional[AuthSession]:
    stmt = select(AuthSession).where(AuthSession.refresh_token_hash == refresh_token_hash)
    return db.execute(stmt).scalar_one_or_none()


def revoke(db: Session, session: AuthSession, *, replaced_by_id: Optional[uuid.UUID] = None) -> None:
    session.revoked_at = datetime.now(timezone.utc)
    if replaced_by_id is not None:
        session.replaced_by_id = replaced_by_id
    db.add(session)
