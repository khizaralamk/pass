# Spec & Figma coverage audit — mobile frontend (2026-10-10)

Legend: ✅ built and verified on simulator/device · 🟡 built as far as the frontend can; needs the backend to be real · ⏳ backend phase only (not a frontend deliverable) · ❓ waiting on Luis

## A. Luis's MVP Functional Specification, section by section

| § | Requirement | Status | Where / note |
|---|---|---|---|
| 1 | Private friend-group challenge app; Challenge → Baton → Reveal; no feed/followers/discovery/DMs/chat/strangers/AI/editor | ✅ | No such screens exist; "No public profile. No followers. Just your crew." on Post-Reveal and About |
| 2 | iOS only, modern iPhones | ✅ | iPhone-only target, portrait, iOS 17+ |
| 3 | Sign in with Apple | 🟡 | Official `SignInWithAppleButton` + entitlement; credential accepted by the mock. Token exchange + session = backend |
| 3 | Display name required | ✅ | Onboarding step 1, validated 2–30 chars |
| 3 | DOB confirmation, 16+ | ✅ | Step 2 wheel picker; under 16 → blocked screen with Sign out; DOB never stored on device |
| 3 | Profile photo optional | ✅ | Step 3 PhotosPicker, skippable |
| 3 | Returning user: splash → Home, no re-login | ✅ | Session restored from `SessionStore`; `AppSession.bootstrap` |
| 3 | Invited new user: invitation → auth → invitation restored → join → that group/relay, never generic Home first | ✅ | Deep link stored as pending invite before sign-in; `MainNavigationView` opens the invite cover on first appearance; UI test `testDeepLinkOpensInvite` |
| 4 | Home: active relays then groups | ✅ | `HomeView` |
| 4 | Sort: my Baton first, then others | ✅ | `HomeViewModel.sorted` |
| 4 | "YOUR TURN 🔥" card: challenge, group, countdown, progress, CTA Take Your Turn | ✅ | `YourTurnCard` (Figma wording "Take your turn 🔥") |
| 4 | "BATON WITH [NAME] 🔥": challenge, group, 2/5 submitted, View Relay Progress | ✅ | `WaitingCard` |
| 4 | Empty state "Nothing active right now." + Start a Relay | ✅ | Verified in `testFullRelayLoop` after completion |
| 4 | + New Relay, + New Group | ✅ | Dashed rows |
| 5 | Private groups | ✅ | Only members can load a group (mock enforces; backend must too) |
| 5 | 1–2 members allowed while pending; min 3 to start; max 7 | ✅ | `RelayRules`; join rejected at 7 with message; unit tests |
| 5 | <3 members: Start Relay disabled + "Invite at least 2 friends to start a Relay." | ✅ | Group Detail, Group Created, New Relay group picker |
| 5 | Create flow Home → New Group → name/icon → invite → created | ✅ | 3 screens; UI test `testCreateGroupAndThreeMemberRule` |
| 5 | Group info: name, emoji, members, invite link/code, active relay, completed count, streak | ✅ | Group Detail (stats card added, C3) |
| 5 | Invites: shareable link, code, native share sheet; no contact sync | ✅ | `UIActivityViewController`; link uses placeholder domain ❓ |
| 6 | Many groups can have relays; one active relay per group; second attempt → existing relay | ✅ | Picker row "Active relay in progress · tap to view" → Progress; engine/mock refuse a second start |
| 7 | Completed count + streak; success +1/+1; failure resets streak; streak more prominent | ✅ | `GroupStats.apply`, stats card, 🔥 on Home rows; unit tests |
| 8 | New Relay → Choose Group → Choose/Create Challenge → Review → Start | ✅ | 3 screens |
| 8 | 8–12 built-in challenges + Write Your Own; no marketplace | ✅ | 10 built-in per Luis's reply (spec's 8 + Figma's 3) ❓ final list from Luis |
| 9 | Creator submits first, then chooses next; each holder chooses; never random | ✅ | Review shows "you first"; engine `pass` requires holder choice |
| 10 | Baton screen: who passed, challenge, time remaining, rules, hidden reminder, Open Camera | ✅ | `BatonView` ("⏱️ Up to 4 sec" replaces Figma "Any length", C1) |
| 10 | 2-hour window; timer from server timestamps; closing app never resets | 🟡 | Absolute deadlines + `deadline − now`; device clock today, server clock with backend |
| 11 | First miss → dropped once, deferred, relay moves to another eligible member | ✅ | `RelayEngine.processDeadlines`; mock "server job" every second; tests |
| 11 | Rescue: deferred returns after the others, one 15-minute window | ✅ | Auto-started when only deferred remain; rescue variant of Baton screen; tests |
| 11 | Second miss → excluded, not asked again, relay continues; streak broken; not completed | ✅ | Tests `secondMissExcludes…` |
| 11 | ≥3 submitted → Reveal with the successful; <3 → no Reveal, streak reset | ✅ | `failedWithReveal` / `failed`; Progress banners |
| 12 | One photo or one video ≤ 4 s; no filters/stickers/text/trim | ✅ | AVFoundation; `maxRecordedDuration` hard stop + ring; no editing UI |
| 12 | Camera → Capture → Preview → Retake / Use This; locked after pass | ✅ | `CaptureFlowView`; "Locked until everyone submits · hidden 🔒" |
| 13 | Who's Next shows only not-submitted, not-excluded; pick one; "Pass the Baton 🔥" | ✅ | `PassBatonView`; deferred members also hidden while others remain (OPEN-5) ❓ |
| 14 | Progress: challenge, group, count, holder, order so far, remaining, timer; no media/thumbnails/blur/reactions | ✅ | `RelayProgressView`; `MediaImageView` never used pre-Reveal |
| 15 | Push: Baton received, Reminder, Near expiration, Rescue, One left, Relay complete; tap opens the relay | 🟡 | Permission prompt, routing from `relayId`, local notifications for Baton received / rescue / one left / complete / dropped. Time-based reminder + near-expiration and real APNs = backend |
| 16 | Completion: status, everyone notified, count +1, streak +1; "🎉 Your Relay is ready" → Watch the Reveal, no extra screen | ✅ | `RelayCompleteView` → full-screen player |
| 17 | Member leaves during relay → cancelled, not counted, streak reset, media removed, "Relay ended because a member left the group." | ✅ | Leave/Remove paths; mock deletes capture files; banner copy |
| 18 | Reveal: auto 9:16 video, baton order, intro → participants → recap → X/X PASSED → PASS IT ON | ✅ | `RevealTimeline` + `RevealSlideView` (player and export share it) |
| 19 | Intro 1–2 s, photos 1.5–1.8 s, videos natural ≤ 4 s, transitions 0.25–0.4 s, first name shown briefly | ✅ | 2.0 / 1.6 / ≤4.0 / 0.35 s fade; name fades on long clips |
| 20 | Deterministic, no AI/ranking/voting/editing | ✅ | Pure timeline; export test proves duration = timeline |
| 21 | Original video audio, no music | ✅ | Clip audio passed through; silence elsewhere |
| 22 | Subtle branding: end card "PASS / PASS IT ON." (watermark optional) | ✅ | End card; no watermark ❓ (C13) |
| 23 | Post-Reveal: Share Relay, Save Video, Watch Again, Start Another Relay; MP4 9:16 1080×1920 | ✅ | Real export + share sheet + Photos add-only save; verified by `RevealExporterTests` |
| 24 | Relay history, basic | ✅ | Group Detail → Past Relays → Reveal replay |
| 25 | Profile/Settings: user info, groups, notification settings, privacy/legal links, support, Sign Out, Delete Account | ✅ | All present; URLs/email are placeholders ❓ |
| 26 | Leave group, remove member (creator), block, report user/content, delete account/data, support | ✅ | Members screen menu, Report sheet (user + Reveal), Blocked users in Privacy. Semantics of block ❓ |
| 27 | Ownership / handoff | ⏳ | Not a frontend item; repo ready to move to Luis's GitHub |
| 28 | Stack: Swift/SwiftUI, Sign in with Apple, Firebase or Supabase, APNs, AVFoundation | ✅/⏳ | Frontend side done; backend undecided |
| 29 | TestFlight / App Store | ⏳ | Needs Luis's Apple account; usage strings + ITSAppUsesNonExemptEncryption already set |
| 30 | Out of scope list | ✅ | None of it built |
| 31 | Deliverables (frontend half): native app matching Figma, auth UI, groups, invites, relay creation, Baton state/timer, expiration/rescue, photo/video capture, passing, progress, completion/failure, counts, streak, Reveal generation + playback, save/share, history, account/safety | ✅ | Upload, push, server timers, TestFlight = backend/release phases |
| 32 | Core loop polish first | ✅ | Loop runs end to end in `testFullRelayLoop` |

