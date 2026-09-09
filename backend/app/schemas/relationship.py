import uuid
from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

# Mirrors app.models.relationship.RELATIONSHIP_TYPES exactly — kept as a
# literal here (rather than imported) so this schema module has zero
# dependency on the ORM layer, matching every other schemas/*.py file in
# this codebase.
RelationshipType = Literal["mom", "dad", "siblings", "best_friend", "love", "grandparents", "other"]

PermissionType = Literal["stress_level"]


def _validate_custom_label(relationship_type: str, custom_relationship_label: Optional[str]) -> None:
    if relationship_type == "other":
        if not custom_relationship_label or not custom_relationship_label.strip():
            raise ValueError("custom_relationship_label is required when relationship_type is 'other'")
    elif custom_relationship_label is not None:
        raise ValueError("custom_relationship_label may only be set when relationship_type is 'other'")


class InvitationCreate(BaseModel):
    relationship_type: RelationshipType
    custom_relationship_label: Optional[str] = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def _check_custom_label(self) -> "InvitationCreate":
        _validate_custom_label(self.relationship_type, self.custom_relationship_label)
        return self


class InvitationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    relationship_type: RelationshipType
    custom_relationship_label: Optional[str]
    status: Literal["pending", "accepted", "declined", "revoked"]
    expires_at: datetime
    created_at: datetime


class InvitationCreateResponse(InvitationRead):
    # The raw, opaque token — the only time it is ever transmitted. Never
    # logged, never stored (only its SHA-256 hash is persisted), and not
    # returned by any other endpoint. The future frontend is responsible
    # for embedding this in whatever deep-link scheme it uses; this phase
    # deliberately returns only the token itself, not a pre-built URL.
    token: str


class InvitationPreview(BaseModel):
    """
    What an authenticated prospective invitee sees before deciding whether
    to accept — deliberately minimal: no owner email, no owner user id,
    nothing beyond what's needed to make an informed accept/decline
    decision.
    """

    relationship_type: RelationshipType
    custom_relationship_label: Optional[str]
    owner_display_name: Optional[str]
    status: Literal["pending", "accepted", "declined", "revoked"]
    expires_at: datetime
    is_expired: bool


class RelationshipRead(BaseModel):
    id: uuid.UUID
    owner_user_id: uuid.UUID
    comfort_user_id: uuid.UUID
    relationship_type: RelationshipType
    custom_relationship_label: Optional[str]
    status: Literal["accepted", "revoked"]
    # Which side of the relationship the caller is on, so a single
    # combined "my relationships" response is self-describing per row
    # without the client having to compare ids itself.
    my_role: Literal["owner", "comfort_person"]
    counterparty_display_name: Optional[str]
    accepted_at: datetime
    revoked_at: Optional[datetime]
    created_at: datetime
    updated_at: datetime


class PermissionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    relationship_id: uuid.UUID
    permission_type: PermissionType
    granted: bool
    granted_at: Optional[datetime]
    revoked_at: Optional[datetime]
