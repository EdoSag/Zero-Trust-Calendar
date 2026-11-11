import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../data/calendar_store.dart';
import '../data/subscriptions.dart';
import '../model/calendar_event.dart';
import 'caldav_responder.dart';

/// The desktop bridge's login and TLS certificate (K16). Made once per
/// phone and kept in the phone's secure storage, so a desktop app that
/// trusted the certificate keeps working after a restart.
@immutable
class BridgeCredentials {
  const BridgeCredentials({
    required this.username,
    required this.password,
    required this.certPem,
    required this.keyPem,
    required this.fingerprint,
  });

  final String username;
  final String password;
  final String certPem;
  final String keyPem;

  /// SHA-256 of the certificate, as desktop apps show it ("AB:CD:…"), to
  /// check before trusting it.
  final String fingerprint;

  static const _key = 'caldav_credentials';

  Map<String, String> toJson() => {
    'u': username,
    'p': password,
    'c': certPem,
    'k': keyPem,
    'f': fingerprint,
  };

  static BridgeCredentials? fromJson(Object? json) {
    if (json is! Map) return null;
    final m = json.cast<String, Object?>();
    if (m.values.any((v) => v is! String)) return null;
    return BridgeCredentials(
      username: m['u']! as String,
      password: m['p']! as String,
      certPem: m['c']! as String,
      keyPem: m['k']! as String,
      fingerprint: m['f']! as String,
    );
  }

  /// A random password: 20 letters and digits without look-alikes, in
  /// groups of four so it is easy to type on a desktop.
  static String newPassword([Random? random]) {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = random ?? Random.secure();
    final raw = List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
    return [
      for (var i = 0; i < raw.length; i += 4) raw.substring(i, i + 4),
    ].join('-');
  }

  /// A new self-signed P-256 certificate (ten years) and password.
  static BridgeCredentials create() {
    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem(
      {'CN': 'ZT Calendar on this phone', 'O': 'Zero-Trust'},
      priv,
      pub,
    );
    final cert = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
    final sha = X509Utils.x509CertificateFromPem(cert).sha256Thumbprint ?? '';
    final fingerprint = [
      for (var i = 0; i + 1 < sha.length; i += 2)
        sha.substring(i, i + 2).toUpperCase(),
    ].join(':');
    return BridgeCredentials(
      username: 'zt',
      password: newPassword(),
      certPem: cert,
      keyPem: CryptoUtils.encodeEcPrivateKeyToPem(priv),
      fingerprint: fingerprint,
    );
  }

  static Future<BridgeCredentials> loadOrCreate(PreferencesStore store) async {
    try {
      final stored = await store.read(_key);
      if (stored != null) {
        final c = fromJson(jsonDecode(stored));
        if (c != null) return c;
      }
    } on Object {
      // Unreadable: make new ones.
    }
    final made = await compute((_) => create(), null);
    await store.write(_key, jsonEncode(made.toJson()));
    return made;
  }

  /// A new password (desktop apps must log in again); same certificate.
  Future<BridgeCredentials> withNewPassword(PreferencesStore store) async {
    final next = BridgeCredentials(
      username: username,
      password: newPassword(),
      certPem: certPem,
      keyPem: keyPem,
      fingerprint: fingerprint,
    );
    await store.write(_key, jsonEncode(next.toJson()));
    return next;
  }
}

/// Whether [address] is on a home or office network (or this phone), the
/// only places the bridge answers.
bool isLocalAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal) return true;
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
  // IPv6 unique local (fc00::/7).
  return (b[0] & 0xfe) == 0xfc;
}

/// Constant-time check of a `Basic` Authorization header.
bool checkBasicAuth(String? header, String username, String password) {
  if (header == null || !header.startsWith('Basic ')) return false;
  String given;
  try {
    given = utf8.decode(base64.decode(header.substring(6).trim()));
  } on Object {
    return false;
  }
  final want = utf8.encode('$username:$password');
  final got = utf8.encode(given);
  var diff = want.length ^ got.length;
  for (var i = 0; i < want.length; i++) {
    diff |= want[i] ^ (i < got.length ? got[i] : 0);
  }
  return diff == 0;
}

