import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The answer to "Finished this block?" on the notification a block gets
/// when it ends.
enum PlanAnswerKind {
  /// Done.
  done,

  /// Done, and the task needs more time.
  more,

  /// Didn't do it: the time goes back to the task.
  skip,
}

@immutable
class PlanAnswer {
  const PlanAnswer(this.blockId, this.kind);

  /// The block's event id. An opaque id: no title or time is kept.
  final String blockId;
  final PlanAnswerKind kind;

  Map<String, Object?> toJson() => {'b': blockId, 'a': kind.name};

  static PlanAnswer? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['b'];
    final kind = PlanAnswerKind.values.asNameMap()[json['a']];
    return id is String && id.isNotEmpty && kind != null ? PlanAnswer(id, kind) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlanAnswer && other.blockId == blockId && other.kind == kind;

  @override
  int get hashCode => Object.hash(blockId, kind);

  @override
  String toString() => 'PlanAnswer($blockId ${kind.name})';
}

/// Where answers wait until Calendar is unlocked.
///
/// The buttons on the notification work while Calendar is locked or closed.
/// Nothing can be saved to the encrypted calendar then, so the answer (a
/// block id and which button) is kept on the phone and applied the next
/// time the Planner runs.
abstract interface class PlannerAnswerBox {
  Future<void> add(PlanAnswer answer);

  /// The answers that wait, oldest first; they are removed.
  Future<List<PlanAnswer>> take();

  /// Fires when an answer was added while the app is running.
  Stream<void> get arrived;
}

/// For tests.
class MemoryPlannerAnswerBox implements PlannerAnswerBox {
  final _answers = <PlanAnswer>[];
  final _arrived = StreamController<void>.broadcast();

  @override
  Future<void> add(PlanAnswer answer) async {
    _answers.add(answer);
    _arrived.add(null);
  }

  @override
  Future<List<PlanAnswer>> take() async {
    final out = [..._answers];
    _answers.clear();
    return out;
  }

  @override
  Stream<void> get arrived => _arrived.stream;
}

/// The name the app's main isolate listens under, so a button pressed while
/// the app is open is applied at once.
const _portName = 'zt-calendar-planner-answers';
const _fileName = 'planner_answers.jsonl';

/// Adds [answer] to the file in [directory]: one JSON object per line.
Future<void> appendPlanAnswer(Directory directory, PlanAnswer answer) async {
  await directory.create(recursive: true);
  await File('${directory.path}/$_fileName').writeAsString(
    '${jsonEncode(answer.toJson())}\n',
    mode: FileMode.append,
    flush: true,
  );
}

/// Reads and removes the answers in [directory]. The file is moved aside
/// first, so an answer written meanwhile is never lost.
Future<List<PlanAnswer>> takePlanAnswers(Directory directory) async {
  final file = File('${directory.path}/$_fileName');
  final taking = File('${directory.path}/$_fileName.taking');
  final out = <PlanAnswer>[];
  for (final f in [taking, file]) {
    if (!await f.exists()) continue;
    final source = f == file ? await f.rename(taking.path) : f;
    for (final line in const LineSplitter().convert(await source.readAsString())) {
      if (line.trim().isEmpty) continue;
      try {
        final a = PlanAnswer.fromJson(jsonDecode(line));
        if (a != null) out.add(a);
      } on Object {
        // A line cut short: skipped.
      }
    }
    await source.delete();
  }
  return out;
}

/// Keeps a button press from the notification, in whichever isolate it
/// arrives (the app's, or the one Android starts while the app is closed),
/// and tells the running app, if there is one.
Future<void> recordPlanAnswer(PlanAnswer answer) async {
  try {
    await appendPlanAnswer(await getApplicationSupportDirectory(), answer);
    IsolateNameServer.lookupPortByName(_portName)?.send(null);
  } on Object {
    // Storage unavailable: the block is asked about again in the app.
  }
}

/// The answers kept in the app's own folder on the phone.
class FilePlannerAnswerBox implements PlannerAnswerBox {
  FilePlannerAnswerBox() {
    try {
      IsolateNameServer.removePortNameMapping(_portName);
      IsolateNameServer.registerPortWithName(_port.sendPort, _portName);
      _port.listen((_) => _arrived.add(null));
    } on Object {
      // No isolate names here: answers are picked up on resume.
    }
  }

  final _port = ReceivePort();
  final _arrived = StreamController<void>.broadcast();

  @override
  Future<void> add(PlanAnswer answer) async {
    await appendPlanAnswer(await getApplicationSupportDirectory(), answer);
    _arrived.add(null);
  }

  @override
  Future<List<PlanAnswer>> take() async {
    try {
      return await takePlanAnswers(await getApplicationSupportDirectory());
    } on Object {
      return const [];
    }
  }

  @override
  Stream<void> get arrived => _arrived.stream;

  void close() {
    IsolateNameServer.removePortNameMapping(_portName);
    _port.close();
    _arrived.close();
  }
}

final plannerAnswerBoxProvider = Provider<PlannerAnswerBox>((ref) {
  final box = FilePlannerAnswerBox();
  ref.onDispose(box.close);
  return box;
});
