"""
All registration/login/refresh/logout business logic. Routes stay thin —
they parse the request, call one of these functions, and translate the
result (or a raised DomainError) into an HTTP response.
"""

from dataclasses import dataclass
from typing import Optional

from sqlalchemy.orm import Session

from app.core.exceptions import (
    InactiveUserError,
    EmailAlreadyRegisteredError,
    InvalidCredentialsError,
    InvalidRefreshTokenError,
)
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    hash_password,
    hash_refresh_token,
    refresh_token_expiry,
    verify_password,
)
from app.models.auth_session import AuthSession
from app.models.user import User
from app.repositories import auth_session_repository, profile_repository, user_repository


@dataclass
class IssuedTokens:
    access_token: str
    refresh_token: str
    session: AuthSession


def register_user(
    db: Session,
    *,
    email: str,
    password: str,
    full_name: Optional[str] = None,
    user_agent: Optional[str] = None,
    ip_address: Optional[str] = None,
) -> tuple[User, IssuedTokens]:
    if user_repository.get_by_email(db, email) is not None:
        raise EmailAlreadyRegisteredError(f"{email} is already registered")

    user = user_repository.create(db, email=email, password_hash=hash_password(password))
    profile_repository.create_for_user(db, user_id=user.id, full_name=full_name)

    tokens = _issue_tokens(db, user, user_agent=user_agent, ip_address=ip_address)
    db.commit()
    db.refresh(user)
    return user, tokens


def authenticate_user(
    db: Session,
    *,
    email: str,
    password: str,
    user_agent: Optional[str] = None,
    ip_address: Optional[str] = None,
) -> tuple[User, IssuedTokens]:
    user = user_repository.get_by_email(db, email)
    if user is None or not verify_password(password, user.password_hash):
        raise InvalidCredentialsError("Incorrect email or password")
    if not user.is_active:
        raise InactiveUserError("This account has been deactivated")

    user_repository.mark_login(db, user)
    tokens = _issue_tokens(db, user, user_agent=user_agent, ip_address=ip_address)
    db.commit()
    db.refresh(user)
    return user, tokens


def refresh_tokens(
    db: Session,
    *,
    raw_refresh_token: str,
    user_agent: Optional[str] = None,
    ip_address: Optional[str] = None,
) -> IssuedTokens:
    token_hash = hash_refresh_token(raw_refresh_token)
    session = auth_session_repository.get_by_token_hash(db, token_hash)

    # A missing OR already-revoked/expired session is reported identically
    # to the caller — a revoked session being presented again is exactly
    # what a stolen/replayed refresh token looks like, and the response
    # must not let an attacker distinguish "revoked" from "never existed".
    if session is None or not session.is_active:
        raise InvalidRefreshTokenError("Refresh token is invalid, expired, or has been revoked")

    user = user_repository.get_by_id(db, session.user_id)
    if user is None or not user.is_active:
        raise InvalidRefreshTokenError("Refresh token is invalid, expired, or has been revoked")

    new_tokens = _issue_tokens(db, user, user_agent=user_agent, ip_address=ip_address)
    # Rotation: the old session is revoked and linked to its replacement
    # in the same transaction that creates the new one.
    auth_session_repository.revoke(db, session, replaced_by_id=new_tokens.session.id)
    db.commit()
    return new_tokens


def logout(db: Session, *, current_user: User, raw_refresh_token: str) -> None:
    token_hash = hash_refresh_token(raw_refresh_token)
    session = auth_session_repository.get_by_token_hash(db, token_hash)

    if session is None or session.user_id != current_user.id:
        # Don't reveal whether the token exists at all if it belongs to
        # someone else — logout is idempotent from the caller's point of view.
        raise InvalidRefreshTokenError("Refresh token is invalid")

    auth_session_repository.revoke(db, session)
    db.commit()


def _issue_tokens(
    db: Session,
    user: User,
    *,
    user_agent: Optional[str] = None,
    ip_address: Optional[str] = None,
) -> IssuedTokens:
    access_token = create_access_token(subject=str(user.id))
    raw_refresh_token = generate_refresh_token()

    session = auth_session_repository.create(
        db,
        user_id=user.id,
        refresh_token_hash=hash_refresh_token(raw_refresh_token),
        expires_at=refresh_token_expiry(),
        user_agent=user_agent,
        ip_address=ip_address,
    )
    return IssuedTokens(access_token=access_token, refresh_token=raw_refresh_token, session=session)
