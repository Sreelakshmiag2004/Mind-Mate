"""
Profile deliberately holds ONLY the fields the audit confirmed the
current MindMate app actually collects today, in `enter_details_page.dart`
/ `edit_profile_page.dart` (name, age group, phone, city, country, profile
photo) plus one bookkeeping field (`onboarding_completed_at`) needed to
reproduce `main.dart`'s SplashScreen routing logic ("does this user still
need to see EnterDetailsPage?") without re-deriving it from field
presence/absence the way the old client did.

Explicitly NOT included here, and why:
  * `comfortPerson` / relationship data — a separate future module
    (`comfort_persons`), not a profile attribute.
  * `vaultPasswordHash` — authentication data for a not-yet-built module
    (Vault), not profile data, and out of scope for Phase 1.
  * Anything notification-preference related — belongs to a future
    `notifications` module; the old `NotificationSettingsPage` never
    persisted these anyway (confirmed dead UI in the audit).
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin


class Profile(Base, TimestampMixin):
    __tablename__ = "profiles"

    # 1:1 with users — the FK IS the PK, so a user can have at most one profile.
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )

    full_name: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    # Free-text, validated against the app's current age-bracket options at
    # the API/schema layer (see app/schemas/profile.py) rather than a rigid
    # DB CHECK constraint, so the bracket labels can evolve without a migration.
    age_group: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    city: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    country: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    profile_image_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    onboarding_completed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    user: Mapped["User"] = relationship(back_populates="profile")  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<Profile user_id={self.user_id}>"
