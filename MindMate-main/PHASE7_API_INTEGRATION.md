# Phase 7 — Flutter API Foundation + Authentication Integration

**Scope of this phase:** API infrastructure and authentication only, per the
Phase 7 brief. Backend unmodified. Journal/mood/checklist/shoutout/media/
relationship/stress/weekly-reflection integration explicitly out of scope.
Firebase dependencies and code for every other feature left untouched and
still present.

---

## A. Phase Summary

This phase introduces a complete, tested, centralized network layer
(`lib/core/network/`, `lib/core/storage/`, `lib/data/models/auth/`,
`lib/data/repositories/auth_repository.dart`) and wires it into the app's
three existing, visually-unchanged authentication surfaces — the login
screen and splash-screen session check in `lib/main.dart`, the registration
screen in `lib/register_page.dart`, and the logout action in
`lib/settings_page.dart` — so that account creation, sign-in, sign-out, and
startup session restoration are now backed by the real FastAPI backend
(verified directly against a live running instance of it; see section S)
rather than only Firebase Auth.

Per an explicit decision made with the user before writing any screen code
(see section P), the new backend calls run **alongside**, not instead of,
the existing Firebase Auth calls on login/register/logout — both systems
end up authenticated together, so every screen this phase does not touch
(Home, Journal, Vault, Favorites, Settings, Edit Profile — all of which
still read `FirebaseAuth.instance.currentUser`) keeps working exactly as it
did before this phase, unmodified.

62 automated tests were written for this phase's new code — 57 fast,
fully-mocked unit tests plus 5 tests run end-to-end against a real,
locally-running instance of the FastAPI backend — and all 62 pass (section
Q/R/S).

## B. Existing Auth Flow Before Changes

- **Registration** (`register_page.dart`): `FirebaseAuth.createUserWithEmailAndPassword`,
  then a raw Firestore write to `users/{email-prefix}` with `{uid, email,
  name, provider: 'email', comfortPerson: {...}}`. A Firestore existence
  check (`_userExists`) ran first to reject a duplicate email client-side.
- **Login** (`main.dart`): the same existence check, then
  `FirebaseAuth.signInWithEmailAndPassword`, then a Firestore read to
  decide which screen to route to next.
