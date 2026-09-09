"""
Explicit, revocable consent for what a comfort person may see about the
relationship owner — separate from the Relationship row itself so that
"the relationship exists and is accepted" and "the owner has actually
consented to share X" are two independently-checkable facts, per the
Phase 4 brief: accepting an invitation must never implicitly grant access
to everything.

Only one permission type is implemented today: `stress_level`, covering
the one feature the old UI actually promises ("View today's stress level"
in favorite_page.dart — currently a dead `// TODO: Implement stress level
view` button). There is no UI anywhere in the app offering a comfort
person visibility into mood history, journals, checklists, or media
individually, so no permission rows for those are created or checked; see
app/services/stress_service.py and app/api/routes/relationships.py for
what `stress_level` does and does not expose. `permission_type` is still
its own column (not a boolean flag on Relationship) so a future,
genuinely-requested permission (e.g. mood trend) is an additional row,
never a schema change or a growing set of boolean columns.

One row per (relationship_id, permission_type): granting/revoking flips
`granted` and stamps `granted_at`/`revoked_at` on the same row rather than
inserting a new history row each time, matching how `MoodEntry`/
`ChecklistCompletion` are upserted elsewhere in this codebase rather than
append-only-logged.
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin

PERMISSION_TYPES = ("stress_level",)


class RelationshipPermission(Base, TimestampMixin):
    __tablename__ = "relationship_permissions"
    __table_args__ = (
        CheckConstraint("permission_type IN ('stress_level')", name="ck_relationship_permissions_type"),
        UniqueConstraint(
            "relationship_id", "permission_type", name="uq_relationship_permissions_relationship_type"
        ),
        Index("ix_relationship_permissions_relationship_id", "relationship_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    relationship_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("relationships.id", ondelete="CASCADE"), nullable=False
    )

    permission_type: Mapped[str] = mapped_column(String(30), nullable=False)
    granted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    granted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    relationship_ref: Mapped["Relationship"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<RelationshipPermission relationship_id={self.relationship_id} "
            f"type={self.permission_type} granted={self.granted}>"
        )