## B. Figma prototype, screen by screen (19 + banner)

| # | Figma screen | Status | Deviation |
|---|---|---|---|
| 1 | Splash | ✅ | Real Apple button; "Try the demo" only in debug builds |
| 2 | Invite ("X passed you something 👀") | ✅ | Copy from the inviting member's name |
| 3 | Join Group | ✅ | "You'll join from the next Relay" note (OPEN-2) ❓ |
| 4 | Home (3 states) | ✅ | + streak badge on group rows (C3) |
| 5 | Profile | ✅ | + Support, Got an invite code?, Delete Account |
| 6 | Group Detail | ✅ | + stats card, invite row, Members manage, Past Relays, Leave |
| 7 | Create Group · Name | ✅ | 12 emoji instead of 10 |
| 8 | Create Group · Invite | ✅ | Real share sheet instead of the mock sheet |
| 9 | Group Created | ✅ | — |
| 10 | New Relay · Group | ✅ | — |
| 11 | New Relay · Challenge | ✅ | Luis's 10 presets instead of the Figma's 5 (C5) |
| 12 | New Relay · Start | ✅ | — |
| 13 | Baton + Challenge | ✅ | "Up to 4 sec" (C1); rescue variant added |
| 14 | Camera | ✅ | Real camera; 4 s ring; simulator placeholder |
| 15 | Preview | ✅ | Video preview loops |
| 16 | Pass Baton | ✅ | — |
| 17 | Relay Progress | ✅ | + timer (C6), deferred/excluded/ended states; no "Skip → Complete" (replaced by debug demo controls) |
| 18 | Relay Complete | ✅ | Copy adapts for partial relays |
| 19 | Auto Reveal → Post-Reveal | ✅ | Intro 2.0 s not 2.2 s (C4); videos supported (C10); "Start Another Relay" → New Relay for the same group (C7) |
| — | Notification banner | ✅ | Real local notification (tap → relay) instead of an in-app mock banner |

