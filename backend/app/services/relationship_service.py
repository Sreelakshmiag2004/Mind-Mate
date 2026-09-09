"""
Business logic for comfort-person relationships, invitation tokens, and
consent — see app/models/relationship*.py for the schema-level reasoning.
This module is the single place relationship/consent authorization rules
live, per the Phase 4 brief's "centralize relationship authorization" —
app/api/routes/relationships.py and app/api/routes/stress.py never
duplicate an ownership or consent check themselves.
"""

import uuid
from datetime import datetime, timezone
from typing import Literal, Optional, Sequence

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError, SelfRelationshipError
from app.core.security import generate_invitation_token, hash_invitation_token, invitation_token_expiry
from app.models.relationship import Relationship
from app.models.relationship_invitation import RelationshipInvitation
from app.models.relationship_permission import RelationshipPermission
from app.repositories import (
    profile_repository,
    relationship_invitation_repository,
    relationship_permission_repository,
    relationship_repository,
)
from app.schemas.relationship import InvitationCreate

STRESS_LEVEL_PERMISSION = "stress_level"


def _display_name(db: Session, user_id: uuid.UUID) -> Optional[str]:
    profile = profile_repository.get_by_user_id(db, user_id)
    return profile.full_name if profile is not None else None


def _invitation_is_usable(invitation: RelationshipInvitation) -> bool:
    if invitation.status != "pending":
        return False
    expires_at = invitation.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at > datetime.now(timezone.utc)


# --- Invitations ---


def create_invitation(
    db: Session, *, owner_user_id: uuid.UUID, payload: InvitationCreate
) -> tuple[RelationshipInvitation, str]:
    raw_token = generate_invitation_token()
    invitation = relationship_invitation_repository.create(
        db,
        owner_user_id=owner_user_id,
        relationship_type=payload.relationship_type,
        custom_relationship_label=payload.custom_relationship_label,
        token_hash=hash_invitation_token(raw_token),
        expires_at=invitation_token_expiry(),
    )
    db.commit()
    db.refresh(invitation)
    return invitation, raw_token


def get_invitation_preview(db: Session, *, token: str) -> tuple[RelationshipInvitation, Optional[str], bool]:
    """
    Returns (invitation, owner_display_name, is_expired). Raises
    NotFoundError for a token that doesn't exist or is no longer 'pending'
    (already accepted/declined/revoked) — an expired-but-still-pending
    token is returned (not raised) with is_expired=True, so a caller can
    render a clear "this invite has expired" message rather than an
    indistinguishable 404. Accept/decline still hard-reject an expired
    token — see accept_invitation/decline_invitation.
    """
    invitation = relationship_invitation_repository.get_by_token_hash(db, hash_invitation_token(token))
    if invitation is None or invitation.status != "pending":
        raise NotFoundError("Invitation not found")

    expires_at = invitation.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    is_expired = expires_at <= datetime.now(timezone.utc)

    return invitation, _display_name(db, invitation.owner_user_id), is_expired


def accept_invitation(db: Session, *, token: str, accepting_user_id: uuid.UUID) -> Relationship:
    invitation = relationship_invitation_repository.get_by_token_hash(db, hash_invitation_token(token))
    if invitation is None or not _invitation_is_usable(invitation):
        raise NotFoundError("Invitation not found, expired, or already used")

    if invitation.owner_user_id == accepting_user_id:
        raise SelfRelationshipError("You cannot accept your own invitation")

    existing = relationship_repository.get_active_pair(
        db, owner_user_id=invitation.owner_user_id, comfort_user_id=accepting_user_id
    )
    if existing is not None:
        raise ConflictError("An active relationship already exists between these users")

    now = datetime.now(timezone.utc)

    # Atomic: the invitation is consumed and the relationship + its
    # founding consent grant are created in the same DB transaction, then
    # committed once. If anything below raises, nothing is persisted.
    relationship = relationship_repository.create(
        db,
        owner_user_id=invitation.owner_user_id,
        comfort_user_id=accepting_user_id,
        relationship_type=invitation.relationship_type,
        custom_relationship_label=invitation.custom_relationship_label,
        accepted_at=now,
    )

    # Creating and sharing the invitation IS the owner's consent decision
    # in this product (the info dialog in regfav.dart tells the owner
    # exactly what accepting enables before they ever generate the link).
    # That consent is materialized here as an explicit, independently
    # revocable RelationshipPermission row — not as an implicit property
    # of the relationship's 'accepted' status — so the owner can later
    # revoke just the stress-sharing consent without deleting the
    # relationship itself. See app/models/relationship_permission.py.
    relationship_permission_repository.create(
        db, relationship_id=relationship.id, permission_type=STRESS_LEVEL_PERMISSION, granted=True, granted_at=now
    )

    invitation.status = "accepted"
    invitation.accepted_at = now
    invitation.accepted_by_user_id = accepting_user_id
    invitation.resulting_relationship_id = relationship.id
    db.add(invitation)

    db.commit()
    db.refresh(relationship)
    return relationship


