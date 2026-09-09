"""
Relationships, invitations, and consent — see app/services/relationship_service.py
for every authorization/consent rule (this router never re-implements one).
"""

import uuid
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError, SelfRelationshipError
from app.dependencies.auth import get_current_active_user
from app.dependencies.pagination import PaginationParams, pagination_params
from app.models.user import User
from app.schemas.common import Page
from app.schemas.relationship import (
    InvitationCreate,
    InvitationCreateResponse,
    InvitationPreview,
    InvitationRead,
    PermissionRead,
    RelationshipRead,
)
from app.schemas.stress import ComfortStressView
from app.services import relationship_service, stress_service

router = APIRouter(prefix="/relationships", tags=["relationships"])


def _domain_error_to_http(exc: Exception) -> HTTPException:
    if isinstance(exc, NotFoundError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    if isinstance(exc, ConflictError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    if isinstance(exc, PermissionDeniedError):
        return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    if isinstance(exc, SelfRelationshipError):
        return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    raise exc  # pragma: no cover - programmer error, not a domain error


# --- Invitations ---


@router.post(
    "/invitations",
    response_model=InvitationCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a comfort-person invitation",
    description=(
        "Generates a single-use, expiring invitation token, replacing the old app's unverified "
        "`mindmate://invite?...` deep link. The raw token is returned exactly once here — only its "
        "hash is ever stored — so the caller must capture it now to build a shareable invite."
    ),
)
def create_invitation(
    payload: InvitationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> InvitationCreateResponse:
    invitation, raw_token = relationship_service.create_invitation(db, owner_user_id=current_user.id, payload=payload)
    return InvitationCreateResponse(
        id=invitation.id,
        relationship_type=invitation.relationship_type,
        custom_relationship_label=invitation.custom_relationship_label,
        status=invitation.status,
        expires_at=invitation.expires_at,
        created_at=invitation.created_at,
        token=raw_token,
    )


@router.get(
    "/invitations",
    response_model=Page[InvitationRead],
    summary="List invitations you've sent",
)
def list_invitations(
    pagination: PaginationParams = Depends(pagination_params),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Page[InvitationRead]:
    items, total = relationship_service.list_invitations_for_owner(
        db, owner_user_id=current_user.id, limit=pagination.limit, offset=pagination.offset
    )
    return Page[InvitationRead](
        items=[InvitationRead.model_validate(item) for item in items],
        total=total,
        limit=pagination.limit,
        offset=pagination.offset,
    )


@router.get(
    "/invitations/{token}",
    response_model=InvitationPreview,
    summary="Preview an invitation before accepting/declining it",
    description="Requires authentication (unlike the old raw deep link) so a token can't be scanned/probed anonymously.",
)
def preview_invitation(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> InvitationPreview:
    try:
        invitation, owner_display_name, is_expired = relationship_service.get_invitation_preview(db, token=token)
    except NotFoundError as exc:
        raise _domain_error_to_http(exc)
    return InvitationPreview(
        relationship_type=invitation.relationship_type,
        custom_relationship_label=invitation.custom_relationship_label,
        owner_display_name=owner_display_name,
        status=invitation.status,
        expires_at=invitation.expires_at,
        is_expired=is_expired,
    )


@router.post(
    "/invitations/{token}/accept",
    response_model=RelationshipRead,
    summary="Accept an invitation",
    description=(
        "Atomically consumes the invitation and creates the accepted relationship (plus its founding "
        "stress_level consent grant) in one transaction. Rejects expired, already-used, revoked, "
        "unknown, or self-owned invitations, and a duplicate active relationship with the same owner."
    ),
)
def accept_invitation(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> RelationshipRead:
    try:
        relationship = relationship_service.accept_invitation(db, token=token, accepting_user_id=current_user.id)
    except (NotFoundError, ConflictError, SelfRelationshipError) as exc:
        raise _domain_error_to_http(exc)
    return RelationshipRead(**relationship_service.to_relationship_read_dict(db, relationship, current_user.id))


@router.post(
    "/invitations/{token}/decline",
    response_model=InvitationRead,
    summary="Decline an invitation",
)
def decline_invitation(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> InvitationRead:
    try:
        invitation = relationship_service.decline_invitation(db, token=token, declining_user_id=current_user.id)
    except (NotFoundError, SelfRelationshipError) as exc:
        raise _domain_error_to_http(exc)
    return InvitationRead.model_validate(invitation)


# --- Relationships ---


@router.get(
    "",
    response_model=Page[RelationshipRead],
    summary="List your relationships",
    description=(
        "role=owner: the comfort people you've added. role=comfort_person: the people who have "
        "added you as their comfort person. Only your own relationships are ever returned."
    ),
)
def list_relationships(
    role: Literal["owner", "comfort_person"] = Query(default="owner"),
    pagination: PaginationParams = Depends(pagination_params),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Page[RelationshipRead]:
    rows, total = relationship_service.list_relationships(
        db, user_id=current_user.id, role=role, limit=pagination.limit, offset=pagination.offset
    )
    return Page[RelationshipRead](
        items=[RelationshipRead(**row) for row in rows],
        total=total,
        limit=pagination.limit,
        offset=pagination.offset,
    )


@router.post(
    "/{relationship_id}/revoke",
    response_model=RelationshipRead,
    summary="Revoke a relationship",
    description="Either party may end the relationship. Immediately revokes every consent grant on it.",
)
def revoke_relationship(
    relationship_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> RelationshipRead:
    try:
        relationship = relationship_service.revoke_relationship(
            db, relationship_id=relationship_id, caller_user_id=current_user.id
        )
    except NotFoundError as exc:
        raise _domain_error_to_http(exc)
    return RelationshipRead(**relationship_service.to_relationship_read_dict(db, relationship, current_user.id))


# --- Consent ---


@router.get(
    "/{relationship_id}/permissions",
    response_model=list[PermissionRead],
    summary="List consent grants on a relationship",
)
def list_permissions(
    relationship_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> list[PermissionRead]:
    try:
        permissions = relationship_service.list_permissions(
            db, relationship_id=relationship_id, caller_user_id=current_user.id
        )
    except NotFoundError as exc:
        raise _domain_error_to_http(exc)
    return [PermissionRead.model_validate(p) for p in permissions]


@router.post(
    "/{relationship_id}/permissions/{permission_type}/grant",
    response_model=PermissionRead,
    summary="Grant consent (owner only)",
    description="Only the relationship owner may grant access to their own data.",
)
def grant_permission(
    relationship_id: uuid.UUID,
    permission_type: Literal["stress_level"],
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> PermissionRead:
    try:
        permission = relationship_service.grant_permission(
            db, relationship_id=relationship_id, owner_user_id=current_user.id, permission_type=permission_type
        )
    except (NotFoundError, PermissionDeniedError) as exc:
        raise _domain_error_to_http(exc)
    return PermissionRead.model_validate(permission)


@router.post(
    "/{relationship_id}/permissions/{permission_type}/revoke",
    response_model=PermissionRead,
    summary="Revoke consent (owner only)",
    description="Takes effect immediately: any subsequent stress-indicator request from the comfort person is rejected.",
)
def revoke_permission(
    relationship_id: uuid.UUID,
    permission_type: Literal["stress_level"],
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> PermissionRead:
    try:
        permission = relationship_service.revoke_permission(
            db, relationship_id=relationship_id, owner_user_id=current_user.id, permission_type=permission_type
        )
    except (NotFoundError, PermissionDeniedError) as exc:
        raise _domain_error_to_http(exc)
    return PermissionRead.model_validate(permission)


# --- Comfort-person stress view (Part 6) ---


@router.get(
    "/{relationship_id}/stress/today",
    response_model=ComfortStressView,
    summary="View a supported person's stress indicator (comfort person only)",
    description=(
        "Requires an accepted, non-revoked relationship where the caller is the comfort person, plus "
        "an active stress_level consent grant from the owner. Never returns journal, shoutout, or media "
        "content — see app/services/stress_service.py for exactly what feeds this indicator."
    ),
)
def get_comfort_stress_today(
    relationship_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> ComfortStressView:
    try:
        relationship = relationship_service.authorize_comfort_stress_access(
            db, relationship_id=relationship_id, caller_user_id=current_user.id
        )
    except (NotFoundError, PermissionDeniedError) as exc:
        raise _domain_error_to_http(exc)

    result = stress_service.compute_stress(db, user_id=relationship.owner_user_id)
    return ComfortStressView(
        score=result.score,
        level=result.level,
        confidence=result.confidence,
        calculated_at=result.calculated_at,
        data_window_start=result.data_window_start,
        data_window_end=result.data_window_end,
    )
