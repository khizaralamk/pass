# PASS

**Private friend-group challenge relays for iPhone.** One person holds the Baton, completes the Challenge with a photo or a 4-second video, and passes it on. Submissions stay hidden until everyone is done, and then PASS automatically builds a vertical **Reveal** video of the whole Relay.

> **Challenge → Baton → Submission → Pass → Anticipation → Reveal → Share → Another Relay**

Native SwiftUI · iOS 17+ · iPhone · Frontend prototype with an in-app mock backend

---

## Status

This is a **working frontend prototype**. The whole core loop runs on one iPhone against an in-app mock backend, so it needs no accounts, keys or server to try.

| Area | State |
|---|---|
| Sign in, onboarding (name, DOB 16+), Home, Profile | ✅ Built (mock auth on the simulator) |
| Groups, invite codes and links (`pass://i/CODE`) | ✅ Built |
| Relay creation, Baton, 2-hour timer, miss → defer → rescue → exclude | ✅ Built (`RelayEngine`, unit tested) |
| Relay Progress, streak and completed count | ✅ Built |
| Camera (photo + 4-second video), Preview, Retake | ✅ Built (video needs a real device) |
| **Reveal**: 1080×1920 H.264/AAC MP4, built on the device | ✅ Built (`RevealExporter`) |
| Share, Save to Photos, Watch Again, Relay History | ✅ Built |
| Real backend (Supabase), APNs push, multi-phone play | ⏳ Next phase: adapters are scaffolded in `PASS/Data/Supabase` |

Full list: [`Documentation/05-KNOWN-LIMITATIONS.md`](Documentation/05-KNOWN-LIMITATIONS.md)

---

## How to run

### Requirements
- A Mac with **Xcode 26.2** or newer
- An iPhone simulator, or an iPhone on **iOS 17.0+**
- No accounts, API keys or setup needed: the app uses the built-in mock backend by default

### On the simulator (fastest)
1. Clone the repo:
   ```bash
   git clone https://github.com/khizaralamk/pass.git
   cd pass
   ```
2. Open **`PASS.xcodeproj`** in Xcode. On first open, Xcode fetches the one Swift package (`supabase-swift`). Wait for it to finish.
3. At the top of Xcode, choose the **PASS** scheme and an iPhone simulator (for example **iPhone 17 Pro Max**).
4. Press **▶ Run** (`⌘R`).
5. In the app: **Splash → Try the demo → onboarding → Home**.

**Skip straight to Home with demo data:** Product → Scheme → Edit Scheme → Run → Arguments → add `-demoSession -resetState`.

### On your iPhone
1. Connect the iPhone, and turn on **Developer Mode** on it (Settings → Privacy & Security).
2. In Xcode: select the **PASS** target → **Signing & Capabilities** → choose your **Team** and, if needed, change the **Bundle Identifier** to a unique one.
3. Choose your iPhone at the top and press **▶ Run**.
4. On the device, you can use the real camera (photo and video) and **Continue with Apple**.

### Try the full loop (about 2 minutes)
1. **Home** → open the **Friday Night Crew** Relay (the Baton is with you) → **Take your turn 🔥**
2. **Open Camera** → capture → **Use This ✓** → pick who's next → **Pass the Baton 🔥**
3. **Relay Progress** → use the **demo controls** to act as the other members (and to move the clock forward to see a miss and a rescue)
4. When everyone has submitted → **Watch the Reveal** → the video is generated on the device
5. **Share Relay**, **Save Video** or **Watch Again**

More demo data and controls: [`Documentation/04-MOCK-DATA.md`](Documentation/04-MOCK-DATA.md). For example, join the **Brunch Club** group with code `PASS-BR22`, and use **Profile → Reset demo data** to start over.

> The simulator has no camera, so the shutter uses a placeholder photo there. Video capture needs a real iPhone.

---

## Run the tests

In Xcode: **`⌘U`**. That runs 55 unit tests (Swift Testing) and the UI journeys (XCUITest).

