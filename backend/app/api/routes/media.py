import uuid
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.database import get_db
from app.core.exceptions import FileTooLargeError, NotFoundError, StorageError, UnsupportedMediaTypeError
from app.dependencies.auth import get_current_active_user
from app.dependencies.pagination import PaginationParams, pagination_params
from app.models.user import User
from app.schemas.common import Page
from app.schemas.media import MediaAssetDetail, MediaAssetRead
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
        "never trust a client-declared type. See backend/README.md for the exact allow-list and the size limit."
    ),
)
async def upload_media(
    file: UploadFile = File(...),
    duration_seconds: Optional[int] = Form(default=None, ge=0, description="Only meaningful for voice/video; client-reported, display-only"),
    db: Session = Depends(get_db),
    storage: ObjectStorageService = Depends(get_storage_service),
    current_user: User = Depends(get_current_active_user),
) -> MediaAssetRead:
    data = await file.read()

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
    description="Only the authenticated user's own uploads. Optional `media_type` filter (voice/image/video).",
)
def list_media(
    media_type: Optional[str] = Query(default=None, pattern="^(voice|image|video)$"),
    pagination: PaginationParams = Depends(pagination_params),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Page[MediaAssetRead]:
    items, total = media_service.list_media(
        db, user_id=current_user.id, media_type=media_type, limit=pagination.limit, offset=pagination.offset
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
