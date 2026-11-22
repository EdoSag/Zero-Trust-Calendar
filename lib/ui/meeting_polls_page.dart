import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../booking/booking_crypto.dart';
import '../data/calendar_store.dart';
import '../data/find_a_time.dart';
import '../model/calendar_event.dart';
import '../polls/meeting_polls.dart';
import '../polls/poll_crypto.dart';
import '../util/format.dart';
import 'event_details_page.dart';
import 'working_hours_tile.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Meeting polls (K-5): the list, a new poll, and one poll's votes.
class MeetingPollsPage extends ConsumerWidget {
  const MeetingPollsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final polls = ref.watch(meetingPollsProvider);
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(l.meetingPolls)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.newMeetingPoll),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PollEditorPage()),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(l.meetingPollsIntro),
          ),
          ...switch (polls) {
            AsyncData(:final value) when value.isEmpty => [
              ListTile(title: Text(l.pollNone, style: small)),
            ],
            AsyncData(:final value) => [
              for (final p in value)
                ListTile(
                  leading: Icon(p.chosen == null ? Icons.how_to_vote_outlined : Icons.event_available),
                  title: Text(p.title),
                  subtitle: Text(
                    p.chosen == null
                        ? '${l.findATimeLength(p.durationMin)} · ${l.pollTimesCount(p.times.length)}'
                        : l.pollPickedOn(_when(context, p.chosen!)),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => PollDetailsPage(pollId: p.id)),
                  ),
                ),
            ],
            _ => [const LinearProgressIndicator()],
          },
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.pollPrivacy, style: small),
          ),
        ],
      ),
    );
  }
}

String _when(BuildContext context, DateTime t) => '${relativeDay(t)}, ${formatTime(context, t)}';

Future<void> sharePollLink(BuildContext context, MeetingPoll poll) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: context.l10n.pollShareText(poll.title, poll.link),
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Up to [count] free times for a poll, one per day, inside my working
/// hours, from tomorrow on.
List<DateTime> suggestPollTimes({
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  required Map<int, List<(int, int)>> hours,
  required Duration length,
  required DateTime now,
  int count = 3,
}) {
  final from = dayOf(now).add(const Duration(days: 1));
  final slots = freeSlots(
    busy: busyBlocks(events: events, calendars: calendars, from: from),
    from: from,
    now: now,
    length: length,
    hours: hours,
    days: 21,
  );
  final out = <DateTime>[];
  for (final s in slots) {
    if (out.any((o) => sameDay(o, s))) continue;
    // Mid-morning when the day allows it, else the first free time.
    final day = [for (final x in slots) if (sameDay(x, s)) x];
    out.add(day.firstWhere((x) => x.hour >= 10, orElse: () => day.first));
    if (out.length == count) break;
  }
  return out;
}

/// Makes a new poll: title, length, the times to vote on.
class PollEditorPage extends ConsumerStatefulWidget {
  const PollEditorPage({super.key});

  @override
  ConsumerState<PollEditorPage> createState() => _PollEditorPageState();
}

class _PollEditorPageState extends ConsumerState<PollEditorPage> {
  final _title = TextEditingController();
  final _host = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  int _duration = 60;
  List<DateTime>? _times;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _host, _location, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  List<DateTime> _suggested() => suggestPollTimes(
    events: [...?ref.read(eventsProvider).value],
    calendars: ref.read(calendarsProvider).value ?? const [ZtCalendarInfo.personal],
    hours: currentWorkingHours(ref),
    length: Duration(minutes: _duration),
    now: DateTime.now(),
  );

  Future<void> _addTime() async {
    final now = DateTime.now();
    final last = _times!.isEmpty ? now : _times!.last;
    final day = await showDatePicker(
      context: context,
      initialDate: last.isBefore(now) ? now : last,
      firstDate: dayOf(now),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(last));
    if (time == null) return;
    final t = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (_times!.any((x) => x.isAtSameMomentAs(t))) return;
    setState(() => _times = [..._times!, t]..sort());
  }

  Future<void> _save() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
    final times = _times ?? const <DateTime>[];
    if (_title.text.trim().isEmpty) return say(l.pollNeedsTitle);
    if (times.length < 2) return say(l.pollNeedsTimes);
    setState(() => _saving = true);
    try {
      final poll = MeetingPoll(
        id: newPollId(),
        key: newPollKey(),
        privateKey: BookingKeyPair.generate().privateKey,
        title: _title.text.trim(),
        hostName: _host.text.trim(),
        description: _description.text.trim(),
        location: _location.text.trim(),
        durationMin: _duration,
        times: times,
        createdAt: DateTime.now(),
      );
      // Kept (and synced) first, so the link never exists without its key.
      await meetingPollsCollection.save(
        ref.read(ztSyncControllerProvider.notifier),
        await ref.read(ztLocalStoreProvider.future),
        poll,
      );
      await ref.read(pollBackendProvider).savePoll(poll);
      if (!mounted) return;
      final nav = Navigator.of(context);
      await sharePollLink(context, poll);
      nav
        ..pop()
        ..push(MaterialPageRoute<void>(builder: (_) => PollDetailsPage(pollId: poll.id)));
    } on Object catch (e) {
      say(l.couldNotSave('$e'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Suggested once the events are in.
    if (_times == null && ref.watch(eventsProvider).hasValue) _times = _suggested();
    final times = _times ?? const <DateTime>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l.newMeetingPoll),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l.pollCreate),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.pollTitleHint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _host,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.pollHostHint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _location,
              maxLength: 200,
              decoration: InputDecoration(labelText: l.pollLocationHint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _description,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.pollDescriptionHint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [30, 60, 90, 120])
                  ChoiceChip(
                    label: Text(l.findATimeLength(m)),
                    selected: _duration == m,
                    onSelected: (_) => setState(() => _duration = m),
                  ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.pollTimes, style: Theme.of(context).textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(l.pollTimesHint, style: Theme.of(context).textTheme.bodySmall),
          ),
          for (final t in times)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(_when(context, t)),
              subtitle: Text(formatSpan(context, t, t.add(Duration(minutes: _duration)), false)),
              trailing: IconButton(
                tooltip: l.pollRemoveTime,
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _times = [...times]..remove(t)),
              ),
            ),
          if (times.length < pollMaxTimes)
            ListTile(
              key: const ValueKey('poll-add-time'),
              leading: const Icon(Icons.add),
              title: Text(l.pollAddTime),
              onTap: _addTime,
            ),
        ],
      ),
    );
  }
}

