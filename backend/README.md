# MindMate Backend — Phase 5: AI-Generated Weekly Reflection

This is the new MindMate backend: **Python / FastAPI / PostgreSQL / S3-compatible
object storage**, built to fully replace the Flutter app's current Firebase
Auth + Firestore + Storage backend. It does not use Firebase in any way, and
it does not talk to the existing Firebase project. The Flutter app has not
been modified and still points at Firebase — this backend is a parallel,
independent build.

* **Phase 1** (done): users, profiles, authentication (register / login /
  refresh / logout / me).
* **Phase 2** (done): journals, moods, checklists.
* **Phase 3** (done): shoutouts (a private daily venting entry — see
  "Shoutout data model" for why it is *not* a messaging feature) and Vault
  media — voice notes, images, videos — stored in S3-compatible object
  storage (MinIO locally) with only metadata in PostgreSQL.
* **Phase 4** (done): comfort-person relationships with explicit,
  revocable consent (replacing the old app's unverified `mindmate://invite`
  deep link — see "Relationship & invitation model") and a deterministic,
  rule-based stress indicator (giving real backend substance to
  `favorite_page.dart`'s "View today's stress level" button, currently
  wired to a TODO) that a consented comfort person can view for the person
  they support.
* **Phase 5** (this phase): a personalized, AI-generated weekly reflection —
  a short, supportive summary of one user's own mood/checklist/journal/
  shoutout/stress activity over a completed calendar week, built from a
  privacy-controlled statistical aggregate (never raw journal/shoutout
  text) and validated against a strict output schema before it is ever
  stored or returned. See "Weekly reflection architecture" below.
* **Not yet in scope**: push notifications (including any "your weekly
  reflection is ready" notification — this phase only builds the
  generate/retrieve API a future notification would call), and any
  Flutter integration. See "What Phase 5 deliberately does not include"
  at the end of this file.

## 1. Architecture

The same layering as Phase 1/2, now with a second axis for media — a
storage abstraction sitting beside the database, used only by the media
vertical:

```
HTTP request
  → app/api/routes/*.py      FastAPI routers: parse request, call a service,
                              translate results/exceptions to HTTP responses.
      → app/services/*.py    Business logic (ownership checks, uniqueness
                              rules, upload/delete consistency). Framework-
                              agnostic — raises plain Python exceptions, never
                              HTTPException.
          → app/repositories/*.py   Thin data-access functions per table.
              → app/models/*.py     SQLAlchemy 2.x ORM models.
                  → PostgreSQL

          → app/services/storage/*.py   ObjectStorageService interface —
                                         used ONLY by media_service.py.
                  → S3-compatible object storage (MinIO locally, AWS S3
                    or any S3-compatible provider in production)
```

Shoutouts reuse every Phase 2 pattern as-is (`NotFoundError`/`ConflictError`,
`Page[T]`, `PaginationParams`) — no new shared abstractions were needed for
them, because a Shoutout turned out to be the same shape of resource as a
Journal entry (see "Shoutout data model" below).

Media introduces one new shared idea: **`ObjectStorageService`**
(`app/services/storage/base.py`), an abstract interface with exactly three
methods (`upload`, `delete`, `generate_presigned_download_url`). Two
implementations exist — `S3StorageService` (real, boto3-backed, used by the
running app) and `InMemoryStorageService` (test-only, see "Testing" below) —
and `media_service.py` is written only against the interface. This is what
makes "swap MinIO for AWS S3, or any other S3-compatible provider, without
touching business logic" a property of the code, not just an intention: only
`.env` changes.

```
Flutter (future)
   │  multipart upload / JSON metadata calls
   ▼
FastAPI (app/api/routes/media.py)
   │  auth, validation, ownership
   ▼
Media Service (app/services/media_service.py)
   │                                   │
   │ metadata                         │ bytes
   ▼                                   ▼
PostgreSQL (media_assets)     ObjectStorageService
                                       │
                                       ▼
                          MinIO (dev) / AWS S3 (prod)
```

Phase 4 adds two verticals that share the same layering but lean on it
differently. Relationships/invitations/consent follow the standard
route → service → repository → model path, with every ownership/consent
rule centralized in `relationship_service.py` (see its module docstring) so
`api/routes/relationships.py` never re-implements one. The stress indicator
is deliberately **not** a stored resource: `stress_service.py` reads only
aggregate numbers (a mood average, a checklist completion rate) via
`stress_repository.py` and computes a fresh `StressResult` on every call —
nothing is persisted, and journal/shoutout/media content is never read (see
"Stress indicator" below). The comfort-person-facing route
(`GET /relationships/{id}/stress/today`) calls the *same*
`stress_service.compute_stress()` the owner's own `/stress/today` calls,
after `relationship_service.authorize_comfort_stress_access()` has verified
an accepted relationship and a live `stress_level` consent grant — one
scoring function, two authorization paths, not two implementations of the
score.

Phase 5 adds a third axis, alongside the database and object storage: an
**AI provider** — external, network-bound, and the first dependency in
this codebase that can fail in ways the app cannot control (a timeout, a
malformed response, a safety refusal). It is treated exactly like Phase
3 treated object storage: one abstract interface
(`AIReflectionProvider`, `app/services/ai/base.py`), one real
implementation (`AnthropicReflectionProvider`, boto3's role played here
by the `anthropic` SDK), one test-only fake
(`MockAIReflectionProvider`), and a factory
(`app/services/ai/factory.py`) that picks between them — business logic
is written only against the interface. See "AI provider abstraction"
below.

The full request flow for a weekly reflection:

```
FastAPI (app/api/routes/reflections.py)
   │  auth, request validation
   ▼
Reflection Service (app/services/reflection_service.py)
   │  cache check: does a row already exist for (user, week)?
   ▼
Weekly Aggregator (app/services/weekly_aggregation_service.py)
   │  reads ONLY counts/numbers/enums via the repository layer
   ▼
Structured Weekly Summary (app.schemas.reflection.WeeklySummary)
   │  the ONLY thing that ever reaches the AI provider
   ▼
AIReflectionProvider (app/services/ai/*.py)
   │  validated, structured output only
   ▼
WeeklyReflection row (app/models/reflection.py) ── PostgreSQL
   │
   ▼
API response (app.schemas.reflection.WeeklyReflectionRead)
```

Every box above is a distinct module with a single responsibility, on
purpose: `reflection_service.py` is the only place that decides
cache-hit-vs-regenerate; `weekly_aggregation_service.py` is the only
place that turns raw activity into the structured summary and is the
enforcement point for the privacy boundary (see "Privacy boundary"
below); `app/services/ai/*.py` is the only place that ever talks to an
AI provider's SDK. None of the three imports FastAPI/HTTPException — the
same framework-agnostic-service-layer rule Phase 1-4 already follows.

## 2. Folder structure

