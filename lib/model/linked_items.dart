import 'package:flutter/foundation.dart';

/// What Calendar needs of a ZT Notes note. Read from the encrypted Notes
/// items (Notes' `Note.toItemJson`); tolerant of fields newer versions add.
@immutable
class LinkedNote {
  const LinkedNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    return firstLine.isEmpty ? 'Untitled note' : firstLine;
  }

  /// A live note's JSON, or null for notebooks, tags and trashed notes.
  static LinkedNote? fromItem(
    String id,
    Map<String, Object?>? json,
    DateTime updatedAt,
  ) {
    // Notes never carry a `kind`; notebooks and tags do.
    if (json == null || json['kind'] != null) return null;
    if (json['trashedAt'] != null) return null;
    return LinkedNote(
      id: id,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      updatedAt: updatedAt,
    );
  }

  /// JSON for a new note Calendar creates in ZT Notes (same shape as a
  /// note made in Notes itself, so every Notes version can read it).
  static Map<String, Object?> newNoteJson({
    required String title,
    required String body,
    required DateTime now,
  }) => {
    'title': title,
    'body': body,
    'notebookId': null,
    'tagIds': <String>[],
    'createdAt': now.toUtc().toIso8601String(),
  };
}

/// A ZT Tasks task with a due date, shown on the calendar.
@immutable
class LinkedTask {
  const LinkedTask({
    required this.id,
    required this.title,
    required this.due,
    required this.completed,
    required this.hasTime,
    this.repeats = false,
  });

  final String id;
  final String title;
  final DateTime due;
  final bool completed;

  /// False when the due date is just a day (stored at midnight).
  final bool hasTime;

  /// A repeating task: ZT Tasks rolls it on to the next date when it's
  /// ticked off, so Calendar leaves that to ZT Tasks.
  final bool repeats;

  /// JSON for a new ZT Tasks task (same shape as one made in ZT Tasks).
  /// Dates are local times, as ZT Tasks writes them.
  static Map<String, Object?> newTaskJson({
    required String title,
    required DateTime due,
    required bool hasTime,
    String? notes,
    required DateTime now,
  }) {
    final dueAt = hasTime ? due : DateTime(due.year, due.month, due.day);
    return {
      'title': title,
      'description': null,
      'category': null,
      'priority': 'medium',
      'startDate': null,
      'dueDate': dueAt.toIso8601String(),
      'reminderAt': null,
      'recurrence': null,
      'tags': <String>[],
      'notes': notes,
      'links': <String>[],
      'isCompleted': false,
      'isArchived': false,
      'deletedAt': null,
      'completedAt': null,
      'subTasks': <Object?>[],
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      '_v': 1,
    };
  }

  /// [json] (a stored task) ticked off or back on.
  static Map<String, Object?> completedJson(
    Map<String, Object?> json,
    bool completed,
    DateTime now,
  ) => {
    ...json,
    'isCompleted': completed,
    'completedAt': completed ? now.toIso8601String() : null,
    'updatedAt': now.toIso8601String(),
  };

  /// Tasks are ZT Tasks' default collection: items without a `kind`.
  static LinkedTask? fromItem(String id, Map<String, Object?>? json) {
    if (json == null || json['kind'] != null) return null;
    if (json['deletedAt'] != null || json['isArchived'] == true) return null;
    final dueRaw = json['dueDate'];
    if (dueRaw is! String) return null;
    final parsed = DateTime.tryParse(dueRaw);
    if (parsed == null) return null;
    final due = parsed.toLocal();
    final title = (json['title'] as String?)?.trim() ?? '';
    return LinkedTask(
      id: id,
      title: title.isEmpty ? 'Untitled task' : title,
      due: due,
      completed: json['isCompleted'] == true,
      hasTime: !(due.hour == 0 && due.minute == 0) &&
          !(due.hour == 23 && due.minute == 59),
      repeats: json['recurrence'] != null,
    );
  }
}

/// A ZT Contacts contact: a guest to pick, and their birthdays.
@immutable
class LinkedContact {
  const LinkedContact({
    required this.id,
    required this.name,
    this.emails = const [],
    this.phones = const [],
    this.birthdays = const [],
  });

  final String id;
  final String name;
  final List<String> emails;
  final List<String> phones;

  /// (month, day, year or null).
  final List<(int, int, int?)> birthdays;

  static LinkedContact? fromItem(String id, Map<String, Object?>? json) {
    if (json == null || json['kind'] != 'contact') return null;
    if (json['deletedAt'] != null || json['trashedAt'] != null) return null;
    String str(Object? v) => v is String ? v.trim() : '';
    List<String> strs(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    var name = str(json['displayName']);
    if (name.isEmpty) {
      name = '${str(json['firstName'])} ${str(json['lastName'])}'.trim();
    }
    if (name.isEmpty) name = str(json['company']);
    final emails = strs(json['emails']);
    final phones = strs(json['phones']);
    if (name.isEmpty) name = emails.isNotEmpty ? emails.first : '';
    if (name.isEmpty) return null;
    return LinkedContact(
      id: id,
      name: name,
      emails: emails,
      phones: phones,
      birthdays: [
        for (final b in strs(json['birthdays']))
          if (parseBirthday(b) case final (int, int, int?) d) d,
      ],
    );
  }

  /// `1990-04-12`, `--04-12` (no year) or any date [DateTime] can parse.
  static (int, int, int?)? parseBirthday(String raw) {
    final v = raw.trim();
    final noYear = RegExp(r'^--(\d{2})-?(\d{2})$').firstMatch(v);
    if (noYear != null) {
      final m = int.parse(noYear.group(1)!);
      final d = int.parse(noYear.group(2)!);
      return _valid(m, d) ? (m, d, null) : null;
    }
    final full = RegExp(r'^(\d{4})-?(\d{2})-?(\d{2})').firstMatch(v);
    if (full != null) {
      final y = int.parse(full.group(1)!);
      final m = int.parse(full.group(2)!);
      final d = int.parse(full.group(3)!);
      // vCard uses 1604 (and some apps 0000) for "year unknown".
      return _valid(m, d) ? (m, d, y <= 1604 ? null : y) : null;
    }
    final parsed = DateTime.tryParse(v);
    return parsed == null ? null : (parsed.month, parsed.day, parsed.year);
  }

  static bool _valid(int m, int d) => m >= 1 && m <= 12 && d >= 1 && d <= 31;
}
