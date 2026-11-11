import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../caldav/caldav_bridge.dart';
import '../data/calendar_store.dart';
import '../data/entries.dart';
import '../data/find_a_time.dart';
import '../data/linked_apps.dart';
import '../data/phone_calendar_sync.dart';
import '../data/shared_calendars.dart';
import '../data/subscriptions.dart';
import '../model/calendar_event.dart';
import '../platform/channels.dart';
import '../reminders/reminders.dart';
import '../ui/guest_actions.dart';
import '../ui/import_sheet.dart';
import '../ui/linked_app_launcher.dart';
import '../ui/linked_pickers.dart';
import '../ui/event_details_page.dart';
import '../ui/home_page.dart';
import '../ui/navigation.dart';
import '../util/format.dart';
import '../widget/my_day_widget.dart';
import '../widget/up_next_widget.dart';
import 'auth_providers.dart';
import 'calendar_settings.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Routes between the shared account screens and the calendar.
///
/// Signed out: sign in or create an account. Signed in but locked (cold
/// start, auto-lock): unlock with the account password or biometrics. A new
/// recovery key is always shown, and confirmed, before the vault opens.
/// The latest home screen widget tap not yet acted on. Set by [AppGate]
/// whether or not the calendar is unlocked; taken by [CalendarHome].
final ValueNotifier<Uri?> pendingWidgetTap = ValueNotifier<Uri?>(null);

class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  /// Stays on the sign-in screen until it hands back a result, even though
  /// Supabase reports the session a moment earlier.
  late bool _signingIn = ref.read(currentUserProvider) == null;
  UnlockResult? _awaitingRecoveryKey;
  StreamSubscription<Uri?>? _widgetTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Widget taps are caught here, above the unlock screen, and kept until
    // CalendarHome is showing, so a tap made while locked still opens the
    // new-event editor once unlocked.
    _widgetTaps = HomeWidget.widgetClicked.listen(
      (uri) {
        if (uri != null) pendingWidgetTap.value = uri;
      },
      onError: (_) {},
    );
    _takeLaunchWidgetTap();
  }

  Future<void> _takeLaunchWidgetTap() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (uri != null) pendingWidgetTap.value = uri;
    } on Object {
      // No widget support here.
    }
  }

  @override
  void dispose() {
    _widgetTaps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A key still waiting behind the recovery-key screen is zeroed when the
  /// app leaves the foreground, so coming back asks for the password.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      final UnlockResult? pending = _awaitingRecoveryKey;
      if (pending != null) {
        pending.dek.fillRange(0, pending.dek.length, 0);
        setState(() => _awaitingRecoveryKey = null);
      }
    }
  }

  Future<void> _onUnlocked(UnlockResult result) async {
    // Calendar shows notes, tasks and contacts from the same account, so it
    // also derives those apps' keys while it holds the account key.
    await ref.read(linkedKeysProvider.notifier).deriveFrom(result.dek);
    if (!mounted) return;
    if (result.newRecoveryKey != null) {
      setState(() {
        _signingIn = false;
        _awaitingRecoveryKey = result;
      });
      return;
    }
    setState(() => _signingIn = false);
    ref.read(vaultControllerProvider.notifier).unlock(result.dek, legacyDek: result.legacyDek);
  }

  void _forgotPassword() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ZtForgotPasswordScreen()),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(vaultControllerProvider, (_, VaultState next) {
      // Don't leave a page open over a locked vault.
      if (next is VaultLocked) {
        Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      }
    });
    ref.listen(currentUserProvider, (_, user) {
      if (user == null) {
        ref.read(vaultControllerProvider.notifier).lock();
        ref.read(reminderSchedulerProvider).cancelAll().ignore();
        clearUpNext().ignore();
        clearMyDay().ignore();
        setState(() => _signingIn = true);
      }
    });

    final UnlockResult? pending = _awaitingRecoveryKey;
    if (pending != null) {
      return ZtRecoveryKeyScreen(
        recoveryKey: pending.newRecoveryKey!,
        onDone: () {
          setState(() => _awaitingRecoveryKey = null);
          ref
              .read(vaultControllerProvider.notifier)
              .unlock(pending.dek, legacyDek: pending.legacyDek);
        },
      );
    }

    if (ref.watch(passwordRecoveryProvider)) {
      return ZtResetPasswordScreen(
        onUnlocked: (UnlockResult result) {
          ref.read(passwordRecoveryProvider.notifier).done();
          _onUnlocked(result);
        },
      );
    }

    // Signing out (from Settings, the unlock screen, or another device)
    // takes this account's events out of Android's calendar.
    ref.listen(currentUserProvider, (prev, next) {
      if (prev != null && next == null) {
        ref.read(calendarSettingsProvider.notifier).update(
          (x) => x.copyWith(phoneCalendarIds: const {}),
        );
        const PhoneCalendarBridge().sync(const []).catchError((Object _) => false);
      }
    });
    final user = ref.watch(currentUserProvider);
    if (user == null || _signingIn) {
      return ZtSignInScreen(onUnlocked: _onUnlocked, onForgotPassword: _forgotPassword);
    }

    if (ref.watch(vaultControllerProvider) is VaultLocked) {
      return ZtUnlockScreen(
        email: user.email,
        onUnlocked: _onUnlocked,
        onSignOut: () => ref.read(accountServiceProvider).signOut(),
        onForgotPassword: _forgotPassword,
      );
    }

    return const CalendarHome();
  }
}

