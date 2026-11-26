# Zero-Trust Calendar

An end-to-end encrypted calendar, linked to your notes, tasks and contacts.
On the phone it is called **ZT Calendar**; in stores and on release pages,
**Zero-Trust Calendar**. Same account, settings and look as the other
Zero-Trust apps, built on
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core). Part of the
[Zero-Trust suite](https://zerotrust.bz).

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
  - **ZT Tasks:** tasks with a due date show on the calendar. Tick them off
    from the calendar, or add a new task with its due date (quick add).
    Repeating tasks are completed in ZT Tasks, which rolls them forward.
  - **ZT Contacts:** pick guests from your contacts (call or email them from
    the event), and see contacts' birthdays.
- **Import from Google Calendar:** Google Takeout's Calendar .zip (every
  calendar in it becomes a ZT calendar) or any .ics file (Apple, Outlook,
  Proton). Repeating events, changed and cancelled occurrences, time zones
  and reminders come across. Importing the same file again skips what's
  already there. **Export** everything as one .ics file.
- **Home-screen widget** (Android): "Up next", the next five events.
- **Drag and drop** (week, 3 days, day): long-press an event to move it,
  drag its bottom edge to change its length, long-press an empty slot to
  create one there. Snaps to 15 minutes; Undo; repeating events ask "this
  event / following / all".
- **Time zones:** each timed event can have its own zone (a flight that
  lands in New York). The editor shows its local time and yours.
- **Quick add:** type "Lunch with Dana Fri 1pm at Cafe Noir" or
  "מחר ב-13:00 פגישה" (English and Hebrew: dates, times, ranges,
  durations, "every Monday", places) and see what it means before adding.