def decline_invitation(db: Session, *, token: str, declining_user_id: uuid.UUID) -> RelationshipInvitation:
    invitation = relationship_invitation_repository.get_by_token_hash(db, hash_invitation_token(token))
    if invitation is None or not _invitation_is_usable(invitation):
        raise NotFoundError("Invitation not found, expired, or already used")

    if invitation.owner_user_id == declining_user_id:
        raise SelfRelationshipError("You cannot decline your own invitation")

    invitation.status = "declined"
    invitation.declined_at = datetime.now(timezone.utc)
    db.add(invitation)
    db.commit()
    db.refresh(invitation)
    return invitation


def list_invitations_for_owner(
    db: Session, *, owner_user_id: uuid.UUID, limit: int, offset: int
) -> tuple[Sequence[RelationshipInvitation], int]:
    return relationship_invitation_repository.list_for_owner(db, owner_user_id=owner_user_id, limit=limit, offset=offset)


# --- Relationships ---


def get_relationship_for_party(db: Session, *, relationship_id: uuid.UUID, user_id: uuid.UUID) -> Relationship:
    relationship = relationship_repository.get_by_id_for_party(db, relationship_id=relationship_id, user_id=user_id)
    if relationship is None:
        raise NotFoundError("Relationship not found")
    return relationship


def to_relationship_read_dict(db: Session, relationship: Relationship, caller_user_id: uuid.UUID) -> dict:
    """
    Shapes one Relationship row into the dict app.schemas.relationship.RelationshipRead
    expects, resolving `my_role`/`counterparty_display_name` relative to
    whichever party is asking. The one place this mapping happens, used by
    both list_relationships below and every route that hands back a single
    RelationshipRead (accept/revoke) — see app/api/routes/relationships.py.
    """
    role = "owner" if relationship.owner_user_id == caller_user_id else "comfort_person"
    counterparty_id = relationship.comfort_user_id if role == "owner" else relationship.owner_user_id
    return {
        "id": relationship.id,
        "owner_user_id": relationship.owner_user_id,
        "comfort_user_id": relationship.comfort_user_id,
        "relationship_type": relationship.relationship_type,
        "custom_relationship_label": relationship.custom_relationship_label,
        "status": relationship.status,
        "my_role": role,
        "counterparty_display_name": _display_name(db, counterparty_id),
        "accepted_at": relationship.accepted_at,
        "revoked_at": relationship.revoked_at,
        "created_at": relationship.created_at,
        "updated_at": relationship.updated_at,
    }


def list_relationships(
    db: Session, *, user_id: uuid.UUID, role: Literal["owner", "comfort_person"], limit: int, offset: int
) -> tuple[list[dict], int]:
    if role == "owner":
        items, total = relationship_repository.list_for_owner(db, owner_user_id=user_id, limit=limit, offset=offset)
    else:
        items, total = relationship_repository.list_for_comfort_user(
            db, comfort_user_id=user_id, limit=limit, offset=offset
        )
    rows = [to_relationship_read_dict(db, item, user_id) for item in items]
    return rows, total


def revoke_relationship(db: Session, *, relationship_id: uuid.UUID, caller_user_id: uuid.UUID) -> Relationship:
    relationship = get_relationship_for_party(db, relationship_id=relationship_id, user_id=caller_user_id)
    if relationship.status == "revoked":
        return relationship

    now = datetime.now(timezone.utc)
    relationship.status = "revoked"
    relationship.revoked_at = now
    db.add(relationship)

    # Revoking the relationship invalidates every consent grant on it —
    # access must respect this immediately (Phase 4 brief). Permission
    # rows are stamped revoked here rather than left "granted=True but
    # orphaned", so a permissions listing never shows a stale grant on a
    # dead relationship.
    for permission in relationship_permission_repository.list_for_relationship(db, relationship_id=relationship.id):
        if permission.granted:
            permission.granted = False
            permission.revoked_at = now
            db.add(permission)

    db.commit()
    db.refresh(relationship)
    return relationship


