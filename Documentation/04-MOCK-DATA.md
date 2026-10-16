# Mock backend and demo data

`MockDataStore` (actor) is the whole backend for this phase. It applies `RelayEngine`, simulates ~220 ms latency,
persists itself to `Application Support/MockState.json`, and broadcasts `DataChange` / `RelayEvent`s.

## Fixtures (seeded on first sign-in, mirror the Figma)
- **Friday Night Crew 🌙** `PASS-FN74`: Jake (admin), you, Maya, Zoe, Cam. Streak 7, 23 completed. Live relay "Worst Selfie": Jake submitted, the Baton is with you (1 h 58 min). Two completed relays in History.
- **Court Crew 🏀** `PASS-CT31`: Jordan (admin), you, Dev. Streak 2, 5 completed. One completed relay.
- **Brunch Club 🥞** `PASS-BR22`: Sam, Priya, Leo; you are **not** a member. Live relay with Priya holding. Use this code (or `pass://i/PASS-BR22`) to exercise the invite flow.
- 10 built-in challenges (Luis's V1 list, email 2026-10-10) + Write your own.
- Fixture "photos" are generated gradients with initials (no network, no Unsplash).

## Demo controls (DEBUG builds only, `AppConfiguration.demoControlsEnabled`)
| Where | Control | Stands in for |
|---|---|---|
| Relay Progress | "{Name} submits and passes on" | another member's phone |
| Relay Progress | "Holder drops the Baton" | the server's deadline job (expires the open turn now) |
| Relay Progress | "Skip 2 hours" | the server clock |
| Group Detail | "+ Friend joins" / "A member leaves" | invite acceptance / spec §17 cancellation |
| Profile | "Simulate an incoming invite", "Fast timers", "Reset demo data" | deep link, staging timers (3 min / 1 min), fresh install |

Local notifications are scheduled for events that concern you (Baton received, rescue, one left, Relay ready) so the
tap → correct relay routing can be tested. They will be replaced by APNs pushes.

## Launch arguments (DEBUG)
`-resetState` wipes session + mock state · `-demoSession` signs in as "Khizar" with onboarding done · `-fastTimers` uses 3-min/1-min windows.

## What is persistent vs. temporary
Persistent across launches: the mock session/profile (UserDefaults), mock state JSON, media files, Reveal exports in Caches.
Temporary: captures in `tmp/` until submitted. Everything is removed by "Reset demo data" + "Delete Account" or a reinstall.
