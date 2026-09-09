"""
All cryptographic primitives used by authentication live here, and only
here — nothing outside this module hashes a password, signs a token, or
generates a session secret.

Two different hashing strategies are used deliberately, for two different
threat models:

* Passwords are low-entropy, human-chosen secrets that are vulnerable to
  offline brute-force/dictionary attack, so they use Argon2id (via
  passlib), a slow, memory-hard KDF. This directly replaces the old
  Flutter app's unsalted SHA-256 password hashing.
* Refresh tokens are 256-bit cryptographically random strings
  (`secrets.token_urlsafe`) with no guessable structure, so hashing them
  with a slow KDF would only add latency for no security benefit. They
  are hashed with SHA-256 purely so the raw, bearer-equivalent secret is
  never persisted at rest (per the Phase 1 requirement) — this is a
  lookup/integrity hash, not a password hash.
"""

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

import jwt
from passlib.context import CryptContext

from app.core.config import settings

# --- Password hashing (Argon2id) ---

_pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")


def hash_password(plain_password: str) -> str:
    return _pwd_context.hash(plain_password)


def verify_password(plain_password: str, password_hash: str) -> bool:
    return _pwd_context.verify(plain_password, password_hash)


# --- Access tokens (JWT) ---

TOKEN_TYPE_ACCESS = "access"


class TokenError(Exception):
    """Raised for any invalid, expired, or malformed JWT."""


def create_access_token(subject: str) -> str:
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(minutes=settings.access_token_expire_minutes)
    payload: Dict[str, Any] = {
        "sub": subject,
        "type": TOKEN_TYPE_ACCESS,
        "iat": int(now.timestamp()),
        "exp": expires_at,
        # A random per-token id, so two tokens issued for the same user in
        # the same second (e.g. register immediately followed by refresh)
        # are still guaranteed to be distinct strings, not just distinct
        # in theory. Also leaves room for future jti-based revocation.
        "jti": uuid.uuid4().hex,
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> Dict[str, Any]:
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    except jwt.ExpiredSignatureError as exc:
        raise TokenError("Access token has expired") from exc
    except jwt.InvalidTokenError as exc:
        raise TokenError("Access token is invalid") from exc

    if payload.get("type") != TOKEN_TYPE_ACCESS:
        raise TokenError("Token is not an access token")
    return payload


# --- Refresh tokens (opaque, hashed at rest) ---


def generate_refresh_token() -> str:
    """A high-entropy, unguessable bearer secret — never a JWT."""
    return secrets.token_urlsafe(64)


def hash_refresh_token(raw_token: str) -> str:
    """
    Deterministic, fast hash used only for exact-match lookup of a
    high-entropy random token — see the module docstring for why this
    intentionally does NOT use Argon2/bcrypt.
    """
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def refresh_token_expiry() -> datetime:
    return datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_expire_days)


# --- Relationship invitation tokens (Phase 4) ---
#
# Same treatment as refresh tokens, for the same reason: a high-entropy
# opaque bearer secret, hashed with SHA-256 for at-rest lookup rather than
# a slow password KDF. Deliberately a *separate* pair of functions (not a
# reuse of generate_refresh_token/hash_refresh_token) so the two token
# families can change independently later without one's needs (e.g. a
# different length) leaking into the other's call sites.


def generate_invitation_token() -> str:
    """A high-entropy, unguessable bearer secret carrying no user data — see app/models/relationship_invitation.py."""
    return secrets.token_urlsafe(32)


def hash_invitation_token(raw_token: str) -> str:
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def invitation_token_expiry() -> datetime:
    return datetime.now(timezone.utc) + timedelta(days=settings.invitation_expire_days)
