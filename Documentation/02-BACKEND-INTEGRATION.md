# Backend integration boundary

The frontend talks only to the protocols in `PASS/Data/Protocols/Repositories.swift`. The backend phase (Supabase or
Firebase) adds real implementations and swaps them in `AppDependencies.live()`. Nothing in `Features/` changes.

## Contracts to implement

| Protocol | Mock | Real implementation does |
|---|---|---|
| `AuthService` | `MockAuthService` | Sign in with Apple: send `AppleCredential.identityToken` (+ nonce) to the backend, store the session token in **Keychain**, restore it on launch, revoke the Apple token on `deleteAccount()` |
| `UserRepository` | `MockUserRepository` | profile row (display name, DOB kept server-side only for the 16+ check, avatar upload to a private bucket), notification preferences, block list, reports |
| `GroupRepository` | `MockGroupRepository` | groups, create (server generates the `PASS-XXXX` code), invite preview by code, join (enforce max 7, blocked creators), leave/remove (cancel active relay + delete its media, spec §17) |
| `RelayRepository` | `MockRelayRepository` | active relays, relay by id, history, challenges table, `start_relay`, `submit` (upload media first, then record), `pass_baton`. All rule enforcement server-side, mirroring `RelayEngine` |
| `DataChangeSource` | `MockDataChangeSource` | Supabase Realtime / Firestore listeners → `DataChange` events |
| `NotificationService` | `LocalNotificationService` | keep for permission; APNs token registration goes through `UserRepository.registerDeviceToken` (`register_device_token`) |
| `RevealManifestProvider` | `MockRevealManifestProvider` | Edge Function `reveal-manifest` → signed URLs → files cached in `LocalMediaStore` under their storage path, then the same `RevealManifest` the mock builds |
| `MediaStore` | `LocalMediaStore` | keep: local cache for captures, downloads and Reveal exports |
| `SessionStore` | `UserDefaultsSessionStore` | move the token to Keychain; keep the pending invite code + prompt flags in UserDefaults |

## Server responsibilities the client assumes
- **Clock**: deadlines are absolute timestamps from the server. Add a `server_now()` call on launch/foreground and feed the offset to `AdjustableDateProvider` (today it is the device clock).
- **Deadline processing**: a scheduled job applies `RelayEngine.processDeadlines` semantics (first miss → deferred, rescue 15 min, second miss → excluded, finish/fail). The client only polls on foreground and reacts to change events.
- **Hidden media**: submissions live in a private bucket; signed URLs are issued only after the relay has a Reveal (spec §14). `RevealManifest` is the shape the client wants back.
- **Notifications** (spec §15): `baton_received`, `reminder`, `near_expiration`, `rescue`, `one_person_left`, `relay_complete`, each with `{"relayId": "<id>"}` in the payload. `AppRouter.handle(notificationUserInfo:)` already routes that key.
- **Invite links**: `https://<domain>/i/<CODE>` + `apple-app-site-association`; the client parses both the universal link and `pass://i/<CODE>` (`DeepLink.parse`). Add the Associated Domains entitlement when the domain exists.
- **Validation**: enforce `Documentation/VALIDATION.md` server-side; the client's checks are UX only.

## Configuration (done)
`Config/Dev.xcconfig`, `Staging.xcconfig`, `Release.xcconfig` define `PASS_SUPABASE_URL` / `PASS_SUPABASE_ANON_KEY` (empty =
mock) and `#include? "Secrets.xcconfig"` (gitignored; copy `Secrets.example.xcconfig`). `Config/Info.plist` exposes both as
`$(PASS_SUPABASE_URL)` / `$(PASS_SUPABASE_ANON_KEY)`, read by `AppConfiguration.Backend.fromInfoPlist()`. The xcconfigs are
not yet attached to the build configurations in the pbxproj (see below). `INVITE_LINK_BASE` still lives in `AppConfiguration`
until the domain exists. Separate bundle IDs for dev/staging if several builds must coexist on one phone. Push requires the
`aps-environment` entitlement and the Push capability on the App ID.

## Mapping notes
- IDs are strings (`ID<Tag>`); UUIDs from Postgres/Firestore map directly.
- `Relay.turns` is the audit trail of Baton holdings; the server can return only the open turn plus the participant states if it prefers, and the client derives the rest (`currentTurn`, `holder`, `orderedForProgress`).
- `MediaType`, `ParticipantState`, `RelayStatus`, `RelayOutcome` are string enums; reuse the raw values as DB enums.

## How to switch to Supabase

The adapters live in `PASS/Data/Supabase/` and implement every protocol with the official `supabase-swift` package
(`https://github.com/supabase/supabase-swift`, `from: 2.0.0`, product `Supabase`, linked to the PASS target).
`AppDependencies.live()` switches on `AppConfiguration.backend`: `.mock` (default, what every test runs against) or
`.supabase(url:anonKey:)`.

