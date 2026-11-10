import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../model/linked_items.dart';

/// The sibling apps whose data Calendar shows: notes linked to events, tasks
/// with due dates, contacts as guests and their birthdays.
enum LinkedApp {
  notes('notes', 'dev.sagron.zerotrustnotes', writable: true),
  tasks('tasks', 'dev.sagron.zerotrusttasks', writable: true),
  contacts('contacts', 'dev.sagron.zerotrustcontacts');

  const LinkedApp(this.appId, this.androidPackage, {this.writable = false});

  /// The app's id: its HKDF label and `vault_items.app` value.
  final String appId;
  final String androidPackage;

  /// Calendar writes to Notes only to create a new note ("Meeting notes"
  /// for an event), and to Tasks only to create a task or tick one off. It
  /// never writes Contacts.
  final bool writable;
}

/// The other apps' keys for the unlocked account, derived from the account
/// key at unlock (see AppGate) and zeroed when the vault locks.
final linkedKeysProvider =
    NotifierProvider<LinkedKeys, Map<LinkedApp, Uint8List>>(LinkedKeys.new);

class LinkedKeys extends Notifier<Map<LinkedApp, Uint8List>> {
  @override
  Map<LinkedApp, Uint8List> build() {
    ref.listen(vaultControllerProvider, (_, VaultState next) {
      if (next is VaultLocked) clear();
    });
    ref.onDispose(_zero);
    return const {};
  }

  /// Derives each linked app's key from [dek]. Doesn't take ownership of
  /// [dek].
  Future<void> deriveFrom(Uint8List dek) async {
    final keys = <LinkedApp, Uint8List>{
      for (final app in LinkedApp.values)
        app: await KeyHierarchy.appKey(dek, app.appId),
    };
    _zero();
    state = keys;
  }

  void clear() {
    _zero();
    state = const {};
  }

  void _zero() {
    for (final key in state.values) {
      key.fillRange(0, key.length, 0);
    }
  }
}

/// Lets the engine pull another app's items but never upload: Calendar
/// only reads Tasks and Contacts.
class ReadOnlySyncBackend implements SyncBackend {
  ReadOnlySyncBackend(this.inner);
  final SyncBackend inner;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) =>
      inner.pull(app, since: since);

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) =>
      inner.fetch(app, itemIds);

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    if (items.isNotEmpty) {
      throw StateError('Calendar never writes $app items');
    }
    return <String>{};
  }

  @override
  Future<void> Function() subscribe(
    String app,
    void Function(RemoteItem) onChange,
  ) => inner.subscribe(app, onChange);
}

/// Calendar's own encrypted copy of a sibling app's items, opened with that
/// app's key and kept up to date from the account. Separate from the other
/// app's own file; deleting it loses nothing.
final linkedMirrorProvider = FutureProvider.family<LinkedMirror, LinkedApp>((
  ref,
  app,
) async {
  final unlocked = ref.watch(linkedKeysProvider.select((m) => m[app]));
  if (unlocked == null) throw const VaultIsLocked();
  final key = Uint8List.fromList(unlocked);
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    key.fillRange(0, key.length, 0);
  });
  final userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  final path = await ZtLocalStore.pathFor(
    appId: 'calendar_${app.appId}',
    userId: userId,
  );
  ZtLocalStore store;
  try {
    store = await ZtLocalStore.open(appKey: key, path: path);
  } on LocalStoreUnreadable {
    await ZtLocalStore.moveAside(path);
    store = await ZtLocalStore.open(appKey: key, path: path);
  }
  final deviceId = await ref.watch(ztDeviceIdProvider.future);
  final backend = ref.watch(ztSyncBackendProvider);
  final engine = await ItemSyncEngine.fromVault(
    appId: app.appId,
    appKey: key,
    deviceId: deviceId,
    store: store,
    backend: app.writable ? backend : ReadOnlySyncBackend(backend),
  );
  final mirror = LinkedMirror(app: app, store: store, engine: engine);
  if (disposed) {
    await mirror.close();
    throw const VaultIsLocked();
  }
  ref.onDispose(mirror.close);
  mirror.start();
  return mirror;
});

