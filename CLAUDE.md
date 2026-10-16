# PASS iOS — project instructions

Native iOS app for PASS (private friend-group challenge relays). Frontend phase: everything runs against an in-app mock
backend; Supabase/Firebase are integrated in a later phase. Spec: `../../../../docs/MVP Functional Specification.pdf`;
Figma source: `../../../../docs/figma/make-source/src/App.tsx`. Discovery and decisions: `Documentation/`.

## Stack
- Swift 5 language mode, SwiftUI, iOS 17.0+, iPhone only, portrait, dark only. One package: `supabase-swift` (product `Supabase`), used only under `PASS/Data/Supabase`.
- Swift Concurrency: `async/await`, one `actor` (`MockDataStore`), `@MainActor @Observable` view models.
- Fonts: Outfit (display) + Inter (body) bundled as variable TTFs (`PASS/Resources/Fonts`, OFL).
- Project uses Xcode file-system-synchronized groups: adding a file under `PASS/`, `PASSTests/` or `PASSUITests/` adds it to the target. Never put non-source files (Info.plist etc.) inside `PASS/`; they live in `Config/`.

## Layout
```
PASS/App            PASSApp, AppDelegate (notification delegate), AppDependencies (composition root), AppSession, AppRouter, RootView, MainNavigationView
PASS/Core           Config (AppConfiguration), DesignSystem (PassColor/PassFont/PassButton/PassCard/PassComponents/PassMotion/MediaImageView/ShareSheet), Errors (AppError, Loadable), Utilities
PASS/Domain         Models (User, Group, Relay, Challenge, Report, Identifiers) · Rules (RelayEngine, RelayRules, Validators, InviteCode)
PASS/Data           Protocols (AuthService, UserRepository, GroupRepository, RelayRepository, RevealManifestProvider, MediaStore, SessionStore, NotificationService, DataChangeSource) · Mock (MockDataStore, MockFixtures, MockServices) · Supabase (real adapters, chosen by AppConfiguration.backend; mock stays the default)
PASS/Features       Auth, Home, Groups, Relay, Baton, Capture, Reveal, Settings — each screen = View (+ ViewModel when it has async work)
PASSTests           Swift Testing: engine scenarios, validators, timeline, deep links, mock store
PASSUITests         XCUITest journeys (launch args `-demoSession -resetState -fastTimers`)
Config/             Info.plist (fonts, URL scheme `pass://`, PASS_SUPABASE_URL/ANON_KEY), PASS.entitlements, Dev/Staging/Release.xcconfig + Secrets.example.xcconfig (empty keys = mock)
Documentation/      discovery, decisions, backend integration, validation rules, mock data, known limitations
```

## Rules
- Dependency direction: Views → ViewModels → `Data/Protocols` ← `Data/Mock`. Domain imports nothing but Foundation. Views never touch `MockDataStore` except through `AppDependencies.mockStore` for DEBUG demo controls.
- Game rules live only in `Domain/Rules/RelayEngine.swift` (pure, tested). Copy them server-side in the backend phase; do not fork them in views.
- Every async screen state is a `Loadable<T>`; each path must end in `.loaded`/`.failed`. Guard stale results with a generation counter; cancellation is never shown as an error (`AppError.isCancellation`).
- Countdowns are `deadline - clock.now()` via `CountdownText`; never persist remaining time.
- Never show another member's media before a Reveal (spec §14). `MediaImageView` is only used for avatars, fixtures, History and Reveal.
- Copy: use the Figma wording (`Take your turn 🔥`, `Pass the Baton 🔥`, `Nothing active right now.`); rule copy from the spec.
- Secrets: none in the repo. Config placeholders (`pass-app.example`) live in `AppConfiguration`; Supabase URL/anon key come from `Config/Secrets.xcconfig` (gitignored) → Info.plist → `AppConfiguration.backend`. See `Documentation/02-BACKEND-INTEGRATION.md` (“How to switch to Supabase”).
- Validation rules are in `Validators` and documented in `Documentation/VALIDATION.md`; client validation is not a security boundary.

## Build & test
```
xcodebuild -project PASS.xcodeproj -scheme PASS -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
xcodebuild -project PASS.xcodeproj -scheme PASS -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test -only-testing:PASSTests
TEST_RUNNER_PASS_UI_SHOTS=/tmp/shots xcodebuild ... test -only-testing:PASSUITests   # saves screenshots
```
Device: `xcodebuild -destination 'platform=iOS,name=Khizar’s iPhone' -allowProvisioningUpdates build`, then `xcrun devicectl device install app`.
Delete `DerivedData/PASS-*/Logs/Test` after UI runs: xcresult bundles with simulator logs are large and the Mac's disk is tight.

## Mock backend & demo
- All state is in `MockDataStore` (JSON-persisted in Application Support; "Reset demo data" in Profile wipes it). Fixtures mirror the Figma: Friday Night Crew (live relay, Baton with you), Court Crew, Brunch Club (join with `PASS-BR22`).
- DEBUG-only demo controls (Progress, Group Detail, Profile) stand in for other members and the server clock.
- Simulator has no camera: the shutter produces a placeholder photo; video needs a device.
