# Verification log — 2026-10-09

| Check | Result |
|---|---|
| `xcodebuild build` (iPhone 17 Pro Max simulator, Debug) | passes, 0 errors |
| `xcodebuild build` (Khizar's iPhone 14, automatic signing) | passes; installed and launched via `devicectl` |
| Unit tests `PASSTests` | 44 tests / 10 suites pass (engine scenarios, stats, validators, invite code, formatters, timeline, deep links, mock store, session store, Reveal export) |
| UI tests `PASSUITests` (simulator) | 5/5 journeys pass: onboarding + validation, full relay loop (Baton → camera → preview → pass → progress → complete → Reveal → Post-Reveal → Home empty), create group + 3-member rule, group detail/history/settings/invite by code, deep link `pass://i/PASS-BR22` |
| Screenshots | `scratchpad/shots/*.png` from the UI run (also attached in the xcresult) |
| Reveal MP4 export | `RevealExporterTests`: 3-photo relay → MP4, 1080×1920, duration = timeline ±0.1 s, 1 video + 1 audio track, ~4 s on the simulator |
| Dynamic Type | Home at AccessibilityM: layout intact, long names truncate (screenshot `home-ax.png`) |
| Device UI test | runner could not start: the iPhone needs Settings → Developer → Enable UI Automation (not an app issue); the app itself installs and launches |
| Static checks | no SwiftLint configured (none added, per the brief) |

Fixes made during verification: card border overlays intercepted taps (`allowsHitTesting(false)`), settings rows now use
an explicit `contentShape`, UI tests wait for navigation transitions before tapping.

Reliability fixes in M7: camera recording that ends by the 4 s limit before the stop handler registers no longer hangs;
no force-unwrap in the navigation shell; the date of birth is not persisted on device; a notification tap during a cold
launch is replayed once the router exists; the Reveal exporter interleaves audio per frame (AVAssetWriter stalls when one
track runs far ahead) and fails fast instead of waiting forever on a failed writer.

Environment note: the Mac's disk hit 0 bytes free mid-session (UI-test result bundles with simulator logs are large).
Freed by deleting regenerable caches (other projects' DerivedData, VS Code update cache, npm cache). ~4.6 GB free at the end.
