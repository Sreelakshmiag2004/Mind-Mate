"""
Phase 4: a "relationship" is the backend's replacement for the single
`comfortPerson` map the audit found on the old app's user document
(`register_page.dart`, `regfav.dart`) — one owner ("the person being
supported") connected to one comfort person ("the person who may check in
on them"), with a relationship type drawn from the fixed list the old
`RegFavPage` UI actually offers (`_options` in regfav.dart): Mom, Dad,
Siblings, Best Friend, Love, Grandparents, Others (+ free-text label).

Deliberately NOT reproduced from the old shape:
  * A free-text `name` for the comfort person. In the old app the comfort
    person wasn't necessarily a registered user at all — just a name typed
    into a text field, because the "invite" was only ever an unverified
    deep link (`mindmate://invite?...`) with nobody on the other end
    required to actually be a MindMate account. In this backend, a
    relationship only ever exists between two real `users.id` rows (see
    RelationshipInvitation below for how the second one gets attached) —
    so the comfort person's display name comes from *their own*
    `profiles.full_name`, never a copy typed by the owner. Storing a second,
    possibly-stale copy of someone else's name on this table would be
    exactly the kind of redundant data the Phase 2/3 audits flagged
    elsewhere.
  * A "primary comfort person" flag. Nothing in the old UI distinguishes
    one comfort person as more primary than another — there is only ever
    at most one, full stop (a single map field, not a list). This table
    does not carry that one-at-a-time limit forward as a hard constraint
    (a real relational model naturally supports more than one), but
    nothing requires multiple either; see backend/README.md Phase 4
    section for the full reasoning.

Only two statuses are implemented — 'accepted' and 'revoked' — not the
full pending/declined vocabulary the general relationship-model brief
allows. That's deliberate: a row in this table is only ever created at
the moment an invitation is accepted (see RelationshipInvitation), so
"pending" and "declined" are states an *invitation* passes through, not
states a relationship itself is ever observed in — a relationship that
was declined or never acted on never gets a row here at all.
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin

# Mirrors regfav.dart's `_options` labels verbatim (snake_cased), plus
# 'other' for the free-text "Others" branch. See RELATIONSHIP_TYPES below
# for the single source of truth shared with the CHECK constraint and the
# Pydantic schema.
RELATIONSHIP_TYPES = ("mom", "dad", "siblings", "best_friend", "love", "grandparents", "other")

RELATIONSHIP_STATUSES = ("accepted", "revoked")


class Relationship(Base, TimestampMixin):
    __tablename__ = "relationships"
    __table_args__ = (
        CheckConstraint("owner_user_id <> comfort_user_id", name="ck_relationships_no_self_relationship"),
        CheckConstraint(
            "relationship_type IN ('mom','dad','siblings','best_friend','love','grandparents','other')",
            name="ck_relationships_relationship_type",
        ),
        CheckConstraint("status IN ('accepted','revoked')", name="ck_relationships_status"),
        # Both sides of the relationship need their own index: an owner
        # listing "the comfort people I've added" scans by owner_user_id,
        # a comfort person listing "who I support" scans by
        # comfort_user_id — two independent access patterns, not one
        # reversible one.
        Index("ix_relationships_owner_user_id", "owner_user_id"),
        Index("ix_relationships_comfort_user_id", "comfort_user_id"),
        # A given pair may only have ONE currently-active (accepted, not
        # yet revoked) relationship row at a time — this is the "duplicate
        # active relationships cannot be created accidentally" constraint.
        # It is a *partial* unique index (not a plain UniqueConstraint) so
        # that revoking and later re-accepting a new invitation between
        # the same two people is allowed to create a second, independent
        # row instead of being permanently blocked by history.
        Index(
            "uq_relationships_owner_comfort_active",
            "owner_user_id",
            "comfort_user_id",
            unique=True,
            postgresql_where=text("status = 'accepted'"),
            sqlite_where=text("status = 'accepted'"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)

    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    comfort_user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    relationship_type: Mapped[str] = mapped_column(String(20), nullable=False)
    # Populated only when relationship_type == 'other' — mirrors
    # regfav.dart's `_otherRelationController` ("Enter Relationship").
    custom_relationship_label: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    status: Mapped[str] = mapped_column(String(10), nullable=False, default="accepted")

    accepted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    owner: Mapped["User"] = relationship(foreign_keys=[owner_user_id])  # noqa: F821
    comfort_user: Mapped["User"] = relationship(foreign_keys=[comfort_user_id])  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<Relationship id={self.id} owner_user_id={self.owner_user_id} "
            f"comfort_user_id={self.comfort_user_id} status={self.status}>"
        )