class LinkedMirror {
  LinkedMirror({required this.app, required this.store, required this.engine});

  final LinkedApp app;
  final ZtLocalStore store;
  final ItemSyncEngine engine;
  AppLifecycleListener? _lifecycle;
  final _refreshed = StreamController<void>.broadcast();

  /// Pulls now, then follows live changes, and pulls again on resume.
  void start() {
    refresh().ignore();
    engine.startLive();
    _lifecycle = AppLifecycleListener(onResume: () => refresh().ignore());
  }

  Future<void> refresh() async {
    try {
      await engine.sync();
    } on Object {
      // Offline: what's already on this device still shows.
    }
    if (!_refreshed.isClosed) _refreshed.add(null);
  }

  Stream<List<LocalItem>> watch() async* {
    yield await store.liveItems();
    await for (final _ in _merge(store.changes, _refreshed.stream)) {
      yield await store.liveItems();
    }
  }

  /// Creates a new item (never overwrites one) and pushes it.
  Future<String> create(Map<String, Object?> json) async {
    if (!app.writable) throw StateError('Calendar never writes ${app.appId}');
    final id = const Uuid().v4();
    await engine.save(id, json);
    refresh().ignore();
    return id;
  }

  /// Ticks a ZT Tasks task off (or back on), changing only `isCompleted`,
  /// `completedAt` and `updatedAt` and keeping every other field as stored.
  Future<void> setTaskCompleted(String id, bool completed) async {
    if (app != LinkedApp.tasks) throw StateError('Only tasks are ticked off');
    final item = await store.get(id);
    final json = item?.json;
    if (item == null || item.deleted || json == null) {
      throw StateError('That task is gone');
    }
    final now = DateTime.now();
    await engine.save(id, LinkedTask.completedJson(json, completed, now));
    refresh().ignore();
  }

  Future<void> close() async {
    _lifecycle?.dispose();
    await _refreshed.close();
    await engine.close();
    await store.close();
  }

  static Stream<void> _merge(Stream<Object?> a, Stream<Object?> b) {
    late final StreamController<void> controller;
    StreamSubscription<Object?>? sa;
    StreamSubscription<Object?>? sb;
    controller = StreamController<void>(
      onListen: () {
        sa = a.listen((_) => controller.add(null));
        sb = b.listen((_) => controller.add(null));
      },
      onCancel: () async {
        await sa?.cancel();
        await sb?.cancel();
      },
    );
    return controller.stream;
  }
}

Stream<List<LocalItem>> _items(Ref ref, LinkedApp app) async* {
  final mirror = await ref.watch(linkedMirrorProvider(app).future);
  yield* mirror.watch();
}

/// ZT Notes notes (not trashed), newest first. Empty until the first pull.
final linkedNotesProvider = StreamProvider<List<LinkedNote>>((ref) async* {
  await for (final items in _items(ref, LinkedApp.notes)) {
    yield [
      for (final i in items)
        ?LinkedNote.fromItem(i.itemId, i.json, i.updatedAt),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
});

/// ZT Tasks tasks that have a due date.
final linkedTasksProvider = StreamProvider<List<LinkedTask>>((ref) async* {
  await for (final items in _items(ref, LinkedApp.tasks)) {
    yield [for (final i in items) ?LinkedTask.fromItem(i.itemId, i.json)];
  }
});

/// ZT Contacts contacts, by name.
final linkedContactsProvider = StreamProvider<List<LinkedContact>>((
  ref,
) async* {
  await for (final items in _items(ref, LinkedApp.contacts)) {
    yield [for (final i in items) ?LinkedContact.fromItem(i.itemId, i.json)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
});
