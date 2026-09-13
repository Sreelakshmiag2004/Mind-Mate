"""
Business logic for the Vault lock (PHASE14B — see
app/models/vault_lock.py). This module never hashes or compares a
password itself — it exclusively delegates to
app.core.security.hash_password/verify_password (Argon2id, the same
utility the account password already uses).
"""

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, InvalidCredentialsError
from app.core.security import hash_password, verify_password
from app.models.vault_lock import VaultLock
from app.repositories import vault_repository


def get_state(db: Session, *, user_id: uuid.UUID) -> Optional[VaultLock]:
    """`None` means "not configured yet" — a normal state, not an error; see app/api/routes/vault.py."""
    return vault_repository.get_by_user_id(db, user_id=user_id)


def create_lock(db: Session, *, user_id: uuid.UUID, password: str) -> VaultLock:
    """
    One Vault lock per user. Raises [ConflictError] (-> 409) if this user
    already has one — callers who want to change an existing Vault
    password need a distinct "change password" flow (not built in this
    phase; see the PHASE14B implementation report, "Limitations/deferred
    items"), not a silent overwrite here.
    """
    if vault_repository.get_by_user_id(db, user_id=user_id) is not None:
        raise ConflictError("A Vault lock already exists for this user")

    lock = vault_repository.create(db, user_id=user_id, password_hash=hash_password(password))
    db.commit()
    db.refresh(lock)
    return lock


def unlock(db: Session, *, user_id: uuid.UUID, password: str) -> VaultLock:
    """
    Verifies [password] against the stored Argon2 hash. Raises
    [InvalidCredentialsError] (-> 401) both when no Vault lock exists yet
    for this user AND when one exists but the password doesn't match —
    deliberately the SAME error for both cases, so a caller can never use
    this endpoint's response to learn "you haven't set one up" versus
    "you got it wrong" (mirrors app.api.routes.auth's identical treatment
    of an unknown email vs. a wrong password at login).

    On success, shifts the previous `last_viewed_at` into
    `previous_viewed_at` and sets a fresh `last_viewed_at` — the same pair
    the old Firestore `vaultLastViewed`/`vaultPrevLastViewed` fields
    tracked, now updated atomically in one transaction instead of the old
    app's separate read-then-write.
    """
    lock = vault_repository.get_by_user_id(db, user_id=user_id)
    if lock is None or not verify_password(password, lock.password_hash):
        raise InvalidCredentialsError("Incorrect Vault password")

    lock.previous_viewed_at = lock.last_viewed_at
    lock.last_viewed_at = datetime.now(timezone.utc)
    db.add(lock)
    db.commit()
    db.refresh(lock)
    return lock