/// One poll: the votes per time, sharing, picking the time.
class PollDetailsPage extends ConsumerWidget {
  const PollDetailsPage({super.key, required this.pollId});
  final String pollId;

  Future<void> _pick(BuildContext context, WidgetRef ref, MeetingPoll poll, DateTime time,
      List<PollVote> votes) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.pollPick),
        content: Text(l.pollPickConfirm(_when(context, time))),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(l.pollPick)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final pickedText = l.pollPickedOn(_when(context, time));
    try {
      final event = pollEvent(poll, time, votes, id: const Uuid().v4());
      await ref.read(calendarRepositoryProvider).saveEvent(event);
      final picked = poll.copyWith(chosen: time, eventId: event.id);
      await meetingPollsCollection.save(
        ref.read(ztSyncControllerProvider.notifier),
        await ref.read(ztLocalStoreProvider.future),
        picked,
      );
      // Guests see the picked time; no more votes.
      await ref.read(pollBackendProvider).savePoll(picked, closed: true);
      messenger.showSnackBar(
        SnackBar(content: Text(pickedText), duration: const Duration(seconds: 4)),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.couldNotSave('$e')), duration: const Duration(seconds: 4)),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, MeetingPoll poll) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.pollDelete),
        content: Text(l.pollDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pollBackendProvider).deletePoll(poll.id);
      await meetingPollsCollection.delete(
        ref.read(ztSyncControllerProvider.notifier),
        MeetingPoll.itemIdFor(poll.id),
      );
      nav.pop();
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.couldNotSave('$e')), duration: const Duration(seconds: 4)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final poll = (ref.watch(meetingPollsProvider).value ?? const <MeetingPoll>[])
        .where((p) => p.id == pollId)
        .firstOrNull;
    if (poll == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(l.pollGone)));
    }
    final theme = Theme.of(context);
    final votesAsync = ref.watch(pollVotesProvider(pollId));
    final votes = votesAsync.value ?? const <PollVote>[];
    final tallies = tallyPoll(poll, votes);
    final best = bestTimes(tallies);
    return Scaffold(
      appBar: AppBar(
        title: Text(poll.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(context, ref, poll);
            },
            itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(l.pollDelete))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pollVotesProvider(pollId).future),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                [
                  l.findATimeLength(poll.durationMin),
                  if (poll.location.isNotEmpty) poll.location,
                  l.pollVoteCount(votes.length),
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (poll.chosen == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('poll-share'),
                        onPressed: () => sharePollLink(context, poll),
                        icon: const Icon(Icons.share_outlined),
                        label: Text(l.pollShare),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(l.pollPickedOn(_when(context, poll.chosen!))),
                subtitle: Text(l.pollOpenEvent),
                onTap: poll.eventId == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EventDetailsPage(eventId: poll.eventId!),
                        ),
                      ),
              ),
            if (votesAsync case AsyncError(:final error))
              ListTile(
                leading: Icon(Icons.cloud_off, color: theme.colorScheme.error),
                title: Text(l.pollLoadFailed('$error')),
              ),
            if (votesAsync.isLoading && !votesAsync.hasValue) const LinearProgressIndicator(),
            const Divider(),
            for (final t in tallies)
              _TallyTile(
                tally: t,
                best: best.contains(t.time),
                chosen: poll.chosen != null && poll.chosen!.isAtSameMomentAs(t.time),
                onPick: poll.chosen == null ? () => _pick(context, ref, poll, t.time, votes) : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _TallyTile extends StatelessWidget {
  const _TallyTile({required this.tally, required this.best, required this.chosen, this.onPick});
  final PollTally tally;
  final bool best;
  final bool chosen;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final t = tally.time;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _when(context, t),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (best && !chosen)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Chip(
                    label: Text(l.pollBest),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (chosen)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Icon(Icons.check_circle, color: theme.colorScheme.primary),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${l.pollYesNames(tally.yes.length, tally.yes.isEmpty ? '–' : tally.yes.join(', '))}\n'
            '${l.pollMaybeNames(tally.maybe.length, tally.maybe.isEmpty ? '–' : tally.maybe.join(', '))}',
            style: theme.textTheme.bodySmall,
          ),
          if (onPick != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onPick, child: Text(l.pollPick)),
            ),
        ],
      ),
    );
  }
}