- **Session restore** (`main.dart`'s `SplashScreen`): a one-shot check of
  `FirebaseAuth.instance.currentUser` on startup — not a persistent
  `authStateChanges()` listener. There was nothing to preserve or replace
  on that front (see section O).
- **Logout** (`settings_page.dart`): `FirebaseAuth.instance.signOut()`,
  then `Navigator.pushReplacementNamed(context, '/')`. (The Vault screen's
  own "Logout" icon in `vault.dart` does not actually call `signOut()` at
  all — it just navigates to `HomePage`. That is a pre-existing,
  Vault-scoped bug this phase does not touch.)
- No token of any kind was ever stored by the app itself — the Firebase
  SDK managed its own session transparently. No HTTP client, no API
  client, no repository layer, no typed models existed anywhere in the
  project (confirmed in PHASE6_INTEGRATION_AUDIT.md, Step 5/8).

## C. New Auth Flow

```
Register/Login screen
   │
   ▼
AuthRepository.register()/login()   ── POST /auth/register or /auth/login
   │  on success: tokens saved to secure storage
   ▼
(best-effort) legacy Firebase sign-up/sign-in — see section P
   │
   ▼
existing navigation logic — UNCHANGED

Any future authenticated FastAPI call
   │
   ▼
ApiClient — attaches "Authorization: Bearer <access_token>"
   │
   ├─ 200-299 ──────────────────────────────► returned to caller
   │
   └─ 401 ──► ApiClient refreshes (POST /auth/refresh, single-flight
              across concurrent requests) ──► retries the original
              request exactly once ──► success, or a clean
              UnauthorizedException if the refresh itself failed

Logout
   │
   ▼
AuthRepository.logout() ── POST /auth/logout (best-effort) + clears
   │                        secure storage unconditionally
   ▼
FirebaseAuth.instance.signOut() (unchanged)
```

## D. Files Created

**Core network/storage layer:**
- `lib/core/config/app_config.dart` — `API_BASE_URL` via `--dart-define`, request timeout.
- `lib/core/network/api_endpoints.dart` — path constants for `/health` and `/auth/*` only.
- `lib/core/network/api_exception.dart` — typed exception hierarchy (`NetworkException`, `BadRequestException`, `UnauthorizedException`, `ForbiddenException`, `NotFoundException`, `ConflictException`, `ValidationException`, `RateLimitException`, `ServerException`, `UnknownApiException`), all mapped from a real Dio failure, all with safe user-facing messages.
- `lib/core/storage/secure_storage_service.dart` — `TokenStorage` interface + `SecureTokenStorage` (flutter_secure_storage-backed) implementation.
- `lib/core/network/api_client.dart` — Dio wrapper: Bearer-header injection, single-flight refresh-on-401 with exactly-once retry, uniform `ApiException` conversion.

**Data layer:**
- `lib/data/models/auth/user_model.dart`, `profile_model.dart`, `me_response_model.dart`, `token_response_model.dart` — hand-written `fromJson` models matching the live-verified backend response shapes (section G).
- `lib/data/repositories/auth_repository.dart` — `register`, `login`, `refresh`, `logout`, `getCurrentUser`, `hasStoredSession`, `restoreSession`. The only class screens call for auth.

**Tests:**
- `test/fakes/fake_token_storage.dart` — in-memory `TokenStorage` test double.
- `test/core/network/api_exception_test.dart` — 17 tests.
- `test/core/network/api_client_test.dart` — 16 tests, including the refresh/retry/single-flight state machine, against a scripted fake `HttpClientAdapter`.
- `test/core/storage/secure_storage_service_test.dart` — 5 tests against the real `SecureTokenStorage`, with `flutter_secure_storage`'s platform channel mocked.
- `test/data/repositories/auth_repository_test.dart` — 19 tests, `ApiClient` mocked via `mocktail`.
- `test/integration/auth_live_backend_test.dart` — 5 tests against a real, running FastAPI instance (section S).

**Docs:**
- `API_CONFIGURATION.md` — how to set `API_BASE_URL` per environment.
- `PHASE7_API_INTEGRATION.md` — this file.

**Android (supporting change — see section T):**
- `android/app/src/debug/res/xml/network_security_config.xml` — permits plaintext HTTP, **debug builds only**, to `10.0.2.2`/`localhost`/`127.0.0.1` (the local dev server has no TLS certificate).

## E. Files Modified

| File | What changed | Why | What was preserved |
|---|---|---|---|
| `pubspec.yaml` | Added `dio`, `flutter_secure_storage` (deps) and `mocktail` (dev dep) | Section F | Every existing dependency untouched — nothing removed, nothing version-bumped |
| `lib/main.dart` | `_LoginPageState._login()` now calls `AuthRepository.instance.login()` first (surfacing `ApiException.message` on failure) before the preserved, best-effort legacy Firebase sign-in; login's password field validator relaxed from "≥6 chars" to "non-empty," matching the backend's actual `LoginRequest` rule; `SplashScreen._checkUserStatus` now awaits `AuthRepository.instance.restoreSession()` (best-effort, non-blocking) before its unchanged Firebase-based routing logic; the old `_userExists` Firestore pre-check is no longer called from `_login` (see section L) | Wire the new backend into the existing login screen/splash flow per Steps 12 & 15 | Visual design, all navigation destinations/targets, the Google sign-in button and forgot-password flow (both untouched — see section P/backend gaps), every other screen |
| `lib/register_page.dart` | `_register()` now calls `AuthRepository.instance.register()` first, then the preserved (now fallback-aware — see section M) legacy Firebase sign-up; the old `_userExists` pre-check is no longer called from `_register`; the password field validator now matches the backend's actual policy (≥8 chars, ≥1 letter, ≥1 digit) instead of the old "≥6 chars" rule | Wire the new backend into the existing registration screen per Step 13 | Visual design, the success snackbar + pop-back-to-login navigation, the Google sign-up button (untouched) |
| `lib/settings_page.dart` | The "Logout" option now calls `AuthRepository.instance.logout()` before the existing `FirebaseAuth.instance.signOut()` | Wire the new backend into the existing logout action per Step 14 | Visual design, the redirect to `/` afterward |
| `android/app/src/debug/AndroidManifest.xml` | Added an `<application android:networkSecurityConfig="@xml/network_security_config">` merge-in, debug source set only | Without it, a debug build cannot reach a plain-HTTP local dev backend at all — see section T | Release/profile manifests untouched; the existing `INTERNET` permission declaration untouched |
| `.flutter-plugins-dependencies`, `linux/flutter/generated_plugin_registrant.{cc,h}`, `linux/flutter/generated_plugins.cmake`, `macos/Flutter/GeneratedPluginRegistrant.swift` | Auto-regenerated by `flutter pub get`/`flutter build` to register `flutter_secure_storage`'s platform plugin | Automatic Flutter tooling output, not hand-edited | N/A — verified by diff (section V) to contain only the new plugin's registration, nothing else |

**Explicitly NOT modified:** `lib/homepage.dart`, `lib/journal_page.dart`, `lib/journal_entry_page.dart`, `lib/shoutout_page.dart`, `lib/favorite_page.dart`, `lib/regfav.dart`, `lib/vault.dart`, `lib/vault_password.dart`, `lib/edit_profile_page.dart`, `lib/enter_details_page.dart`, any relationship-type onboarding screen (`mom_page.dart` etc.), `lib/notifications_settings_page.dart`, `lib/help.dart`, `lib/about_us.dart`, `lib/custom_snackbar.dart`, any Hive model, any backend file, `android/app/src/main/AndroidManifest.xml`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`.

## F. Dependencies Added/Changed

| Dependency | Kind | Why this one |
|---|---|---|
| `dio: ^5.7.0` (resolved 5.11.1) | Runtime | Chosen over the bare `http` package specifically for its interceptor API — the standard, documented way to implement centralized Bearer-header injection and transparent refresh-on-401. `http` has no equivalent extension point; that logic would otherwise have to be duplicated at every call site. |
| `flutter_secure_storage: ^9.2.2` (resolved 9.2.4) | Runtime | The project's only pre-existing local-storage options (Hive, `shared_preferences`) are plaintext on disk — unacceptable for a refresh token valid for `REFRESH_TOKEN_EXPIRE_DAYS` (30 by default). Backed by Keychain (iOS) / EncryptedSharedPreferences+Keystore (Android). |
| `mocktail: ^1.0.4` | Dev only | No code generation (unlike `mockito`), used to mock `ApiClient` in `auth_repository_test.dart`. `ApiClient` itself is tested against a real `Dio` with a scripted fake `HttpClientAdapter`, not mocktail, since mocking `Dio` directly would bypass the interceptor logic under test. |

No existing dependency's version constraint was changed. `pubspec.lock` is git-ignored in this repo (confirmed — it does not appear in `git status` before or after `flutter pub get`), so there is no lockfile diff to review.

## G. API Contract Used

Verified directly against a live, locally-running instance of the backend
(SQLite-backed, via `backend/.venv` — the same documented test-only
database trade-off `backend/tests/conftest.py` already uses; no backend
file was touched to do this), not just read from source:

| Endpoint | Auth required | Verified request | Verified response |
|---|---|---|---|
| `POST /auth/register` | No | `{email, password, full_name?}` | 201 `{access_token, refresh_token, token_type: "bearer", expires_in: 900}`; 409 `{detail: "An account with this email already exists"}`; 422 `{detail: [{loc, msg, type}, ...]}` |
| `POST /auth/login` | No | `{email, password}` | 200 same token shape; 401 `{detail: "Incorrect email or password"}` (identical for unknown email vs. wrong password) |
| `POST /auth/refresh` | No | `{refresh_token}` | 200 a **rotated** token pair (both values change); 401 `{detail: "Refresh token is invalid or expired"}` — confirmed a used/rotated-out refresh token is rejected on reuse |
| `POST /auth/logout` | Yes (Bearer) | `{refresh_token}` | 204, empty body |
| `GET /auth/me` | Yes (Bearer) | — | 200 `{user: {id, email, is_active, is_verified, created_at, last_login_at}, profile: {full_name, age_group, phone, city, country, profile_image_url, onboarding_completed_at}}`; 401 `{detail: "Not authenticated"}` (no header) or `{detail: "Could not validate credentials"}` (bad/expired token) |
| `GET /health` | No | — | 200 `{status: "ok", database: "connected"}` |

No endpoint, field, or status code above was guessed or invented — every row was produced by an actual `curl` exchange with the running server before the corresponding Dart code was written.

## H. Token Storage Design

`TokenStorage` (interface, `lib/core/storage/secure_storage_service.dart`)
+ `SecureTokenStorage` (the one real implementation, `flutter_secure_storage`-backed:
Keychain on iOS, `EncryptedSharedPreferences`+Keystore on Android — configured
explicitly via `AndroidOptions(encryptedSharedPreferences: true)`).

- Both tokens are always written together (`saveTokens`) — the backend
  never issues one without the other, and a refresh rotates both.
- `clear()` removes both — called on logout (unconditionally, even if the
  server call fails) and whenever a refresh attempt itself fails.
- The interface exists specifically so `ApiClient`/`AuthRepository` can be
  unit-tested against an in-memory fake (`test/fakes/fake_token_storage.dart`)
  without touching a platform channel; `SecureTokenStorage` itself is
  separately tested against a mocked version of `flutter_secure_storage`'s
  real platform channel (`test/core/storage/secure_storage_service_test.dart`)
  so there is still a genuine end-to-end test of the real implementation.
- Not Hive, not `shared_preferences` — both are plaintext on disk.

## I. Token Refresh Design

Implemented once, inside `ApiClient` (`_rejectErrorStatusCodes` /
`_handleUnauthorized` / `_performRefresh`), and reused by everything else
— `AuthRepository.restoreSession()` deliberately calls `getCurrentUser()`
rather than re-implementing "expired → refresh → retry" a second time, so
there is exactly one implementation of this state machine in the app.

- **Single-flight:** a nullable `Future<bool>? _refreshInFlight` field. The
  first 401 to arrive starts a refresh and stores its `Future`; every
  concurrent 401 awaits that same `Future` instead of starting its own.
  This matters concretely because the backend **rotates** refresh tokens
  on every use (confirmed live — see section G) — a second, uncoordinated
  refresh call would invalidate the first and fail. Verified in
  `api_client_test.dart` with two genuinely concurrent requests forced to
  overlap via an artificial delay in the refresh response, asserting
  exactly one `/auth/refresh` call happened.
- **Retry exactly once:** the retried request is tagged
  `extra['__retried'] = true`; a 401 on the retried request itself is
  never retried again (verified by a dedicated test).
- **No refresh for a login/register 401:** those calls run with
  `requiresAuth: false`, so their own 401 (wrong password, etc.) is never
  mistaken for an expired session.
- **On refresh failure:** tokens are cleared and the original 401
  propagates as `UnauthorizedException` — never a silent retry loop, never
  a partially-updated token pair.
- **Lock release:** `_refreshInFlight` is reset to `null` in
  `_performRefresh`'s `finally` block, so a later, non-concurrent 401
  triggers its own fresh refresh rather than permanently reusing the first
  attempt's (possibly now-stale) result.

## J. API Error Handling

`ApiException` (abstract) + ten concrete subtypes
(`lib/core/network/api_exception.dart`), covering every status this phase
asks for: 400, 401, 403, 404, 409, 422 (with parsed per-field messages,
`ValidationException.fieldErrors`), 429, 500/502/503 (collapsed to one
generic, fixed "server unavailable" message — the raw backend body, which
could contain a stack trace in a misconfigured deployment, is never
shown), and network-level failures (timeout, no connection, cancelled,
bad certificate) with no status code at all. An unrecognized status code
falls back to `UnknownApiException` rather than crashing.

Every `.message` is safe to show directly in the existing
`showCustomSnackBar` calls — either the backend's own `detail` string
(already written to be user-facing) or a generic fallback. Nothing ever
surfaces a raw exception string, a stack trace, or the literal word
"Firebase" for a FastAPI failure.

## K. Authentication Repository Design

`AuthRepository` (`lib/data/repositories/auth_repository.dart`) is the
only class a screen calls — it knows nothing about Dio, HTTP headers, or
JSON keys, and nothing above it (screens) knows those things either. A
lazily-constructed static `.instance` singleton is used for screens (no
DI package exists in this project — see PHASE6_INTEGRATION_AUDIT.md, Step
8 — and adding one wasn't part of Steps 4/6's ask); tests construct
`AuthRepository(apiClient: ..., tokenStorage: ...)` directly with fakes
injected.

Public surface: `register`, `login`, `refresh`, `logout`, `getCurrentUser`,
`hasStoredSession`, `restoreSession`. One deliberate, documented piece of
duplication: `refresh()` re-implements a small part of what
`ApiClient._performRefresh` already does internally, because the two serve
different callers (the interceptor's internal retry path vs. an explicit
public method for, e.g., a future "refresh on app resume" hook) and Step 9
asked for a directly testable `refresh()` on the repository's own surface.

## L. Login Integration

`lib/main.dart`, `_LoginPageState._login()`. Calls
`AuthRepository.instance.login(email, password)` first; an `ApiException`
surfaces via the existing `showCustomSnackBar` and aborts (no legacy
Firebase call, no navigation). On success, the preserved legacy Firebase
sign-in runs best-effort (section P), then the existing navigation logic
(unchanged) decides between `/selectFavPerson` and `/enterDetails` exactly
as before.

The old `_userExists` Firestore pre-check is deliberately no longer called
here (it remains, still used by the untouched Google sign-in path) —
`POST /auth/login` already returns one identical 401 for both "unknown
email" and "wrong password" by design (verified live, section G), and the
old pre-check could not distinguish "no backend account yet" from "no
account at all," which would have incorrectly blocked a legacy-only
Firebase user from ever reaching the new login flow.

The password field's validator was relaxed from "≥6 characters" to
"non-empty," matching the backend's actual `LoginRequest` schema
(`min_length=1` — login has no *policy*, only registration does).

## M. Registration Integration

`lib/register_page.dart`, `_register()`. Calls
`AuthRepository.instance.register(email, password, fullName)` first,
handling 409 (duplicate email) and 422 (validation) via the same
`ApiException.message` → snackbar path. On success, the preserved legacy
Firebase sign-up runs best-effort: it now falls back to
`signInWithEmailAndPassword` if Firebase reports `email-already-in-use`
(rather than treating that as a registration failure), since the backend
account — the one this method is actually responsible for — has already
been created successfully by that point; a pre-existing legacy Firebase
account for the same email is exactly the transitional case this fallback
exists for. The Firestore user-doc write was changed from a plain `.set()`
to `.set(..., SetOptions(merge: true))` — necessary once the fallback can
sign in to a pre-existing account, so this write can no longer risk
clobbering that account's already-completed profile fields.

The password field's validator now matches the backend's exact
`RegisterRequest` policy (≥8 characters, ≥1 letter, ≥1 digit) instead of
the old "≥6 characters" rule, which would let a user submit a password the
backend then rejects with a 422 anyway.

## N. Logout Integration

`lib/settings_page.dart`, the "Logout" `_SettingsOption`. Now calls
`AuthRepository.instance.logout()` — which sends the stored refresh token
to `POST /auth/logout` (best-effort: failure doesn't block the rest) and
unconditionally clears secure storage — before the existing
`FirebaseAuth.instance.signOut()` and the existing redirect to `/`. Both
authentication systems this phase maintains in parallel end up logged out
together.

(The separate, pre-existing "Logout" icon on the Vault screen —
`vault.dart` — does not call `signOut()` at all today, Firebase or
otherwise; it only navigates to `HomePage`. That is an unrelated,
Vault-scoped issue this phase does not touch.)

## O. Session Restoration

`AuthRepository.restoreSession()`, called from `SplashScreen._checkUserStatus`
(`main.dart`) before its existing, unchanged Firebase-based routing logic.
If no access token is stored, it returns immediately without a network
call. If one is stored, it calls `getCurrentUser()` (`GET /auth/me`) —
`ApiClient`'s own interceptor transparently refreshes and retries once if
the access token has expired, so there is no second "expired → refresh"
implementation here. A refresh failure (or an outright-invalid stored
token) clears storage and returns `null`. A network/server failure is
**not** treated the same as "logged out" — it's rethrown, so a genuine
connectivity blip doesn't force a real session back through login; tokens
are left untouched for a later retry.

This call is deliberately non-blocking for navigation: which screen the
splash routes to is still decided entirely by the pre-existing,
Firebase-based logic, unchanged, regardless of the new backend session's
outcome — per the decision recorded in section P, only authentication
itself is migrated in this phase.

## P. Firebase Auth Removal Scope

**Before writing any screen code, this exact tension was raised with the
user and resolved explicitly** (not assumed): critical rules 1–2 say the
new register/login/logout must make zero Firebase Auth calls, while
"other features → existing Firebase/local implementation" (Step 16)
implies those untouched screens keep working — but every one of them
reads `FirebaseAuth.instance.currentUser`, which would be `null` forever
after a FastAPI-only login.

**Decision (user-selected): dual sign-in.** The new
`AuthRepository`/`ApiClient`/models/`api_exception.dart` — the actual "new
authentication implementation" the critical rules name — contain **zero**
Firebase code, verified by grep. The three screen-level call sites
(`_login`, `_register`, logout) call `AuthRepository` first as the source
of truth for the new session, and **only after that succeeds**, run the
pre-existing Firebase Auth calls as a preserved, best-effort side effect —
so the not-yet-migrated screens keep working unmodified during this
transitional phase, exactly as Step 16 anticipates.

**Concrete consequence, by design:** a user's session now depends on
*both* systems succeeding for every feature to work. If the FastAPI call
fails, nothing proceeds (no legacy Firebase call is attempted, no
navigation happens) — the new backend is authoritative. If the legacy
Firebase call fails *after* the FastAPI call has already succeeded (e.g.
Firebase is down, or credentials have drifted between the two systems),
that failure is caught and logged via `debugPrint` only, non-fatal: the
user proceeds into the app with a valid FastAPI session, but
Firebase-dependent screens (Home, Journal, Vault, Favorites, Settings,
Edit Profile) may not work correctly until the next successful dual
sign-in. This is a real, acknowledged risk of running two authentication
systems in parallel — not a bug, but a known, temporary cost of an
incremental (rather than big-bang) migration, and it goes away entirely
once those screens are migrated to the backend in a later phase.

## Q. Tests Added

62 tests total, all passing (section R):

- **`api_exception_test.dart`** (17): every `DioExceptionType` →
  `ApiException` subtype mapping; every status code 400–503 plus an
  unrecognized one; `ValidationException`'s field-error parsing, including
  multiple errors per field and a malformed/empty detail list.
- **`api_client_test.dart`** (16), against a real `Dio` with a scripted
  fake `HttpClientAdapter` (not a mock of `Dio` itself, which would bypass
  the interceptors under test): Bearer-header injection (present/absent
  per `requiresAuth`, absent when no token is stored); 2xx pass-through
  and 204→`null`; the full refresh-and-retry state machine (success,
  "retry at most once," refresh failure clears tokens, no refresh without
  a stored refresh token); single-flight refresh under genuinely
  concurrent requests (forced to overlap via an artificial delay) plus
  confirmation the lock releases for a later, separate 401; every other
  status code's mapping through the live client, not just the exception
  unit tests.
- **`secure_storage_service_test.dart`** (5), against the real
  `SecureTokenStorage` with `flutter_secure_storage`'s actual platform
  channel (`plugins.it_nomads.com/flutter_secure_storage`) mocked at the
  exact method/argument shapes read from its installed source — save,
  read, replace, clear, and cross-instance persistence.
- **`auth_repository_test.dart`** (19), `ApiClient` mocked via mocktail:
  every method's success and failure path, including that `register`
  omits an empty `full_name`, that `logout` still clears storage even when
  the server call throws, and that `restoreSession` distinguishes "no
  session" from "couldn't check right now."
- **`auth_live_backend_test.dart`** (5) — see section S.

## R. Test Results

```
flutter test test/core test/data test/integration
...
+62: All tests passed!
```

All 62 new tests pass. `flutter analyze` on every new file
(`lib/core/**`, `lib/data/**`, all new `test/**` files) reports **no
issues**. `flutter analyze` on the three modified screen files reports
only pre-existing `info`-level lints (`use_build_context_synchronously`)
already pervasive throughout this codebase's existing style, plus one
pre-existing unused import (`path_provider` in `main.dart`) and one
pre-existing unused-parameter warning (`settings_page.dart`) — neither
introduced by this phase; both existed before any Phase 7 edit.

`flutter test` on the **whole** project (not just the new tests) fails to
even compile `test/widget_test.dart` — this is a pre-existing,
unrelated issue: `file_picker: any` in `pubspec.yaml` (present before this
phase, untouched by it) has no version bound, so a fresh `flutter pub get`
resolves the newest `file_picker`, whose `FilePicker.platform` API was
removed/renamed — breaking `lib/vault.dart`, `lib/viewall_images.dart`,
and `lib/viewall_videos.dart` (all Vault-scoped, all out of this phase's
scope). `test/widget_test.dart` is itself Flutter's unmodified default
counter-app boilerplate (it asserts on `find.text('0')`/`'1'`, which
doesn't exist anywhere in this app) that transitively imports the whole
app, including Vault, so it fails to compile for a reason unrelated to
anything this file tests. See section W for the recommended (out-of-scope)
fix. This is why section R's authoritative results are scoped to
`test/core test/data test/integration` — that is the complete, real test
suite for everything this phase actually built.

**This is not a test-only problem.** A separate, additional check —
`flutter build apk --debug`, attempted purely to validate the new
`android/app/src/debug/` manifest/network-security-config compiles (not
required by this phase, done as extra verification) — fails at the exact
same `lib/vault.dart`/`lib/viewall_images.dart`/`lib/viewall_videos.dart`
compile errors. In its current state, **the whole app cannot be built at
all**, on any platform. This is not something Phase 7 introduced:
`file_picker: any` (an unbounded version constraint with no upper bound)
was already in `pubspec.yaml` untouched by this phase, and is what pulled
in `file_picker` 11.0.3 the moment `flutter pub get` ran fresh in this
environment — unrelated to `dio`/`flutter_secure_storage`/`mocktail`,
confirmed by temporarily removing this phase's three added dependencies
and re-running `flutter pub get`, which left `pubspec.yaml`'s
`file_picker: any` line — and therefore this same failure — in place
either way. This is a pre-existing, urgent, whole-app-blocking issue,
flagged here with more weight than a typical "known limitation" because of
that.

## S. Manual Integration Results

A real instance of the backend was started locally (via
`backend/.venv`, the SQLite `DATABASE_URL` trade-off
`backend/tests/conftest.py` already documents and relies on for the same
reason — **no backend file was modified to do this**) and used two ways:

1. **Direct `curl` verification** of every endpoint's exact request/response
   shape (section G) — this is what the Dart models, `ApiEndpoints`
   constants, and `ApiException` status mapping were written against, not
   guessed from reading the backend source alone.
2. **`test/integration/auth_live_backend_test.dart`** — 5 tests run
   through the real `ApiClient`/`AuthRepository`, hitting the live server
   with real HTTP, real JWTs, and real refresh-token rotation:
   - register → login → `GET /auth/me` → logout, end to end, asserting the
     logged-out refresh token is genuinely rejected by the live server
     afterward (not just cleared locally).
   - a duplicate registration against the live server returns a real 409.
   - a wrong password against the live server returns a real 401.
   - a corrupted/expired-simulated access token triggers `ApiClient`'s
     *actual* refresh-and-retry interceptor against the real server — the
     same code path `api_client_test.dart` exercises with a script, here
     exercised with the genuine thing — and the call still succeeds
     transparently.
   - a backend-rejected password returns a real, live 422, parsed into a
     `ValidationException`.

   Result: **all 5 pass** against the live server (see section Q/R for the
   combined count). This is the strongest verification available in this
   environment, well beyond documenting a limitation — a real backend
   *was* reachable here, so it was used.

No backend file was modified in the course of any of this.

## T. Security Review

- No secret, credential, token, or `.env` file is committed by this phase
  (checked by grep across every new file — none found; `pubspec.lock` is
  git-ignored in this repo and was never touched either way).
- Tokens live only in `flutter_secure_storage` (Keychain/Keystore-backed),
  never in Hive, `shared_preferences`, or a plain file.
- The refresh token — the longer-lived, more sensitive of the two
  credentials — is never logged, and `ApiException`'s 5xx handling never
  surfaces a raw backend response body (which could contain a stack trace
  in a misconfigured deployment) to the UI.
- The one supporting Android change (`android/app/src/debug/res/xml/network_security_config.xml`)
  permits plaintext HTTP **only** for `10.0.2.2`/`localhost`/`127.0.0.1`,
  **only** in the `debug` build variant (Gradle never merges `src/debug/`
  resources into a `profile` or `release` build) — a release build still
  requires HTTPS, as it always should. This is necessary supporting
  infrastructure for the very feature this phase builds (an Android debug
  build otherwise cannot reach a plain-HTTP local dev server at all), not
  an unrelated change.
- Password validation client-side now matches the backend's real policy
  (section M) — a defense-in-depth improvement (the backend still
  independently enforces it via 422), not a replacement for server-side
  validation.
- The dual-sign-in decision (section P) means a device that completes a
  FastAPI login always also attempts a matching Firebase sign-in with the
  same credentials — no new credential material is created or stored by
  this arrangement; it's the same email/password already being submitted
  to Firebase in the pre-existing flow, just sequenced after the new call
  instead of being the only call.

## U. UI Preservation Check

- Login screen: identical layout, copy, and styling; only the submit
  handler's internal logic changed, plus the password field's validation
  *message* for an edge case (empty password) — unchanged for every valid
  input.
- Signup screen: identical layout, copy, and styling; same internal-logic
  change, plus the password validator now rejects a password the backend
  would have rejected anyway (a stricter, correctness-improving change,
  not a visual one).
- Navigation: `/selectFavPerson` vs. `/enterDetails` routing after login,
  and the pop-back-to-login after registration, are both byte-for-byte the
  same decisions as before — same conditions, same destinations.
- Logout: still returns to `'/'` (the splash/login route) afterward.
- No other screen's file was modified (section E's exclusion list).
- Journal, mood, checklist, shoutout, and Vault functionality: unaltered —
  no file belonging to any of those features was touched, and their
  behavior is unchanged for as long as the paired legacy Firebase sign-in
  keeps succeeding (section P's documented, acknowledged limitation).

## V. Git Status

```
 M MindMate-main/.flutter-plugins-dependencies          (auto-generated — new plugin registration only)
 M MindMate-main/android/app/src/debug/AndroidManifest.xml
 M MindMate-main/lib/main.dart
 M MindMate-main/lib/register_page.dart
 M MindMate-main/lib/settings_page.dart
 M MindMate-main/linux/flutter/generated_plugin_registrant.cc   (auto-generated)
 M MindMate-main/linux/flutter/generated_plugin_registrant.h    (auto-generated)
 M MindMate-main/linux/flutter/generated_plugins.cmake          (auto-generated)
 M MindMate-main/macos/Flutter/GeneratedPluginRegistrant.swift  (auto-generated)
 M MindMate-main/pubspec.yaml
?? MindMate-main/API_CONFIGURATION.md
?? MindMate-main/PHASE7_API_INTEGRATION.md
?? MindMate-main/android/app/src/debug/res/           (network_security_config.xml)
?? MindMate-main/lib/core/
?? MindMate-main/lib/data/
?? MindMate-main/test/core/
?? MindMate-main/test/data/
?? MindMate-main/test/fakes/
?? MindMate-main/test/integration/
```

Reviewed line-by-line (`git diff`) for every modified file — see section E
for what changed and why in each. Confirmed:

- No secrets, `.env` files, or generated credentials anywhere in the diff
  or the new files.
- No Firebase configuration file (`google-services.json`,
  `GoogleService-Info.plist`, `android/app/src/main/AndroidManifest.xml`)
  touched or deleted.
- No file outside this phase's stated scope modified.
- **No backend file modified** — confirmed by `git status` scoped to
  `backend/` showing no tracked-file changes; the only backend-directory
  artifacts from this phase's work (a throwaway SQLite database and a
  server log, both from the manual verification in section S) are
  git-ignored (`*.db`, and the log was deleted before finishing this
  phase) and were never part of any commit.
- `PHASE6_INTEGRATION_AUDIT.md` shows as untracked because it was written
  in the prior phase and has not been committed yet — unrelated to this
  phase's own changes, listed here only for completeness.

No commit was made — these changes are left staged in the working tree for
review, per not assuming permission to commit on this project.

## W. Known Limitations / Backend Gaps

Carried forward from PHASE6_INTEGRATION_AUDIT.md (not new discoveries, restated for this phase's context):

- **Google sign-in** has no backend endpoint (rule 19 — not implemented
  here). Its button is untouched and still Firebase-only; a user who signs
  up/in via Google gets no FastAPI session at all until the backend adds
  OAuth support.
- **Password reset** has no backend endpoint (rule 20 — not implemented
  here). The "Forgot Password?" link and Settings' "Change password" are
  untouched and still Firebase-only.
- **No `PATCH /me/profile`-equivalent endpoint** exists yet, so
  `enter_details_page.dart`/`edit_profile_page.dart` still write profile
  fields to Firestore only — the backend's `ProfileRead` those fields
  would map to has no write path yet.

New to this phase:

- **The dual-sign-in transitional risk** — see section P. This is the
  single most important thing to understand about this phase's design: a
  user is now "logged in" to two independent systems, and only the
  FastAPI one is guaranteed by this phase's own logic to succeed.
- **`file_picker: any` in `pubspec.yaml`** (pre-existing, untouched by
  this phase) resolves to a version whose API broke `lib/vault.dart`,
  `lib/viewall_images.dart`, and `lib/viewall_videos.dart` — see section R.
  Recommended fix (not performed here, out of scope): pin `file_picker` to
  a specific, currently-working version.
- **`test/widget_test.dart`** is Flutter's unmodified, never-customized
  default counter-app test — unrelated to this app's actual UI, and
  already meaningless even before the `file_picker` issue. Worth deleting
  or replacing in a future phase, not this one.
- **The Vault screen's own "Logout" icon** (`vault.dart`) does not call
  `FirebaseAuth.signOut()` today, and now also does not call
  `AuthRepository.logout()` — it only navigates to `HomePage`. Pre-existing
  behavior, Vault-scoped, out of this phase's edit scope; flagged here so
  it isn't mistaken for something this phase should have wired up.

## X. Recommended Next Phase

Per the audit's Step 4/10 prioritization: **Journal integration** is the
cleanest next target — the backend's `Journal` resource maps almost
directly onto the existing Firestore shape (only `streak`, computed
client-side, has no backend equivalent yet), and `journal_page.dart`
already isolates its Firestore calls into a small number of methods that
would translate directly onto a new `JournalRepository` built the same way
`AuthRepository` was built here. Mood and Checklist are the next-cleanest
after that, for the same reason (Step 10's model-mapping tables already
confirm both are close-to-direct translations, with Checklist's item
catalog already verified byte-identical to the app's hardcoded labels).

---

## Explicit confirmations

```
Backend modified: NO
Journal integration: NO
Mood integration: NO
Checklist integration: NO
Shoutout integration: NO
Media integration: NO
Relationship integration: NO
Stress integration: NO
Weekly Reflection integration: NO
Firebase Firestore migration: NO
Firebase Storage migration: NO
Data migration: NO
```