From the terminal:
```bash
# Unit tests: game rules, validators, Reveal timeline, deep links, mock store
xcodebuild -project PASS.xcodeproj -scheme PASS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test -only-testing:PASSTests

# UI journeys
xcodebuild -project PASS.xcodeproj -scheme PASS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test -only-testing:PASSUITests
```

---

## How it works

- **Game rules live in one place:** [`PASS/Domain/Rules/RelayEngine.swift`](PASS/Domain/Rules/RelayEngine.swift) is a pure, tested engine: Baton turns, 2-hour windows, deferral, 15-minute rescues, exclusion, completion and streaks. In the backend phase, the same rules move to the server.
- **Countdowns** are always `deadline − now`, never a stored "time left", so closing the app never resets a timer.
- **Hidden until the Reveal:** no screen shows another member's media before the Relay ends.
- **The Reveal** ([`PASS/Features/Reveal`](PASS/Features/Reveal)) is a fixed, deterministic template: challenge intro → each participant in Baton order → recap → *X/X PASSED 🔥* → *PASS IT ON.* Each frame is drawn by the same SwiftUI view the player shows, clip frames and original audio are read with `AVAssetReader`, and `AVAssetWriter` writes a 1080×1920, 30 fps H.264/AAC MP4. The result is cached per Relay.
- **Swappable backend:** views talk to protocols in `PASS/Data/Protocols`. `Data/Mock` is the default implementation, and `Data/Supabase` holds the real adapters.

## Tech stack
| | |
|---|---|
| UI | SwiftUI, `@Observable` view models, iOS 17+, iPhone, portrait, dark |
| Concurrency | `async/await`, an `actor` mock store |
| Media | AVFoundation (capture, `AVAssetReader` / `AVAssetWriter`), Photos |
| Backend (next phase) | Supabase via `supabase-swift`, APNs |
| Fonts | Outfit + Inter (bundled, SIL Open Font License) |
| Tests | Swift Testing + XCUITest |

## Project structure
```
PASS/
├── App/            App entry, routing, dependency setup
├── Core/           Design system, configuration, errors, utilities
├── Domain/         Models + RelayEngine (all game rules)
├── Data/           Protocols · Mock backend (default) · Supabase adapters
└── Features/       Auth · Home · Groups · Relay · Baton · Capture · Reveal · Settings
PASSTests/          Unit tests (Swift Testing)
PASSUITests/        UI journeys (XCUITest)
Config/             Info.plist, entitlements, Dev/Staging/Release xcconfigs, Secrets.example
Documentation/      Discovery, decisions, backend integration, validation, mock data, limitations
```

## Documentation
| File | What's inside |
|---|---|
| [`00-DISCOVERY.md`](Documentation/00-DISCOVERY.md) | Scope and how the spec maps to the app |
| [`01-DECISIONS.md`](Documentation/01-DECISIONS.md) | Product and technical decisions |
| [`02-BACKEND-INTEGRATION.md`](Documentation/02-BACKEND-INTEGRATION.md) | How to switch from the mock to Supabase |
| [`03-VALIDATION.md`](Documentation/03-VALIDATION.md) | Input and rule validation |
| [`04-MOCK-DATA.md`](Documentation/04-MOCK-DATA.md) | Demo data and controls |
| [`05-KNOWN-LIMITATIONS.md`](Documentation/05-KNOWN-LIMITATIONS.md) | What isn't built yet |
| [`07-SPEC-COVERAGE.md`](Documentation/07-SPEC-COVERAGE.md) | Spec sections vs. what's implemented |

## Configuration and secrets
No secrets are committed. To connect a real backend, copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (it's gitignored) and fill in the Supabase URL and anon key. Leave them empty to keep the mock backend. Details are in [`02-BACKEND-INTEGRATION.md`](Documentation/02-BACKEND-INTEGRATION.md).

---

Built by **Khizar Alam**.
