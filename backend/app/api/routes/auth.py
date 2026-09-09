from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import (
    EmailAlreadyRegisteredError,
    InactiveUserError,
    InvalidCredentialsError,
    InvalidRefreshTokenError,
)
from app.core.database import get_db
from app.dependencies.auth import get_current_active_user
from app.models.user import User
from app.repositories import profile_repository
from app.schemas.auth import LoginRequest, LogoutRequest, MeResponse, RefreshRequest, RegisterRequest, TokenResponse
from app.schemas.profile import ProfileRead
from app.schemas.user import UserRead
from app.services import auth_service
from app.services.auth_service import IssuedTokens

router = APIRouter(prefix="/auth", tags=["auth"])


def _client_context(request: Request) -> dict:
    return {
        "user_agent": request.headers.get("user-agent"),
        # `request.client` is None under some test transports; guarded here
        # rather than at every call site.
        "ip_address": request.client.host if request.client else None,
    }


def _token_response(tokens: IssuedTokens) -> TokenResponse:
    return TokenResponse(
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, request: Request, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        _, tokens = auth_service.register_user(
            db,
            email=payload.email,
            password=payload.password,
            full_name=payload.full_name,
            **_client_context(request),
        )
    except EmailAlreadyRegisteredError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account with this email already exists")

    return _token_response(tokens)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        _, tokens = auth_service.authenticate_user(
            db, email=payload.email, password=payload.password, **_client_context(request)
        )
    except (InvalidCredentialsError, InactiveUserError):
        # Deliberately identical error for both cases so a client can't
        # use this endpoint to enumerate which emails are registered.
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password")

    return _token_response(tokens)


@router.post("/refresh", response_model=TokenResponse)
def refresh(payload: RefreshRequest, request: Request, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        tokens = auth_service.refresh_tokens(
            db, raw_refresh_token=payload.refresh_token, **_client_context(request)
        )
    except InvalidRefreshTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token is invalid or expired")

    return _token_response(tokens)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    payload: LogoutRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Response:
    try:
        auth_service.logout(db, current_user=current_user, raw_refresh_token=payload.refresh_token)
    except InvalidRefreshTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token is invalid")

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=MeResponse)
def me(db: Session = Depends(get_db), current_user: User = Depends(get_current_active_user)) -> MeResponse:
    profile = profile_repository.get_by_user_id(db, current_user.id)
    return MeResponse(user=UserRead.model_validate(current_user), profile=ProfileRead.model_validate(profile))
