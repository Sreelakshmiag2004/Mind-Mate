import uuid
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, Response, UploadFile, status
from pydantic import ValidationError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.database import get_db
from app.core.exceptions import FileTooLargeError, NotFoundError, StorageError, UnsupportedMediaTypeError
from app.dependencies.auth import get_current_active_user
from app.dependencies.pagination import PaginationParams, pagination_params
from app.models.user import User
from app.schemas.common import Page
from app.schemas.media import MediaAssetDetail, MediaAssetRead, MediaAssetUpdate, MediaUploadLegacyFields
from app.services import media_service
from app.services.media_service import DOWNLOAD_URL_EXPIRES_IN_SECONDS
from app.services.storage import ObjectStorageService, get_storage_service

router = APIRouter(prefix="/media", tags=["media"])


@router.post(
    "/upload",
    response_model=MediaAssetRead,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a voice note, image, or video",
    description=(
        "Direct multipart upload. `media_type` is derived server-side from the file's content type — "
        "never trust a client-declared type. See backend/README.md for the exact allow-list and the size limit. "
        "PHASE14I-B: optionally accepts `legacy_source`/`legacy_created_at` for the Vault legacy-Hive-media "
        "migration; omit both for a normal upload. Duplicate-safe: a repeated request with the same "
        "`legacy_source` for this user returns the existing MediaAsset rather than creating another one — "
        "see backend/README.md."
    ),
)
async def upload_media(
    request: Request,
    file: UploadFile = File(...),
    duration_seconds: Optional[int] = Form(default=None, ge=0, description="Only meaningful for voice/video; client-reported, display-only"),
    legacy_source: Optional[str] = Form(
        default=None,
        description=(
            "PHASE14I-B, optional. One of 'image:<id>' / 'voice:<id>' / 'video:<id>' identifying the legacy "
            "Hive record this upload migrates. Omit for a normal upload. A repeated upload with a "
            "legacy_source already recorded for this user returns the existing MediaAsset unchanged."
        ),
    ),
    legacy_created_at: Optional[str] = Form(
        default=None,
        description=(
            "PHASE14I-B, optional. The original Hive DateTime as an ISO-8601 string, preserved verbatim in "
            "legacy_created_at. Send it already converted to UTC (e.g. Dart's `.toUtc().toIso8601String()`) — "
            "see backend/README.md for why a naive value cannot be safely reinterpreted server-side."
        ),
    ),
    db: Session = Depends(get_db),
    storage: ObjectStorageService = Depends(get_storage_service),
    current_user: User = Depends(get_current_active_user),
) -> MediaAssetRead:
    data = await file.read()

    # FastAPI's own Form-parameter binding treats an explicitly-submitted
    # BLANK multipart field the same as an omitted one for any Optional
    # Form field (see fastapi.dependencies.utils._get_multidict_value:
    # `value == ""` is coerced to the field's default) — so by the time
    # `legacy_source` above is bound, "the field was present but blank"
    # and "the field was never sent" are already indistinguishable. That
    # collapse is exactly wrong for `legacy_source`: an explicit blank
    # must be rejected with 422 (PHASE14I-B contract), not silently
    # treated as "normal upload." Re-reading the raw multipart form here
    # recovers the distinction before it's lost.
    raw_form = await request.form()
    if "legacy_source" in raw_form:
        legacy_source = raw_form.get("legacy_source")

    try:
        legacy_fields = MediaUploadLegacyFields(legacy_source=legacy_source, legacy_created_at=legacy_created_at)
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=[{"loc": err["loc"], "msg": err["msg"], "type": err["type"]} for err in exc.errors()],
        )

    try:
        # `media_service.upload_media` makes a blocking network call to
        # object storage; this route is `async def` (needed for `await
        # file.read()` above), so without this it would block the whole
        # event loop for as long as that call takes — including a
        # MinIO/S3 outage's full connect timeout. `run_in_threadpool`
        # dispatches it to a worker thread instead, exactly like FastAPI
        # already does automatically for the plain `def` routes below.
        asset = await run_in_threadpool(
            media_service.upload_media,
            db,
            storage,
            user_id=current_user.id,
            data=data,
            content_type=file.content_type,
            original_filename=file.filename,
            duration_seconds=duration_seconds,
            legacy_source=legacy_fields.legacy_source,
            legacy_created_at=legacy_fields.legacy_created_at,
        )
    except UnsupportedMediaTypeError as exc:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail=str(exc))
    except FileTooLargeError as exc:
        raise HTTPException(status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail=str(exc))
    except StorageError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))

    return MediaAssetRead.model_validate(asset)