```
backend/
├── app/
│   ├── main.py                    FastAPI app, CORS, router registration
│   ├── core/
│   │   ├── config.py              Settings, loaded from environment/.env (incl. Phase 3's S3_*/MAX_UPLOAD_SIZE_MB and Phase 5's AI_*)
│   │   ├── security.py            Password hashing, JWT, refresh-token hashing
│   │   ├── database.py            Engine, session factory, get_db dependency
│   │   └── exceptions.py          Domain exception types (incl. Phase 3's UnsupportedMediaTypeError/FileTooLargeError/StorageError, Phase 4's SelfRelationshipError/PermissionDeniedError, and Phase 5's AIProviderError family)
│   ├── models/
│   │   ├── user.py · profile.py · auth_session.py                 (Phase 1)
│   │   ├── journal.py · mood.py · checklist.py                    (Phase 2)
│   │   ├── shoutout.py            Shoutout
│   │   ├── media_asset.py         MediaAsset
│   │   ├── relationship.py        Relationship
│   │   ├── relationship_invitation.py   RelationshipInvitation
│   │   ├── relationship_permission.py   RelationshipPermission
│   │   └── reflection.py          WeeklyReflection
│   ├── schemas/
│   │   ├── user.py · profile.py · auth.py                         (Phase 1)
│   │   ├── journal.py · mood.py · checklist.py · common.py        (Phase 2)
│   │   ├── shoutout.py
│   │   ├── media.py               MediaAssetRead, MediaAssetDetail
│   │   ├── relationship.py        InvitationCreate/Read, RelationshipRead, PermissionRead
│   │   ├── stress.py              StressResult (owner view), ComfortStressView (narrower)
│   │   └── reflection.py          WeeklySummary, AIReflectionOutput, WeeklyReflectionRead/GenerateRequest
│   ├── repositories/
│   │   ├── user_repository.py · profile_repository.py · auth_session_repository.py   (Phase 1)
│   │   ├── journal_repository.py · mood_repository.py · checklist_repository.py       (Phase 2)
│   │   ├── shoutout_repository.py
│   │   ├── media_repository.py
│   │   ├── relationship_repository.py · relationship_invitation_repository.py · relationship_permission_repository.py
│   │   ├── stress_repository.py   Aggregate-only reads (averages/counts), never row content
│   │   ├── weekly_aggregation_repository.py   Journal/shoutout activity by DATE only — never title/content
│   │   └── reflection_repository.py   CRUD (get-or-upsert) for weekly_reflections
│   ├── services/
│   │   ├── auth_service.py                                        (Phase 1)
│   │   ├── journal_service.py · mood_service.py · checklist_service.py                (Phase 2)
│   │   ├── shoutout_service.py
│   │   ├── media_service.py       Upload/list/retrieve/delete + consistency handling
│   │   ├── relationship_service.py    Invitations, accept/decline, revoke, consent — all authorization rules
│   │   ├── stress_service.py      The stress-score formula (see "Stress indicator" below); nothing persisted
│   │   ├── weekly_aggregation_service.py   Raw activity -> WeeklySummary; the privacy-boundary enforcement point
│   │   ├── reflection_service.py  Cache check -> aggregate -> AI provider -> persist; see "Weekly reflection architecture"
│   │   ├── storage/
│   │   │   ├── base.py            ObjectStorageService (the interface)
│   │   │   ├── s3_storage.py      S3StorageService — boto3, works for MinIO or AWS S3
│   │   │   ├── memory_storage.py  InMemoryStorageService — test-only fake
│   │   │   └── factory.py         get_storage_service() — picks the implementation
│   │   └── ai/
│   │       ├── base.py            AIReflectionProvider (the interface)
│   │       ├── anthropic_provider.py   AnthropicReflectionProvider — the `anthropic` SDK, structured output
│   │       ├── mock_provider.py   MockAIReflectionProvider — test-only fake
│   │       └── factory.py         get_ai_provider() — picks the implementation
│   ├── api/routes/
│   │   ├── auth.py · health.py                                    (Phase 1)
│   │   ├── journals.py · moods.py · checklists.py                 (Phase 2)
│   │   ├── shoutouts.py
│   │   ├── media.py
│   │   ├── relationships.py       Invitations, relationships, consent, comfort-person stress view
│   │   ├── stress.py              The authenticated user's own /stress/today and /stress/history
│   │   └── reflections.py         /reflections/weekly, /reflections/weekly/{week_start}, /reflections/weekly/generate
│   └── dependencies/
│       ├── auth.py                get_current_user / get_current_active_user
│       └── pagination.py          Shared limit/offset query-param dependency
├── alembic/versions/
│   ├── a1b2c3d4e5f6_create_users_profiles_auth_sessions.py         (Phase 1)
│   ├── b2c3d4e5f6a7_create_journals_moods_checklists.py            (Phase 2)
│   ├── c3d4e5f6a7b8_create_shoutouts_and_media_assets.py           (Phase 3)
│   ├── d4e5f6a7b8c9_create_relationships_invitations_permissions.py (Phase 4)
│   └── e5f6a7b8c9d0_create_weekly_reflections.py                   (Phase 5)
├── tests/
│   ├── conftest.py                Test app/DB/storage/AI-provider wiring + register_and_get_headers() helper
│   ├── test_auth.py               20 tests (Phase 1, unchanged)
│   ├── test_journals.py · test_moods.py · test_checklists.py       44 tests (Phase 2, unchanged)
│   ├── test_shoutouts.py          21 tests
│   ├── test_media.py              19 tests
│   ├── test_relationships.py      36 tests
│   ├── test_stress.py             12 tests
│   └── test_reflections.py        36 tests
├── Dockerfile · docker-compose.yml · requirements.txt
├── .env.example · alembic.ini
└── README.md                      (this file)
```

## 3-4. Environment & Docker setup

Unchanged from Phase 1 — see below; nothing about environment variables,
`.env`, or Docker Compose changed in Phase 2.

```bash
cd backend
python -m venv .venv
source .venv/Scripts/activate      # Windows Git Bash; .venv\Scripts\activate.bat on cmd.exe
pip install -r requirements.txt
cp .env.example .env               # then set a real JWT_SECRET_KEY, S3 credentials, and AI_API_KEY
docker compose up --build          # postgres + minio + minio-init + backend, with healthchecks
```