- **Open .ics files and invitations** from mail and other apps ("Open
  with ZT Calendar"): add them to a calendar, update an invitation you
  already added, or remove a cancelled one. `webcal://` links subscribe.
- **Holidays and subscribed calendars:** public holidays by country and
  any .ics link (school, team, sports). Downloaded without your account,
  stored encrypted, refreshed twice a day, read-only.
- **Email invitations:** add guests by email and send a standard .ics
  invitation (or update) from your own mail app; Gmail, Outlook and Apple
  Calendar can accept it. Replies are recorded by hand on the event.
- **Reminder buttons:** Snooze 10 min, Open map, Open note, Running late
  (SMS or email to guests).
- **Video calls and attachments:** a meeting link with a Join button
  (found automatically in imported invitations), and encrypted file
  attachments (25 MB each).
- **Planner** (menu > Planner, off until you set it up): fits your ZT Tasks
  tasks into the free time around your events and plans again when your
  calendar or your tasks change. You choose your work and personal hours,
  which tasks it plans ("Only tasks I switch on" or "All tasks"), the usual
  task length, block sizes, the break after meetings and the most planned
  time per day; a preview shows the plan before anything is saved. Blocks
  are ordinary encrypted events in a "Planned" calendar, so they sync, get
  reminders and show in every view and widget, marked and numbered ("Write
  report (1 of 3)"). Tap a block to mark it done (the last part ticks the
  task off in ZT Tasks), ask for more time, say "Not now", lock it where it
  is or move it; a block you drag is locked where you drop it. When a block
  ends, a notification asks whether you finished, and its buttons work
  while Calendar is locked: the answer is kept on the phone (a block id
  and the button, nothing else) and applied at the next unlock. A task
  that no longer fits before its due date shows in a banner on the
  calendar, with quick fixes. **Habits** keep time for things you do
  regularly (lunch, exercise, or your own): the days, the length, the best
  time and the window it must fit in; each day it gets the free time
  nearest its best time, is shortened or skipped when there's no room, and
  "Skip today" frees the time. A weekly **focus time** goal keeps time in
  your work hours free of meetings. The Planner screen shows the week:
  task time per day, focus time against the goal, and the last seven days
  (task time done, habits kept). Everything is worked out on the phone by the
  `zt_scheduler` package of Zero-Trust-Core: no server, no AI. It plans
  while Calendar is unlocked. The automatic Planner is part of Plus (plan
  feature `planner`, checked on the phone; when the plan can't be checked,
  offline, nothing is held back). On the free plan **Find a time for a
  task** suggests the earliest free time on each of the next days, in work
  hours, personal hours or any time, and adds the task as an ordinary event
  linked to it.
- **Timing a task** (in the Planner): **Start now** on a block or a planned
  task puts the block at this moment and times the work; **Stop** ends it
  at the time really worked and marks it done, so the rest of the task is
  planned again; **Log time worked** adds time already spent, ending now.
  The time is kept as done blocks in the Planned calendar, so it counts
  toward the task and syncs like any event. One block is timed at a time,
  and what is being timed shows across the top of the calendar with Stop.
- **Planned blocks count as busy** (Planner > Calendars that count as busy,
  off by default): booking pages and Find a time treat every planned block
  as taken, not only locked and done ones.
- **AI helper** (Plus, optional, hidden until the server switches it on;
  each part off until you switch it on, after a screen that says what is
  sent): **Guess task lengths** sends a task's title and gets back minutes;
  **Ask the Planner** turns one sentence ("I'm sick today, move
  everything") into changes from a fixed menu (a task's length, priority,
  due date or "not before"; lock, release or mark a block done; keep a time
  free; change one day's hours; add a habit). Every change is shown with a
  check box and what it does to the plan, nothing is applied until you tap
  Apply, and Undo puts it back. **Hide titles** sends labels (Task A, Event
  B) instead of titles. The request goes to the `planner-ai` function of
  Zero-Trust-Core, which checks the plan and a monthly limit and keeps only
  counts, never the text. The Planner itself still places every block.
- **Mark as done:** any event of yours can be ticked off on its page, and
  is then shown crossed out (a repeating event one day at a time).
- **Show on this phone** (optional, per calendar, off by default): copies
  events into Android's own calendar so Wear OS, Android Auto and other
  apps can see them.
- **Shared calendars:** invite people by link or QR code; everyone you
  invite sees and edits its events, end-to-end encrypted with a key only
  the members' phones hold. A family calendar is one calendar for the
  whole household, and a ZT Family circle's calendar also shows in that
  circle's family hub. "Share when I'm busy"
  shows members when you're busy in your other calendars (times only,
  never titles), so Find a time works.
- **Booking pages:** share a link (`https://zerotrust.bz/book/#…`) and
  people pick a free time, which goes straight into your calendar.
- **Meeting polls:** propose a few times, send the link
  (`https://zerotrust.bz/poll/#…`) and pick the time once guests have
  voted.
- **Jewish calendar** (optional): Hebrew dates, holidays and Shabbat
  times, worked out on the phone.
- **Desktop calendar apps** (Settings, off by default): the phone itself
  serves your visible calendars, read-only, to Thunderbird, Apple Calendar
  or Evolution over CalDAV on the home or office Wi-Fi. No server is
  involved, and it stops when the app locks.

## Privacy

Like every Zero-Trust app, it is zero-knowledge: your data is encrypted on
your device, with keys made from your password, before anything is sent.
The server stores only ciphertext and your password itself is never
sent, so neither we nor anyone who breaks into the server can read your
data. The recovery key shown at sign-up is the only way back in if you
forget the password. How the keys work:
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core#key-hierarchy) and
[zerotrust.bz/security](https://zerotrust.bz/security/).

- Events and calendars are items in the shared `vault_items` table,
  encrypted on the device with the Calendar app key (`app = 'calendar'`).
  No database change was needed. Old and new accounts sign in exactly as in
  the other apps.
- Notes, tasks and contacts are read with those apps' own keys, derived from
  the account key at unlock and zeroed at lock, into Calendar's own
  encrypted copies on the phone (`calendar_notes`, `calendar_tasks`,
  `calendar_contacts`). Contacts is strictly read-only (uploads throw).
  Notes is only ever written to create a new note. Tasks is written only to
  create a task or tick one off or on.
- What leaves the vault, and only when needed: reminder notifications carry
  the event title (turn off in Settings so they only say "Event"; on the lock
  screen Android hides the content anyway). The home widget shows only times
  unless you turn on titles in Settings. The .ics export is a plain file and
  the app says so before exporting.
- Reminder buttons that need event details (map, note, guests) open the
  app first, so places, notes and guests never reach the notification.
- An emailed invitation is a plain .ics file handed to your mail app; the
  app says so before sending.
- Subscribed and holiday calendars are fetched straight from their address
  with no account or cookie; the copy is stored encrypted like events.
- "Show on this phone" copies title, time and place (not descriptions,
  guests, notes or attachments) unencrypted into a local Android calendar
  that isn't synced anywhere. Turning it off removes them.
- A shared calendar's server rows say that it exists and who is in it,
  never its name or events. Files and linked notes stay private to whoever
  added them.
- For a booking page, the server sees when you're busy (start and end
  only, never titles) so it can offer free times. Visitors' names, emails
  and notes are encrypted on their device to the page's key, so only your
  phones can read them.
- A meeting poll and its votes are encrypted with a key that is only in
  the link, so the server can't read them.
- The desktop bridge answers only local-network addresses, only with its
  password, and only to read. A computer keeps the copy it last read,
  unencrypted, in its calendar app.

## One account, one core

One Zero-Trust account opens every app in the suite. Sign-in, unlock
(fingerprint or face, auto-lock), the recovery key, settings, the look,
sync and languages come from
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core), so they work
the same in every app. Accounts made before the core still sign in and
see their data.