# --- Consent / permissions ---


def list_permissions(
    db: Session, *, relationship_id: uuid.UUID, caller_user_id: uuid.UUID
) -> Sequence[RelationshipPermission]:
    # Either party may see what's currently shared — this is read-only and
    # discloses nothing beyond "is stress_level currently granted", which
    # both the owner and the comfort person already implicitly know.
    get_relationship_for_party(db, relationship_id=relationship_id, user_id=caller_user_id)
    return relationship_permission_repository.list_for_relationship(db, relationship_id=relationship_id)


def _set_permission(
    db: Session, *, relationship_id: uuid.UUID, owner_user_id: uuid.UUID, permission_type: str, granted: bool
) -> RelationshipPermission:
    relationship = get_relationship_for_party(db, relationship_id=relationship_id, user_id=owner_user_id)
    if relationship.owner_user_id != owner_user_id:
        # The caller is a legitimate party (comfort person) but consent
        # over the owner's own data is the owner's decision alone.
        raise PermissionDeniedError("Only the relationship owner can manage consent")

    now = datetime.now(timezone.utc)
    permission = relationship_permission_repository.get(
        db, relationship_id=relationship_id, permission_type=permission_type
    )
    if permission is None:
        permission = relationship_permission_repository.create(
            db, relationship_id=relationship_id, permission_type=permission_type, granted=granted, granted_at=now
        )
    else:
        permission.granted = granted
        permission.granted_at = now if granted else permission.granted_at
        permission.revoked_at = None if granted else now
        db.add(permission)

    db.commit()
    db.refresh(permission)
    return permission


def grant_permission(
    db: Session, *, relationship_id: uuid.UUID, owner_user_id: uuid.UUID, permission_type: str
) -> RelationshipPermission:
    return _set_permission(
        db, relationship_id=relationship_id, owner_user_id=owner_user_id, permission_type=permission_type, granted=True
    )


def revoke_permission(
    db: Session, *, relationship_id: uuid.UUID, owner_user_id: uuid.UUID, permission_type: str
) -> RelationshipPermission:
    return _set_permission(
        db, relationship_id=relationship_id, owner_user_id=owner_user_id, permission_type=permission_type, granted=False
    )


# --- Comfort-person stress authorization (Part 6) ---


def authorize_comfort_stress_access(
    db: Session, *, relationship_id: uuid.UUID, caller_user_id: uuid.UUID
) -> Relationship:
    """
    Every check the Phase 4 brief requires for GET
    .../stress/today, centralized in one place so no route re-implements
    (and potentially gets wrong) any of them:

      1. Caller is authenticated — enforced by the route's dependency, not here.
      2/3/4. Relationship exists, and (5) is currently 'accepted' (never
         pending/nonexistent, never revoked).
      5. Caller is specifically the comfort_user side, not the owner
         (the owner already has their own /stress/today for their own data).
      6. The 'stress_level' permission is currently granted.

    Raises NotFoundError if the caller isn't a party to this relationship
    at all (id doesn't exist, or belongs to two different other users) —
    that's an IDOR probe and must not be distinguishable from "doesn't
    exist". Raises PermissionDeniedError (403) for every other failure,
    since at that point the caller already legitimately knows this
    relationship exists.
    """
    relationship = get_relationship_for_party(db, relationship_id=relationship_id, user_id=caller_user_id)

    if relationship.comfort_user_id != caller_user_id:
        raise PermissionDeniedError("Only the comfort person may view this relationship's stress indicator")

    if relationship.status != "accepted":
        raise PermissionDeniedError("This relationship is not active")

    permission = relationship_permission_repository.get(
        db, relationship_id=relationship.id, permission_type=STRESS_LEVEL_PERMISSION
    )
    if permission is None or not permission.granted:
        raise PermissionDeniedError("Consent to view the stress indicator has not been granted")

    return relationship
