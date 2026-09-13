"""
Vault-lock endpoints (PHASE14B — see app/models/vault_lock.py and the
PHASE14B implementation report for the full contract). Every response
uses the same VaultLockRead shape (`configured`/`last_viewed_at`/
`previous_viewed_at`) regardless of which endpoint produced it, and never
includes `password`/`password_hash` under any circumstance.

Two endpoints suggested by the PHASE14B task are deliberately NOT
implemented here:

* `POST /vault/unlock/biometric` — the existing Flutter biometric unlock
  (`local_auth` in `vault_password.dart`) is entirely device-local, with
  no server-verifiable credential of any kind. Inventing a protocol for
  it now would mean guessing at a security design with no spec — worse
  than leaving it explicitly deferred. Biometric integration is deferred
  to the Flutter Vault-lock phase, once a concrete, reviewed protocol
  (what does the server actually verify?) exists.
* `POST /vault/lock/viewed` — this phase's only successful-view trigger
  is a correct password submitted to `POST /vault/unlock`, so a separate
  "record a view" endpoint would have no real caller yet; adding one
  speculatively would be an unused, untested surface. `last_viewed_at`
  is updated inside `unlock()` itself instead (see
  app/services/vault_service.py). If a future phase adds another way to
  successfully enter the Vault (e.g. a server-verified biometric flow),
  a dedicated "record a view" endpoint can be added then, once there is
  a second real caller for it.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import ConflictError, InvalidCredentialsError
from app.dependencies.auth import get_current_active_user
from app.models.user import User
from app.models.vault_lock import VaultLock
from app.schemas.vault import VaultLockCreate, VaultLockRead, VaultUnlockRequest
from app.services import vault_service

router = APIRouter(prefix="/vault", tags=["vault"])


def _to_read(lock: Optional[VaultLock]) -> VaultLockRead:
    if lock is None:
        return VaultLockRead(configured=False, last_viewed_at=None, previous_viewed_at=None)
    return VaultLockRead(
        configured=True, last_viewed_at=lock.last_viewed_at, previous_viewed_at=lock.previous_viewed_at
    )


@router.get(
    "/lock",
    response_model=VaultLockRead,
    summary="Get your Vault lock state",
    description="Always 200 — `configured: false` means no Vault password has been set yet; never 404.",
)
def get_lock(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VaultLockRead:
    lock = vault_service.get_state(db, user_id=current_user.id)
    return _to_read(lock)


@router.post(
    "/lock",
    response_model=VaultLockRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create your Vault password",
    description=(
        "One per user — 409 if you already have one. Stores only an Argon2 hash; the password itself is "
        "never persisted or returned."
    ),
)
def create_lock(
    payload: VaultLockCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VaultLockRead:
    try:
        lock = vault_service.create_lock(db, user_id=current_user.id, password=payload.password)
    except ConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return _to_read(lock)


@router.post(
    "/unlock",
    response_model=VaultLockRead,
    summary="Verify your Vault password",
    description=(
        "401 for any incorrect attempt, including when no Vault lock has been created yet — this endpoint "
        "never reveals which of those two happened. On success, updates last_viewed_at (shifting the "
        "previous value into previous_viewed_at)."
    ),
)
def unlock(
    payload: VaultUnlockRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VaultLockRead:
    try:
        lock = vault_service.unlock(db, user_id=current_user.id, password=payload.password)
    except InvalidCredentialsError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc))
    return _to_read(lock)