/// The calendar once unlocked: runs sync, keeps reminders, the home widget
/// and "Show on this phone" in step with the events, refreshes subscribed
/// calendars, and handles reminder buttons and files other apps open
/// Calendar with.
class CalendarHome extends ConsumerStatefulWidget {
  const CalendarHome({super.key});

  @override
  ConsumerState<CalendarHome> createState() => _CalendarHomeState();
}

class _CalendarHomeState extends ConsumerState<CalendarHome> {
  StreamSubscription<ReminderTap>? _taps;
  StreamSubscription<void>? _files;
  Timer? _debounce;
  Timer? _hourly;
  String? _lastPhonePayload;

  @override
  void initState() {
    super.initState();
    _taps = ref.read(reminderSchedulerProvider).taps.listen(_onReminder);
    pendingWidgetTap.addListener(_takeWidgetTap);
    _files = IncomingFiles.instance.arrived.listen((_) => _takeFiles());
    // Reminders more than 30 days ahead, and the widget's "next", move on
    // as time passes; subscribed calendars are fetched again.
    _hourly = Timer.periodic(const Duration(hours: 1), (_) {
      _schedule();
      _refreshFeeds();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _schedule();
      _takeFiles();
      _refreshFeeds();
      _takeWidgetTap();
    });
  }

  /// "Up next" and "My day" open today; their + opens a new event. Each tap
  /// is taken once.
  void _takeWidgetTap() {
    final uri = pendingWidgetTap.value;
    if (uri == null || !mounted) return;
    pendingWidgetTap.value = null;
    ref.read(focusedDayProvider.notifier).today();
    if (uri.host == 'new-event') createEvent(context);
    // "My day": its task list opens ZT Tasks.
    if (uri.host == 'tasks') openLinkedApp(LinkedApp.tasks).ignore();
  }

  @override
  void dispose() {
    _taps?.cancel();
    pendingWidgetTap.removeListener(_takeWidgetTap);
    _files?.cancel();
    _debounce?.cancel();
    _hourly?.cancel();
    super.dispose();
  }

  void _refreshFeeds() {
    ref.read(subscriptionServiceProvider).refreshStale().catchError((Object _) {});
  }

  Future<void> _takeFiles() async {
    final files = await IncomingFiles.instance.take();
    for (final f in files) {
      if (!mounted) return;
      await handleIncomingFile(context, ref, f);
    }
  }

