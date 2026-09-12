"""
Domain-level exceptions raised by the service layer. Routes translate
these into HTTP responses — the service layer itself never imports
FastAPI/HTTPException, keeping business logic testable independent of
the web framework.
"""


class DomainError(Exception):
    """Base class for all service-layer errors."""


class EmailAlreadyRegisteredError(DomainError):
    pass


class InvalidCredentialsError(DomainError):
    pass


class InvalidRefreshTokenError(DomainError):
    pass


class InactiveUserError(DomainError):
    pass


# --- Generic errors, reused across the journal/mood/checklist domains (Phase 2) ---
#
# A single reusable pair, rather than one class per resource type
# (`JournalNotFoundError`, `MoodNotFoundError`, ...): every Phase 2 resource
# needs identical semantics — "not found, or not yours, respond the same
# way" and "a uniqueness rule was violated" — so a per-resource subclass
# would only add boilerplate, not clarity. The route layer already knows
# which resource it's handling; the exception doesn't need to.


class NotFoundError(DomainError):
    """
    Raised when a resource doesn't exist OR doesn't belong to the current
    user. Deliberately a single case for both — see app/dependencies on
    ownership scoping: a route must never be able to distinguish "this
    isn't yours" from "this doesn't exist" in its response, or it leaks
    the existence of other users' data (IDOR-by-timing/response-shape).
    """


class ConflictError(DomainError):
    """Raised when an operation would violate a uniqueness rule (e.g. two journal entries for the same date)."""


# --- Media-specific errors (Phase 3) ---


class UnsupportedMediaTypeError(DomainError):
    """Raised when an upload's content type isn't in the allow-list — see app/services/media_service.py."""


class FileTooLargeError(DomainError):
    """Raised when an upload exceeds settings.max_upload_size_bytes."""


class StorageError(DomainError):
    """
    Raised when the object-storage backend itself fails (upload, delete, or
    presigned-URL generation). Kept distinct from NotFoundError/ConflictError
    because it maps to a 502-class response, not a 404/409 — it means the
    infrastructure failed, not that the request was invalid.
    """


# --- Relationship / consent / stress errors (Phase 4) ---
#
# Invitation tokens that don't exist, have expired, or have already been
# used/declined/revoked all reuse NotFoundError above rather than a new
# type: they share NotFoundError's exact semantics (respond identically
# regardless of *why* the token isn't currently acceptable, so a caller
# probing with a guessed or leaked token learns nothing about its history).
# Likewise, "this relationship id doesn't exist, or you are neither its
# owner nor its comfort person" reuses NotFoundError for the same
# IDOR-resistance reason journals/moods/shoutouts already rely on it for.


class SelfRelationshipError(DomainError):
    """Raised when a user attempts to form a relationship with themselves (invite or accept)."""


class PermissionDeniedError(DomainError):
    """
    Raised when the caller *is* a legitimate party to the relationship in
    question (so its existence is already known to them — this is not an
    IDOR case, see NotFoundError above) but the specific action isn't
    currently allowed: the relationship isn't 'accepted' yet, has been
    revoked, or the owner hasn't granted (or has revoked) the specific
    consent the action requires. Maps to 403, not 404.
    """


# --- AI / weekly reflection errors (Phase 5) ---
#
# One family, deliberately mirroring how StorageError (Phase 3) is used:
# a failure in an external, out-of-process dependency (there, object
# storage; here, an AI provider) maps to a 502, never a 4xx — the
# request itself was valid, the infrastructure it depends on failed.
# NotFoundError is reused as-is for "this week's reflection doesn't
# exist, or isn't yours" (see app/repositories/reflection_repository.py),
# for the same IDOR-resistance reason every other Phase 1-4 resource
# relies on it for — no new type needed there.


class AIProviderError(DomainError):
    """
    Raised when the configured AIReflectionProvider fails for a reason not
    covered by a narrower subclass below (e.g. an HTTP 5xx from the
    provider, a connection error). Maps to 502. Every
    AIReflectionProvider implementation must raise only this class or one
    of its subclasses — never let a provider-SDK-specific exception
    escape app/services/ai/*.py.
    """


class AIProviderTimeoutError(AIProviderError):
    """Raised when the AI provider does not respond within the configured timeout."""


class AIProviderResponseError(AIProviderError):
    """
    Raised when the AI provider responds, but its output cannot be
    validated against app.schemas.reflection.AIReflectionOutput (malformed
    JSON, a missing/oversized field, or a safety refusal). The caller must
    never store this response as a valid reflection — see
    app/services/reflection_service.py.
    """


# --- Scheduler errors (Phase 11A) ---


class DuplicateScheduleTimeError(DomainError):
    """
    Raised when a PUT /scheduler/{entry_date} request contains the same
    scheduled_time in two different rows — see
    app/services/scheduler_service.py. Maps to 422 (the request itself is
    self-contradictory), distinct from ConflictError's 409 (a uniqueness
    rule violated against already-persisted data, or a concurrent-request
    race — see that module's docstring for how both layers cooperate).
    """
