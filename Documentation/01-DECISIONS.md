# Architecture decisions (frontend phase)

| # | Decision | Why | Trade-off |
|---|---|---|---|
| D1 | iOS 17.0 deployment target (template was 26.2) | Reaches ~95 % of iPhones; unlocks `@Observable`, `NavigationStack`, `PasteButton`, `ContentUnavailableView` | Can't use iOS 18+ APIs; raise later if Luis agrees |
| D2 | Swift 5 language mode + approachable concurrency, `@MainActor @Observable` view models, one `actor` for the mock store | Modern concurrency without Swift 6 strict-mode churn on a template that is already in Swift 5 mode | Some `Sendable` checks are warnings, not errors; revisit when adopting Swift 6 |
| D3 | Single app target with feature folders, no SPM modules | MVP size; synchronized groups make files automatic | Access control is by convention; split into packages only if the team grows |
| D4 | Protocol-typed repositories + composition root (`AppDependencies.live()`) | Backend (Supabase or Firebase, undecided) plugs in by replacing one factory; views never see SDK types | Slight indirection; worth it for the stated backend uncertainty |
| D5 | Game rules in a pure `RelayEngine` with event output | Testable scenarios (drop, rescue, exclusion, streak) with simulated time; serves as the backend's reference | Rules exist twice once the server implements them; the engine tests are the contract |
| D6 | Mock state persisted as JSON in Application Support | A demo on a phone survives relaunches; everything is still obviously mock (resettable) | Not a real persistence design; replaced wholesale by the backend |
| D7 | Routes carry IDs only; `AppRouter` resolves relay → screen (Baton / Pass / Progress / Complete) | Deep links and push taps use the same path as in-app navigation | Screens load their own data (one fetch per push) |
| D8 | Reveal = pure timeline + one `RevealSlideView` used by both the player and the MP4 exporter | Deterministic, pixel-identical playback and export, no video-editing code in the UI | Export renders frames on the main actor with yields (~10–20 s for a 5-person relay); fine with a progress bar |
| D9 | Camera via `AVCaptureMovieFileOutput.maxRecordedDuration` for the 4-second cap | Hard limit enforced by the capture pipeline, not by UI timing | Movie files are `.mov`; the exporter and player handle them |
| D10 | Real Sign in with Apple button + DEBUG "Try the demo" | The official button and entitlement are in place; demo path works on the simulator without an account | Token exchange and session restoration arrive with the backend |
| D11 | Placeholder domain `pass-app.example` in `AppConfiguration` | Luis has not provided a domain; links still demonstrate the flow | Must be replaced before TestFlight, with the Associated Domains entitlement |
| D12 | Figma wording for UI copy, spec for rules; C1–C13 and OPEN-1…7 resolved as in `00-DISCOVERY.md` §6 | Follows BUILD-PLAN guidance | Each is a one-line change once Luis answers |
