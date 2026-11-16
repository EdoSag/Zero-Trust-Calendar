import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/calendar_store.dart';
import '../data/subscriptions.dart';
import '../model/calendar_event.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Subscribe to a calendar by link (a school, team or sports .ics, or a
/// webcal:// link another app opened Calendar with).
Future<void> showSubscribeDialog(
  BuildContext context,
  WidgetRef ref, {
  String? url,
  String? name,
}) async {
  final link = TextEditingController(text: url ?? '');
  final title = TextEditingController(text: name ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(context.l10n.subscribeToACalendar),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: link,
              autofocus: url == null,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: context.l10n.link,
                hintText: 'https://example.com/calendar.ics',
              ),
            ),
            TextField(
              controller: title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.name,
                helperText: context.l10n.leaveEmptyForCalendarsOwnName,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.calendarDownloadsItFromThat,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('feed-link-help'),
                icon: const Icon(Icons.help_outline),
                label: Text(context.l10n.whereDoIFindTheLink),
                onPressed: () => showFeedLinkHelp(d),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(context.l10n.cancel)),
        FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(context.l10n.subscribe)),
      ],
    ),
  );
  final rawUrl = link.text.trim();
  final rawName = title.text.trim();
  link.dispose();
  title.dispose();
  if (ok != true || rawUrl.isEmpty || !context.mounted) return;
  // An empty name takes the calendar's own name from the file.
  await _subscribe(context, ref, rawName, rawUrl);
}

/// Step-by-step help for getting a calendar's private link out of Google
/// Calendar, Outlook and iCloud.
Future<void> showFeedLinkHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (d) {
    final l10n = d.l10n;
    final theme = Theme.of(d);
    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    );
    return AlertDialog(
      title: Text(l10n.getALinkFromAnotherCalendar),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            section(l10n.feedHelpGoogleTitle, l10n.feedHelpGoogle),
            section(l10n.feedHelpOutlookTitle, l10n.feedHelpOutlook),
            section(l10n.feedHelpIcloudTitle, l10n.feedHelpIcloud),
            Text(l10n.feedHelpPrivacy, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(), child: Text(l10n.close)),
      ],
    );
  },
);

Future<void> _subscribe(
  BuildContext context,
  WidgetRef ref,
  String name,
  String url,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final count = (await ref.read(calendarsProvider.future)).length;
  final shown = name.isEmpty ? feedNameFromUrl(url) : name;
  messenger.showSnackBar(SnackBar(content: Text(currentL10n.downloadingName(shown))));
  try {
    final added = await ref.read(subscriptionServiceProvider).subscribe(
      name: name,
      url: url,
      color: calendarPalette[count % calendarPalette.length],
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(currentL10n.subscribedTo(added.name))));
  } on Object catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(currentL10n.couldNotSubscribe('$e'))));
  }
}

/// Public holidays by country, and subscribing by link.
class HolidaysPage extends ConsumerWidget {
  const HolidaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(calendarsProvider).value ?? const <ZtCalendarInfo>[];
    final subscribed = {for (final c in calendars) if (c.url != null) c.url!: c};
    final feeds = {
      for (final f in ref.watch(feedsProvider).value ?? const <CalendarFeed>[]) f.calendarId: f,
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.holidaysAndSubscriptions)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(context.l10n.subscribeByLink),
            subtitle: Text(context.l10n.anyIcsOrWebcalLink),
            onTap: () => showSubscribeDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(context.l10n.whereDoIFindTheLink),
            subtitle: Text(context.l10n.googleOutlookOrIcloud),
            onTap: () => showFeedLinkHelp(context),
          ),
          for (final c in calendars)
            if (c.isSubscription && !holidayCalendars.any((h) => h.url == c.url))
              _SubscriptionTile(calendar: c, feed: feeds[c.id]),
          const Divider(),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              context.l10n.publicHolidaysComeFromGoogles,
            ),
          ),
          for (final h in holidayCalendars)
            if (subscribed[h.url] case final c?)
              _SubscriptionTile(calendar: c, feed: feeds[c.id])
            else
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(holidayRegionName(h.name)),
                trailing: const Icon(Icons.add),
                onTap: () => _subscribe(context, ref, context.l10n.holidaysOf(holidayRegionName(h.name)), h.url),
              ),
        ],
      ),
    );
  }
}

class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile({required this.calendar, required this.feed});
  final ZtCalendarInfo calendar;
  final CalendarFeed? feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = feed;
    return ListTile(
      leading: Icon(Icons.rss_feed, color: Color(calendar.color)),
      title: Text(calendar.name),
      subtitle: Text(
        f == null
            ? context.l10n.downloading
            : f.error != null
            ? context.l10n.lastRefreshFailed('${f.error}')
            : context.l10n.nEvents(f.events.length),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'refresh':
              await ref.read(subscriptionServiceProvider).refresh(calendar);
            case 'remove':
              await ref.read(calendarRepositoryProvider).deleteCalendar(calendar.id);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'refresh', child: Text(context.l10n.refreshNow)),
          PopupMenuItem(value: 'remove', child: Text(context.l10n.unsubscribe)),
        ],
      ),
    );
  }
}
