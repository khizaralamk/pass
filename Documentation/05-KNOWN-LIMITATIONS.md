# Known limitations (frontend phase)

- **No real backend.** Auth, groups, relays, media and notifications are local. Two phones cannot play together yet.
- **Sign in with Apple** shows the official button and accepts the credential, but there is no token exchange/session; the simulator uses "Try the demo".
- **Push notifications** are local only (scheduled by the mock for events that concern you). No APNs registration yet.
- **Timer source** is the device clock with an adjustable offset; the server-corrected clock comes with the backend.
- **Invite links** use the placeholder domain `pass-app.example`; universal links need the real domain + Associated Domains entitlement. The custom scheme `pass://i/CODE` works today.
- **Terms / Privacy / Support** URLs and email are placeholders in `AppConfiguration`.
- **Simulator**: no camera (placeholder photo), no video recording. Emoji rendered as "?" boxes in the iOS 26.3 simulator runtime in our runs; they render on a device.
- **Reveal export** renders at 30 fps on the main actor with yields; a 5-person relay takes roughly 10–20 s on a recent iPhone. Exports are cached per relay/template version.
- **Reveal watermark** during content (spec §22 "possible") is not drawn; only the end card. One constant to add if Luis wants it.
- **Decisions pending Luis** (`00-DISCOVERY.md` §6): who gets the Baton after a miss, mid-relay joiners, creator window, rescue order, deferred members in "Who's next", remove/block semantics, report destination, final challenge list, intro duration.
- **Not built (out of MVP)**: feed, followers, chat, filters, stickers, music, reactions, voting, leaderboards, subscriptions, contact sync.