/// Too many wrong passwords from one address: it waits [lockout].
class LoginThrottle {
  LoginThrottle({
    this.maxFailures = 5,
    this.lockout = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxFailures;
  final Duration lockout;
  final DateTime Function() _clock;
  final Map<String, (int, DateTime)> _failures = {};

  bool blocked(String who) {
    final f = _failures[who];
    if (f == null) return false;
    if (_clock().difference(f.$2) > lockout) {
      _failures.remove(who);
      return false;
    }
    return f.$1 >= maxFailures;
  }

  void failed(String who) {
    final f = _failures[who];
    _failures[who] = (f == null ? 1 : f.$1 + 1, _clock());
  }

  void succeeded(String who) => _failures.remove(who);
}

/// The HTTPS server desktop apps talk to. Answers only local addresses,
/// only with the password, and only reads.
class CalDavServer {
  CalDavServer({
    required this.credentials,
    required this.snapshot,
    this.port = defaultPort,
  });

  static const defaultPort = 8443;

  final BridgeCredentials credentials;
  final List<DavCalendar> Function() snapshot;
  final int port;
  final _throttle = LoginThrottle();
  HttpServer? _server;

  int? get boundPort => _server?.port;

  Future<void> start() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(credentials.certPem))
      ..usePrivateKeyBytes(utf8.encode(credentials.keyPem));
    final server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      port,
      context,
    );
    server.idleTimeout = const Duration(seconds: 30);
    _server = server;
    server.listen(_serve, onError: (Object _) {});
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final res = request.response;
    try {
      final from = request.connectionInfo?.remoteAddress;
      if (from == null || !isLocalAddress(from)) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      final who = from.address;
      if (_throttle.blocked(who)) {
        res.statusCode = HttpStatus.tooManyRequests;
        return;
      }
      if (!checkBasicAuth(
        request.headers.value(HttpHeaders.authorizationHeader),
        credentials.username,
        credentials.password,
      )) {
        _throttle.failed(who);
        res.statusCode = HttpStatus.unauthorized;
        res.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Basic realm="ZT Calendar", charset="UTF-8"',
        );
        return;
      }
      _throttle.succeeded(who);
      // Bodies are small XML queries; refuse anything big.
      final bytes = await request.fold<List<int>>([], (all, chunk) {
        if (all.length + chunk.length > 256 * 1024) {
          throw const HttpException('Too large');
        }
        return all..addAll(chunk);
      });
      final answer = CalDavResponder(snapshot()).handle(
        DavRequest(
          method: request.method.toUpperCase(),
          path: request.uri.path,
          depth: request.headers.value('depth'),
          body: utf8.decode(bytes, allowMalformed: true),
        ),
      );
      res.statusCode = answer.status;
      answer.headers.forEach(res.headers.set);
      res.headers.set('Cache-Control', 'no-store');
      if (answer.body.isNotEmpty) res.add(utf8.encode(answer.body));
    } on Object {
      try {
        res.statusCode = HttpStatus.badRequest;
      } on Object {
        // Headers already sent.
      }
    } finally {
      await res.close().catchError((Object _) => null);
    }
  }
}

/// This phone's address on the local network, for the desktop app.
Future<String?> localNetworkAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    // Wi-Fi first, then any other local network (USB or Ethernet).
    interfaces.sort((a, b) {
      int rank(NetworkInterface i) => i.name.startsWith('wlan') ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback && isLocalAddress(a)) return a.address;
      }
    }
  } on Object {
    // No network information.
  }
  return null;
}

@immutable
class DesktopBridgeState {
  const DesktopBridgeState({
    this.enabled = false,
    this.running = false,
    this.address,
    this.port = CalDavServer.defaultPort,
    this.credentials,
    this.error,
  });

  /// The user turned it on (kept on this phone only).
  final bool enabled;
  final bool running;
  final String? address;
  final int port;
  final BridgeCredentials? credentials;
  final String? error;

  String? get url => address == null ? null : 'https://$address:$port/';
}

final desktopBridgeProvider =
    NotifierProvider<DesktopBridgeController, DesktopBridgeState>(
      DesktopBridgeController.new,
    );

/// Runs the bridge while the vault is unlocked and the signed-in account
/// has it on; it stops the moment the vault locks (the events are no longer
/// readable). The switch belongs to the account that turned it on: another
/// account unlocked on this phone finds it off, and turning it on there
/// makes a new password, so a desktop set up for one account never reads
/// another's calendars.
class DesktopBridgeController extends Notifier<DesktopBridgeState> {
  static const _onKey = 'caldav_on';
  CalDavServer? _server;

  /// The account that turned the bridge on, or null when it is off.
  String? _owner;

  /// Bumped by every stop, so a start that was still awaiting when the
  /// vault locked knows to close what it opened.
  int _generation = 0;
  Future<void>? _starting;

