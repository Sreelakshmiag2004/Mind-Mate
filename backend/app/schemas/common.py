"""
Shared, resource-agnostic schemas. `Page` exists once here rather than
being redefined per resource because journals and moods both need
identical list-pagination shape — this is the one generic abstraction
Phase 2 introduces, and only because two independent domains needed the
exact same thing.
"""

from typing import Generic, List, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    items: List[T]
    total: int
    limit: int
    offset: int
