"""
`get_current_user` is the authentication dependency: every protected
route depends on it (directly or transitively) to require and validate a
bearer access token. `get_current_active_user` layers an authorization
check (account not deactivated) on top of it — the two are kept separate
so a future endpoint that needs "any known user, even a deactivated one"
remains possible without re-implementing token parsing.
"""

import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import TokenError, decode_access_token
from app.models.user import User
from app.repositories import user_repository

_bearer_scheme = HTTPBearer(auto_error=True, description="Paste the access token returned by /auth/login")


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = decode_access_token(credentials.credentials)
    except TokenError:
        raise unauthorized

    raw_user_id = payload.get("sub")
    if raw_user_id is None:
        raise unauthorized

    try:
        user_id = uuid.UUID(str(raw_user_id))
    except ValueError:
        raise unauthorized

    user = user_repository.get_by_id(db, user_id)
    if user is None:
        raise unauthorized

    return user


def get_current_active_user(user: User = Depends(get_current_user)) -> User:
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This account has been deactivated")
    return user
