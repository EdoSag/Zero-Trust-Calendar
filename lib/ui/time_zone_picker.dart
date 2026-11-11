import 'package:flutter/material.dart';

import '../util/time_zones.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Picks an IANA time zone. Returns '' for "the phone's time zone", the
/// zone id, or null when cancelled.
Future<String?> pickTimeZone(
  BuildContext context, {
  required String? current,
  required DateTime at,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => _TimeZonePage(current: current, at: at),
  ),
);

class _TimeZonePage extends StatefulWidget {
  const _TimeZonePage({required this.current, required this.at});
  final String? current;
  final DateTime at;

  @override
  State<_TimeZonePage> createState() => _TimeZonePageState();
}

class _TimeZonePageState extends State<_TimeZonePage> {
  late final List<String> _all = allZoneIds();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().replaceAll(' ', '_');
    final shown = q.isEmpty
        ? _all
        : [for (final id in _all) if (id.toLowerCase().contains(q)) id];
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l10n.searchCityOrRegion,
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      body: ListView.builder(
        itemCount: shown.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text(context.l10n.phonesTimeZone),
              subtitle: Text(
                context.l10n.followsPhoneZone(utcOffsetLabel(null, widget.at)),
              ),
              selected: widget.current == null,
              onTap: () => Navigator.of(context).pop(''),
            );
          }
          final id = shown[i - 1];
          return ListTile(
            title: Text(zoneCity(id)),
            subtitle: Text('$id · ${utcOffsetLabel(zoneFor(id), widget.at)}'),
            selected: id == widget.current,
            onTap: () => Navigator.of(context).pop(id),
          );
        },
      ),
    );
  }
}
