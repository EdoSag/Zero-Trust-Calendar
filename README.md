# Zero-Trust Calendar

An end-to-end encrypted calendar (on the phone: **ZT Calendar**). Same
account, settings and look as the other Zero-Trust apps, built on
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core).

## What it does

- **Views:** month, week, 3 days, day and schedule (agenda). Swipe between
  months, weeks and days; tap the month name to jump to a date; "Today"
  button; search across titles, places and descriptions (on the device).
- **Events:** all-day and timed, several days long, colours, multiple
  calendars (Personal, Work, …) that can be hidden, locations that open in
  the phone's maps app, descriptions.
- **Repeating events:** every day, week (on chosen weekdays), month (on a
  day or the nth weekday), year, or custom, ending never, on a date or after
  N times. Edit or delete "this event", "this and following" or "all
  events", like Google Calendar.
- **Reminders:** several per event, minutes to weeks before (all-day events:
  at 9:00 on the day or days before). Scheduled with the OS so they fire
  while the app is closed or locked; the next 30 days are kept scheduled.
- **Linked with the other apps:**
  - **ZT Notes:** link notes to an event (agenda, meeting notes, packing
    list), read them from the event, or create a new note for the event.
  - **ZT Tasks:** tasks with a due date show on the calendar (read-only).
  - **ZT Contacts:** pick guests from your contacts (call or email them from
    the event), and see contacts' birthdays.
- **Import from Google Calendar:** Google Takeout's Calendar .zip (every
  calendar in it becomes a ZT calendar) or any .ics file (Apple, Outlook,
  Proton). Repeating events, changed and cancelled occurrences, time zones
  and reminders come across. Importing the same file again skips what's
  already there. **Export** everything as one .ics file.
- **Home-screen widget** (Android): "Up next", the next five events.

## Privacy

- Events and calendars are items in the shared `vault_items` table,
  encrypted on the device with the Calendar app key (`app = 'calendar'`).
  No database change was needed. Old and new accounts sign in exactly as in
  the other apps.
- Notes, tasks and contacts are read with those apps' own keys, derived from
  the account key at unlock and zeroed at lock, into Calendar's own
  encrypted copies on the phone (`calendar_notes`, `calendar_tasks`,
  `calendar_contacts`). Tasks and Contacts are strictly read-only (uploads
  throw). Notes is only ever written to create a new note; Calendar never
  edits an existing one.
- What leaves the vault, and only when needed: reminder notifications carry
  the event title (turn off in Settings so they only say "Event"; on the lock
  screen Android hides the content anyway). The home widget shows only times
  unless you turn on titles in Settings. The .ics export is a plain file and
  the app says so before exporting.

## Google Play

- `USE_EXACT_ALARM` is declared: Play allows it for calendar apps, so
  reminders are on time without asking for the exact-alarm permission.
- Data safety: events stay on the device or end-to-end encrypted.

## Build

Like the other apps: push to `main` builds a signed APK release (see
`.github/workflows/android-apk.yml`); pull requests get a test build. The
repository needs the `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEYSTORE_PASSWORD` secrets, the same shared keystore as the other
apps. Locally, put `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `.env`, then
`flutter run`.

Never add `cryptography_flutter`: it breaks the core's key derivation.

Regenerate the launcher icon with `flutter test tool/launcher_icon_test.dart`.
