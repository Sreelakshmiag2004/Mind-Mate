"""
The Vault lock — a SEPARATE, secondary credential gating access to the
Vault/media feature, deliberately isolated from `users`, `profiles`, and
`media_assets` (per the PHASE14A audit report, Section I/O, and this
table's own security requirement). It is never conflated with the
account password: a user authenticates with their account password/JWT
first (as for every other resource in this backend), then — only if
they've set one up — re-enters this second, Vault-specific password to
view their media library, mirroring `vault_password.dart`'s existing
create-once/authenticate-thereafter UX exactly, just backed by this table
instead of an unsalted-SHA-256 Firestore field on the user's own profile
document.

`password_hash` uses the exact same Argon2id hashing
(`app.core.security.hash_password`/`verify_password`) as the account
password — never SHA-256, never plaintext, never reversible encryption.
See backend/README.md, "Vault security — a gap identified, not silently
filled", for the gap this table closes, and the PHASE14B implementation
report for the full security rationale.

One row per user: `user_id` is UNIQUE (not merely indexed) — a user has
at most one Vault lock, matching `vault_password.dart`'s own "create a
password if none exists yet, else authenticate against the existing one"
flow, which never supports more than one per account.

`last_viewed_at`/`previous_viewed_at` mirror the old app's
`vaultLastViewed`/`vaultPrevLastViewed` Firestore fields, both updated
together on every successful unlock (see app/services/vault_service.py).
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, GUID, TimestampMixin


class VaultLock(Base, TimestampMixin):
    __tablename__ = "vault_locks"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True
    )

    # Argon2id, via app.core.security.hash_password — the exact same
    # utility/algorithm used for the account password. Never returned in
    # any API response (see app/schemas/vault.py) and never compared with
    # anything but app.core.security.verify_password.
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    last_viewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    previous_viewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship()  # noqa: F821

    def __repr__(self) -> str:  # pragma: no cover
        return f"<VaultLock id={self.id} user_id={self.user_id}>"
