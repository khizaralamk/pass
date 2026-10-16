# PASS iOS — Milestone 0: Discovery & System Design

Date: 2026-10-09 · Author: frontend phase kickoff · Sources: `docs/MVP Functional Specification.pdf` (Luis, v1.0), Figma Make prototype (`docs/figma/make-source/src/App.tsx` + `index.css`, 19 screens), `docs/figma/FIGMA-NOTES.md`, `docs/figma/FIGMA-FLOW-AND-CONTRADICTIONS.md`, `docs/BUILD-PLAN.md`.

---

## 1. Repository audit

| Item | Finding |
|---|---|
| Location | `APP/frontend/pass/PASS/` (git repo, 1 commit "Initial Commit") |
| Xcode | 26.2 (17C52), project `objectVersion 77`, **file-system-synchronized groups** (files on disk = files in target; no pbxproj edits needed for sources) |
| Template | Xcode "App" template with SwiftData (`Item`, `ContentView` with `NavigationSplitView`) — all placeholder, to be removed |
| Deployment target | **26.2** (template default). Too new for a public app. Build plan recommends iOS 17+; Luis is being asked on 12 Oct. **Decision: set to iOS 17.0** (widest reach that still allows `@Observable`, `NavigationStack`, `ContentUnavailableView`, `PasteButton`). Raise later if Luis prefers. |
| Swift | Language mode 5, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, default isolation nonisolated. Keep language mode 5 to avoid Swift 6 strict-concurrency churn; annotate UI models `@MainActor`. |
| Bundle ID / team | `com.luis.PASS`, team `X6AR2W6J5P`, automatic signing. Preserved. |
| Device family | iPhone + iPad (`1,2`), all orientations. Spec: iPhone only → **iPhone only, portrait only** (iPad runs in compatibility mode). |
| Dependencies | None (no SPM packages). Keep it that way for the frontend phase. |
| Tests | **None**. Unit (Swift Testing) + UI (XCUITest) targets to be added via the `xcodeproj` Ruby gem (installed, v1.27). |
| Assets | Empty AppIcon, AccentColor. No fonts. Figma uses Outfit + Inter (Google Fonts, OFL) → bundled as variable TTFs (`Outfit[wght].ttf`, `Inter[opsz,wght].ttf`). |
| Config files | None. No `.gitignore`. No Info.plist (generated). |
| CLAUDE.md | None in the project. To be created. |
| Backend | `APP/backend/` is empty. Supabase vs Firebase undecided → no SDK, no credentials. |

## 2. MVP feature inventory (from the spec; § = spec section)

