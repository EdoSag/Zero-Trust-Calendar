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
- **Show on this phone** (optional, per calendar, off by default): copies
  events into Android's own calendar so Wear OS, Android Auto and other
  apps can see them.

## Privacy

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

## License

Zero-Trust is **source-available**, not open source. The code is published under the
[PolyForm Noncommercial License 1.0.0](LICENSE):

- You may download, build and use the app yourself, study the code, fork it, change it,
  and share your version for free or for personal, hobby, research or nonprofit use.
- You may not use it, or anything built from it, commercially: no selling it, no paid
  subscriptions, no ads or paid features. Commercial rights stay with the copyright holder.
- When you share the code or a version of it, include the [LICENSE](LICENSE) file and its
  `Required Notice` line.

Third-party libraries keep their own licences; the app lists them under
Settings > Open-source licences.

### Contributing

Pull requests are welcome. By sending one you agree that your contribution is licensed to
the copyright holder under terms that let them use, change and relicense it, including
commercially, and to everyone else under the same licence as this repository.
