# Input validation rules (client; the backend must enforce the same)

| Field | Rule | Message |
|---|---|---|
| Display name | trimmed, internal whitespace collapsed, 2–30 characters | "Name is required." / "Name needs at least 2 characters." / "Name can't be longer than 30 characters." |
| Date of birth | not in the future, age ≤ 120, **age ≥ 16** (`RelayRules.minimumAge`) | "You need to be 16 or older to use PASS." → blocked screen |
| Group name | 2–30 characters, same normalisation | as above with "Group name" |
| Group emoji | one of the picker's emoji | — |
| Challenge (write your own) | 3–60 characters | "Challenge needs at least 3 characters." |
| Invite code | `PASS-` + 4 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`; accepts lowercase, spaces, missing prefix, or a full invite link | "That doesn't look like a PASS code. It looks like PASS-AB12." |
| Report details | optional, ≤ 500 characters | "Details can't be longer than 500 characters." |
| Photo | one JPEG, long edge ≤ 1920 px (resized on capture) | — |
| Video | one clip, 0.3 s < length ≤ 4.0 s (hard-stopped by the capture pipeline) | "Hold the button a little longer to record." |

Behaviour: errors appear inline under the field and clear on the next valid submit; the primary button is disabled while
the required field is empty and while a request is in flight (no double submits); valid input is never discarded on a
failed request (the preview keeps the capture, the form keeps its text).
