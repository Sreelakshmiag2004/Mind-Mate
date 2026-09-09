"""
Import every model module here so that Base.metadata is fully populated
as soon as `app.models` is imported — this is what Alembic's env.py and
`Base.metadata.create_all` (tests only, never production) rely on.
"""

from app.models.base import Base
from app.models.user import User
from app.models.profile import Profile
from app.models.auth_session import AuthSession
from app.models.journal import JournalEntry
from app.models.mood import MoodEntry
from app.models.checklist import ChecklistItem, ChecklistCompletion
from app.models.shoutout import Shoutout
from app.models.media_asset import MediaAsset
from app.models.relationship import Relationship
from app.models.relationship_invitation import RelationshipInvitation
from app.models.relationship_permission import RelationshipPermission

__all__ = [
    "Base",
    "User",
    "Profile",
    "AuthSession",
    "JournalEntry",
    "MoodEntry",
    "ChecklistItem",
    "ChecklistCompletion",
    "Shoutout",
    "MediaAsset",
    "Relationship",
    "RelationshipInvitation",
    "RelationshipPermission",
]
