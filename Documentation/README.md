# PASS iOS (frontend phase)

Native SwiftUI app. Open `PASS.xcodeproj` in Xcode 26.2+, select the **PASS** scheme, run on any iPhone simulator
(iOS 17+) or a device. No packages, no credentials, no setup.

- First launch: Splash → **Try the demo** (simulator) or **Continue with Apple** (device) → onboarding → Home.
- To jump straight to Home with demo data: Edit Scheme → Arguments → `-demoSession -resetState`.
- Tests: `⌘U` runs 43 unit tests (Swift Testing) and 5 UI journeys (XCUITest). CLI commands are in `CLAUDE.md`.
- Docs: `Documentation/00-DISCOVERY.md` (scope, decisions), `02-BACKEND-INTEGRATION.md`, `04-MOCK-DATA.md` (demo controls), `05-KNOWN-LIMITATIONS.md`.