## Install

Android: get the latest signed APK from this repository's
[Releases](https://github.com/EdoSag/Zero-Trust-Calendar/releases/latest),
or from [zerotrust.bz/install](https://zerotrust.bz/install/#calendar),
which also shows each file's SHA-256, the signing fingerprint and an
Obtainium link. GitHub Releases are the main way the apps are published.

Builds from GitHub check for a newer release themselves (Settings > About,
one anonymous request a day, can be turned off). Every Zero-Trust app is signed
with the same key, and Android only installs an update signed with it.

## Languages

English and Hebrew, with right-to-left layout. Choose under
Settings > Appearance > Language. Quick add reads both languages.

## Build from source

Flutter 3.47.9, the version CI pins (3.50 deprecates `material.dart` and
fails analyze).

```bash
# .env (not committed; CI writes its own). Public client values only:
# never a service-role key, because .env is bundled into the APK.
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<publishable key>

flutter pub get
dart run zt_release_checks --app calendar   # shared release checks
flutter analyze && flutter test test/
flutter run
```

Never add `cryptography_flutter`: it breaks the core's key derivation and
sign-in fails.

Launcher icons are drawn from the suite's brand mark:
`flutter test tool/launcher_icon_test.dart`.

## Branches and releases

Work happens on `Dev`: pull requests target `Dev`, never `main`, and get a
test build. A release is one `Dev` → `main` pull request. Every push to
`main` runs the suite's release checks, builds a signed APK and a Google Play bundle
and publishes them as a GitHub Release named "Zero-Trust Calendar"
(`.github/workflows/android-apk.yml`). The workflow needs the repository
secrets `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD`, the
keystore shared by all Zero-Trust apps.

## Google Play

- `USE_EXACT_ALARM` is declared: Play allows it for calendar apps, so
  reminders are on time without asking for the exact-alarm permission.
- Data safety: events stay on the device or end-to-end encrypted.

## Support and security

- Help centre: [zerotrust.bz/help](https://zerotrust.bz/help/). Questions and
  account deletion: support@zerotrust.bz.
- Security problems: please report them privately to cyber@zerotrust.bz. What
  the encryption does and doesn't protect against is on
  [zerotrust.bz/security](https://zerotrust.bz/security/).
- [Privacy policy](https://zerotrust.bz/privacy/) and
  [terms](https://zerotrust.bz/terms/).

## License

Copyright (C) 2026 Edo Sagron (https://zerotrust.bz)

Zero-Trust is open source under the [GNU Affero General Public License v3.0](LICENSE)
(AGPL-3.0-only), the same licence Signal uses.

- You may use, study, change and share the code, including in your own projects.
- If you share a changed version, or run it for other people over a network, you must
  publish your full source code under the same licence.
- This program comes with no warranty; see the licence for details.

Third-party libraries keep their own licences; the app lists them under
Settings > Open-source licences.

### Name and logo

The AGPL covers the code, not the brand. "Zero-Trust", "ZT", the app names and icons are
reserved. If you publish a fork, give it a different name and icon so nobody mistakes it
for an official Zero-Trust app.

### Servers

The official apps use the Zero-Trust servers. A fork must use its own backend (for
example its own Supabase project) and must not connect to the official servers.

### Contributing

Pull requests are welcome. By sending one you agree that your contribution is licensed
under the AGPL-3.0 and that the copyright holder may also license it under other terms,
including commercially. This keeps the project able to offer paid plans and other licences.
