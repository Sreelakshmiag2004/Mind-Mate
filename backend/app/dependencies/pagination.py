from dataclasses import dataclass

from fastapi import Query


@dataclass
class PaginationParams:
    limit: int
    offset: int


def pagination_params(
    limit: int = Query(default=30, ge=1, le=100, description="Max items to return (1-100)"),
    offset: int = Query(default=0, ge=0, description="Number of items to skip"),
) -> PaginationParams:
    return PaginationParams(limit=limit, offset=offset)
