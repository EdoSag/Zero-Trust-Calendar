import 'package:flutter/material.dart';

import '../util/time_zones.dart';

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
          decoration: const InputDecoration(
            hintText: 'Search city or region',
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
              title: const Text('Phone\'s time zone'),
              subtitle: Text(
                'Follows the phone when you travel (${utcOffsetLabel(null, widget.at)})',
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
