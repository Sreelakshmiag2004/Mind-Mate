import re
import uuid
from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

# Deliberately not imported from app.models.media_asset.MEDIA_TYPES:
# schemas/ never imports models/ anywhere else in this codebase (it's a
# one-way dependency, models -> nothing, api/services -> schemas+models),
# so this small tuple is kept here in sync by hand instead. If the set of
# media types ever changes, both this and MEDIA_TYPES must be updated
# together.
_LEGACY_SOURCE_PREFIXES = ("image", "voice", "video")
LEGACY_SOURCE_PATTERN = re.compile(rf"^({'|'.join(_LEGACY_SOURCE_PREFIXES)}):\S+$")


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
    # PHASE14I-B. Returned (rather than kept purely internal) because the
    # migration flow genuinely needs it back: after GET /media lists a
    # user's items, the Flutter migration code has to tell which of its
    # local Hive records already migrated without issuing one lookup call
    # per item — matching this field against a local
    # `"<type>:<hive-id>"` key is how it does that. `None` for every
    # ordinary (non-legacy) upload, which is every row before this phase
    # and the overwhelming majority of rows after it.
    legacy_source: Optional[str] = None
    # PHASE14I-B. The preserved original Hive creation date — see
    # app/models/media_asset.py's module docstring for why this is a
    # separate field from `created_at` rather than a replacement for it.
    # Always timezone-aware UTC when present (see the validator on
    # MediaUploadLegacyFields below for how a client-supplied value gets
    # there). `None` for every ordinary upload.
    #
    # Client display guidance: use `legacy_created_at` (when non-null) as
    # the note's "real" date for chronology/sorting shown to the user;
    # `created_at` is when the row was migrated into this backend, not
    # when the note was originally made, and should not be presented as
    # the note's date for a migrated item.
    legacy_created_at: Optional[datetime] = None
    created_at: datetime


class MediaUploadLegacyFields(BaseModel):
    """
    PHASE14I-B. Validates the two optional `legacy_source`/
    `legacy_created_at` multipart Form fields accepted by
    `POST /media/upload`, before either ever reaches the service layer.

    This is a separate schema — rather than inline checks in
    app/api/routes/media.py — for the same reason MediaAssetUpdate is:
    it lets the exact same validation rules be exercised directly (e.g.
    from a test or a future direct service-layer caller) without going
    through HTTP multipart parsing.

    Both fields are optional and independent of each other; omitting both
    (the normal-upload case, and every upload before this phase) is the
    default and leaves both stored as NULL.
    """

    legacy_source: Optional[str] = Field(default=None, max_length=300)
    legacy_created_at: Optional[datetime] = None

    @field_validator("legacy_source")
    @classmethod
    def _validate_legacy_source(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return value
        if not value.strip():
            raise ValueError("legacy_source must not be blank")
        if not LEGACY_SOURCE_PATTERN.match(value):
            raise ValueError(
                "legacy_source must look like '<image|voice|video>:<legacy-hive-id>' "
                f"(got {value!r})"
            )
        return value

    @field_validator("legacy_created_at")
    @classmethod
    def _normalize_to_utc(cls, value: Optional[datetime]) -> Optional[datetime]:
        """
        Every DateTime column in this schema is timezone-aware UTC (see
        app/models/base.py's TimestampMixin and app/models/media_asset.py)
        and every server-assigned timestamp elsewhere in this codebase
        uses `datetime.now(timezone.utc)` — this normalizes a
        client-supplied value to that same convention rather than
        inventing a second, incompatible one.

        A value that already carries an explicit UTC offset (e.g. an
        ISO-8601 string ending in `Z` or `+00:00`) is converted to UTC
        as-is. A *naive* value (no offset at all) is assumed to already
        be UTC and is stamped with `tzinfo=UTC` rather than converted —
        there is no reliable way to know what offset a naive value was
        really in.

        This matters here specifically because `vault.dart`'s Hive
        records are timestamped with plain `DateTime.now()` (local device
        time, not UTC, and Hive does not itself persist a UTC/offset
        marker). Ambiguity is unavoidable purely from the wire format, so
        the migration client is responsible for calling `.toUtc()` on the
        original Hive `DateTime` (e.g. `hiveDate.toUtc().toIso8601String()`,
        which produces an explicit `Z`-suffixed string) before sending
        it — see the PHASE14I-B implementation report, "Timezone/date
        handling", for this documented as a limitation of the wire
        contract rather than something this backend can detect or fix.
        """
        if value is None:
            return value
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


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
