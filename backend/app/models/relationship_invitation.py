"""
Real backend invitation tokens, replacing the old `RegFavPage`'s fake
"invite link" (`mindmate://invite?from=<uid>&name=<name>&relation=<relation>`
— confirmed from source: a URL assembled client-side from plain-text query
parameters, never checked by anything, never expiring, reusable forever,
and carrying the owner's raw Firebase uid in the clear). None of that is
reproduced here on purpose:

  * The token is a 256-bit `secrets.token_urlsafe` random string with no
    embedded user data — unlike the old link, knowing a token reveals
    nothing about who created it.
  * Only a SHA-256 hash of the token is ever persisted (`token_hash`),
    the same treatment `auth_sessions.refresh_token_hash` gives refresh
    tokens (see app/core/security.py) — this is a lookup/integrity hash
    for a high-entropy secret, not a password hash. The raw token is
    handed to the caller exactly once, at creation, and never stored.
  * It expires (`expires_at`) and is single-use: `status` moves from
    'pending' to exactly one terminal state ('accepted', 'declined', or
    'revoked') and every lookup path rejects anything not still 'pending'
    and not yet expired.

`accepted_by_user_id` / `resulting_relationship_id` are populated together,
in the same transaction that flips `status` to 'accepted' and creates the
Relationship row — see relationship_service.accept_invitation for the
atomic accept+activate.
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin

INVITATION_STATUSES = ("pending", "accepted", "declined", "revoked")


class RelationshipInvitation(Base, TimestampMixin):
    __tablename__ = "relationship_invitations"
    __table_args__ = (
        CheckConstraint(
            "relationship_type IN ('mom','dad','siblings','best_friend','love','grandparents','other')",
            name="ck_relationship_invitations_relationship_type",
        ),
        CheckConstraint(
            "status IN ('pending','accepted','declined','revoked')",
            name="ck_relationship_invitations_status",
        ),
        Index("ix_relationship_invitations_owner_user_id", "owner_user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)

    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    relationship_type: Mapped[str] = mapped_column(String(20), nullable=False)
    custom_relationship_label: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    # SHA-256 hex digest (64 chars) of the raw invitation token. Unique so a
    # lookup by hash also serves as an O(1) integrity check, exactly like
    # auth_sessions.refresh_token_hash.
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)

    status: Mapped[str] = mapped_column(String(10), nullable=False, default="pending")

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    accepted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    declined_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    accepted_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    resulting_relationship_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        GUID(), ForeignKey("relationships.id", ondelete="SET NULL"), nullable=True
    )

    owner: Mapped["User"] = relationship(foreign_keys=[owner_user_id])  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<RelationshipInvitation id={self.id} owner_user_id={self.owner_user_id} status={self.status}>"
