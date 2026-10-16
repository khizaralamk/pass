# Luis's reply (2026-10-10) checked against the build — 2026-10-11

| Luis's point | Status in app + backend |
|---|---|
| Missing screens in Figma style, inside the $2,300 scope, reviewed during development | ✅ 14 spec-only screens built in the Figma style; screenshots in the verification doc for his review |
| Video limited to 4 s (spec wins) | ✅ hard stop in capture, CHECK constraint `duration_ms ≤ 4000` server-side |
| Group screen shows lifetime completed count **and** streak, streak more prominent | ✅ stats card: streak 34 pt with 🔥, completed count 20 pt muted; streak also on Home rows |
| V1 challenges: Worst Selfie, Show Your View, Current Fit, What Are You Eating?, Find Something Red, Friday Night, Recreate This Photo, One Second From Your Day, Best Impression, Before Midnight; custom stays | ✅ **changed today**: iOS fixtures + SQL seed now carry exactly these 10; old titles deactivated server-side; "Write your own" unchanged |
| Miss the 2 h window → deferred to the end; Baton auto-passes to the next eligible who hasn't submitted, by a predefined member order | ✅ order = group join order (earliest first), identical in `RelayEngine` and `pass.advance()`; next turn starts at the expired deadline |
| Deferred cannot be picked manually; rescue (15 min) after the others | ✅ Who's Next hides deferred members; rescue auto-starts when only deferred remain |
| Join during an active Relay → next Relay; roster locked at start | ✅ participants snapshot at `start_relay`; invite screen says "You'll join from the next Relay" |
| Several deferred → one rescue each, in the order they missed | ✅ `deferred_at` ascending on both sides; covered by `03_deadlines.sql` and `RelayEngineTests` |
| Client-owned infra (Apple, GitHub); backend + domain after developer selected | ✅ nothing is tied to Khizar's accounts except the dev signing team (switch documented in the publish checklist) |

## Monday talking point: Reveal interruption / last participant goes offline
Nothing depends on the last participant's phone. The server marks the relay complete the moment the final `submit` row
lands (one transaction). The Reveal is not "generated" anywhere in the cloud: every member's app renders it on their own
device from the `reveal-manifest` (signed URLs for the sealed media) using a deterministic timeline, so a closed app or lost
connection only delays *that* person's viewing. Upload is the only fragile step: the capture stays on the device until the
server confirms, with retry (409-tolerant re-upload), and the Baton timer keeps running server-side, so a holder who loses
connectivity for the full window is treated like any miss (deferred, rescue later). Export to MP4 for sharing is also
local and cached per relay.

## Still for the call
- Confirm "predefined member order" = join order (current) vs. a creator-set order (would add a reorder screen; not in V1 scope).
- Backend: Supabase recommended (reasons in `backend/docs/00-SYSTEM-DESIGN.md`).
- Domain for invite links; report destination email.
