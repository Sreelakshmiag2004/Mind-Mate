from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict


class AgeGroup(str, Enum):
    """
    Mirrors the five options `enter_details_page.dart` / `edit_profile_page.dart`
    currently offer. Kept as an API-layer enum (not a DB CHECK constraint)
    so the bracket labels can change without an Alembic migration —
    see app/models/profile.py.
    """

    TEENAGERS_13_17 = "Teenagers(13-17)"
    YOUNG_ADULTS_18_24 = "Young adults(18-24)"
    ADULTS_25_34 = "Adults(25-34)"
    MID_AGED_35_54 = "Mid-aged(35-54)"
    SENIORS_55_PLUS = "Seniors(55 & above)"


class ProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    full_name: Optional[str] = None
    age_group: Optional[str] = None
    phone: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    profile_image_url: Optional[str] = None
    onboarding_completed_at: Optional[datetime] = None