  Future<void> _onReminder(ReminderTap tap) async {
    if (!mounted) return;
    final event = await ref.read(calendarRepositoryProvider).event(tap.eventId);
    if (!mounted) return;
    if (tap.occurrence != null) ref.read(focusedDayProvider.notifier).set(tap.occurrence!);
    switch (tap.action) {
      case ReminderAction.map when event != null && event.location.isNotEmpty:
        await openLocation(event.location);
      case ReminderAction.note when event != null && event.noteIds.isNotEmpty:
        final notes = await ref.read(linkedNotesProvider.future);
        final note = notes.where((n) => n.id == event.noteIds.first).firstOrNull;
        if (!mounted) return;
        if (note != null) {
          await showNoteSheet(context, note);
        } else {
          await openLinkedApp(LinkedApp.notes);
        }
      case ReminderAction.late when event != null:
        final contacts = await ref.read(linkedContactsProvider.future);
        if (!mounted) return;
        await sendRunningLate(context, event, guestsOf(event, contacts));
      default:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailsPage(
              eventId: tap.eventId,
              occurrenceStart: tap.occurrence,
            ),
          ),
        );
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _apply);
  }

  Future<void> _apply() async {
    if (!mounted) return;
    final own = ref.read(eventsProvider).value;
    if (own == null) return;
    // Reminders, the widgets and the phone's calendar cover shared
    // calendars too.
    final events = [...own, ...ref.read(sharedEventsProvider)];
    final settings = ref.read(calendarSettingsProvider);
    final calendars = ref.read(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final now = DateTime.now();
    final reminders = remindersFor(
      events,
      now: now,
      showTitles: settings.notificationTitles,
      hiddenCalendars: {for (final c in calendars) if (c.hidden) c.id},
      bodyFor: (e, start) {
        final end = e.allDay
            ? addDays(dayOf(start), (e.duration.inHours / 24).round())
            : start.add(e.duration);
        final when = e.allDay
            ? '${relativeDay(start, now: now)}, ${currentL10n.allDayLower}'
            : '${relativeDay(start, now: now)}, ${formatSpan(context, start, end, false)}';
        return when;
      },
    );
    try {
      await ref.read(reminderSchedulerProvider).sync(reminders);
    } on Object {
      // Notifications unavailable; the calendar itself still works.
    }
    if (!mounted) return;
    final entries = buildEntries(
      range: DateRange(dayOf(now), addDays(dayOf(now), 14)),
      events: [...events, ...ref.read(feedEventsProvider)],
      calendars: calendars,
      contacts: settings.showBirthdays
          ? ref.read(linkedContactsProvider).value ?? const []
          : const [],
    );
    await publishUpNext(
      upNextRows(
        entries,
        now: now,
        showTitles: settings.widgetTitles,
        formatTime: (t) => formatTime(context, t),
      ),
    );
    if (!mounted) return;
    await publishMyDay(
      myDay(
        entries: entries,
        tasks: ref.read(linkedTasksProvider).value ?? const [],
        now: now,
        showTitles: settings.widgetTitles,
        formatTime: (t) => formatTime(context, t),
        date: DateFormat.MMMMEEEEd(currentL10n.localeName).format(now),
      ),
    );
    await _shareBusyTimes(events, calendars, now);
    await _syncPhoneCalendar(events, calendars, settings, now);
  }

  /// "Find a time": keeps this account's busy times (times only) up to
  /// date in each shared calendar where it already shares them. Turning
  /// sharing on or off is only done by the switch, so another phone of the
  /// same account never undoes it.
  Future<void> _shareBusyTimes(
    List<CalendarEvent> events,
    List<ZtCalendarInfo> calendars,
    DateTime now,
  ) async {
    final me = ref.read(accountServiceProvider).currentUserId;
    if (me == null) return;
    final actions = ref.read(sharedCalendarActionsProvider);
    for (final c
        in ref.read(sharedCalendarsProvider).value ??
            const <SharedCalendar>[]) {
      if (c.waiting || !c.busy.any((b) => b.userId == me)) continue;
      try {
        await actions.publishBusy(
          c.spaceId,
          busyBlocks(
            events: events,
            calendars: calendars,
            from: dayOf(now),
            exceptCalendarId: c.id,
          ),
          onlyUpdate: true,
        );
      } on Object {
        // Offline or locked: next time.
      }
    }
  }

  /// "Show on this phone": copies the chosen calendars into Android's
  /// calendar, only when something changed.
  Future<void> _syncPhoneCalendar(
    List<CalendarEvent> events,
    List<ZtCalendarInfo> calendars,
    CalendarSettings settings,
    DateTime now,
  ) async {
    const bridge = PhoneCalendarBridge();
    if (!bridge.supported) return;
    final enabled = settings.phoneCalendarIdsFor(
      ref.read(accountServiceProvider).currentUserId,
    );
    // Nothing on and nothing copied: skip. Otherwise an empty payload
    // removes what an earlier account or setting put there.
    if (enabled.isEmpty && _lastPhonePayload == '[]') return;
    final payload = phoneCalendarPayload(
      events: [...events, ...ref.read(feedEventsProvider)],
      calendars: calendars,
      enabledIds: enabled,
      now: dayOf(now),
    );
    final key = jsonEncode(payload);
    if (key == _lastPhonePayload) return;
    try {
      if (payload.isNotEmpty && !await bridge.hasPermission()) return;
      if (await bridge.sync(payload)) _lastPhonePayload = key;
    } on Object {
      // Calendar provider unavailable: try again on the next change.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Runs sync for the unlocked vault (push, pull, live changes).
    ref.watch(ztSyncControllerProvider);
    // And for every shared calendar (on unlock, live, every 5 minutes).
    ref.watch(ztSpacesProvider);
    // The desktop calendar bridge, when the user turned it on (K16).
    ref.watch(desktopBridgeProvider);
    ref.listen(eventsProvider, (_, _) => _schedule());
    ref.listen(sharedEventsProvider, (_, _) => _schedule());
    ref.listen(linkedTasksProvider, (_, _) => _schedule());
    ref.listen(calendarsProvider, (_, _) => _schedule());
    ref.listen(feedsProvider, (_, _) => _schedule());
    ref.listen(calendarSettingsProvider, (_, _) => _schedule());
    ref.listen(linkedContactsProvider, (_, _) => _schedule());
    // Reminders and the widget carry text in the app's language. The
    // debounce lets the new language load first.
    ref.listen(ztLanguageProvider, (_, _) => _schedule());
    return const HomePage();
  }
}
