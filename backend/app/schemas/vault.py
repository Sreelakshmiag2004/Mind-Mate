"""
Schemas for the Vault lock (PHASE14B — see app/models/vault_lock.py).
`VaultLockRead` is the ONLY response shape used by every Vault-lock
endpoint (create/get/unlock) — it never includes `password`/
`password_hash` under any circumstance; that field simply does not exist
anywhere in this module.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator

# Deliberately NOT the account password's letter+digit complexity policy
# (see app.schemas.auth._validate_password_strength) — the Vault lock is
# a lighter, secondary, local-gate credential, matching
# vault_password.dart's own existing rule (a minimum length, no
# complexity requirement beyond that). See the PHASE14B implementation
# report, "Design decisions", for the full reasoning behind keeping this
# a separate, simpler policy rather than reusing the account one.
VAULT_PASSWORD_MIN_LENGTH = 6
VAULT_PASSWORD_MAX_LENGTH = 128


class VaultLockCreate(BaseModel):
    """POST /vault/lock request body."""

    password: str = Field(min_length=1, max_length=VAULT_PASSWORD_MAX_LENGTH)

    @field_validator("password")
    @classmethod
    def _check_password(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Password must not be empty or whitespace-only")
        if len(value) < VAULT_PASSWORD_MIN_LENGTH:
            raise ValueError(f"Password must be at least {VAULT_PASSWORD_MIN_LENGTH} characters long")
        return value


class VaultUnlockRequest(BaseModel):
    """
    POST /vault/unlock request body. Deliberately only the minimal
    structural bounds (non-empty, a sane max length) — NOT
    [VaultLockCreate]'s minimum-length policy check. This endpoint's job
    is "does this match what's already stored", not "is this a valid new
    password"; a too-short attempt should fail the same way any other
    wrong attempt does (401, via Argon2 comparison), not be turned away
    earlier with a different status code for a reason unrelated to
    whether it's correct.
    """

    password: str = Field(min_length=1, max_length=VAULT_PASSWORD_MAX_LENGTH)


class VaultLockRead(BaseModel):
    """
    Safe Vault-lock state — returned by GET /vault/lock, POST /vault/lock,
    and POST /vault/unlock alike, so every caller gets one consistent
    shape regardless of which endpoint produced it. `configured=False`
    with both timestamps `None` is the normal, non-error state for a user
    who hasn't set a Vault password up yet — never a 404.
    """

    configured: bool
    last_viewed_at: Optional[datetime] = None
    previous_viewed_at: Optional[datetime] = None
