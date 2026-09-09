from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.database import get_db

router = APIRouter(tags=["health"])


@router.get("/health")
def health_check(response: Response, db: Session = Depends(get_db)) -> dict:
    """
    Liveness + database-connectivity check in one call. Returns 200 with
    `database: "connected"` when a real round-trip query to PostgreSQL
    succeeds, or 503 with the error surfaced when it doesn't — this is
    the concrete, automatable way to "verify PostgreSQL connectivity"
    rather than just trusting that the app process started.
    """
    try:
        db.execute(text("SELECT 1"))
        database_status = "connected"
    except Exception as exc:  # pragma: no cover - exercised only when DB is down
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "degraded", "database": "unreachable", "detail": str(exc)}

    return {"status": "ok", "database": database_status}
