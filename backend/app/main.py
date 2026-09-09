from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import auth, checklists, health, journals, media, moods, reflections, relationships, shoutouts, stress
from app.core.config import settings

app = FastAPI(
    title="MindMate API",
    version="0.5.0",
    description=(
        "MindMate backend — Phase 5 (users, profiles, authentication, journals, moods, checklists, "
        "shoutouts, media/voice-note storage, comfort-person relationships with explicit consent, a "
        "deterministic rule-based stress indicator, and an AI-generated personalized weekly "
        "reflection built from privacy-controlled activity aggregates). This service is entirely "
        "independent of Firebase; it is the planned replacement, not an extension, of the Flutter "
        "app's current Firebase Auth/Firestore/Storage backend."
    ),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(journals.router)
app.include_router(moods.router)
app.include_router(checklists.router)
app.include_router(shoutouts.router)
app.include_router(media.router)
app.include_router(relationships.router)
app.include_router(stress.router)
app.include_router(reflections.router)