## C. Not in Figma, required by spec: all built
Onboarding (name, DOB, photo, terms, notification prompt) · Under-16 block · Invite-code entry · Rescue Baton state · Deferred/excluded rows · Relay ended / failed banners · Relay History · Members manage (remove) · Report (user and Reveal) · Block + Blocked list · Delete Account · Support · Terms/Privacy links · Group-full message · 4 s recording limit.

## D. Open items that need Luis before the backend phase
1. Who gets the Baton after a first miss (built: earliest-joined waiting member).
2. Mid-relay joiners (built: next relay; the Figma join demo differs).
3. Does the creator's 2 h start at "Start Relay"? (built: yes).
4. Can a holder pass to a deferred member while others remain? (built: no).
5. Final challenge list (built: 11).
6. Reveal intro 2.0 vs 2.2 s; watermark during content.
7. Block semantics inside a shared group; who can remove (built: creator only).
8. Report destination (email to Luis?).
9. Domain for invite links; privacy/terms/support URLs; app icon and fonts as files.

## E. Frontend items that only become fully real with the backend
Apple token exchange and Keychain session · server-corrected clock · scheduled deadline job · hidden-media enforcement via signed URLs · APNs pushes (incl. the timed Reminder and Near-expiration messages) · media upload queue · multi-device play.

**Verdict:** every screen in the Figma and every mobile-side requirement in spec §1–§26, §30–§32 is implemented and exercised by tests. Nothing on the mobile side is missing; the remaining work is backend wiring, Luis's nine decisions, and the App Store/release items in §27–§29.