| # | Feature | § | Frontend phase |
|---|---|---|---|
| F1 | Sign in with Apple; returning user splash → Home | 3 | Mock auth service; official button wired; demo sign-in for simulator |
| F2 | Onboarding: display name, DOB (16+), optional photo, terms | 3 | Full, with validation + under-16 block |
| F3 | Invite restore: invited user goes to the invite before Home | 3 | Pending-route store + invite code entry + deep link parsing |
| F4 | Home: active relays (mine first), groups, empty state, +New Relay, +New Group | 4 | Full |
| F5 | Groups: private, 3-min/7-max, create flow (name/emoji → invite → created) | 5 | Full (mock) |
| F6 | Invites: link, code `PASS-XXXX`, native share sheet | 5 | Full (share sheet with mock link) |
| F7 | One active relay per group; redirect to existing | 6 | Full |
| F8 | Group stats: completed count, streak (streak prominent) | 7 | Full |
| F9 | New relay: choose group → challenge (10 built-in, Luis's V1 list + write your own) → review → start | 8–9 | Full |
| F10 | Baton screen: who passed, challenge, timer, rules, hidden note, Open Camera | 10 | Full; timer from a `Clock` abstraction (server clock later) |
| F11 | Expiration & rescue: first miss → deferred; 15-min rescue; second miss → excluded; <3 → failed | 11 | Pure `RelayEngine` rules + mock deadline processor + demo controls |
| F12 | Submission: one photo or ≤4 s video; camera → preview → retake/use | 12 | Real AVFoundation camera on device; simulator fallback |
| F13 | Pass the baton: eligible list, one pick | 13 | Full |
| F14 | Relay progress: names/status only, no media, timer | 14 | Full incl. deferred/excluded states |
| F15 | Push notifications + tap → correct relay | 15 | Permission prompt, routing from payload, local demo notification; APNs later |
| F16 | Completion → "Your relay is ready" → Watch the Reveal | 16 | Full |
| F17 | Member leaves → relay cancelled, neutral message | 17 | Full (mock) |
| F18 | Reveal: deterministic 9:16 sequence, timings, names, branding | 18–22 | In-app player (SwiftUI) + MP4 export (AVFoundation) |
| F19 | Post-reveal: Share, Save, Watch Again, Start Another | 23 | Full |
| F20 | Relay history per group | 24 | Full (mock) |
| F21 | Profile/Settings: info, groups, notifications, privacy/legal, support, sign out, delete account | 25 | Full (mock) |
| F22 | Safety: leave, remove member, block, report | 26 | Full (mock) |
| F23 | Ownership, stack, App Store, deliverables | 27–31 | Out of frontend phase (documented) |

## 3. Figma screen inventory (19 prototype screens + 1 banner)

Splash · Invite · Join Group · Home (3 states) · Profile · Group Detail · Create Group: Name · Create Group: Invite · Group Created · New Relay: Group · New Relay: Challenge · New Relay: Start · Baton + Challenge · Camera · Preview · Pass Baton · Relay Progress · Relay Complete · Auto Reveal · Post-Reveal · Notification banner.

Design tokens (from `index.css` / `FIGMA-NOTES.md`): background `#0A0A0A`/`#0D0D0D`, card `#161616` + 1 px white 7 % border, radius 20/14, violet `#6B46FF`, red `#FF2D55`, orange `#FF6B35`, amber `#FF9F0A`, green `#30D158`, blue `#0A84FF`, surface button `#1C1C1E`; Outfit 400–900 display, Inter 400–600 body; 56 pt pill buttons; fade-up 0.42 s / scale-in 0.38 s / screen-in 0.35 s with `cubic-bezier(0.22,1,0.36,1)`; dark only.

## 4. Screen → feature mapping and additions

| Screen | Feature | Status |
|---|---|---|
| Splash | F1 | Figma |
| **Onboarding (name, DOB, photo, terms)** | F2 | Added (spec, not in Figma) in Figma style |
| **Under 16** | F2 | Added |
| **Invite code entry** | F3 | Added |
| Invite → Join Group | F3, F5 | Figma |
| Home | F4, F8 | Figma + streak badge on group rows |
| Profile / Settings | F21 | Figma + Support, Terms, Delete Account, Blocked users |
| Group Detail | F5–F8, F20, F22 | Figma + stats card, invite row, history, member actions, leave |
| Create Group (3 screens) | F5, F6 | Figma |
| New Relay (3 screens) | F7, F9 | Figma |
| Baton + Challenge | F10 | Figma + **rescue variant** ("Last chance") |
| Camera / Preview | F12 | Figma + 4 s limit ring |
| Pass Baton | F13 | Figma |
| Relay Progress | F14 | Figma + timer, deferred/excluded, **ended/failed states** |
| Relay Complete / Reveal / Post-Reveal | F16, F18, F19 | Figma |
| **Relay History** | F20 | Added |
| **Report / Block sheets** | F22 | Added |
| **Notification permission** | F15 | Added (after onboarding, native prompt with a short explainer) |

## 5. Primary user journey & navigation map

```
Launch ─ session? ─ no ─► Splash ─ Continue with Apple ─► Onboarding (name → DOB → photo → terms)
   │                                                         │ pending invite? ─ yes ─► Invite → Join Group → Group / Baton
   │                                                         └ no ─► Invite code? (skip) ─► Home
   └─ yes ─► Home ──► YOUR TURN → Baton → Camera → Preview → Pass Baton → Progress
             ├────► BATON WITH X → Progress ─(complete)─► Relay Complete → Reveal → Post-Reveal
             ├────► + New Relay → Group → Challenge → Review → Camera (creator first)
             ├────► + New Group → Name → Invite → Created → (Start a Relay | Go to Group)
             ├────► Group row → Group Detail → (New Relay | Progress | History → Reveal | Members → Remove/Report/Block | Leave)
             └────► Avatar → Profile → (Group | Notifications | Privacy | About | Support | Sign Out | Delete Account)
Deep link pass://i/CODE or https://<domain>/i/CODE → Invite (restored after sign-in if needed)
Notification tap {relayId} → that relay (Baton if mine, Progress otherwise, Complete if finished)
```

Implementation: one `NavigationStack` rooted at Home with a typed `Route` enum; full-screen covers for Camera/Preview and the Reveal player; sheets for share/report/invite-code.

## 6. Requirements & design discrepancy report (decisions taken for the frontend phase)

| # | Conflict | Decision (changeable constant/copy) |
|---|---|---|
| C1 | Figma "⏱️ Any length" vs spec 4 s video | Spec wins: "⏱️ Up to 4 sec"; camera auto-stops at 4.0 s |
| C2 | Figma has no onboarding | Add name/DOB/photo/terms screens in Figma style |
| C3 | Streak / completed count missing in Figma | Stats card on Group Detail (streak large, count small) + 🔥 on Home rows |
| C4 | Reveal intro 2.2 s (Figma) vs 1–2 s (spec) | 2.0 s (satisfies the spec, closest to Figma); one constant in `RevealTemplate` |
| C5 | 5 challenges vs 8–12 | Resolved 2026-10-10: Luis's 10 (Worst Selfie … Before Midnight); custom stays. Previously 11 built-in; Luis's final list replaces the fixture |
| C6 | No timer on Progress | Countdown shown next to the holder |
| C7 | "Start Another Relay" → Home | → New Relay with the same group preselected (spec intent) |
| C8 | Join mid-relay gets the baton (Figma) | Demo fixture mirrors Figma; rule for real backend is OPEN (Luis) |
| C9 | Invite = code only | Code + link + real iOS share sheet |
| C10 | Reveal photos only | Video segments supported in player and export |
| C11 | Reveal copy on a partial relay | "{X}/{Y} PASSED 🔥" with X = successful; recap label "X of Y submitted" |
| C12 | Group code format | `PASS-XXXX` (A–Z, 2–9, no confusables) |
| C13 | Watermark | None (Figma); end card only. Easy to add |
| OPEN-1 | Who gets the baton after a miss | Earliest-joined eligible member who hasn't submitted (mock rule) |
| OPEN-2 | Required participants | Members at relay start; joiners wait for the next relay (except the demo fixture, C8) |
| OPEN-3 | Creator's window | 2 h, starts at "Start Relay" |
| OPEN-4 | Rescue order | First dropped, first rescued; if the only one left, rescue starts immediately |
| OPEN-5 | Pass to a deferred member | Not offered while others remain |
| OPEN-6 | Who removes a member | Group creator only. Block = that person cannot invite you and is hidden from pickers; unblock in Privacy |
| OPEN-7 | Report destination | Mock stores the report; backend to email Luis |

Client-side validation is **not** a security boundary; the backend must enforce every rule above.

## 7. Proposed architecture

Single app target, feature-oriented folders, four layers:

- **Presentation** (`Features/*/…View.swift`, `Core/DesignSystem`): SwiftUI views + `@Observable @MainActor` view models for screens with async work. Local `@State` for transient UI.
- **Application** (`App/`): `AppDependencies` (composition root), `AppSession` (auth/onboarding state), `AppRouter` (routes, deep links, notifications).
- **Domain** (`Domain/`): plain Swift models + pure rules (`RelayEngine`, `Validators`, `RevealTimeline`, `RelayRules` constants). No SwiftUI, no Foundation networking.
- **Data** (`Data/`): protocols (`AuthService`, `GroupRepository`, `RelayRepository`, `ChallengeRepository`, `SessionStore`, `NotificationService`, `MediaStore`) + `Mock*` implementations backed by one in-memory `MockDataStore` actor with deterministic fixtures and simulated latency. Future `Supabase*`/`Firebase*` implementations satisfy the same protocols.

Dependency direction: Views → ViewModels → protocols ← Mock/Remote. Domain depends on nothing. Features share only `Core` and `Domain`.

## 8. State management & data flow

- `AppSession` (`@Observable`, main actor): `.loading / .signedOut / .onboarding(step) / .signedIn(User)`; owns the pending route.
- Screen view models own their loading/error/content state (`Loadable<T>`), guard against stale async results with task cancellation on disappear and a generation counter, and never leave loading stuck (every path sets a terminal state).
- Store mutations publish through an `AsyncStream` of change events; view models refresh on events, on foreground and on pull-to-refresh.
- Countdowns derive from `deadline - clock.now` every second; nothing is persisted.
- Persistence: only the mock session (user id, name, onboarding done) in `UserDefaults` via `SessionStore` — not sensitive; the real token goes to Keychain in the backend phase.

## 9. Configuration, validation, security

- `AppConfiguration`: environment (debug/release), invite link base URL (placeholder domain), rule constants, feature flags (`demoControlsEnabled` = DEBUG only).
- No secrets anywhere; `.gitignore` for Xcode user data and future `*.xcconfig` secrets.
- Validation rules documented in `Documentation/VALIDATION.md` (name 2–30 chars, DOB 16+, group name 2–30, challenge 3–60, code `PASS-XXXX`).
- Usage strings for camera, microphone, photo-library add. No PII logged.

## 10. Testing strategy

- **Unit (Swift Testing)**: `RelayEngine` (start, pass, drop, rescue, exclude, complete, fail, cancel, streak), validators, invite code, `RevealTimeline`, mock repositories, router parsing.
- **UI (XCUITest)**: launch → demo sign-in → onboarding → home; create group; start relay → camera (simulator mock) → pass baton → progress; validation errors.
- **Build checks**: `xcodebuild build` + `test` on the iPhone 17 Pro Max simulator after each milestone.

## 11. Milestone plan

| M | Scope | Acceptance |
|---|---|---|
| 1 | Clean template, iOS 17 target, folders, design system, fonts, config, errors, test targets | Builds; design system previews; empty tests run |
| 2 | Session, router, root flow, composition root, mock store + fixtures, Home | Launch → splash → demo sign-in → Home with fixtures; deep link parses |
| 3 | Core screens: Home cards, Group detail, Create group, New relay, Baton, Camera, Preview, Pass, Progress, Complete, Reveal player, Post-reveal | Full core loop runs on the simulator with demo controls |
| 4 | Onboarding + validation, relay engine rules, deadline processing, rescue, demo controls | Unit tests for every rule pass |
| 5 | Mock data boundaries documented, change stream, latency/error simulation | All flows work without backend; `BACKEND-INTEGRATION.md` |
| 6 | Settings, safety, history, ended/failed, invite code entry, notifications, group-full, under-16 | Every button works; no dead ends |
| 7 | Reveal MP4 export, accessibility, Dynamic Type, Reduce Motion, concurrency audit | Export plays; VoiceOver labels; no stuck states |
| 8 | Final build + tests, CLAUDE.md, README, known limitations | All checks documented |
