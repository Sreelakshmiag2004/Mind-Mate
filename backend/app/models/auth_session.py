"""
One row per issued refresh token ("session"). Access tokens are stateless
JWTs and are never stored; this table exists specifically so refresh
tokens — which are long-lived and therefore must be revocable — have
somewhere to be revoked.

Only a SHA-256 hash of the refresh token is ever stored (see
`app/core/security.py` for why that's the right hash for this value).
`replaced_by_id` records the rotation chain: on every `/auth/refresh`
call the presented session is revoked and a new one is created and
linked here, which is what makes refresh-token reuse detectable in a
future phase (a revoked session being presented again is a signal of a
stolen/replayed token).
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # SHA-256 hex digest (64 chars) of the raw refresh token. Unique so a
    # lookup by hash is also an O(1) integrity check.
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)

    user_agent: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    # Stored as a string (not Postgres' native INET) so this table's model
    # code is dialect-portable for the same reason GUID is — see app/models/base.py.
    ip_address: Mapped[Optional[str]] = mapped_column(String(45), nullable=True)

    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    replaced_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        GUID(), ForeignKey("auth_sessions.id", ondelete="SET NULL"), nullable=True
    )

    user: Mapped["User"] = relationship(back_populates="sessions")  # noqa: F821

    @property
    def is_active(self) -> bool:
        from datetime import timezone

        now = datetime.now(timezone.utc)
        expires_at = self.expires_at if self.expires_at.tzinfo else self.expires_at.replace(tzinfo=timezone.utc)
        return self.revoked_at is None and expires_at > now

    def __repr__(self) -> str:  # pragma: no cover
        return f"<AuthSession id={self.id} user_id={self.user_id} revoked={self.revoked_at is not None}>"