  @override
  DesktopBridgeState build() {
    ref.listen(vaultControllerProvider, (_, VaultState next) {
      if (next is VaultUnlocked) {
        state = DesktopBridgeState(
          enabled: _mine,
          credentials: state.credentials,
        );
        if (_mine) _start();
      } else {
        _stop();
      }
    });
    ref.onDispose(() {
      _generation++;
      _server?.stop();
    });
    _load();
    return const DesktopBridgeState();
  }

  PreferencesStore get _prefs => ref.read(ztPreferencesStoreProvider);

  String? get _me => ref.read(accountServiceProvider).currentUserId;

  bool get _mine => _owner != null && _owner == _me;

  bool get _unlocked => ref.read(vaultControllerProvider) is VaultUnlocked;

  Future<void> _load() async {
    try {
      final stored = await _prefs.read(_onKey);
      _owner = stored == null || stored.isEmpty ? null : stored;
      if (_unlocked && _mine) {
        state = DesktopBridgeState(
          enabled: true,
          credentials: state.credentials,
        );
        await _start();
      }
    } on Object {
      // Stays off.
    }
  }

  Future<void> setEnabled(bool on) async {
    final me = _me;
    var credentials = state.credentials;
    if (on && me != null && _owner != null && _owner != me) {
      // Last turned on by another account: its desktop apps must not get in.
      credentials =
          await (credentials ?? await BridgeCredentials.loadOrCreate(_prefs))
              .withNewPassword(_prefs);
    }
    _owner = on ? me : null;
    await _prefs.write(_onKey, _owner ?? '');
    state = DesktopBridgeState(
      enabled: on && me != null,
      credentials: credentials,
      port: state.port,
    );
    if (on && me != null) {
      await _start();
    } else {
      await _stop();
    }
  }

  /// Makes a new password; desktop apps must log in with it.
  Future<void> newPassword() async {
    final c = state.credentials ?? await BridgeCredentials.loadOrCreate(_prefs);
    final next = await c.withNewPassword(_prefs);
    final wasRunning = state.running;
    await _stop();
    state = DesktopBridgeState(enabled: state.enabled, credentials: next);
    if (wasRunning) await _start();
  }

  List<DavCalendar> _snapshot() {
    final calendars =
        ref.read(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final events = ref.read(allEventsProvider).value ?? const [];
    return [
      for (final c in calendars)
        if (!c.hidden)
          DavCalendar(
            info: c,
            events: [
              for (final e in events)
                if (e.calendarId == c.id) e,
            ],
          ),
    ];
  }

  Future<void> _start() {
    if (_server != null) return Future.value();
    return _starting ??= _startOnce().whenComplete(() {
      _starting = null;
      // A stop and a new start came while this one was awaiting: start
      // again for the new state.
      if (_server == null &&
          state.error == null &&
          _unlocked &&
          _mine &&
          state.enabled) {
        _start();
      }
    });
  }

  Future<void> _startOnce() async {
    final generation = _generation;
    bool current() =>
        generation == _generation && _unlocked && _mine && state.enabled;
    try {
      final creds =
          state.credentials ?? await BridgeCredentials.loadOrCreate(_prefs);
      if (!current()) return;
      final server = CalDavServer(credentials: creds, snapshot: _snapshot);
      await server.start();
      if (!current()) {
        // Locked, signed out or switched off while starting.
        await server.stop();
        return;
      }
      _server = server;
      final address = await localNetworkAddress();
      if (_server != server) return;
      state = DesktopBridgeState(
        enabled: true,
        running: true,
        credentials: creds,
        address: address,
        port: server.boundPort ?? CalDavServer.defaultPort,
      );
    } on Object catch (e) {
      if (generation != _generation) return;
      state = DesktopBridgeState(
        enabled: state.enabled,
        credentials: state.credentials,
        error: '$e',
      );
    }
  }

  Future<void> _stop() async {
    _generation++;
    final s = _server;
    _server = null;
    await s?.stop();
    state = DesktopBridgeState(
      enabled: state.enabled,
      credentials: state.credentials,
    );
  }

  /// The network may have changed (another Wi-Fi): read the address again.
  Future<void> refreshAddress() async {
    if (!state.running) return;
    state = DesktopBridgeState(
      enabled: state.enabled,
      running: true,
      credentials: state.credentials,
      port: state.port,
      address: await localNetworkAddress(),
    );
  }
}
