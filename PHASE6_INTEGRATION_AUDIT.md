# MindMate — Phase 6 Flutter ↔ FastAPI Integration Audit

**Scope of this document:** inspection and analysis only. No Flutter code, no backend code, and no Firebase configuration were changed while producing this report. All findings below are traced to actual code paths in `MindMate-main/lib/` (33 files) and `backend/app/` (Phase 1–5, commit `d61ded2`), not inferred from file names.

---

## 0. Executive summary

- The Flutter app has **no state-management framework, no repository layer, and no API/service abstraction**. Every screen (`StatefulWidget`) talks to `FirebaseAuth`/`FirebaseFirestore`/`FirebaseStorage` directly inside its own `State` class. This is actually good news for a rewrite: there is no existing architecture to preserve, so Phase 7 can introduce a clean layer without fighting an existing pattern.
- The app identifies a Firestore user document by **`email.split('@')[0]`** ("username"), not the Firebase Auth `uid`, everywhere except one place (`favorite_page.dart`'s pending-invites code, which uses `user.uid`). That one place writes to fields (`pendingInvitesReceived`, `pendingInvitesSent`, `myComfortCircle`, `inTheirCircle`) that **no other code in the app ever writes**, so it is dead/orphaned code operating on a document ID scheme incompatible with the rest of the app.
- The "comfort person" invite system is **non-functional**: `regfav.dart` builds a `mindmate://invite?...` link; the Android manifest registers the `mindmate://` scheme as a `VIEW`/`BROWSABLE` intent filter so the OS *will* open the app; but `uni_links` (declared in `pubspec.yaml`) is **never imported or called anywhere in `lib/`**, so the incoming link's query parameters are never read. The invite link does nothing.
- **Vault media (images, videos, and the actually-reachable voice-note recording path) never leaves the device today.** It is stored only in local Hive boxes and references local file-system paths. A Firebase Storage upload path for voice notes exists in `vault.dart` (`_startRecording`/`_stopRecordingAndSave`) but is **dead code** — nothing in the widget tree calls it; the wired-up record button calls `_startFloatingRecording`/`_stopFloatingRecordingAndSave`, which is 100% local.
- The backend's own README independently states the old app "reads [the feel-better] answer back but never actually persisted it." This audit independently confirms that exact bug at `journal_page.dart`'s `_setYesterdayFeelBetter`, which only calls `setState` and never writes to Firestore.
- The checklist's 5 hardcoded item labels in `homepage.dart` are **byte-for-byte identical**, in the same order, to the backend's Alembic seed data for the checklist catalog — this mapping is safe and needs no reconciliation.
- A local-only "Scheduler" feature (Hive `schedulerBox`) exists in the Flutter app with **no backend equivalent anywhere in Phases 1–5**. This is a real scope gap, not an integration-mapping task.
- The Notification Settings screen is **purely decorative**: six `Switch` widgets hold local `State` fields that are never persisted (no `SharedPreferences`, no Firestore) and reset every time the screen is rebuilt.

---

## STEP 1 — Flutter application inventory

`MindMate-main/lib/` contains 33 files, no subfolders — everything is flat. There is no `models/`, `services/`, `repositories/`, or `providers/` directory. Functional grouping (by actual behavior, not folder):

| Area | File(s) |
|---|---|
| App entry / auth / routing | `main.dart` |
| Registration / login | `register_page.dart`, `main.dart` (`LoginPage`) |
| Onboarding — profile details | `enter_details_page.dart` |
| Onboarding — comfort person | `regfav.dart`, `mom_page.dart`, `dad_page.dart`, `sibling_page.dart`, `bestfriend_page.dart`, `lovers_page.dart`, `grand_page.dart`, `others_page.dart` |
| Home (checklist, scheduler, mood calendar) | `homepage.dart`, `scheduler_details_page.dart` |
| Journal + Shoutout | `journal_page.dart`, `journal_entry_page.dart`, `shoutout_page.dart` |
| Favorites / relationships | `favorite_page.dart` |
| Vault (voice/image/video) | `vault.dart`, `vault_password.dart`, `vault.g.dart`, `image_note.dart`(+`.g.dart`), `video_note.dart`(+`.g.dart`), `viewall_images.dart`, `viewall_videos.dart`, `duration_adapter.dart` |
| Settings | `settings_page.dart`, `edit_profile_page.dart`, `notifications_settings_page.dart`, `help.dart`, `about_us.dart` |
| Shared UI utility | `custom_snackbar.dart` |

There is **no weekly-reflection UI, no AI-related screen, and no stress-detail screen** beyond a single disabled-looking "View today's stress level" `TextButton` in `favorite_page.dart` whose `onPressed` is a bare `// TODO: Implement stress level view`.

---

## STEP 2 — Firebase dependency inventory

### Firebase Authentication

| File | Function | Purpose | Data returned/used | Screen |
|---|---|---|---|---|
| `main.dart` | `_checkUserStatus()` | Splash-screen session restore | `FirebaseAuth.instance.currentUser`, then `.email` | `SplashScreen` |
| `main.dart` | `_login()` | Email/password sign-in | `signInWithEmailAndPassword` | `LoginPage` |
| `main.dart` | `signInWithGoogle()` | Google OAuth sign-in | `GoogleSignIn` → `GoogleAuthProvider.credential` → `signInWithCredential` | `LoginPage` |
| `main.dart` | Forgot-password `TextButton` | Password reset | `sendPasswordResetEmail` | `LoginPage` |
| `register_page.dart` | `_register()` | Email/password sign-up | `createUserWithEmailAndPassword`, catches `FirebaseAuthException` | `RegisterPage` |
| `register_page.dart` | Google button `onTap` | Google sign-up | same Google flow as above | `RegisterPage` |
| `enter_details_page.dart` | `_checkUserDetails()`, `build()` | Reads `currentUser.email` to key Firestore doc | `FirebaseAuth.instance.currentUser` | `EnterDetailsPage` |
| `homepage.dart`, `journal_page.dart`, `favorite_page.dart`, `regfav.dart`, `vault.dart`, `vault_password.dart`, `edit_profile_page.dart`, `settings_page.dart`, `shoutout_page.dart` | `userId`/`username` getters | Derive the Firestore doc key `email.split('@')[0]` | `currentUser.email` | all of the above |
| `settings_page.dart` | "Change password" option | Re-sends a reset email (no real change-password flow); blocks Google-sign-in users | `sendPasswordResetEmail`, reads `provider` field from Firestore | `SettingsPage` |
| `vault.dart` (`getLastViewed`), `vault_password.dart` | Reads `currentUser.email` to key vault docs | — | `VaultPage`, `VaultPasswordPage` |
| `settings_page.dart` | "Logout" option | `FirebaseAuth.instance.signOut()` | — | `SettingsPage` |

There is **no email-verification flow**, **no auth-state `StreamBuilder`/listener** (session restore is a one-shot check in `SplashScreen.initState`, not a persistent listener), and **no explicit sign-out anywhere except `settings_page.dart`** (the Vault screen's "Logout" icon navigates to `HomePage` instead of calling `signOut()` — it doesn't actually log out).

### Firestore

| Operation | Collection / path | Purpose | Current data shape | FastAPI replacement |
|---|---|---|---|---|
| `set` (create) | `users/{username}` | Register | `{uid, email, name, provider, comfortPerson:{relation,name,customRelation}}` | `POST /auth/register` (returns tokens; profile fields via a later `PATCH` — **no profile-update endpoint currently exists**, see Step 10) |
| `get` | `users/{username}` (existence check) | "does this email already have an account" pre-check on login/register | doc existence | Not needed — `POST /auth/login` / `POST /auth/register` already return the correct error (401 / 409) |
| `update`/`set(merge)` | `users/{username}` | Save onboarding details (name, ageGroup, phone, city, country, profileImage) | flat fields | No dedicated `PATCH /me/profile` endpoint exists in Phase 1–5 (`ProfileRead` is read-only in `MeResponse`) — **gap, see Step 10** |
| `update`(`comfortPerson`) | `users/{username}` | Save selected comfort person | `{relation, name, customRelation}` | `POST /relationships/invitations` (a comfort-person relationship is now a first-class `Relationship`/`RelationshipInvitation`, not a field on the user doc) |
| `get`/`set` | `users/{username}/checklist/{yyyy-MM-dd}` | Daily checklist | `{items: [bool,bool,bool,bool,bool]}` (positional, no labels) | `GET/PATCH /checklists/{entry_date}` + `GET /checklists/items` for labels |
| `get`/`set` | `users/{username}/moods/{yyyy-MM-dd}` | Mood % | `{items: {dateKey: percent}}` — a map keyed by date *nested inside* a doc that is itself keyed by date (redundant/inconsistent shape; two different write paths, `saveMoods()` and `saveMoodForDate()`, don't agree on what "items" contains) | `POST/GET/PATCH /moods` — one row per date, `mood_value: int 0-100` |
| `get`/`set` | `users/{username}/journals/{yyyy-MM-dd}` | Journal entry | `{title, description, date, streak}` | `POST/GET/PATCH/DELETE /journals` — **backend has no `streak` field** (see Step 10) |
| `get`/`set` | `users/{username}/shoutouts/{yyyy-MM-dd}` | Shoutout (via `shoutout_page.dart`) | `{title, description, timestamp}` | `POST/GET/PATCH/DELETE /shoutouts` + `POST /shoutouts/{id}/feel-better` |
| `add` (auto-ID) | `users/{username}/shoutouts` (via **dead** `journal_page.dart::_saveShoutout`) | Unreachable legacy write path | `{problem, timestamp}` — incompatible shape with the doc-per-date structure actually read elsewhere | N/A — dead code, do not port |
| `set` | `users/{username}/voice_notes/{id}` (via **dead** `vault.dart::_stopRecordingAndSave`) | Voice-note metadata | `{id, title, url, localPath, date, duration}` | `POST /media/upload` — dead code path, not currently reachable from the UI |
| `get`/`set(merge)` | `users/{username}` (`vaultPasswordHash`, `vaultLastViewed`, `vaultPrevLastViewed`) | Separate vault-unlock password (SHA-256 hash) + last-viewed timestamp | flat fields on the user doc | No Phase 1–5 endpoint owns a "vault password" concept — **gap, see Step 15** |
| `get`/`update` (`FieldValue.arrayUnion`/`arrayRemove`) | `users/{uid}` (via **dead** `favorite_page.dart::_acceptInvite`/`_declineInvite`/`_showPendingInvitesDialog`) | Orphaned second relationship system keyed by Auth `uid`, never written by any registration/onboarding path | `{pendingInvitesReceived[], pendingInvitesSent[], myComfortCircle[], inTheirCircle[]}` | Superseded entirely by `/relationships/invitations` — do not port this shape |

No `orderBy`/pagination/`where` clauses are used anywhere — every read is a single `.doc(id).get()` or an unfiltered `.collection().get()` (`loadMoods()`). No `snapshots()`/listeners are used anywhere in the app (see Step 12).

### Firebase Storage

| Upload site | Storage path | Trigger | Reachable from UI? |
|---|---|---|---|
| `enter_details_page.dart::_saveDetails` | `profile_images/{username}.jpg` | Onboarding profile picture | ✅ Yes |
| `edit_profile_page.dart::_saveProfile` | `profile_images/{username}.jpg` | Edit-profile picture change | ✅ Yes |
| `vault.dart::_stopRecordingAndSave` | `voice_notes/{username}/{id}.m4a` | The non-wired recording path | ❌ **Dead code** |

Profile images use `getDownloadURL()` and store the resulting public URL as a plain string field (`profileImage`) on the user doc; `edit_profile_page.dart`/`vault_password.dart` render it with `CachedNetworkImage`/`Image.network`. No image is ever deleted from Storage when replaced (old profile picture at the same path is simply overwritten by `putFile`, so this isn't a leak — but there's no delete path either).

**Media/Vault architecture map:** the *only* Firebase Storage usage that is reachable from the UI is profile pictures. Voice/image/video Vault content is 100% local (see Step 3), so the Phase 3 media API's job in migration is almost entirely about *newly* wiring up uploads that never existed in the cloud before — this is closer to "add cloud sync to a local-only feature" than "swap one backend for another."

---

## STEP 3 — Local storage inventory

| Storage | What is stored | Why | Must remain local? | Should move to backend? |
|---|---|---|---|---|
| Hive box `voice_notes` (`VoiceNote`, HiveType 0) | id, title, url, localPath, date, duration | Vault voice notes — the only reachable recording/import path | No | Yes — via `POST /media/upload` (`media_type=voice`) |
| Hive box `image_notes` (`ImageNote`, HiveType 2) | id, path, title, date | Vault images (file-picker imports only) | No | Yes — via `POST /media/upload` (`media_type=image`) |
| Hive box `video_notes` (`VideoNote`, HiveType 3) | id, path, title, date | Vault videos (file-picker imports only) | No | Yes — via `POST /media/upload` (`media_type=video`) |
| Hive box `schedulerBox` (untyped, `Map<String,String>` per date key) | time→description rows for a "daily scheduler" widget | Home-screen scheduler | Local cache is fine for offline use, but **the feature has no backend model or endpoint at all in Phases 1–5** | Needs a product decision before Phase 7 — see Step 17 |
| Hive `DurationAdapter` (HiveType 1) | Codec for `Duration` fields | Supports `VoiceNote.duration` | N/A (infrastructure) | N/A |
| Local filesystem (`path_provider`/`file_picker`/`image_picker` returned paths) | Raw voice-note `.m4a` recordings, imported image/video files | Referenced by the Hive notes above (`path`/`localPath`) | Should become a cache of downloaded/uploaded media once media integration lands | Source-of-truth moves to backend + object storage |
| `shared_preferences` package | Declared in `pubspec.yaml` | — | — | **Not actually used anywhere in `lib/`** (confirmed by full-project grep) — dead dependency today |

**Vault data that exists only on-device today:** all of it that is actually reachable — every image, every video, and every voice note recorded through the app's own record button (`_startFloatingRecording`/`_stopFloatingRecordingAndSave`) or imported through the file picker. The one Firebase Storage upload path for voice notes (`_stopRecordingAndSave`) is dead code, so in practice **0% of Vault media a real user has ever created has left their device**, despite `firebase_storage` being a project dependency.

---

## STEP 4 — Feature-to-backend mapping

| Feature | Existing Flutter implementation | Current source | New FastAPI endpoint | Required Flutter changes | Status |
|---|---|---|---|---|---|
| **Register** | `register_page.dart::_register` | Firebase Auth + Firestore `users/{username}` | `POST /auth/register` | Replace Firebase Auth call; store returned access/refresh tokens; drop the pre-check `_userExists` (backend returns 409) | Needs full rewrite |
| **Login** | `main.dart::_login` | Firebase Auth | `POST /auth/login` | Replace sign-in call; store tokens; backend gives one identical error for bad email or bad password (matches the app's current UX intent) | Needs full rewrite |
| **Google sign-in** | `main.dart`/`register_page.dart` `signInWithGoogle` | Firebase Auth + Google Sign-In SDK | **No Phase 1–5 endpoint** | Backend has no OAuth/social-login endpoint yet | **Blocked — backend gap** |
| **Logout** | `settings_page.dart` (`FirebaseAuth.signOut()`) | Firebase Auth | `POST /auth/logout` | Send stored refresh token; clear local token storage | Needs full rewrite |
| **Refresh token** | Not implemented (Firebase SDK handled this transparently) | — | `POST /auth/refresh` | New logic entirely — nothing to port | New |
| **Current user / session restore** | `main.dart::_checkUserStatus` (one-shot check in splash) | `FirebaseAuth.currentUser` + Firestore doc | `GET /auth/me` | Store tokens in secure storage; call `/auth/me` on startup instead of reading a cached Firebase user | Needs full rewrite |
| **Password reset** | `main.dart`/`settings_page.dart` (`sendPasswordResetEmail`) | Firebase Auth | **No Phase 1–5 endpoint** | Backend has no forgot/reset-password flow | **Blocked — backend gap** |
| **Journal create/edit** | `journal_page.dart` + `journal_entry_page.dart` | Firestore `journals/{date}` | `POST /journals`, `PATCH /journals/{id}` | Store returned `id` (UUID) instead of using the date as the key; **`streak` must be computed client-side or added to the backend** — see Step 10 | Needs full rewrite |
| **Journal read/history** | `_loadTodayJournal`, `_loadJournalForDate` | Firestore | `GET /journals`, `GET /journals/{id}` | Switch from a date-keyed doc lookup to `GET /journals?start_date=&end_date=` + client-side date matching, or track `id`s locally | Needs full rewrite |
| **Journal delete** | Not implemented in UI today | — | `DELETE /journals/{id}` | New UI affordance (optional) | New capability available |
| **Mood create/edit** | `homepage.dart` calendar tap dialog | Firestore `moods/{date}` (buggy nested shape) | `POST /moods`, `PATCH /moods/{id}` | Straightforward — the backend's flat `{entry_date, mood_value}` is actually simpler than the current Firestore shape | Needs full rewrite |
| **Mood history** | `loadMoods()` (loads the *entire* collection, unfiltered) | Firestore | `GET /moods?start_date=&end_date=` | Add pagination/date-range awareness — current code has no page limit at all | Needs full rewrite |
| **Checklist daily** | `homepage.dart` (5 hardcoded `checklistItems` + `List<bool> checklist`) | Firestore `checklist/{date}` (positional bool array) | `GET /checklists/items` (catalog) + `GET/PATCH /checklists/{entry_date}` | Item labels are confirmed byte-identical to backend seed data — map by `sort_order`, not by hardcoded string, going forward | Needs full rewrite, low risk |
| **Checklist history** | Not implemented (only "today", reset at midnight client-side) | — | `GET /checklists/{entry_date}` per date | New capability available if a history UI is ever added | New capability available |
| **Shoutout create/edit** | `shoutout_page.dart::_saveShoutout` | Firestore `shoutouts/{date}` | `POST /shoutouts`, `PATCH /shoutouts/{id}` | Track `id` instead of date-as-key | Needs full rewrite |
| **Shoutout feel-better** | `journal_page.dart::_setYesterdayFeelBetter` (never persists — confirmed bug) | Local `setState` only, no Firestore write | `POST /shoutouts/{id}/feel-better` | This is a **net-new working feature** for the app — the backend explicitly fixes the bug the old app had | Backend fixes an existing bug; Flutter must be rewritten to actually call it |
| **Vault upload (voice/image/video)** | `vault.dart` (Hive-only for images/video; the wired voice-recording path is also Hive-only; a Firebase Storage path exists but is dead code) | Hive + local filesystem | `POST /media/upload` (multipart) | This is effectively **adding cloud sync to a feature that has never had it in production**, not swapping backends | Needs full rewrite + new capability |
| **Vault list/download/delete** | `ValueListenableBuilder` over Hive boxes; delete = `note.delete()` (Hive) | Hive | `GET /media`, `GET /media/{id}` (fresh presigned URL), `DELETE /media/{id}` | Replace Hive listenable with a fetched/cached list; handle presigned URLs expiring (`download_url_expires_in_seconds`) | Needs full rewrite |
| **Relationships / comfort person — create** | `regfav.dart::_saveComfortPerson` (writes a field on the user doc + generates an unverified custom-scheme link) | Firestore field + broken deep link | `POST /relationships/invitations` (returns a one-time token) | Needs a real invite-sharing UI (share sheet already exists via `share_plus`) around the returned token | Needs full rewrite |
| **Relationships — accept** | `favorite_page.dart::_acceptInvite` (dead code, wrong ID scheme, never invoked by any working invite-creation path) | Orphaned Firestore arrays keyed by `uid` | `POST /relationships/invitations/{token}/accept` | New — nothing salvageable from the current accept code | Needs full rewrite |
| **Relationships — decline/revoke** | `favorite_page.dart::_declineInvite` (same dead-code caveat) | Orphaned Firestore arrays | `POST /relationships/invitations/{token}/decline`, `POST /relationships/{id}/revoke` | New | Needs full rewrite |
| **Relationship status / listing** | `favorite_page.dart::_fetchComfortPerson` (reads the single `comfortPerson` field — the app models "one comfort person" as a singular value, not a list) | Firestore field | `GET /relationships?role=owner\|comfort_person` (returns a list, supports many relationships) | **Product-shape change**: backend supports multiple relationships/comfort people; current UI assumes exactly one | Needs full rewrite + product decision |
| **Consent (grant/revoke `stress_level`)** | Not implemented at all today (no consent concept exists client-side) | — | `POST/GET /relationships/{id}/permissions/...` | Entirely new UI/flow | New capability, no legacy to map |
| **Stress — own** | Not implemented (no screen reads or displays the user's own stress) | — | `GET /stress/today`, `GET /stress/history` | New UI | New capability |
| **Stress — comfort-person view** | `favorite_page.dart` "View today's stress level" button — literal `// TODO`, never implemented | — | `GET /relationships/{id}/stress/today` | This is the *first real implementation* of an existing but non-functional button | Backend gives real substance to a button that has always been a stub |
| **Weekly reflection (generate/latest/specific week)** | **No screen, card, or state exists anywhere in `lib/`** | — | `POST /reflections/weekly/generate`, `GET /reflections/weekly`, `GET /reflections/weekly/{week_start}` | Entirely new screen(s), including loading/empty/error states | New capability, no UI to reuse |

---

## STEP 5 — Existing architecture

**Pattern found:** none of Provider, Riverpod, Bloc/Cubit, GetX, or a repository/service layer. Confirmed by `pubspec.yaml` (no state-management package is a dependency) and by every screen file: each is a `StatefulWidget` whose `State` class calls `FirebaseAuth.instance`/`FirebaseFirestore.instance`/`FirebaseStorage.instance` directly inside its own methods (`_loadTodayJournal`, `_saveShoutout`, `loadMoods`, etc.), and re-renders via plain `setState`. There is no dependency injection, no interface between a screen and Firebase, and no shared data-access module — the same `email.split('@')[0]` username-derivation logic is copy-pasted (not shared) across at least ten files.

This is **direct Firebase calls from screens**, the simplest (and most tightly-coupled) of the patterns the audit brief lists.

**Recommended introduction point for the new API layer:**

```text
Flutter UI (StatefulWidget, unchanged shape)
   ↓
Repository layer (NEW — one class per resource: JournalRepository, MoodRepository, AuthRepository, …)
   ↓
API Client (NEW — single Dio instance + interceptor for the Bearer token / refresh)
   ↓
FastAPI
   ↓
PostgreSQL / S3
```

Given there is *no* existing architecture to preserve, the textbook layered structure from the audit brief fits cleanly — there is no legacy pattern it would have to fight. The one adjustment worth making up front: because every screen currently owns its Firebase calls directly, Phase 7 should introduce the repository layer **and** a thin state-management choice (even something as light as `ChangeNotifier`/`Provider`) at the same time, since moving from "State calls Firebase" straight to "State calls a repository" without any intermediate state holder will just recreate the same tight coupling one layer down, one screen at a time.

---

## STEP 6 — Direct Firebase calls from UI (file-by-file)

| File | Firebase call(s) | Feature | Recommended replacement |
|---|---|---|---|
| `main.dart` | `FirebaseAuth` (sign-in, Google sign-in, reset email, session check), `FirebaseFirestore` (user-doc existence/read) | Splash, login | `AuthRepository` + `UserRepository` |
| `register_page.dart` | `FirebaseAuth` (create user, Google), `FirebaseFirestore` (create user doc) | Registration | `AuthRepository` |
| `enter_details_page.dart` | `FirebaseAuth` (current user), `FirebaseFirestore` (read/update), `FirebaseStorage` (profile image upload) | Onboarding details | `ProfileRepository` (needs new backend endpoint — Step 10), `MediaRepository` for the image |
| `homepage.dart` | `FirebaseFirestore` (checklist, moods) | Home screen | `ChecklistRepository`, `MoodRepository` |
| `journal_page.dart` | `FirebaseAuth` (uid derivation), `FirebaseFirestore` (journals, shoutouts — dead write path) | Journal + shoutout preview | `JournalRepository`, `ShoutoutRepository` |
| `shoutout_page.dart` | `FirebaseFirestore` (shoutouts) | Shoutout editor | `ShoutoutRepository` |
| `favorite_page.dart` | `FirebaseAuth`, `FirebaseFirestore` (comfort-person field + dead invite arrays) | Favorites/relationships | `RelationshipRepository` |
| `regfav.dart` | `FirebaseAuth`, `FirebaseFirestore` | Comfort-person selection | `RelationshipRepository` (invitation create) |
| `vault.dart` | `FirebaseAuth`, `FirebaseFirestore` (dead voice-note metadata write), `FirebaseStorage` (dead voice-note upload) | Vault | `MediaRepository` |
| `vault_password.dart` | `FirebaseAuth`, `FirebaseFirestore` (vault password hash, last-viewed) | Vault unlock | No direct backend equivalent — see Step 15 |
| `edit_profile_page.dart` | `FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage` (profile image) | Edit profile | `ProfileRepository` (needs new backend endpoint), `MediaRepository` |
| `settings_page.dart` | `FirebaseAuth` (reset email, sign out), `FirebaseFirestore` (read `provider` field) | Settings | `AuthRepository` |

---

## STEP 7 — Authentication integration analysis

Current flow: Firebase Auth issues and silently refreshes its own ID token; the app never touches a token directly — it just checks `FirebaseAuth.instance.currentUser` on splash and lets the Firebase SDK persist the session between launches.

The new backend flow is explicit token management (`app/schemas/auth.py`, `app/api/routes/auth.py`):

```text
POST /auth/register or /auth/login → {access_token, refresh_token, expires_in}
Authorization: Bearer <access_token>   on every request
access token expires (15 min default) → POST /auth/refresh {refresh_token} → new pair
POST /auth/logout {refresh_token}      → revokes that refresh token server-side
```

1. **Access token storage:** in memory (a singleton/provider) for the running session, mirrored to secure storage so it survives a cold start without an extra network round trip. Do not put it in `shared_preferences` (plaintext).
2. **Refresh token storage:** secure storage only — it is long-lived (30 days by default: `refresh_token_expire_days`) and is the credential that matters most if leaked.
3. **Secure storage availability:** **not present today.** `pubspec.yaml` has no `flutter_secure_storage` (or equivalent) dependency; only `shared_preferences` (plaintext) exists, and it isn't even used anywhere yet (Step 3).
4. **New dependency required:** yes — `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences/Keystore on Android) should be added in Phase 7.
5. **Refresh flow:** an HTTP client interceptor should catch a 401 on any authenticated request, attempt exactly one `POST /auth/refresh` with the stored refresh token, retry the original request once on success, and otherwise fall through to step 6.
6. **On refresh failure:** treat it like the old app's session-expiry case — clear stored tokens and route back to `LoginPage`, the same terminal state `SplashScreen._checkUserStatus` already falls back to today when there's no current user.
7. **Startup session restore:** replace the one-shot `FirebaseAuth.currentUser` check in `SplashScreen.initState` with: read the stored access/refresh tokens → if present, call `GET /auth/me` → on success go to `HomePage` (or onboarding, depending on profile completeness, exactly as today) → on 401, try `/auth/refresh` once → on failure, `LoginPage`.
8. **UID → backend user ID:** every `email.split('@')[0]` "username" derivation used as a Firestore document ID today must be deleted. The backend's `UserRead.id` is a UUID assigned at registration and is what every resource (`journal.user_id`, `mood.user_id`, etc.) is actually keyed by server-side — the client never needs to compute an ID from the email again, and should stop doing so even locally, since nothing downstream expects that string anymore.

---

## STEP 8 — API client requirements

The project currently has: no `http` package usage, no Dio, no interceptors, no API service, no repository layer, no client-side error-handling abstraction, no JSON (de)serialization layer, and no environment configuration (`pubspec.yaml` has zero HTTP client dependency of any kind — all networking today is the Firebase SDKs' own transport).

**Recommendation:** add `dio` (interceptor support makes the Bearer-token/refresh flow in Step 7 far simpler than the raw `http` package) plus `flutter_secure_storage`. Given there is no existing structure to respect (Step 5), the layout the audit brief proposes is appropriate as-is and can be adopted directly:

```text
lib/
 ├── core/
 │   ├── network/
 │   │   ├── api_client.dart       # Dio instance, base URL, auth interceptor
 │   │   ├── api_endpoints.dart    # path constants matching app/api/routes/*.py
 │   │   └── api_exception.dart    # maps HTTPException detail/status → typed errors
 │   └── storage/
 │       └── secure_token_storage.dart
 ├── data/
 │   ├── models/         # one per backend schema (JournalRead, MoodRead, …)
 │   ├── repositories/   # one per resource, called by screens/state
 │   └── services/       # thin wrappers if a resource needs multi-endpoint orchestration
 └── features/           # existing screens, reorganized by feature as they're migrated
```

Existing screens can be migrated into `features/` incrementally (journal first, since it has the clearest 1:1 backend mapping) rather than all at once.

---

## STEP 9 — Environment configuration

**Today:** Firebase configuration is entirely native — `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`, loaded implicitly by `Firebase.initializeApp()` with no arguments in `main.dart`. There is no `firebase_options.dart` (i.e., the project predates or doesn't use the FlutterFire CLI), and **no API base URL configuration exists anywhere in the codebase** — there's nothing to migrate away from on that front, only something to add.

**Recommendation:**

```text
Development (Android emulator): http://10.0.2.2:8000
Development (physical device):  http://<machine's LAN IP>:8000   (same Wi-Fi network)
Development (iOS simulator):    http://127.0.0.1:8000
Production:                     https://<production-domain>      (value supplied at build/deploy time, never hardcoded)
```

Use `--dart-define=API_BASE_URL=...` (or a `.env`-style compile-time constant) rather than hardcoding, mirroring how the backend itself already treats every environment-specific value (`backend/app/core/config.py` — nothing hardcoded, everything from `.env`).

**Android emulator vs. physical device:** `10.0.2.2` is the Android emulator's alias for the host machine's `localhost` and works only inside the emulator; a physical device on the same Wi-Fi network needs the host machine's actual LAN IP instead, and the backend's `cors_origins`/dev server must be reachable on that interface (not bound to `127.0.0.1` only). iOS Simulator, unlike the Android emulator, can reach the host directly via `127.0.0.1` or `localhost`.

**One concrete manifest note:** `AndroidManifest.xml` declares no permissions related to networking explicitly, but Firebase's own transitive dependencies merge in `INTERNET` automatically, so HTTPS calls to a production API need no manifest change. A **plain-HTTP** local dev server, however, will be blocked by Android's default cleartext-traffic policy — `android:usesCleartextTraffic="true"` (or a network-security-config scoped to `10.0.2.2`/the dev LAN IP) will need to be added for local testing against the FastAPI dev server, which is not currently configured for TLS.

---

## STEP 10 — Data model mapping

### User / Profile

| Flutter model | Current fields (Firestore `users/{username}`) | FastAPI model | Field differences | Required transformation |
|---|---|---|---|---|
| *(no Dart class — raw `Map` from Firestore)* | `uid`, `email`, `name`, `provider`, `comfortPerson{relation,name,customRelation}`, `ageGroup`, `phone`, `city`, `country`, `profileImage`, `vaultPasswordHash`, `vaultLastViewed`, `vaultPrevLastViewed`, `pendingInvitesReceived[]`, `pendingInvitesSent[]`, `myComfortCircle[]`, `inTheirCircle[]` | `UserRead` (`id: UUID, email, is_active, is_verified, created_at, last_login_at`) + `ProfileRead` (`full_name, age_group, phone, city, country, profile_image_url, onboarding_completed_at`) | `provider` (OAuth) has no backend field — see Step 4 Google sign-in gap. `comfortPerson` and the four invite arrays are superseded by `Relationship`/`RelationshipInvitation`. `vaultPasswordHash`/`vaultLastViewed` have no backend home at all (Step 15). `ageGroup` free string → backend `AgeGroup` enum with 5 fixed values that are already string-identical to `enter_details_page.dart`'s `_ageGroups` list. | Drop `provider`, the invite arrays, and `comfortPerson` client-side entirely; **backend needs a new `PATCH /me/profile` (or similar) endpoint** — none of Phase 1–5's routes let a client update `full_name`/`age_group`/`phone`/`city`/`country`/`profile_image_url` after registration, which both `enter_details_page.dart` and `edit_profile_page.dart` need to keep working |

### Journal

| Flutter (Firestore doc, keyed by date) | FastAPI `JournalRead` | Differences | Transformation |
|---|---|---|---|
| `title, description, date, streak` | `id (UUID), user_id, entry_date, title, content, created_at, updated_at` | `description`→`content`; date is now a real field (`entry_date`) not the doc key, and the resource has a real `id`; **`streak` does not exist server-side** | Client must locally compute streak from `GET /journals?start_date=&end_date=` (e.g., walk backward from today) or the team must decide the backend should own it |

### Mood

| Flutter (nested/buggy map shape) | FastAPI `MoodRead` | Differences | Transformation |
|---|---|---|---|
| `{items: {dateKey: percent}}` per doc | `id, user_id, entry_date, mood_value (0-100), created_at, updated_at` | Backend shape is flat and one-row-per-date — strictly simpler | No transformation logic needed beyond switching the read/write calls; this is a net simplification |

### Checklist

| Flutter | FastAPI | Differences | Transformation |
|---|---|---|---|
| `items: [bool,bool,bool,bool,bool]` (positional, labels hardcoded client-side) | `GET /checklists/items` → `[{id, label, sort_order}]` (catalog); `GET/PATCH /checklists/{date}` → `{entry_date, items:[{item_id,label,sort_order,completed,completed_at}], completed_count, total_count}` | Backend gives each item a stable UUID (`item_id`) instead of a positional index; labels come from the server instead of being hardcoded | Confirmed the 5 hardcoded labels in `homepage.dart` match the Alembic seed data exactly, in the same order — map by fetching the catalog once and matching on `sort_order` rather than re-hardcoding label strings |

### Shoutout

| Flutter | FastAPI | Differences | Transformation |
|---|---|---|---|
| `{title, description, timestamp}` (+ an unused `feelBetter` field read but never written) | `id, user_id, entry_date, title, content, felt_better, felt_better_at, created_at, updated_at` | `description`→`content`; `felt_better` is now a real, persisted field with its own endpoint | This is where the backend fixes the confirmed existing bug — client work here is a genuine new feature, not a like-for-like port |

### Media

| Flutter (`VoiceNote`/`ImageNote`/`VideoNote`, Hive) | FastAPI `MediaAssetRead`/`MediaAssetDetail` | Differences | Transformation |
|---|---|---|---|
| `id (client uuid), title, url/path/localPath, date, duration` | `id (UUID), user_id, media_type, original_filename, content_type, file_size, duration_seconds, created_at` + (`detail`) `download_url, download_url_expires_in_seconds` | Server derives `media_type`/`content_type` from the uploaded bytes (never trusts a client-declared type); `file_size` is new; download URLs are presigned and **expire**, unlike a local file path | Local `path`/`localPath`/`url` fields go away entirely; the client needs a small in-memory/disk cache keyed by `media_id` so it isn't re-fetching a presigned URL on every rebuild, and needs to handle a stale/expired `download_url` by re-calling `GET /media/{id}` |

### Relationship

| Flutter (`comfortPerson` field + dead invite arrays) | FastAPI `RelationshipRead`/`InvitationRead`/`PermissionRead` | Differences | Transformation |
|---|---|---|---|
| Singular `{relation, name, customRelation}` on the user doc; a broken `mindmate://` deep link | `Relationship{id, owner_user_id, comfort_user_id, relationship_type, custom_relationship_label, status, my_role, counterparty_display_name, accepted_at, revoked_at}` + separate `Invitation`/`Permission` resources; `relationship_type` enum is `mom/dad/siblings/best_friend/love/grandparents/other` | Backend supports **multiple** relationships in either direction (`role=owner` vs `role=comfort_person`); current UI hardcodes an assumption of exactly one. Labels differ in casing/pluralization from the UI's `_options` list (`'Siblings'` vs `siblings`, `'Others'` vs `other`) and need an explicit mapping table, not a naive `.toLowerCase()` | Product decision needed on whether to keep the "one comfort person" UX or expose the new one-to-many capability; either way, an explicit label↔enum mapping table must be written (not derived by string transformation) |

### Stress

| Flutter | FastAPI `StressResult`/`ComfortStressView` | Differences | Transformation |
|---|---|---|---|
| Not implemented (TODO stub) | `score, level, confidence, calculated_at, data_window_start/end, contributors{mood_average, checklist_completion_rate}, disclaimer` (owner view); narrower `ComfortStressView` with no `contributors` for comfort-person callers | N/A — pure greenfield | New screen(s) entirely |

### Weekly Reflection

| Flutter | FastAPI `WeeklyReflectionRead` | Differences | Transformation |
|---|---|---|---|
| Not implemented | `id, user_id, week_start, week_end, status, reflection{summary, mood_insight, habit_insight, positive_highlights[], areas_to_reflect_on[], encouragement}, insufficient_data_reason, ai_provider, ai_model, generated_at` | N/A — pure greenfield | New screen(s) entirely |

---

## STEP 11 — Firebase-specific assumptions and what must change

| Assumption in the current app | Where | What must change |
|---|---|---|
| User identity = `email.split('@')[0]`, used as the Firestore document ID | 10+ files (see Step 2/6) | Replace with the backend's UUID `user.id`, obtained from `/auth/me` or the token payload after login — never derived from the email client-side again |
| A second, incompatible identity scheme (`user.uid`) for the dead invite-array code | `favorite_page.dart` | Delete this code path outright; it's superseded by `/relationships/*` and was never wired to a working invite-creation flow anyway |
| Firestore document existence as an "is this a duplicate account" check (`_userExists`) | `main.dart`, `register_page.dart` | Backend already returns 409 Conflict on duplicate registration and a generic 401 on bad login — no pre-check call needed, which also removes a user-enumeration side channel the old app had |
| `FieldValue.serverTimestamp()` for `created_at`-style fields | `journal_page.dart` (shoutout timestamp — dead path), `vault_password.dart` | Backend sets `created_at`/`updated_at` itself; the client should treat these as read-only, not something it stamps | 
| Firestore's default offline persistence/cache (implicit — never explicitly configured, but present by default in the `cloud_firestore` plugin) | app-wide | A REST client has no automatic offline cache; see Step 13 for what the app actually depends on today vs. what needs deliberate design |
| `FirebaseAuthException`/generic Firestore exceptions caught ad hoc per screen (`catch (e)`, string-interpolated into a snackbar) | most screens | Replace with the typed `ApiException` from Step 8, mapped from HTTP status + the backend's `detail` message, so error UX is consistent instead of per-screen bespoke `catch` blocks |
| Firebase Storage `getDownloadURL()` — a stable, non-expiring public URL | `enter_details_page.dart`, `edit_profile_page.dart` (profile pictures); dead `vault.dart` path | Backend media URLs are **presigned and time-limited** (`download_url_expires_in_seconds`) — any cached/stored URL must be treated as disposable and re-fetched via `GET /media/{id}`, not persisted long-term |
| A custom URI scheme (`mindmate://invite?...`) registered in `AndroidManifest.xml` but never read by any Dart code (`uni_links` is an unused dependency) | `regfav.dart` + manifest | Either wire up `uni_links`/`app_links` properly against the new token-based `POST /relationships/invitations/{token}/accept` flow, or drop the manifest intent filter if invites will be share-text/copy-paste only |

---

## STEP 12 — Real-time behavior analysis

No `snapshots()` / `StreamBuilder` / Firestore listener exists anywhere in `lib/` — every single Firestore read in the app today is a one-shot `.get()`. The only "live" UI in the app is Hive's `ValueListenableBuilder` over local boxes (Vault lists), which is a local-storage reactivity mechanism, not a network one.

| Candidate real-time feature | Currently real-time? | REST polling sufficient? |
|---|---|---|
| Journal/mood/checklist updates | No (one-shot reads) | Yes — nothing today expects live updates from another device/session |
| Relationship status (pending invite → accepted) | No (the working invite flow doesn't check status at all; the dead code polled via a manual "Pending Invites" dialog button, not a listener) | Yes — a pull-to-refresh or manual "check invites" action is consistent with existing UX |
| Stress data (comfort-person view) | Not implemented at all today | Yes for a v1 — "View today's stress level" was always a manual tap, never a push |
| Vault list | Local-only (`ValueListenableBuilder`), not networked | N/A today; once media syncs to the backend, a manual refresh on screen entry is sufficient |

**Conclusion:** nothing in the current app's behavior requires WebSocket/SSE. REST + pull-to-refresh (and, if desired later, simple polling on the relationship/invite screens) fully covers what the app does today. This should be revisited only if a future feature (e.g., live stress alerts to a comfort person) is added — not something Phase 6/7 needs to build.

---

## STEP 13 — Offline behavior

| Feature | What works offline today | Why |
|---|---|---|
| Journal | Nothing — every read/write is a direct Firestore call with no local cache layer built by the app (the `cloud_firestore` plugin's own default disk cache may serve stale reads, but the app never relies on or tests for this deliberately) | No repository/cache layer exists |
| Mood | Same as Journal | Same |
| Checklist | Same as Journal, except the day's checklist state also lives transiently in `State.checklist` until the screen is disposed | Same |
| Vault | **Fully offline-capable today** — it's Hive + local files, with no network dependency at all in the reachable code paths | This is incidental (the feature was simply never wired to the cloud), not a deliberate offline-first design |
| Shoutouts | Nothing — same as Journal | Same |
| Scheduler | Fully offline (Hive-only, no backend concept exists) | Local-only feature by design |

**Recommendation:** given the app has no deliberate offline design today (Vault's "offline capability" is a side effect of never being networked, not an intentional feature), Phase 7 should target **online-first** for Journal/Mood/Checklist/Shoutout — a simple loading/error/retry UX per screen, matching the app's current one-shot-call behavior, just against REST instead of Firestore. Building true offline-first + sync (local queue, conflict resolution) for a mental-health journaling app is a substantial, separate effort that shouldn't be bundled into the initial cutover; it can be considered later specifically for Vault (where users may reasonably expect to record a voice note with no signal) once the base integration is stable. This is a recommendation for a later phase, not something to implement now.

---

## STEP 14 — Weekly Reflection integration

No weekly-reflection screen, card, empty/loading/error state, or any AI-related UI exists anywhere in `lib/` (confirmed — `grep` for "reflection", "weekly", "AI" across `lib/` turns up nothing beyond this audit's own analysis). There is nothing to reuse.

Mapping for when this screen is built:

```text
POST /reflections/weekly/generate   → user-initiated "see my weekly reflection" action (or auto-triggered on screen entry if none exists yet for the current week)
GET  /reflections/weekly            → default screen load: show the latest reflection if one exists
GET  /reflections/weekly/{week_start} → a "past weeks" browsing UI, if desired
```

Because `POST .../generate` is idempotent by default (returns the cached completed reflection unless `force_regenerate: true`), the simplest correct UI is: on screen entry, call `GET /reflections/weekly`; on 404, show an empty state with a "Generate my reflection" button that calls `POST .../generate`; handle the `insufficient_data` `status` value as its own empty state (distinct from "not generated yet"); handle a 502 from the generate call as a retryable error, per the backend's own documented behavior.

---

## STEP 15 — Media/Vault integration

Current flow (all of it local, confirmed in Step 2/3/6):

```text
Select/record media (image_picker / file_picker / record)
     ↓
Store locally (Hive box: image_notes / video_notes / voice_notes)
     ↓
Display (ValueListenableBuilder reading the Hive box directly)
```

Target flow per the backend README:

```text
Select/record media
     ↓
POST /media/upload  (multipart: file + optional duration_seconds)
     ↓
FastAPI → S3/MinIO (bytes) + PostgreSQL (metadata row)
     ↓
GET /media/{id} → presigned, time-limited download_url
```

**Required Flutter changes:**
- Add multipart upload support to the new API client (Dio supports this natively via `FormData`).
- Replace `Hive.box<VoiceNote/ImageNote/VideoNote>('...')` reads with a fetched `GET /media` list (paginated, filterable by `media_type`), cached locally for the current session rather than treated as the source of truth.
- Replace direct `File(note.path)`/`Image.file(...)` rendering with `Image.network`/`VideoPlayerController.network` against the presigned `download_url` from `GET /media/{id}`, with a fallback re-fetch when a cached URL has expired (`download_url_expires_in_seconds`).
- Rename/delete flows (`note.save()`/`note.delete()` on the Hive object today) become `PATCH`-equivalent (**note: Phase 1–5 has no rename/metadata-update endpoint for media — only upload, list, get, delete** — this is a backend gap if "rename" is to be kept) and `DELETE /media/{id}`.
- The recording flow itself (`record` package) is unaffected — only what happens to the resulting file after `_recorder.stop()` changes, from "add to Hive" to "upload, then optionally cache locally."
- The **vault password / biometric lock** (`vault_password.dart`) is a separate concern from media storage — see Step 17; it gates access to the Vault *screen*, not the media itself, and has no natural home in the Phase 1–5 API surface today.

---

## STEP 16 — Relationship and stress integration

**Currently implemented (working):** selecting a comfort-person type/name and generating an (unread, unverified) deep link (`regfav.dart`); displaying that single selection back on the Favorites screen (`favorite_page.dart::_fetchComfortPerson`).

**Dead UI / non-functional:** the entire "Pending Invites" dialog and accept/decline flow in `favorite_page.dart` — it reads/writes Firestore array fields (`pendingInvitesReceived`, etc.) that are never populated by any other code path in the app, because the only invite-creation code (`regfav.dart`) never writes to those fields; it only builds an unread deep link. The "View today's stress level" button is a literal `// TODO`.

**Uses Firebase UID:** only the dead pending-invites code (`favorite_page.dart`), inconsistent with the rest of the app's `email`-derived "username" scheme.

**Uses invite links:** `regfav.dart` builds a `mindmate://invite?from={uid}&name=&relation=` link; the scheme is registered in `AndroidManifest.xml` (`VIEW`/`BROWSABLE` intent filter) so the OS will hand the link to the app, but no Dart code (`uni_links` is unused) ever parses it — so accepting an invite via this link is currently impossible even though the app *looks* like it supports it.

**Local-only:** nothing in this feature area is local-only — it's either a Firestore field (`comfortPerson`) or entirely absent (consent, stress).

**What backend APIs replace it:** `POST /relationships/invitations` (create + one-time token), `GET /relationships/invitations/{token}` (preview), `POST /relationships/invitations/{token}/accept|decline`, `GET /relationships` (list, both roles), `POST /relationships/{id}/revoke`, `GET/POST /relationships/{id}/permissions/{type}/grant|revoke` (consent), `GET /relationships/{id}/stress/today` (comfort-person stress view), `GET /stress/today`/`GET /stress/history` (owner's own view).

**What still needs to be built (product + engineering, not just wiring):**
- A real invite-sharing UI (the app already has `share_plus` — reuse it for the new token-based invite instead of the old unverified deep link).
- An "accept invite" screen that a recipient reaches by pasting/opening a shared token — since the deep link was never functional, this can be designed fresh rather than repaired.
- A **consent** UI, which does not exist in any form today — the owner must be able to see and grant/revoke the `stress_level` permission per relationship; this is the audit's most important privacy-relevant callout, since the backend enforces "minimum necessary" consent (per its own docstrings) but the Flutter app currently has zero UI concept of consent to surface that control to the user.
- A real stress screen for both the owner's own view and the comfort-person's narrower view (`ComfortStressView` deliberately omits `contributors` — the UI should not attempt to show a breakdown to a comfort person, matching the backend's intentional data-minimization).

---

## STEP 17 — Dead code and cleanup candidates

### Definitely removable later (confirmed unreachable or superseded)
- `favorite_page.dart::_showPendingInvitesDialog`/`_acceptInvite`/`_declineInvite` and the underlying `pendingInvitesReceived`/`pendingInvitesSent`/`myComfortCircle`/`inTheirCircle` Firestore fields — orphaned, `uid`-keyed, never populated by any working code path.
- `journal_page.dart`'s private `_saveShoutout`/`selectedIssue`/`problem`/`problemController` fields — unreachable; the UI's actual "Add/Edit" shoutout button navigates to the named `/shoutout` route (`ShoutoutPage`), not this method.
- `vault.dart::_startRecording`/`_stopRecordingAndSave` (the Firebase-Storage-uploading voice-note path) — not called anywhere in the widget tree; `_startFloatingRecording`/`_stopFloatingRecordingAndSave` is what's actually wired to the UI.
- The `mindmate://` intent filter in `AndroidManifest.xml`, if the team chooses a share-text-only invite flow instead of a deep link.
- `uni_links` in `pubspec.yaml` — declared but never imported/used anywhere.

### Possibly reusable
- `custom_snackbar.dart` — generic UI utility, independent of Firebase.
- `share_plus`-based sharing in `regfav.dart` — the mechanism (not the payload) is reusable for the new invite-token flow.
- `local_auth` biometric-unlock code in `vault_password.dart` — the biometric gate itself is independent of what backs the vault password (Firestore today; TBD later, see Step 15).
- Hive `ImageNote`/`VideoNote`/`VoiceNote` models — reusable as a **local cache** layer once media is backend-backed, rather than as the source of truth.
- All relationship-type onboarding screens (`mom_page.dart` etc.) — pure presentational screens with no Firebase calls; reusable as-is, just need their "Next" action wired to the new invitation-creation call instead of `regfav.dart`'s direct Firestore write.

### Must remain
- Every screen's overall visual design/layout — out of scope for this audit and not something Phase 6/7 should touch (explicit instruction: no UI redesign).
- The five checklist item labels/order (confirmed identical to backend seed data — do not change).

### Needs redesign
- The entire relationship/invite UX, since the backend now supports multiple relationships in both directions where the app currently hardcodes "exactly one comfort person."
- The Notification Settings screen, which persists nothing today (no `SharedPreferences`, no backend field) — before wiring it to anything, decide whether it should persist locally, sync to a backend `Profile`-style field (which doesn't exist yet either), or be deferred, since push notifications are explicitly out of scope per the backend README ("Not yet in scope").
- The Vault "last viewed" / vault-password concept, which has no natural backend home in Phase 1–5 (see Step 15) and needs a product decision before it can be ported.

---

## STEP 18 — Dependency audit (`pubspec.yaml`)

| Dependency | Current purpose | Firebase-related? | Still needed? | Action later |
|---|---|---|---|---|
| `firebase_core` | Firebase SDK bootstrap | ✅ | Until cutover complete | Remove after full migration |
| `firebase_auth` | Auth (email/password, Google) | ✅ | Until cutover complete | Remove after full migration |
| `google_sign_in` | Google OAuth for Firebase Auth | Indirectly | Only if the backend gains an OAuth endpoint (currently a gap — Step 4) | Keep pending backend decision, else remove |
| `cloud_firestore` | All Firestore reads/writes | ✅ | Until cutover complete | Remove after full migration |
| `firebase_storage` | Profile-image upload (+ dead voice-note path) | ✅ | Until cutover complete | Remove after full migration |
| `image_picker` | Profile picture, Vault image import | No | Yes | Keep |
| `cupertino_icons` | Icon set | No | Yes | Keep |
| `intl` | Date formatting | No | Yes | Keep |
| `crypto` | SHA-256 hash of the vault password | No | Depends on where the vault password ends up living (Step 15/17) | Revisit |
| `local_auth` | Vault biometric unlock | No | Yes | Keep |
| `record` / `record_linux` | Voice-note recording | No | Yes | Keep |
| `audioplayers` | Voice-note playback | No | Yes | Keep |
| `path_provider` | Local file paths for recordings | No | Yes | Keep |
| `uuid` | Client-side ID generation (Vault notes) | No | Reduced need once the backend assigns IDs, but still useful for optimistic local state | Keep |
| `file_picker` | Vault image/video/audio import | No | Yes | Keep |
| `hive` / `hive_flutter` | Vault local storage, scheduler | No | Yes — repurpose as a cache layer once media is backend-backed (Step 17) | Keep, repurpose |
| `permission_handler` | Mic permission for recording | No | Yes | Keep |
| `video_player` / `video_thumbnail` | Vault video playback/thumbnails | No | Yes | Keep |
| `shared_preferences` | Declared, **unused anywhere in `lib/`** | No | Only once secure-token or simple-preference storage is actually implemented — and secure token storage should use `flutter_secure_storage`, not this | Either start using it deliberately (non-sensitive prefs only) or drop it |
| `cached_network_image` | Profile image caching | No | Yes — will also help with presigned media URLs | Keep |
| `uni_links` | Declared, **never imported/used anywhere** | No | No | Remove now (or replace with `app_links` if the deep-link invite flow is revived — Step 16) |
| `share_plus` | Sharing the invite link | No | Yes | Keep |
| **Not yet present:** `dio` (or similar) | — | No | **New — required for Step 8** | Add |
| **Not yet present:** `flutter_secure_storage` | — | No | **New — required for Step 7** | Add |

No `pubspec.yaml` changes were made in this phase — the table above is guidance for Phase 7.

---

## STEP 19 — Migration strategy

### Strategy A — Fresh backend (new users start on FastAPI/PostgreSQL; existing Firebase data is not imported)
- **Complexity:** low. This is a clean cutover — build the new API layer, point the app at it, ship.
- **Risk:** any existing users lose their journal/mood/checklist/shoutout history and profile details on upgrade (they'd effectively start over). Given the audit found the Vault feature has **never actually synced to any cloud backend** (Step 2/3), Strategy A loses *nothing* for Vault specifically — there's no cloud Vault data to lose in the first place, only whatever is already on each device's local Hive boxes, which this migration doesn't touch either way.
- **Best fit if:** the current user base is small/pre-launch, or the team is comfortable asking existing users to re-onboard.

### Strategy B — One-time migration (import existing Firestore data into PostgreSQL)
- **Complexity:** meaningfully higher, for reasons specific to what this audit found, not just "migrations are generally hard":
  - The mood data's Firestore shape is inconsistent between its two write paths (`saveMoods()` vs `saveMoodForDate()`) and would need cleaning/de-duplication before it maps cleanly to the backend's one-row-per-date `Mood` table.
  - The `comfortPerson` field (singular) needs to become a `Relationship` + a retroactively-"accepted" `RelationshipInvitation` — but the old data was never verified (no acceptance step existed), so a migrated relationship would have no genuine consent trail behind it, which sits awkwardly next to the backend's explicit-consent model (Phase 4's stated design goal).
  - The `journal.streak` field has no backend column at all (Step 10) — either the migration silently drops it (and the client recomputes it going forward) or the backend needs a schema addition just to carry over a legacy value.
  - Auth accounts themselves (Firebase Auth users, including Google-sign-in users) can't be migrated 1:1 into the backend's email+password model without either forcing a password reset for every user or building a Google-OAuth backend flow first (a confirmed current gap — Step 4).
  - Vault media (images/videos/most voice notes) has **no cloud copy to migrate from** — a "migration" for Vault would actually mean a brand-new on-device-to-cloud upload pass initiated from each user's device, not a server-side data migration at all.
- **Risk:** partial/lossy migration is likely given the shape mismatches above; a bad migration is harder to recover from than a clean cutover.
- **Best fit if:** there's a real, active user base whose journal/mood/checklist history has retention value worth this engineering cost.

**This audit does not recommend one strategy over the other** — that's a product decision — but flags that Strategy B's cost here is higher than a generic "export/import" migration would suggest, specifically because of the Firestore data-shape inconsistencies and dead-code paths this audit found, and that Vault media migration (if desired) is really a device-side upload campaign, not a server-side import job, regardless of which strategy is chosen for the rest of the data.

---

## STEP 20 — Recommended final Flutter architecture

```text
                 ┌──────────────────────────┐
                 │        Flutter UI        │   (existing screens, unchanged visually)
                 └────────────┬──────────────┘
                              │
                 ┌────────────▼──────────────┐
                 │   State layer (NEW)        │   ChangeNotifier/Provider per feature —
                 │                            │   replaces ad hoc setState + inline Firebase calls
                 └────────────┬──────────────┘
                              │
                 ┌────────────▼──────────────┐
                 │   Repositories (NEW)       │   JournalRepository, MoodRepository,
                 │                            │   ChecklistRepository, ShoutoutRepository,
                 │                            │   MediaRepository, RelationshipRepository,
                 │                            │   StressRepository, ReflectionRepository,
                 │                            │   AuthRepository
                 └────────────┬──────────────┘
                              │
                 ┌────────────▼──────────────┐
                 │   API Client (NEW)         │   Dio + Bearer-token interceptor +
                 │                            │   refresh-on-401 + typed ApiException
                 └────────────┬──────────────┘
                              │
                 ┌────────────▼──────────────┐
                 │        FastAPI             │
                 └────────────┬──────────────┘
                              │
                 ┌────────────▼──────────────┐
                 │  PostgreSQL + S3/MinIO      │
                 └────────────────────────────┘

         (parallel, local-only concern — not part of the request path above)
                 ┌────────────────────────────┐
                 │  Local cache / offline      │   Hive, repurposed: cached media,
                 │  convenience layer          │   session-scoped list caches — never
                 │                              │   the source of truth once online
                 └────────────────────────────┘
```

**Why this fits:** the current app has no architecture to preserve (Step 5), so there's no migration cost in adopting the textbook layering. The one addition beyond the audit brief's suggested diagram is the explicit **state layer** between UI and repositories — without it, the natural failure mode is that screens keep doing exactly what they do today (own their data-fetching logic directly), just calling a `Repository` instead of `FirebaseFirestore`, which reproduces the same tight coupling one layer down. Secure token storage and the Dio interceptor (Step 7/8) are the two genuinely new pieces of infrastructure; everything else — Hive, `image_picker`, `record`, `local_auth`, `share_plus` — is already in the project and is repurposed rather than replaced.

**Explicit non-goals of this architecture, per the audit's scope:** it does not address the backend gaps found in Step 4/10 (no Google OAuth endpoint, no password-reset endpoint, no profile-update endpoint, no media-rename endpoint, no vault-password concept) — those are product/backend decisions for a future phase, listed here so they aren't rediscovered mid-implementation.

---

## Appendix — Backend gaps surfaced by this audit (not a request to build them now)

These are things the *current* Flutter app does that Phase 1–5 of the backend has no endpoint for. Listed so Phase 7 planning isn't surprised by them:

1. **Google / social sign-in** — `google_sign_in` is used today; no OAuth endpoint exists in `app/api/routes/auth.py`.
2. **Password reset ("forgot password")** — `sendPasswordResetEmail` is used today (both on the login screen and in Settings' "Change password"); no equivalent endpoint exists.
3. **Profile update after registration** — `enter_details_page.dart` and `edit_profile_page.dart` both need to write `full_name`/`age_group`/`phone`/`city`/`country`/`profile_image_url` after account creation; `ProfileRead` is present in `MeResponse` but no `PATCH`/`PUT` route for it exists yet.
4. **Media rename** — Vault's "Rename" context-menu action (`note.title = ...; note.save()`) has no backend equivalent; only upload/list/get/delete exist for media.
5. **A "vault password" / secondary local lock concept** — `vaultPasswordHash`/`vaultLastViewed` have no natural home in any Phase 1–5 resource; this is a client-side/device-security feature the backend was never designed to store.
6. **A "scheduler" feature** — a Hive-only, per-day time/description list on the home screen with no backend model in any phase.

None of these block Phase 7 from starting — Journal, Mood, Checklist, Shoutout, Media, Relationships, Stress, and Weekly Reflection all have working, real backend coverage today and are where integration work should begin.