Phase 4 added no new environment variables. **Phase 5 adds four**:
`AI_PROVIDER` (default `anthropic`), `AI_API_KEY` (a real Anthropic API
key — see [console.anthropic.com](https://console.anthropic.com/)),
`AI_MODEL` (default `claude-opus-5`), and `AI_TIMEOUT_SECONDS` (default
`20`) — see "AI provider abstraction" below for what each controls.
Nothing else changed: relationships/invitations use the same
`JWT_SECRET_KEY`-adjacent security primitives (see
`app/core/security.py`'s invitation-token helpers) and the stress
indicator has no configuration of its own (its window/weights are code
constants in `app/services/stress_service.py`, not environment-tunable —
see "Stress indicator" below for why).

`DATABASE_URL`, `JWT_SECRET_KEY`, `ACCESS_TOKEN_EXPIRE_MINUTES`,
`REFRESH_TOKEN_EXPIRE_DAYS`, `CORS_ORIGINS`, `ENVIRONMENT` are the same six
Phase 1 variables; Phase 3 adds `STORAGE_PROVIDER`, `S3_ENDPOINT_URL`,
`S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET_NAME`, `S3_REGION`, and
`MAX_UPLOAD_SIZE_MB`; Phase 5 adds the four `AI_*` variables above (see
`.env.example` for all of them, and "Storage configuration"/"AI provider
abstraction" below).

> **Verification note, same caveat as Phase 1/2, now covering MinIO too:**
> this sandbox has neither Docker nor a PostgreSQL server (`docker
> --version` / `psql --version` both "command not found"), and therefore no
> MinIO either. Everything below marked VERIFIED was run for real — the
> full test suite (including media upload/download/delete against a real,
> if in-memory, `ObjectStorageService` implementation) and the Alembic
> upgrade/downgrade/upgrade cycle against SQLite standing in for
> PostgreSQL. **A real `docker compose up` bringing up actual PostgreSQL
> and MinIO together, and a real upload through the S3 API, has still not
> been performed.** A live server WAS started in this sandbox and a real
> upload attempt against `S3_ENDPOINT_URL=http://localhost:9000` with no
> MinIO listening there was made deliberately, to verify the failure mode:
> it now returns a clean `502` in ~9 seconds (bounded by the client's own
> connect timeout) with the server remaining fully responsive throughout,
> rather than hanging — see "Problems encountered" in the implementation
> report.

## 5-6. Database setup & Alembic migrations

```bash
alembic upgrade head             # applies all five phases' migrations
alembic downgrade d4e5f6a7b8c9   # roll back to end of Phase 4 (drops weekly_reflections cleanly)
alembic current
alembic history
```

The Phase 2 migration (`b2c3d4e5f6a7_create_journals_moods_checklists.py`)
creates `journal_entries`, `mood_entries`, `checklist_items`, and
`checklist_completions`, and **seeds `checklist_items` with the app's
current 5 fixed wellness tasks** using stable, hard-coded UUIDs (so every
environment ends up with the same catalog row ids). The Phase 3 migration
(`c3d4e5f6a7b8_create_shoutouts_and_media_assets.py`) creates `shoutouts`
and `media_assets`. The Phase 4 migration
(`d4e5f6a7b8c9_create_relationships_invitations_permissions.py`) creates
`relationships`, `relationship_invitations`, and `relationship_permissions`.
The Phase 5 migration (`e5f6a7b8c9d0_create_weekly_reflections.py`)
creates `weekly_reflections` — no seed data, and none of these migrations
touch or re-run anything from an earlier one. There is no
`stress_snapshots` table (the stress indicator is computed on demand and
never persisted — see "Stress indicator" below), and `weekly_reflections`
is the ONLY new table Phase 5 adds — no separate "AI request log" or
"prompt history" table (see "Reflection persistence & caching" below for
why). See "Shoutout data model", "Supported media types", "Relationship &
invitation model", and "Weekly reflection architecture" above for the
full schema per feature.

## 7. Running the API

Unchanged: `uvicorn app.main:app --reload`. Swagger at `/docs`, ReDoc at
`/redoc`, raw schema at `/openapi.json`, liveness+DB check at `/health`.
The OpenAPI title is now "MindMate API" v0.5.0 with the Phase 5 endpoints
included and documented with per-endpoint descriptions (visible in `/docs`).

## 8. Running tests

```bash
pytest -v
```

188 tests total (20 Phase 1 + 44 Phase 2 + 21 shoutouts + 19 media + 36
relationships/invitations/consent + 12 stress + 36 weekly reflections),
all against the same in-memory SQLite database described in Phase 1's
README — see `tests/conftest.py`. **No real API keys, network access, or
running services (PostgreSQL, MinIO, or the Anthropic API) are required
to run the suite.** Media tests never touch a real MinIO/S3: the
`get_storage_service` FastAPI dependency is overridden with
`InMemoryStorageService`, a real (if trivial) implementation of the same
`ObjectStorageService` interface the running app uses, so "was the object
actually written / actually removed" is a real assertion (`storage.count()`,
`storage.object_exists(...)`), not a mock call-count check. The fake bucket
is emptied before every test alongside the DB reset. One service-level test
(`test_upload_media_cleans_up_orphaned_object_on_db_failure`) calls
`media_service.upload_media` directly (bypassing the HTTP layer) to exercise
the DB-failure-after-successful-upload cleanup path specifically. Reflection
tests follow the identical pattern for the AI provider: `get_ai_provider`
is overridden with `MockAIReflectionProvider`, whose `.calls` list and
`.next_error` attribute let a test both assert on exactly what
`WeeklySummary` the "provider" was asked to reflect on (real aggregation
assertions, not a mock call-count check) and simulate a timeout/malformed-
response/generic provider failure without any network access — reset
between tests alongside the DB and the fake storage bucket. Every reflection
test — including the async `POST /reflections/weekly/generate` route —
runs through the ordinary synchronous `TestClient`; no `pytest-asyncio` is
needed (Starlette's `TestClient` already drives the ASGI app's event loop
internally, the same way `media.py`'s async upload route is already tested).

## 9. Authentication flow

**Unchanged from Phase 1.** Every Phase 3 endpoint requires the same bearer
access token as `/auth/me` did, via the same `get_current_active_user`
dependency — Phase 3 added zero new authentication code, only new
*authorization* (ownership) checks inside the shoutout/media services. See
Phase 1's description in git history / the Phase 1 report for the full
register → login → refresh → logout flow.

## 10. API endpoints

### Journals

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| POST | `/journals` | Yes | Create an entry for a date (409 if that date already has one) |
| GET | `/journals` | Yes | List your own entries, paginated, optional `start_date`/`end_date` |
| GET | `/journals/{journal_id}` | Yes | Retrieve one entry (404 if not yours) |
| PATCH | `/journals/{journal_id}` | Yes | Update title/content/date (409 on date collision) |
| DELETE | `/journals/{journal_id}` | Yes | Delete an entry |

**Example — create:**
```bash
curl -X POST http://localhost:8000/journals \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"entry_date": "2025-06-01", "title": "First day", "content": "Feeling okay."}'
```
```json
{
  "id": "1255b211-3e55-4a65-a69e-34c5ae655bb9",
  "user_id": "c48d7b01-b23c-41a8-942e-1b6fd5230895",
  "entry_date": "2025-06-01",
  "title": "First day",
  "content": "Feeling okay.",
  "created_at": "2026-09-08T15:30:37",
  "updated_at": "2026-09-08T15:30:37"
}
```
*(This is real output from this implementation's own end-to-end verification run — see section H of the implementation report.)*

**Example — list with date filter and pagination:**
```bash
curl "http://localhost:8000/journals?start_date=2025-05-01&end_date=2025-07-01&limit=10&offset=0" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```
```json
{"items": [ { "...": "one JournalRead object per entry" } ], "total": 1, "limit": 10, "offset": 0}
```

### Moods

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| POST | `/moods` | Yes | Log a 0-100 mood value for a date (409 if that date already has one) |
| GET | `/moods` | Yes | List your own entries, paginated, optional `start_date`/`end_date` |
| GET | `/moods/{mood_id}` | Yes | Retrieve one entry (404 if not yours) |
| PATCH | `/moods/{mood_id}` | Yes | Change the value and/or date |

No `DELETE /moods/{mood_id}` — the existing app has no delete flow for
moods (only add/edit via the calendar), so none was added; see "Design
decisions".

**Example:**
```bash
curl -X POST http://localhost:8000/moods -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" -d '{"entry_date": "2025-06-01", "mood_value": 72}'
```
```json
{"id": "e15f3557-...", "user_id": "c48d7b01-...", "entry_date": "2025-06-01", "mood_value": 72, "created_at": "...", "updated_at": "..."}
```

### Checklists

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| GET | `/checklists/items` | Yes | The fixed 5-item task catalog (see "Design decisions") |
| GET | `/checklists/{entry_date}` | Yes | Your completion state for every item on that date |
| PATCH | `/checklists/{entry_date}` | Yes | Toggle one or more items for that date |

No `POST`/`DELETE` on the item catalog and no per-completion id-based
routes — see "Design decisions" for why this deliberately isn't the
generic `/checklists/{checklist_id}` CRUD shape.

**Example:**
```bash
curl http://localhost:8000/checklists/items -H "Authorization: Bearer $ACCESS_TOKEN"
```
```json
[
  {"id": "9d1a2b3c-0001-4a11-8b11-000000000001", "label": "Drank enough water 💧", "sort_order": 0},
  {"id": "9d1a2b3c-0002-4a11-8b11-000000000002", "label": "Slept well last night 🛌", "sort_order": 1},
  {"id": "9d1a2b3c-0003-4a11-8b11-000000000003", "label": "Did one thing just for me 😉", "sort_order": 2},
  {"id": "9d1a2b3c-0004-4a11-8b11-000000000004", "label": "Got some fresh air and sunlight 🏝️", "sort_order": 3},
  {"id": "9d1a2b3c-0005-4a11-8b11-000000000005", "label": "Exercised well 🧘‍♂️", "sort_order": 4}
]
```

```bash
curl -X PATCH http://localhost:8000/checklists/2025-06-01 -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"completions": [{"item_id": "9d1a2b3c-0001-4a11-8b11-000000000001", "completed": true}]}'
```
```json
{
  "entry_date": "2025-06-01",
  "items": [
    {"item_id": "9d1a2b3c-0001-...", "label": "Drank enough water 💧", "sort_order": 0, "completed": true, "completed_at": "2026-09-08T15:30:39.951125"},
    {"item_id": "9d1a2b3c-0002-...", "label": "Slept well last night 🛌", "sort_order": 1, "completed": false, "completed_at": null}
  ],
  "completed_count": 1,
  "total_count": 5
}
```

### Scheduler

Added in Phase 11A — the existing app previously had no backend for this
feature at all; it stored an unscoped, date-only-keyed local Hive box
directly on-device, with a confirmed silent-overwrite bug when two rows
shared a time (see the Flutter migration's PHASE11 audit report). This
API is deliberately date-scoped, not per-entry CRUD, mirroring Checklist's
shape rather than Journal's/Mood's — see "Design decisions" below.

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| GET | `/scheduler/{entry_date}` | Yes | Your scheduled rows for that date, ordered by time (empty `items` if nothing is scheduled) |
| PUT | `/scheduler/{entry_date}` | Yes | Replace your ENTIRE schedule for that date with `rows` in one call |

No `DELETE` — a `PUT` that omits a previously-saved time already deletes
it as part of the whole-day replace, matching the existing app's
edit-freely-then-save-once flow. `rows: []` clears the day.

`scheduled_time` must be exactly `"HH:MM"`, 24-hour, zero-padded (`"09:00"`,
`"14:30"`, `"23:45"`) — a malformed or out-of-range time is rejected with
`422`, as is a `PUT` whose `rows` contain the same `scheduled_time` twice
(see "Design decisions" for why that check lives in the service layer, and
why the database also enforces `UNIQUE(user_id, entry_date,
scheduled_time)` as a final backstop against a concurrent-request race).
There is intentionally no "yesterday fallback" here: if a client wants
that display behavior, it fetches yesterday's date itself when today's is
empty — this API only ever answers "what's on this exact date."

**Example — save a day's schedule:**
```bash
curl -X PUT http://localhost:8000/scheduler/2025-06-01 -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"rows": [{"scheduled_time": "09:00", "description": "Gym"}, {"scheduled_time": "14:30", "description": "Study"}]}'
```
```json
{
  "entry_date": "2025-06-01",
  "items": [
    {"id": "b1c2d3e4-...", "entry_date": "2025-06-01", "scheduled_time": "09:00", "description": "Gym", "created_at": "...", "updated_at": "..."},
    {"id": "c2d3e4f5-...", "entry_date": "2025-06-01", "scheduled_time": "14:30", "description": "Study", "created_at": "...", "updated_at": "..."}
  ]
}
```

**Example — a self-contradictory request is rejected before anything is written:**
```bash
curl -X PUT http://localhost:8000/scheduler/2025-06-01 -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"rows": [{"scheduled_time": "09:00", "description": "Gym"}, {"scheduled_time": "09:00", "description": "Study"}]}'
```
```json
{"detail": "scheduled_time '09:00' appears more than once in the same request"}
```
`422 Unprocessable Content` — the prior day's schedule, if any, is left untouched.

### Shoutouts

**Shoutout data model — what the audit found, and why the schema looks like it does.**
A Shoutout is a private, self-authored venting entry ("What's weighing on
your mind?") — confirmed from `journal_page.dart` and `shoutout_page.dart` —
**not** a message sent to anyone. There is no recipient anywhere in the app:
no screen lets a user pick another person, no Firestore field references
anyone but the author, and `favorite_page.dart`'s comfort-circle code has no
connection to shoutouts at all. So this schema uses a single `user_id`
(author == sole reader), not `sender_user_id`/`recipient_user_id` — and the
API has no "sent"/"received" split, self-shoutout handling, or read/unread
state, because none of those concepts exist in the real feature.

The old app also had **two incompatible write shapes for the same Firestore
collection**: `journal_page.dart`'s inline save (`.add({'problem': text,
'timestamp': ...})`, an auto-id doc) and `shoutout_page.dart`'s save
(`.doc(dateKey).set({'title', 'description', 'timestamp'})`, date-keyed).
Every read path expects the second shape, so it's the canonical one here —
one row per user per calendar date, `title`/`content` (renamed from
`description`, same rename rationale as journals), `409` on a duplicate
date. The first shape's data was already orphaned (write-only) in the old
app and isn't migrated — see the migration audit for why Phase 3 starts
from an empty database regardless.

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| POST | `/shoutouts` | Yes | Create an entry for a date (409 if that date already has one) |
| GET | `/shoutouts` | Yes | List your own entries, paginated, optional `start_date`/`end_date` |
| GET | `/shoutouts/{shoutout_id}` | Yes | Retrieve one entry (404 if not yours) |
| PATCH | `/shoutouts/{shoutout_id}` | Yes | Update title/content/date (409 on date collision) |
| DELETE | `/shoutouts/{shoutout_id}` | Yes | Delete an entry |
| POST | `/shoutouts/{shoutout_id}/feel-better` | Yes | Answer the "did you feel better?" follow-up (see below) — one-shot, 409 if already answered |

**Example — create, then answer the follow-up:**
```bash
curl -X POST http://localhost:8000/shoutouts -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entry_date": "2025-07-01", "title": "Overwhelmed", "content": "Too much on my plate."}'
```
```json
{"id": "d25ea96b-...", "user_id": "10c3e9fe-...", "entry_date": "2025-07-01", "title": "Overwhelmed", "content": "Too much on my plate.", "felt_better": null, "felt_better_at": null, "created_at": "...", "updated_at": "..."}
```
```bash
curl -X POST http://localhost:8000/shoutouts/d25ea96b-.../feel-better \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" -d '{"felt_better": true}'
```
```json
{"...": "same shoutout", "felt_better": true, "felt_better_at": "2026-09-08T15:55:06.642234"}
```
*(Both are real output from this implementation's own end-to-end verification run, including the follow-up genuinely persisting on a re-fetch — see the implementation report.)*

### Media (voice notes, images, videos)

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| POST | `/media/upload` | Yes | Direct multipart upload — see "Upload/download/delete behavior" |
| GET | `/media` | Yes | List your own uploads, paginated, optional `media_type` filter |
| GET | `/media/{media_id}` | Yes | Metadata + a fresh, time-limited download URL (404 if not yours) |
| DELETE | `/media/{media_id}` | Yes | Delete both the object and its metadata |

**Example:**
```bash
curl -X POST http://localhost:8000/media/upload -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@recording.m4a;type=audio/mp4" -F "duration_seconds=42"
```
```json
{"id": "...", "user_id": "...", "media_type": "voice", "original_filename": "recording.m4a", "content_type": "audio/mp4", "file_size": 88234, "duration_seconds": 42, "created_at": "..."}
```
```bash
curl http://localhost:8000/media/<id> -H "Authorization: Bearer $ACCESS_TOKEN"
```
```json
{"...": "same fields as above, plus:", "download_url": "https://.../mindmate-media/voice/.../<uuid>.m4a?X-Amz-...", "download_url_expires_in_seconds": 900}
```

### Relationships, invitations & consent

**Relationship & invitation model — what the audit found, and why the
schema looks like it does.** The old app stores a single `comfortPerson`
map on the user's own document (`register_page.dart`, `regfav.dart`): one
owner ("the person being supported"), one comfort person, picked from a
fixed list (Mom, Dad, Siblings, Best Friend, Love, Grandparents, Others +
free-text label), "invited" via an unverified `mindmate://invite?...` deep
link that nobody on the other end is required to actually open or hold a
MindMate account for. Two things don't survive into this backend as a
result: a free-text comfort-person **name** (here the comfort person is
always a real `users` row, and their display name is read live from *their
own* profile, never a copy typed by the owner), and a "primary comfort
person" flag (the old UI never distinguishes one as more primary — there is
only ever at most one at all). See `app/models/relationship.py`'s module
docstring for the full source citations.

An invitation is a single-use, expiring, hashed token — never a raw,
guessable deep link. `POST /relationships/invitations` returns the raw
token exactly once (only its SHA-256 hash is ever stored); previewing or
accepting it requires the recipient to be authenticated first, so a token
can't be probed or scanned anonymously the way the old deep link could be.
Accepting an invitation is one atomic transaction: the invitation is
consumed, the `relationships` row is created, and its founding
`stress_level` consent grant is created together — because in this
product, generating and sharing the invite *is* the owner's consent
decision (the info dialog in `regfav.dart` already tells them exactly what
accepting enables). That consent is still modeled as its own independently
revocable `relationship_permissions` row, not an implicit property of
`status = 'accepted'`, so the owner can later revoke just the
stress-sharing consent without deleting the relationship itself.

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| POST | `/relationships/invitations` | Yes | Create an invitation; returns the raw token once |
| GET | `/relationships/invitations` | Yes | List invitations you've sent, paginated |
| GET | `/relationships/invitations/{token}` | Yes | Preview an invitation before accepting/declining |
| POST | `/relationships/invitations/{token}/accept` | Yes | Accept — creates the relationship + founding consent grant atomically |
| POST | `/relationships/invitations/{token}/decline` | Yes | Decline |
| GET | `/relationships?role=owner\|comfort_person` | Yes | List your relationships from either side (default `owner`) |
| POST | `/relationships/{relationship_id}/revoke` | Yes | End a relationship — either party may; immediately revokes every consent grant on it |
| GET | `/relationships/{relationship_id}/permissions` | Yes | List consent grants on a relationship (either party may read) |
| POST | `/relationships/{relationship_id}/permissions/{permission_type}/grant` | Yes | Grant consent — owner only |
| POST | `/relationships/{relationship_id}/permissions/{permission_type}/revoke` | Yes | Revoke consent — owner only, takes effect immediately |
| GET | `/relationships/{relationship_id}/stress/today` | Yes | The comfort person's view of the owner's stress indicator — see "Stress indicator" |

`permission_type` is currently only `stress_level` (a `Literal`, not a free
string) — the one thing the product actually asks a comfort person to be
able to see. A relationship's `status` is only ever `accepted` or `revoked`
(never `pending`/`declined`) because a `relationships` row is only created
at the moment an invitation is accepted; `pending`/`declined` are states
the *invitation* passes through instead. A duplicate active relationship
between the same two people is rejected with `409`, enforced by a partial
unique index on `(owner_user_id, comfort_user_id) WHERE status = 'accepted'`
— so revoking and later re-accepting a fresh invitation between the same
pair is still allowed to create a new row.

**Example — invite, accept, grant is automatic, then view (as the comfort person):**
```bash
curl -X POST http://localhost:8000/relationships/invitations \
  -H "Authorization: Bearer $OWNER_TOKEN" -H "Content-Type: application/json" \
  -d '{"relationship_type": "best_friend"}'
```
```json
{"id": "...", "relationship_type": "best_friend", "custom_relationship_label": null, "status": "pending", "expires_at": "...", "created_at": "...", "token": "a1b2c3...-the-raw-token-shown-only-here"}
```
```bash
curl -X POST http://localhost:8000/relationships/invitations/a1b2c3.../accept -H "Authorization: Bearer $FRIEND_TOKEN"
```
```json
{"id": "...", "owner_user_id": "...", "comfort_user_id": "...", "relationship_type": "best_friend", "status": "accepted", "my_role": "comfort_person", "counterparty_display_name": "Owner Name", "accepted_at": "...", "revoked_at": null, "created_at": "...", "updated_at": "..."}
```
```bash
curl http://localhost:8000/relationships/<relationship_id>/stress/today -H "Authorization: Bearer $FRIEND_TOKEN"
```
```json
{"score": 42, "level": "moderate", "confidence": "medium", "calculated_at": "...", "data_window_start": "...", "data_window_end": "...", "disclaimer": "This is an automated wellness indicator..."}
```

### Stress indicator

**A deterministic, rule-based score — explicitly not AI/ML, not a
diagnosis.** It gives real backend substance to `favorite_page.dart`'s
"View today's stress level" button, currently wired to `// TODO: Implement
stress level view` in the old app. Two signals feed it, both already
existing MindMate features: the recent 0-100 mood check-ins
(`mood_entries.mood_value`) and recent daily checklist completion. Journal
content, shoutouts, and media are **never** read by this feature — see
`app/services/stress_service.py`'s module docstring for the full formula
and the "why not journal activity" reasoning. Nothing is persisted: every
call recomputes from source rows over a trailing 7-day window, so there is
no `stress_snapshots` table to go stale.

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| GET | `/stress/today` | Yes | Your own stress indicator, full breakdown (`contributors`) included |
| GET | `/stress/history?days=&end_date=` | Yes | One entry per day, most recent first, `days` bounded to 1-90 |
| GET | `/relationships/{relationship_id}/stress/today` | Yes | A consented comfort person's view of the owner's indicator — narrower, no `contributors` |

`score` is `0-100` where higher means more indicated stress, or `null` (not
0) when the window has no mood entries and no checklist activity at all —
`level` is then `"insufficient_data"` rather than a misleadingly confident
`"low"`. Every response carries a fixed `disclaimer` string making clear
this is an automated wellness indicator, not a medical or clinical
assessment. The comfort-person-facing `ComfortStressView` deliberately
omits `contributors` (the mood-average/checklist-rate numbers behind the
score) — the product only ever promised "view today's stress level", not a
breakdown of someone else's private wellness data, matching Phase 4's
"minimum necessary" consent brief.

**Example — insufficient data vs. a real score:**
```bash
curl http://localhost:8000/stress/today -H "Authorization: Bearer $ACCESS_TOKEN"
```
```json
{"score": null, "level": "insufficient_data", "confidence": "none", "calculated_at": "...", "data_window_start": "...", "data_window_end": "...", "contributors": {"mood_average": null, "checklist_completion_rate": null}, "disclaimer": "This is an automated wellness indicator..."}
```

### Weekly reflection

A short, supportive, AI-generated reflection on one completed
Monday-Sunday week, built entirely from a numeric/statistical summary of
that week's mood/checklist/journal/shoutout/stress activity — never from
raw journal or shoutout text. See "Weekly reflection architecture",
"Privacy boundary", and "AI provider abstraction" below for the full
design; this section is the API surface only.

| Method | Route | Auth | Purpose |
|---|---|:---:|---|
| POST | `/reflections/weekly/generate` | Yes | Generate (or return the cached) reflection for a week |
| GET | `/reflections/weekly` | Yes | Your most recent reflection — read-only, never generates |
| GET | `/reflections/weekly/{week_start}` | Yes | One specific week's reflection — 404 if not found or not yours |

`POST .../generate`'s body is entirely optional: `{"week_start": "<a
Monday, ISO date>", "force_regenerate": false}`. Omitting `week_start`
defaults to the most recently *completed* week; an explicit `week_start`
that isn't a Monday, or that refers to a week not yet over, is rejected
with `400`. Omitting `force_regenerate` (or leaving it `false`) makes the
whole endpoint a cheap, idempotent cache read once a week has already
been generated — see "Reflection persistence & caching" for exactly when
the AI provider is (and is never) called again.

**Example — a week with enough activity:**
```bash
curl -X POST http://localhost:8000/reflections/weekly/generate \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"week_start": "2025-06-02"}'
```
```json
{
  "id": "...", "user_id": "...", "week_start": "2025-06-02", "week_end": "2025-06-08",
  "status": "completed",
  "reflection": {
    "summary": "...", "mood_insight": "...", "habit_insight": "...",
    "positive_highlights": ["..."], "areas_to_reflect_on": ["..."], "encouragement": "..."
  },
  "insufficient_data_reason": null,
  "ai_provider": "anthropic", "ai_model": "claude-opus-5",
  "generated_at": "...", "created_at": "...", "updated_at": "..."
}
```

**Example — a week with too little activity to reflect on meaningfully:**
```json
{
  "id": "...", "week_start": "2025-06-09", "week_end": "2025-06-15",
  "status": "insufficient_data",
  "reflection": null,
  "insufficient_data_reason": "No activity was recorded during this week.",
  "ai_provider": null, "ai_model": null, "generated_at": null,
  "created_at": "...", "updated_at": "..."
}
```

A `502` from `POST .../generate` means the AI provider itself failed
(timeout, outage, or an unvalidatable response) — see "Failure / retry /
fallback strategy". Nothing is written to storage in that case, so a
previously-completed reflection for that week (if any) is left exactly as
it was.

All eight resource families — journals, moods, checklists, shoutouts,
media, relationships, the stress indicator, and weekly reflections —
share the same ownership rule: **every read, update, and delete is scoped by
the authenticated user's id in the same database query that looks up the
resource** (`WHERE id = :id AND user_id = :current_user_id`), and `user_id`
is never accepted from the request body/client on create — it always comes
from the JWT via `get_current_active_user`. See the implementation report
for the exact IDOR-prevention pattern and how it's tested (including a test
that an extra, client-supplied `user_id` field in a request body is simply
ignored).

## Object storage architecture

```
Flutter (future)
   │
   ▼
FastAPI  ──auth, validation, ownership──▶  Media Service
                                                │        │
                                        metadata│        │bytes
                                                ▼        ▼
                                          PostgreSQL   ObjectStorageService
                                          (media_      (one interface,
                                           assets)      two implementations)
                                                              │
                                              ┌───────────────┴───────────────┐
                                              ▼                               ▼
                                    S3StorageService                InMemoryStorageService
                                    (boto3 — real app)               (tests only)
                                              │
                                              ▼
                                    MinIO (dev) / AWS S3 (prod)
```

`media_service.py` never imports `boto3` and never knows whether it's
talking to MinIO, AWS S3, or the test fake — it only calls the three
`ObjectStorageService` methods. Swapping providers in production means
changing `S3_ENDPOINT_URL`/credentials in `.env`; it does not mean touching
`app/services/media_service.py`, `app/api/routes/media.py`, or any test.

## MinIO configuration

`docker-compose.yml` adds two services beyond Phase 1/2's `postgres` and
`backend`:

* **`minio`** — the S3-compatible object store itself, with **persistent
  storage** (a named volume, `mindmate_minio_data`, so uploaded objects
  survive a container restart) and a healthcheck (`mc ready local`) that
  gates everything depending on it.
* **`minio-init`** — a one-shot container (image: `minio/mc`) that creates
  the bucket named by `S3_BUCKET_NAME` on first startup, since MinIO doesn't
  auto-create buckets and the backend deliberately doesn't create its own
  bucket at runtime (that's infrastructure setup, not application code's job).

The `backend` service now also waits for `minio-init` to complete
successfully before starting, and has `S3_ENDPOINT_URL` overridden to
`http://minio:9000` (the in-network hostname) the same way `DATABASE_URL` is
overridden to reach `postgres` by service name.

Local MinIO console: `http://localhost:9001` (login with
`S3_ACCESS_KEY`/`S3_SECRET_KEY` from your `.env`). S3 API: `http://localhost:9000`.

## Supported media types & upload limits

Taken directly from what `vault.dart` actually accepts (see
`app/services/media_service.py`'s module docstring for the full source
citation), not invented:

| Media type | Content types accepted | Source |
|---|---|---|
| Voice | `audio/mp4`, `audio/x-m4a`, `audio/mpeg`, `audio/wav`, `audio/x-wav`, `audio/aac`, `audio/opus`, `audio/ogg` | Exactly the `record` package's `.m4a` output plus the file-picker's `allowedExtensions: ['mp3','m4a','wav','aac','opus','ogg']` in the Voice Notes section |
| Image | `image/jpeg`, `image/png`, `image/gif`, `image/webp` | `file_picker`'s `FileType.image` doesn't enumerate an exact list in the Dart source; this is the standard, universally-supported baseline rather than a guess at an exhaustive one |
| Video | `video/mp4` only | The only container `VideoThumbnail`/`VideoPlayerDialog` actually handle correctly anywhere in `vault.dart` |

Anything else is rejected with `415 Unsupported Media Type`. Validation is
by **declared** `Content-Type`, not by inspecting file bytes (no
content-sniffing/magic-byte verification, no antivirus scanning) — an
explicitly documented limitation, not a claimed security guarantee; see
"Vault security" below and "What Phase 5 deliberately does not include".

**Size limit:** `MAX_UPLOAD_SIZE_MB` (default 25MB), enforced server-side
against the actual byte count read, before any byte reaches object storage.
Exceeding it returns `413 Content Too Large`.

## Upload/download/delete behavior

**Upload** (`POST /media/upload`): the file is read fully into memory,
validated (content type, non-empty, size), given a server-generated object
key (`{media_type}/{user_id}/{uuid4}{extension}` — never derived from the
client's filename), and uploaded to object storage. **Only after that
upload succeeds** is a `media_assets` row inserted. If the upload itself
fails, no database row is ever created — there is nothing to orphan.

If the upload succeeds but the following database commit then fails, the
object is now metadata-less. `media_service.upload_media` makes a
best-effort compensating `delete()` of it before re-raising the original
error (logged if that cleanup itself also fails, never allowed to mask the
real error) — this is **best-effort compensation, not a distributed
transaction**. A periodic reconciliation job comparing bucket contents
against `media_assets` rows would be needed to guarantee zero orphans over
time, and is explicitly future work, not built in Phase 3.

**Delete** (`DELETE /media/{id}`): the object is deleted **first**, then the
metadata row. If the object delete fails, the row is kept — so a failed
delete can be safely retried and metadata/object never silently diverge. If
the object delete succeeds but the row delete then fails, the row becomes a
"ghost" pointing at a gone object — a narrower, more detectable failure
(a future reconciliation job can find "rows whose object_key doesn't exist
in the bucket") than a fully untracked orphaned blob, which is why this
ordering was chosen over deleting the row first.

**Download**: `GET /media/{id}` returns a fresh, time-limited (15 minute)
presigned URL, generated on every call — never a stored or cached one. The
raw `object_key` is never exposed to the client at all, in any response.

**A concrete, unavoidable failure window exists** for both directions
above — no ordering of two independent systems (a database and an object
store) without a real distributed transaction can be made perfectly
atomic. What this implementation guarantees instead: the *client* is never
told an operation succeeded when it didn't (no response claims success
before both steps that matter to the client have actually happened), and
every failure mode is one of the two narrow, documented, detectable cases
above — never a silent, untracked orphan on both sides at once.

## Vault security — a gap identified, not silently filled

The old app has a separate, local "Vault password" concept
(`vault_password.dart`) gating access to voice notes/images/videos on the
device, independent of the account password. **This was not carried
forward.** The Phase 1 report already deferred Vault-specific
authentication as a future decision, and Phase 3 does not invent one: media
in this backend is protected by the same account-level JWT ownership check
as every other resource, nothing more. If the product still wants a
second, Vault-specific authorization layer in front of media access (e.g.
re-entering a PIN before `GET /media` returns anything), **that is a real,
identified future security requirement — not something this phase
implements**, because doing so without a clear product decision on its
exact semantics (session-scoped? per-request? biometric-backed like the old
app's `local_auth` check?) would mean guessing at a security control, which
is worse than leaving the gap explicit.

## Weekly reflection architecture

See "1. Architecture" above for the full request-flow diagram
(FastAPI → Reflection Service → Weekly Aggregator → Structured Weekly
Summary → AI Provider → stored `WeeklyReflection` → API response). This
section covers the pieces that diagram doesn't show: what a "week" is,
and how each field of the summary is computed.

**A week is always Monday-Sunday, UTC, and always fully completed** —
`app/services/reflection_service.resolve_week_start` rejects (`400`) an
explicit `week_start` that isn't a Monday, or whose Sunday hasn't
happened yet. Reflecting on a week makes the most sense once it's
actually over; a partial week's "trend" (see below) would be computed
from an arbitrary, still-growing slice of data, which is exactly the
kind of noisy, potentially-misleading signal the safety rules in "Safety
and tone rules" ask this feature to avoid.

**Every summary field is computed from existing, already-tested
aggregate queries — Phase 5 adds no new stress algorithm and no new mood
scale.** `mood_average`/`mood_min`/`mood_max` and
`checklist_completion_rate` are read via the exact same
`app/repositories/stress_repository.py` queries `stress_service.py`
already uses for the stress indicator, so the two features can never
silently disagree about what "this week's mood average" means.
`stress_score_start`/`stress_score_end` call
`stress_service.compute_stress()` itself (not a re-derivation of its
formula) at two reference dates: `week_end` (whose own trailing 7-day
window is exactly this week) and `week_start` (whose trailing window is
mostly the week *before* this one) — giving a legitimate "start of week
vs. end of week" comparison from one existing, already-tested function
rather than a second one. `journal_entry_count`/`shoutout_count`/
`shoutout_positive_feel_better_count` come from
`app/repositories/weekly_aggregation_repository.py`, a new module that
reads only an `entry_date` column or the `felt_better` boolean — see
"Privacy boundary" for why that module's shape is what actually
enforces the boundary, not a separate runtime check.

**Two trend fields, both simple and explicit:** `mood_trend` compares the
average of the week's first three days (Mon-Wed) against its last three
(Fri-Sun), skipping Thursday as a deliberate gap between the two halves;
`stress_trend` compares `stress_score_start`/`stress_score_end` the same
way. Both use a fixed, documented threshold
(`MOOD_TREND_THRESHOLD`/`STRESS_TREND_THRESHOLD = 5` points in
`app/services/weekly_aggregation_service.py`) rather than any statistical
significance test — a deliberately simple, auditable rule matching the
same "transparent, deterministic, not a black box" spirit as Phase 4's
stress indicator, not a claim of statistical rigor. Either trend reads
`"insufficient_data"` when there isn't enough data on both sides of the
comparison to compute one at all.

## Privacy boundary

**The AI provider never receives raw journal/shoutout content, and it is
structurally impossible for it to, not just policy that says it
shouldn't.** `app.schemas.reflection.WeeklySummary` — the only object any
`AIReflectionProvider` implementation is ever given (see
`app/services/ai/base.py`'s `generate_reflection(self, summary:
WeeklySummary)` signature) — has no field capable of holding a title or a
body of text; every field is a count, an average, a min/max, a percentage,
or an enum. `app/services/weekly_aggregation_service.py`, which builds
that object, only ever calls `app/repositories/stress_repository.py`
(pre-existing, aggregate-only) and `app/repositories/
weekly_aggregation_repository.py` (new in this phase, and itself
aggregate/date-only — see its module docstring) — neither module's
functions select `JournalEntry.title`/`.content` or
`Shoutout.title`/`.content` anywhere. Media (voice/image/video) and
relationship data are excluded from the summary entirely — media because
its "content" is a binary blob no aggregation could meaningfully
summarize anyway, and relationships because they describe *other people*,
not the reflecting user's own activity.

The one piece of shoutout data that DOES reach the summary is
`shoutout_positive_feel_better_count` — a count of how many shoutouts
that week were answered "yes" to the existing "did you feel better?"
follow-up (see Phase 3's Shoutout data model). It's a boolean tally, never
text, and was judged worth including because it's a direct, already-
collected signal of self-reported relief specifically — unlike shoutout
*content*, which is exactly the kind of raw, un-aggregated venting text
this boundary exists to keep out of a third-party API call.

**This matches the brief's preferred flow exactly:**

```
Raw PostgreSQL data (journal/shoutout titles & content, media, etc.)
        ↓
Privacy-controlled aggregation (weekly_aggregation_service.py) — reads
        ONLY counts/dates/numbers via the two aggregate-only repositories
        ↓
Structured weekly summary (WeeklySummary) — cannot carry free text at all
        ↓
AI provider (app/services/ai/*.py)
```

**Is journal/shoutout *content* needed for a useful reflection? This
implementation's answer is no.** Mood (a 0-100 self-report), checklist
completion, journal/shoutout *activity counts* (did the user engage that
day, not what they wrote), the feel-better outcome, and the derived
stress trend already give a rule-based-but-real weekly shape — enough for
a supportive, pattern-level reflection ("you engaged with journaling most
days this week" is meaningful without ever reading a word of it). No
journal/shoutout text is sent, none is optional-with-a-flag, and none of
it is identifiable to begin with (the AI provider never receives an
email, a name, or a user id — only aggregate numbers and two ISO dates).
Nothing beyond the already-completed `WeeklyReflection` row (see
"Reflection persistence & caching") is stored afterward; the assembled
prompt string itself is never persisted (see app/models/reflection.py's
module docstring).

## AI provider abstraction

Mirrors Phase 3's `ObjectStorageService` pattern exactly: one abstract
interface (`AIReflectionProvider`, `app/services/ai/base.py`, with an
async `generate_reflection(summary) -> AIReflectionOutput` method plus
`provider_name`/`model_name` properties for observability), one real
implementation (`AnthropicReflectionProvider`), and one test-only fake
(`MockAIReflectionProvider`) — selected by `app/services/ai/factory.py`
based on `settings.ai_provider`, the same "routes/services depend on a
FastAPI dependency, never a concrete class" discipline
`get_storage_service` already established. Swapping in a second real
provider later means adding one new file plus one line in `factory.py` —
`app/services/reflection_service.py` and
`app/services/weekly_aggregation_service.py` would not change at all.

**Why Claude for this first implementation:** this backend is being built
by Claude Code, and the official `anthropic` Python SDK's structured-
output helper (`client.messages.parse(..., output_format=
AIReflectionOutput)`) gave the most directly verifiable integration
available while writing this phase — it validates the model's JSON
response against `AIReflectionOutput` server-side and hands back an
already-parsed, already-validated instance. This is a practical choice
for the first implementation, not a claim that no other provider could
satisfy this interface; see `app/services/ai/anthropic_provider.py`'s
module docstring.

**Configuration is entirely environment-driven** (see "Environment
variables" below) — `AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL` (default
`claude-opus-5`), `AI_TIMEOUT_SECONDS` (default 20). No provider secret is
ever hard-coded, and none is ever persisted to the database (see
`app/models/reflection.py`'s module docstring). **The test suite never
requires a real API key or network access**: `tests/conftest.py`
overrides `get_ai_provider` with a shared `MockAIReflectionProvider`
instance, exactly like `get_storage_service` is overridden with
`InMemoryStorageService` — `AI_API_KEY` is set to a throwaway placeholder
in the test environment purely so `Settings()` itself validates; it is
never read by any code path a test actually exercises.

**Async, with bounded timeouts and a narrow, typed error surface.**
`generate_reflection` is `async def`, called from
`reflection_service.generate_weekly_reflection` (also async) from an
`async def` FastAPI route — no blocking network call runs on the event
loop's own thread. `AnthropicReflectionProvider` constructs its client
with `timeout=settings.ai_timeout_seconds` and `max_retries=1` (not the
SDK's default of 2): a slow or unreachable provider should fail fast into
a clean `502` for the caller's current request, not multiply the
worst-case wall-clock time of a single request — the same reasoning
`app/services/storage/s3_storage.py` applies to its own boto3 client's
timeouts. Every failure mode maps to exactly one of three exceptions
(`AIProviderTimeoutError`, `AIProviderResponseError`, or the base
`AIProviderError` for anything else — see `app/core/exceptions.py`); the
provider implementation's own `except Exception` catch-all guarantees no
SDK-specific exception type can ever escape `app/services/ai/*.py` and
reach the route layer un-translated.

## AI output schema

`app.schemas.reflection.AIReflectionOutput` — `summary`, `mood_insight`,
`habit_insight`, `positive_highlights` (list), `areas_to_reflect_on`
(list), `encouragement` — is enforced two ways at once, not one:

1. **At the provider boundary**, via `client.messages.parse(...,
   output_format=AIReflectionOutput)` — the Anthropic API's own
   constrained decoding guarantees the raw JSON matches this schema's
   shape before the SDK ever hands control back to
   `anthropic_provider.py`.
2. **In the schema itself**, via `Field(max_length=...)` on every string
   (700/400/400/300 chars for summary/mood_insight/habit_insight/
   encouragement) and every list (max 5 items, each item capped at 200
   chars) — a concrete bound on response size regardless of provider,
   not just Claude-specific trust in constrained decoding. A response
   that violates either guarantee is treated identically: never stored,
   never returned as if it were valid (see "Failure / retry / fallback
   strategy" and `app/core/exceptions.py`'s `AIProviderResponseError`).

A safety refusal (`response.stop_reason == "refusal"`) is treated the
same way — `anthropic_provider.py` raises `AIProviderResponseError`
rather than ever returning `None`/empty content as if it were a real
reflection.

## Reflection persistence & caching

**A dedicated table (`weekly_reflections`, `app/models/reflection.py`),
not a cache layer or a recomputation-on-every-request design** — a
generated reflection is exactly the kind of small, user-owned, rarely-
regenerated record the rest of this backend already models as a table
(one row per user per completed week, `UNIQUE(user_id, week_start)`),
and persisting it is what makes "call the AI provider at most once per
user per week" (see below) possible at all.

**Only two statuses exist: `'completed'` and `'insufficient_data'` — a
third, `'failed'`, was deliberately NOT added.** An AI provider failure
is never persisted (see `app/services/reflection_service.py`'s module
docstring for the full reasoning) — a row here means either a reflection
was actually produced, or the week was conclusively determined to be
under-active, never "an attempt happened and failed". This also
sidesteps, by construction, a harder question a `'failed'` status would
raise: does a failed regeneration attempt get to overwrite a
previously-completed reflection? It never gets the chance to, because
nothing is written on failure.

**Caching policy** (`reflection_service.generate_weekly_reflection`):

```
POST /reflections/weekly/generate
        │
        ▼
Row already exists for (user, week)?
        ├── YES, and force_regenerate=false → return the stored row.
        │        No aggregation, no AI call — this is the cost-control
        │        story for this feature end-to-end.
        └── NO, or force_regenerate=true → aggregate → sufficient data?
                 ├── NO  → upsert(status='insufficient_data'), return.
                 │         (Also cached — a week already determined
                 │          insufficient stays that way until an explicit
                 │          force_regenerate.)
                 └── YES → call the AI provider →
                          ├── success → upsert(status='completed', ...), return.
                          └── failure → nothing written; the exception
                                        propagates to a 502 (see below).
```

`upsert` (`app/repositories/reflection_repository.py`) is the table's
only write path — get-or-create keyed by `(user_id, week_start)`, then
overwritten in place, so `force_regenerate=true` updates the same row
rather than appending a second one; this is the enforced "no duplicate
reflections for the same user/week" behavior, verified by
`tests/test_reflections.py::test_duplicate_generate_calls_never_create_a_second_row`.

## Design decisions where the existing Flutter app was ambiguous or silent

* **`description` renamed to `content`.** The old Firestore journal doc used
  `title`/`description`; this backend uses `title`/`content` for the same
  data — a plain rename for a more conventional field name, not a behavior
  change.
* **The old app's journal `streak` field was NOT reproduced.** It was a
  stored, client-computed value with a one-day-lookback bug (flagged in the
  Phase 1 migration audit). A streak is a derived analytics value, not raw
  CRUD data — it belongs in a future Phase 5 (weekly reflection / insights)
  query over `journal_entries.entry_date`, computed correctly from full
  history, not carried forward as a stored field with its original bug.
* **One entry per user per calendar day, enforced by a DB constraint**, for
  both journals and moods — this reproduces the old app's actual behavior
  (Firestore doc keyed by date, so a second save silently overwrote the
  first) as an explicit `UNIQUE(user_id, entry_date)` constraint instead of
  an accidental side effect of a document-id scheme. `POST` now correctly
  rejects a duplicate date with `409 Conflict`; `PATCH` is how you edit that
  day's entry.
* **Mood has no stored label/emoji.** `getEmojiForPercent()` in
  `homepage.dart` derives an emoji from the percent purely for display and
  never writes it anywhere — reproducing it as a stored column would be
  inventing data the app doesn't actually have.
* **The old app's "you can only edit today or yesterday's mood" rule was
  NOT enforced by the backend.** That's a UI policy in `homepage.dart`
  (`canEdit = isToday || isYesterday`), not a data-integrity rule — nothing
  about the mood data model requires it, and baking a UI-layer restriction
  into the API would make the API less reusable than the feature it's
  modeling. Left as a future client-side or product decision.
* **Checklist items are a global catalog, not per-user.** Confirmed from
  source: `homepage.dart` hard-codes the same 5 items for every user, with
  no categories, ordering choice, or user-created tasks anywhere in the
  app. `checklist_items` has no `user_id` column for exactly this reason —
  adding one now would be speculative; it's a straightforward future
  migration if personalization is ever built.
* **Checklist API is date-scoped, not a generic `/checklists/{id}` CRUD
  resource**, despite that being the suggested starting shape. The app has
  no "checklist" as a creatable/deletable thing — it has 5 fixed tasks whose
  *completion* is toggled per date. `GET/PATCH /checklists/{entry_date}`
  models that directly; `GET /checklists/items` exposes the (read-only,
  from this API's perspective) catalog for the client to render.
* **Checklist completion rows are created on first toggle, not
  pre-materialized for every day.** A day nobody has touched yet simply has
  zero rows and reads back as "0 of 5 completed" — this keeps the table's
  size proportional to actual use.
* **Two small, deliberately generic abstractions were introduced**:
  `NotFoundError`/`ConflictError` (one pair, reused by all three Phase 2
  services, instead of six narrower exception classes) and `Page[T]`
  (Phase 1 had no list endpoints, so pagination didn't exist yet). Both
  exist because two-or-more independent Phase 2 domains needed the exact
  same shape, not because either was speculative.
* **The Alembic migration's checklist-item seed data is duplicated (not
  imported) in `tests/conftest.py`.** Alembic version files aren't meant to
  be imported as application modules; the 5-item list is copied there
  instead, with a comment pointing back at the migration as the source of
  truth. A drift between the two would only affect which fixture ids tests
  exercise — it can never affect production data, since production always
  goes through the actual migration.

**Phase 3 additions to this list:**

* **Shoutouts have no sender/recipient split.** See "Shoutout data model"
  above for the full source evidence — this is the single biggest place
  Phase 3 deviated from the task's suggested starting shape, and it was a
  deliberate, source-grounded call, not an oversight.
* **The "did you feel better?" follow-up is persisted (`felt_better`,
  `felt_better_at` on the `shoutouts` row itself), fixing a real bug rather
  than inventing a feature.** The old app's `_loadYesterdayShoutout()`
  already reads `doc['feelBetter']` expecting it to exist; the only code
  that ever sets it, `_setYesterdayFeelBetter()`, calls `setState()` on
  local widget fields and never writes to Firestore. The read path's own
  expectation is the evidence this belongs on the shoutout record, not a
  separate table — a shoutout has at most one such answer, ever, so a 1:1
  column pair is the direct, unforced modeling choice, not a shortcut.
* **The follow-up is a dedicated endpoint (`POST
  .../feel-better`), not folded into `PATCH`.** It's a distinct kind of
  interaction (a one-time Yes/No prompt, not a text edit), and the old
  UI's own behavior treats it as one-shot — once answered, it shows a
  static outcome message with no way back. The endpoint enforces that:
  answering an already-answered shoutout returns `409`.
* **Media types and size limits came from reading `vault.dart`'s actual
  file-picker filters, not from picking a "reasonable-sounding" broad set.**
  See "Supported media types" above for the exact source citations behind
  each allowed content type.
* **`object_key` is 100% server-generated, never derived from the client's
  filename.** `original_filename` is stored and returned for display only;
  nothing about it — including any path separators or traversal sequences
  a malicious client might send — ever reaches the storage key.
* **Ordering media's delete as object-then-row (not row-then-object)** was
  a deliberate deviation from the more literal reading of "delete object
  when metadata deletion succeeds" — see "Upload/download/delete behavior"
  above for why the chosen ordering produces a more detectable failure mode.
* **`duration_seconds` is accepted as optional, unverified, client-supplied
  metadata.** This backend does no audio/video processing (no ffprobe/
  ffmpeg dependency was introduced), so it cannot compute duration itself;
  since the field is purely informational/display (unlike `user_id`, which
  is never trusted from the client), accepting it as reported is a
  reasoned, explicitly-documented trust boundary, not an oversight.
* **Content-type validation is allow-list-by-declared-type, not
  content-sniffing.** No magic-byte verification and no malware scanning
  are implemented — stated as a limitation in "Supported media types", not
  papered over.
* **A blocking-call bug was found and fixed during this phase's own live
  verification, not left in.** The upload route is `async def` (needed for
  `await file.read()`); calling the synchronous, network-bound
  `media_service.upload_media` directly inside it blocked FastAPI's entire
  event loop for as long as object storage took to respond — including a
  full connect-timeout when MinIO is unreachable, observed directly during
  verification. Fixed by dispatching that call through
  `starlette.concurrency.run_in_threadpool`, and by bounding the boto3
  client's own connect/read timeouts (5s/10s, 1 retry) so an outage fails
  fast with a clean `502` instead of hanging. See "Problems encountered" in
  the implementation report for the full before/after.

**Phase 4 additions to this list:**

* **No free-text comfort-person name, and no "primary comfort person"
  flag.** See "Relationship & invitation model" above for the full source
  evidence — both were deliberate, source-grounded omissions, not
  oversights.
* **Only two relationship statuses (`accepted`, `revoked`), not the fuller
  `pending`/`declined` vocabulary a general relationship model might
  suggest.** A `relationships` row is only ever created at the moment an
  invitation is accepted, so those earlier states belong to the
  *invitation*, not the relationship — see `app/models/relationship.py`.
* **Consent is a separate, independently revocable row
  (`relationship_permissions`), not a boolean on the relationship itself.**
  This is what lets an owner revoke just `stress_level` sharing without
  ending the relationship — modeling it as a flag on `relationships` would
  have conflated "we are connected" with "you may see my data", two
  decisions the product treats separately.
* **The founding `stress_level` grant is created automatically on accept,
  not via a separate explicit grant call.** In this product, generating and
  sharing the invitation link *is* the owner's consent decision — the info
  dialog in `regfav.dart` already discloses exactly what accepting enables
  before the link is ever created. It remains independently revocable
  afterward through the normal grant/revoke endpoints.
* **Stress is computed on demand and never persisted — no
  `stress_snapshots` table.** The data it aggregates over is small (at most
  7 days of mood/checklist rows), nothing in the product needs a score to
  outlive the data it was derived from, and a stored snapshot would just be
  a second, potentially-stale copy of a cheap query's result. See
  `app/services/stress_service.py`'s module docstring.
* **Only mood check-ins and checklist completion feed the stress score —
  never journal, shoutout, or media content.** Journal activity was an
  allowed-but-optional signal in the brief and was deliberately left out:
  "didn't journal today" is a weak, easily-misread proxy that would punish
  an unremarkable good day. Shoutout/media content is excluded because this
  feature must never expose private free text to a second person at all.
* **`score` is `None`, never `0`, when there's no data in the window.** A
  missing signal is never silently treated as "0 stress" — `level` reads
  `"insufficient_data"` instead of a falsely confident `"low"`.
* **The comfort-person-facing `ComfortStressView` is a narrower schema than
  the owner's own `StressResult`, not the same object with fields
  hidden.** It omits `contributors` entirely — the product only ever
  promised "view today's stress level", not the underlying mood-average/
  checklist-rate numbers behind someone else's score.
* **Invitation tokens are single-use, expiring, and stored only as a
  SHA-256 hash — the raw token is returned exactly once, at creation.**
  This replaces the old app's unverified, indefinitely-reusable
  `mindmate://invite?...` deep link, which required no recipient
  authentication and had no expiry.

**Phase 5 additions to this list:**

* **`WeeklySummary` has no field capable of holding journal/shoutout
  text — this is a schema-level guarantee, not a runtime check that could
  later be forgotten.** See "Privacy boundary" above; a future change that
  tried to add raw content to this feature would have to add a new field
  to do it, not flip a flag.
* **Only two persisted statuses (`completed`, `insufficient_data`); no
  `failed` status, and an AI provider failure is never written to the
  database at all.** See "Reflection persistence & caching" above — this
  was the deliberate choice over the task brief's suggested `generation
  status` field, specifically to avoid the harder question of whether a
  failed regeneration attempt should be allowed to overwrite a
  previously-completed reflection (it can't, because nothing is ever
  written on failure).
* **A "week" is Monday-Sunday, UTC, and must already be fully over before
  it can be generated.** `POST .../generate` rejects a non-Monday
  `week_start` or one whose Sunday hasn't happened yet with `400` — see
  "Weekly reflection architecture". This wasn't specified by the task
  brief and was a deliberate, explicit choice rather than an implicit
  "whatever range is convenient".
* **Trend fields (`mood_trend`, `stress_trend`) use a fixed, documented
  point threshold, not a statistical test.** A simple, auditable rule
  matching the same "transparent, not a black box" spirit as the Phase 4
  stress indicator — seeing the exact number that decided "improving" vs.
  "stable" is more valuable here than a more sophisticated method whose
  threshold isn't visible at all.
* **`stress_score_start`/`stress_score_end` reuse `stress_service.
  compute_stress()` directly, at two different reference dates, rather
  than a second, reflection-specific stress calculation.** The brief
  explicitly disallows a new stress algorithm; reusing the existing
  function also means the two features can never silently disagree about
  what a given day's stress score is.
* **The only shoutout signal that reaches a reflection is a count of
  positive `felt_better` answers — never any shoutout text, not even
  optionally.** See "Privacy boundary" above for why journal/shoutout
  *content* was judged unnecessary for a useful reflection, versus
  *activity* (did the user engage, and did venting help), which is not
  itself sensitive free text.
* **The AI provider is chosen and swappable via one interface
  (`AIReflectionProvider`) with exactly one real implementation
  (`AnthropicReflectionProvider`) for this phase.** A second provider
  is a new file plus one line in `app/services/ai/factory.py`; see "AI
  provider abstraction" above for why Claude was the practical choice for
  this first implementation specifically, not a claim about provider
  quality in general.
* **The AI's structured output is validated twice — once by the
  provider's own constrained decoding, once again by this codebase's own
  `Field(max_length=...)` bounds on `AIReflectionOutput`.** The second
  check is provider-independent on purpose: it holds even against a
  future provider implementation that doesn't offer schema-constrained
  generation at all.

**Phase 11A additions to this list** (Scheduler — not part of the
original Phase 1-5 plan; added later, following the same Flutter-migration
audit process as journals/moods/checklists):

* **Scheduler had no backend at all before this phase.** Confirmed from
  source: the existing app stores schedule data only in a local Hive box
  (`schedulerBox`), keyed by date alone with no per-user scoping, written
  independently by two different Flutter files with no shared code between
  them. This is the first backend-authoritative version of that data.
* **`scheduled_time` is a plain `"HH:MM"` string column, not a SQL
  `Time`/`DateTime`.** The app has no concept of seconds or
  timezone-aware scheduling — it's a 24-hour wall-clock label a user picks
  via a time picker on a specific calendar date, nothing more; a real
  `Time` type would imply precision/comparison semantics this feature has
  never had.
* **The old app's "today's schedule falls back to yesterday's" display
  behavior is explicitly NOT implemented here.** Confirmed a deliberate
  product decision (not an oversight): the backend stays a simple,
  date-specific API — `GET /scheduler/{entry_date}` only ever answers
  "what's on this exact date." Any "show yesterday's if today is empty"
  behavior is the Flutter client's responsibility (a second `GET` call),
  not something this API implements or is aware of.
* **The API is a whole-day `GET`/`PUT` pair, not per-row CRUD.** The
  existing Flutter UI only ever edits a full day at once (add/remove rows
  freely, then one "Save"), never a single row in isolation — a `PUT`
  that replaces the entire day's row set in one call matches that
  exactly, and needs no separate `DELETE` (a row's absence from `rows` is
  how it's removed).
* **Duplicate-time rejection is deliberately a service-layer check
  (`DuplicateScheduleTimeError`, mapped to 422), not a Pydantic
  validator**, because it has to inspect the whole `rows` list as a set,
  not one field in isolation — no existing schema in this codebase has a
  precedent for that shape of cross-item check. `UNIQUE(user_id,
  entry_date, scheduled_time)` at the database level is the independent,
  final backstop against the same rule being violated by a genuine
  concurrent-request race (mapped to 409 via the pre-existing
  `ConflictError`, distinct from a single self-contradictory request's
  422) — this directly fixes a real, confirmed bug in the old app, where
  two rows sharing a time silently overwrote one another instead of being
  rejected.

## What Phase 5 deliberately does not include

Push notifications (including any "your weekly reflection is ready"
notification a client might want to trigger off of this feature) and any
Flutter integration — both explicitly out of scope for this phase; see
"Recommended Phase 6" in the Phase 5 implementation report for how a
notification would plug into the API this phase built without this phase
needing to build the notification itself. Also still not implemented, and
explicitly identified rather than guessed at: a Vault-specific
authorization layer beyond account-level JWT ownership (see "Vault
security" above), a reconciliation job for the narrow, documented
database/object-storage inconsistency windows described in
"Upload/download/delete behavior", any permission type beyond
`stress_level` (the consent model supports adding more `permission_type`
values later without a schema change, but nothing in the current product
asks a comfort person to see anything else yet).