1. **Credentials.** Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored) and fill in the project
   URL and anon key from the Supabase dashboard. `//` starts a comment in xcconfig, so write the URL as
   `https:/$()/<ref>.supabase.co` or without a scheme (the app prepends `https://`).
2. **Attach the xcconfigs** once in Xcode: project → Info → Configurations → Debug = `Dev`, Release = `Release` (add a
   `Staging` configuration pointing at `Staging.xcconfig` when a staging project exists). Until that is done the Info.plist
   placeholders expand to empty strings and the app stays on the mock. Keep Debug on `Dev.xcconfig`.
3. **Resolve the package** (File → Packages → Resolve) and build. The first build downloads `supabase-swift` (~50 MB of
   checkouts; the Mac's disk is tight, delete `DerivedData/PASS-*/Logs/Test` after test runs).
4. **Run.** With both keys non-empty `AppDependencies.supabase(...)` builds:
   `SupabaseAuthService` (Sign in with Apple via `auth.signInWithIdToken` with the raw nonce from `SplashView`; `signInDemo`
   uses `demo+<device>@pass.test` email/password, DEBUG only), `SupabaseUserRepository`, `SupabaseGroupRepository`,
   `SupabaseRelayRepository` (`create_upload_slot` → Storage upload to `media` → `submit`), `SupabaseRevealManifestProvider`,
   `SupabaseChangeSource` (Realtime V2 `postgres_changes` on `relays`, `relay_participants`, `baton_turns`, `groups`,
   `group_members`), and `ServerClock` (`server_now` on launch/foreground → `AdjustableDateProvider.setOffset`).
   `AppDependencies.mockStore` is `nil`, so the DEBUG demo controls disappear.
5. **Push.** On a real backend `AppDependencies.bootstrap()` calls `registerForRemoteNotifications()`; `AppDelegate` hands the
   hex token to `UserRepository.registerDeviceToken(_:environment:)` (`register_device_token`, `development` in DEBUG,
   `production` otherwise) once the session is `.signedIn`, i.e. once a `profiles` row exists for the FK.

### Error mapping
`SupabaseErrorMapping` turns SDK errors into `AppError`: PostgREST `P0001` → the contract code in `message` (+ the user-safe
`details`) → `.unauthorized/.notFound/.conflict/.permissionDenied/.validation`; `PGRST301/302/303` and HTTP 401 → `.unauthorized`;
`42501` → `.permissionDenied`; `URLError` → `.network`; `AuthError.sessionMissing` → `.unauthorized`; `StorageError` → `.media`.
Edge Functions return the same `{ code, message }` body. Covered by `PASSTests/SupabaseErrorMappingTests.swift`.

### Media and caching
- Captures are uploaded from `CapturedMedia.fileURL` (`image/jpeg` or `video/quicktime`) to the slot's `storagePath`
  (`relays/<relayId>/<userId>.jpg|mov`) and then copied into `LocalMediaStore` under that same path, so the author's own
  History thumbnail renders without a download. A `409` on upload (retry after a failed `submit`) is treated as success.
- Reveal: `reveal-manifest` returns signed URLs; each file is downloaded into `LocalMediaStore` under the submission's
  storage path (the manifest `fileName` points there), so `RevealExporter` and playback are unchanged.
- The avatar is uploaded to the `avatars` bucket as `<userId>.jpg` and mirrored locally under that name; `get_me` downloads it
  when missing (fresh install).

### Contract mismatches found while wiring
- **`reports.reason`**: the DB enum is `harassment | nudity | violence | spam | other`, while the contract says enums use the
  Swift raw values (the UI strings). The client sends the short keys (`ReportReason.serverKey`). Pick one in the contract.
- **`RevealManifest` wire shape** uses `relayId` + `url`, the Swift struct uses `relayID` + `fileName`; the provider maps it
  (`SupabaseRevealManifestProvider.Wire`). Items carry no `storagePath`, so the local cache name comes from the relay's
  submissions (fallback `relays/<relayId>/<position>.<ext>`).
- **`server_now()`** is documented as `"...Z"`; a plain `timestamp` would arrive without a zone. `RFC3339.date(from:)` assumes
  UTC when no zone is present and tolerates Postgres' six fractional digits.
- **`complete_onboarding`** takes `p_color_hex`; the contract does not say who picks the colour. The client sends the
  placeholder's colour (`SupabaseUserRepository.defaultColorHex`, a deterministic pick from `PassColor.memberPaletteHex`).
- **`get_me` → `null`** before onboarding: `SupabaseAuthService` caches a placeholder `User` (Apple full name if given) so
  `AppSession`/Onboarding behave as with the mock.
- `User.dateOfBirth` is always `null` from the server (spec: DOB never stored); the client only sends `p_age_verified`.
- `RevealManifest` is still declared in `Features/Reveal/RevealTimeline.swift` although `Data/Protocols` now references it;
  moving it to `Domain/Models` is a mechanical follow-up (no Features edits were allowed in this pass).
