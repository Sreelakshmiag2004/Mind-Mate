import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


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
    content_type: str
    file_size: int
    duration_seconds: Optional[int] = None
    created_at: datetime


class MediaAssetDetail(MediaAssetRead):
    """GET /media/{id}'s response — same fields, plus a fresh, time-limited download URL."""

    download_url: str
    download_url_expires_in_seconds: int