@router.get(
    "",
    response_model=Page[MediaAssetRead],
    summary="List your media",
    description=(
        "Only the authenticated user's own uploads. Optional `media_type` filter (voice/image/video). "
        "PHASE14I-B: optional exact-match `legacy_source` filter for the Vault legacy-Hive-media migration "
        "lookup — e.g. `GET /media?legacy_source=image:abc` — returns that one item if this user has already "
        "migrated it, or an empty page if not. Never returns another user's matching legacy_source."
    ),
)
def list_media(
    media_type: Optional[str] = Query(default=None, pattern="^(voice|image|video)$"),
    legacy_source: Optional[str] = Query(default=None, max_length=300),
    pagination: PaginationParams = Depends(pagination_params),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Page[MediaAssetRead]:
    items, total = media_service.list_media(
        db,
        user_id=current_user.id,
        media_type=media_type,
        legacy_source=legacy_source,
        limit=pagination.limit,
        offset=pagination.offset,
    )
    return Page[MediaAssetRead](
        items=[MediaAssetRead.model_validate(item) for item in items],
        total=total,
        limit=pagination.limit,
        offset=pagination.offset,
    )


@router.get(
    "/{media_id}",
    response_model=MediaAssetDetail,
    summary="Retrieve one media item, with a fresh download URL",
    description="404 if it doesn't exist OR isn't yours. The download URL is time-limited and regenerated on every call.",
)
def get_media(
    media_id: uuid.UUID,
    db: Session = Depends(get_db),
    storage: ObjectStorageService = Depends(get_storage_service),
    current_user: User = Depends(get_current_active_user),
) -> MediaAssetDetail:
    try:
        asset = media_service.get_media(db, user_id=current_user.id, media_id=media_id)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))

    try:
        download_url = media_service.build_download_url(storage, asset)
    except StorageError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))

    return MediaAssetDetail(
        **MediaAssetRead.model_validate(asset).model_dump(),
        download_url=download_url,
        download_url_expires_in_seconds=DOWNLOAD_URL_EXPIRES_IN_SECONDS,
    )


@router.patch(
    "/{media_id}",
    response_model=MediaAssetRead,
    summary="Rename a media item",
    description=(
        "PHASE14B. Updates ONLY the display `title` — never object_key, media_type, duration_seconds, "
        "original_filename, or ownership; the stored object itself is never renamed. 404 if it doesn't exist "
        "OR isn't yours. A blank/whitespace-only title is rejected with 422."
    ),
)
def update_media(
    media_id: uuid.UUID,
    payload: MediaAssetUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> MediaAssetRead:
    try:
        asset = media_service.update_media_title(
            db, user_id=current_user.id, media_id=media_id, title=payload.title
        )
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return MediaAssetRead.model_validate(asset)


@router.delete(
    "/{media_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a media item",
    description="Deletes the stored object first, then its metadata — see backend/README.md for why that ordering.",
)
def delete_media(
    media_id: uuid.UUID,
    db: Session = Depends(get_db),
    storage: ObjectStorageService = Depends(get_storage_service),
    current_user: User = Depends(get_current_active_user),
) -> Response:
    try:
        media_service.delete_media(db, storage, user_id=current_user.id, media_id=media_id)
    except NotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except StorageError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))
    return Response(status_code=status.HTTP_204_NO_CONTENT)
