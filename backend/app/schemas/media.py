import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


class MediaAssetRead(BaseModel):
    """
    Used for the list endpoint and as the base of MediaAssetDetail.
    Deliberately has no `download_url` — generating a presigned URL per
    item in a paginated list is unnecessary work for a screen that's just
    showing titles/thumb) — a client asks for the download URL by fetching
    one specific item via GET /media/{id}.
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    media_type: str
    original_filename: Optional[str] = None
    # PHASE14B: the Vault rename target (see app/models/media_asset.py).
    # `None` until a caller PATCHes it — not an error state; every
    # pre-existing row (and every newly-uploaded one) starts this way.
    title: Optional[str] = None
    content_type: str
    file_size: int
    duration_seconds: Optional[int] = None
    created_at: datetime


class MediaAssetDetail(MediaAssetRead):
    """GET /media/{id}'s response — same fields, plus a fresh, time-limited download URL."""

    download_url: str
    download_url_expires_in_seconds: int


class MediaAssetUpdate(BaseModel):
    """
    PATCH /media/{media_id} request body (PHASE14B). This endpoint's only
    purpose is to set a new display title, so — unlike ShoutoutUpdate/
    JournalUpdate's "every field optional, omitted = unchanged" PATCH
    convention — `title` is required here: there is nothing else on this
    endpoint a caller could choose to omit.

    A blank or whitespace-only title is rejected with a 422 (both
    `min_length=1`, for a bare empty string, and the validator below, for
    a string that is non-empty but entirely whitespace) rather than
    silently stored as a meaningless name — this was an explicit product
    decision for PHASE14B, not an oversight. The value is otherwise stored
    exactly as sent (no server-side trimming), matching
    ShoutoutCreate/ShoutoutUpdate's existing convention of leaving
    whitespace handling to the client.
    """

    title: str = Field(min_length=1, max_length=200)

    @field_validator("title")
    @classmethod
    def _reject_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("title must not be blank or whitespace-only")
        return value
