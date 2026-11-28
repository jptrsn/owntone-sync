import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../repositories/owntone_api_repository.dart';
import '../../utils/connectivity_state.dart';

/// Lifecycle of one scan ([ServerDiscoveryService.startBrowse]).
enum DiscoveryState { idle, browsing, candidates, empty, error }

/// One DNS-SD service resolved during a scan, before filtering.
///
/// Field-for-field the Map the Kotlin `dev.educoder.owntone_sync/discovery`
/// channel emits per resolved service (issue 13, maintainer spec comment
/// 7172745528). [verified] flips once the candidate's probe answers — any
/// HTTP answer counts (invariant 44), only a connection-level failure (or
/// an unclassifiable one, invariant 39's unknown rule) leaves it false and
/// the row inert.
class DiscoveryCandidate {
  final String serviceType;
  final String instanceName;
  final String? host;
  final String? ipv4;
  final int port;
  final Map<String, String> txt;
  bool verified;

  DiscoveryCandidate({
    required this.serviceType,
    required this.instanceName,
    required this.host,
    required this.ipv4,
    required this.port,
    required this.txt,
    this.verified = false,
  });

  /// `http://<resolved IPv4>:<port>` — the IPv4 literal is preferred over
  /// the `*.local` host name because it survives OEM mDNS-resolution
  /// quirks (maintainer rule); the host name is only the fallback when the
  /// resolved IPv4 is absent, and it still passes `_isLocalAddress`.
  String get url => candidateUrl(ipv4: ipv4, host: host, port: port);

  /// The row label's leading part: the TXT `Machine Name` OwnTone
  /// advertises, falling back to the instance name (usually identical on
  /// OwnTone; the measured TXT carries it).
  String get displayName {
    final machineName = txt['Machine Name'];
    if (machineName != null && machineName.isNotEmpty) return machineName;
    return instanceName;
  }

  /// The host part shown in the row: resolved IPv4 preferred.
  String get displayHost =>
      (ipv4 != null && ipv4!.isNotEmpty)
          ? ipv4!
          : ((host != null && host!.isNotEmpty) ? host! : '?');
}

/// The candidate URL builder, exposed as a top-level pure function so the
/// unit tests exercise the getter's logic directly (frozen spec: "one
/// pure-Dart helper" — filter/dedupe/URL-building).
String candidateUrl({String? ipv4, String? host, required int port}) {
  final h = (ipv4 != null && ipv4.isNotEmpty) ? ipv4 : (host ?? '');
  return 'http://$h:$port';
}

/// The candidate rule (maintainer, measured 2026-11-25 on the user's LAN):
/// OwnTone registers no dedicated DNS-SD type — the generic `_http._tcp`
/// browse returns a dozen unrelated devices (WLEDs, a printer, a
/// doorbell…) — so a candidate is only an OwnTone server when its decoded
/// TXT carries `mtd-version=`. The other half of the rule (the probe) is
/// [ServerDiscoveryService]'s job.
bool isOwnToneTxt(Map<String, String> txt) => txt.containsKey('mtd-version');

/// The (host, port) identity a candidate is deduped by across the two
/// service types (frozen spec: "dedupe by (host, port) across the two
/// types"). One OwnTone server advertises the same instance on both
/// `_http._tcp` and `_daap._tcp`; it must appear exactly once.
String dedupeKey(DiscoveryCandidate candidate) =>
  '${candidate.host ?? candidate.ipv4}:${candidate.port}';

/// Dedupes [candidates] by [dedupeKey], keeping the first arrival of each
/// host:port (pure, so the unit tests pin AC6 without the platform).
List<DiscoveryCandidate> dedupeCandidates(
  Iterable<DiscoveryCandidate> candidates,
) {
  final seen = <String>{};
  final out = <DiscoveryCandidate>[];
  for (final candidate in candidates) {
    if (seen.add(dedupeKey(candidate))) out.add(candidate);
  }
  return out;
}

/// Parses one channel event into a candidate, or null when it is
/// malformed (defensive: a malformed announcer must not break the scan).
DiscoveryCandidate? candidateFromEvent(Map<String, Object?> event) {
  final port = event['port'];
  if (port is! int) return null;
  final rawTxt = event['txt'];
  final txt = <String, String>{};
  if (rawTxt is Map) {
    rawTxt.forEach((key, value) {
      if (key is String) txt[key] = value?.toString() ?? '';
    });
  }
  return DiscoveryCandidate(
    serviceType: event['serviceType'] as String? ?? '',
    instanceName: event['instanceName'] as String? ?? '',
    host: event['host'] as String?,
    ipv4: event['ipv4'] as String?,
    port: port,
    txt: txt,
  );
}

/// The scan's ChangeNotifier (frozen spec: "`class ServerDiscoveryService
/// extends ChangeNotifier`: states browsing / candidates / empty / error").
///
/// Wraps the Kotlin `dev.educoder.owntone_sync/discovery` EventChannel,
/// opens a ~10 s browse window, applies the TXT filter + (host, port)
/// dedupe (both pure top-level functions above), and probe-verifies each
/// candidate **in parallel, non-blocking the list**: rows render
/// unverified and gain their mark as their probe answers. The probe reuses
/// [OwnToneApiRepository.probeConnection] semantics — verified iff
/// [isProbeSuccess], i.e. any HTTP answer counts, this server's 400
/// included (invariant 44); a connection-level failure or an
/// unclassifiable error never verifies (invariants 39/44).
///
/// The two platform touch-points are injectable ([sourceFactory] and
/// [probe]) so the widget/unit tests drive a scan with no platform channel
/// and no network — the [SyncProvider] `apiRepository`-seam pattern.
class ServerDiscoveryService extends ChangeNotifier {
  static const EventChannel _channel = EventChannel(
    'dev.educoder.owntone_sync/discovery',
  );

  /// Frozen spec: a ~10 s browse window. Injectable so tests do not pay it
  /// (A3: the window starts at startBrowse; verified marks are not
  /// window-gated — a probe may still land after the window closes).
  final Duration browseWindow;

  final Stream<Map<String, Object?>> Function() _sourceFactory;
  final Future<Object?> Function(String url) _probe;

  DiscoveryState _state = DiscoveryState.idle;
  List<DiscoveryCandidate> _candidates = <DiscoveryCandidate>[];
  final Set<String> _seenKeys = <String>{};
  Object? _error;
  StreamSubscription<Map<String, Object?>>? _subscription;
  Timer? _windowTimer;
  int _scanId = 0;
  bool _disposed = false;

  ServerDiscoveryService({
    Stream<Map<String, Object?>> Function()? sourceFactory,
    Future<Object?> Function(String url)? probe,
    this.browseWindow = const Duration(seconds: 10),
  }) : _sourceFactory = sourceFactory ?? _defaultSourceFactory,
       _probe = probe ?? _defaultProbe;

  static Stream<Map<String, Object?>> _defaultSourceFactory() => _channel
      .receiveBroadcastStream()
      .map(
        (event) => Map<String, Object?>.from(event as Map<dynamic, dynamic>),
      );

  /// The default probe: one cheap `GET /api/now-playing`, errors returned
  /// (never thrown) for [isProbeSuccess] to judge — any HTTP answer counts
  /// (invariant 44).
  static Future<Object?> _defaultProbe(String url) async {
    try {
      await OwnToneApiRepository(baseUrl: url).probeConnection();
      return null;
    } on Object catch (e) {
      return e;
    }
  }

  DiscoveryState get state => _state;
  List<DiscoveryCandidate> get candidates => List.unmodifiable(_candidates);
  Object? get error => _error;
  bool get isBrowsing => _state == DiscoveryState.browsing;

  /// Starts (or restarts) a scan. Rows arriving inside the window render
  /// immediately, unverified; the window close resolves an
  /// candidate-less scan into the explicit empty state (AC5: never a
  /// spinner, never a dead end).
  void startBrowse() {
    _cancelInternals();
    final scan = ++_scanId;
    _candidates = <DiscoveryCandidate>[];
    _seenKeys.clear();
    _error = null;
    _state = DiscoveryState.browsing;
    notifyListeners();
    _subscription = _sourceFactory().listen(
      (event) => _onEvent(event, scan),
      onError: (Object e, StackTrace stackTrace) {
        if (scan != _scanId || _disposed) return;
        _cancelInternals();
        _error = e;
        // Neutral, not red: a scan surface is not an `unreachable`
        // surface (invariants 41/57).
        _state = DiscoveryState.error;
        notifyListeners();
      },
      onDone: () {
        if (scan != _scanId || _disposed) return;
        if (_state == DiscoveryState.browsing) _endWindow(scan);
      },
    );
    _windowTimer = Timer(browseWindow, () => _endWindow(scan));
  }

  /// Stops the scan (cancel subscription + invalidate pending probes).
  void stopBrowse() {
    _scanId++;
    _cancelInternals();
    _state = DiscoveryState.idle;
    notifyListeners();
  }

  void _onEvent(Map<String, Object?> event, int scan) {
    if (scan != _scanId || _disposed) return;
    final candidate = candidateFromEvent(event);
    if (candidate == null) return;
    // Filter + dedupe (the pure helpers): a candidate must carry
    // mtd-version= and appear once per host:port across the two types.
    if (!isOwnToneTxt(candidate.txt)) return;
    if (!_seenKeys.add(dedupeKey(candidate))) return;
    _candidates.add(candidate);
    // Rows always render (maintainer rule 3 — even exactly one candidate
    // is a row the user must tap); never wait on the probe.
    _state = DiscoveryState.candidates;
    notifyListeners();
    unawaited(_verify(candidate, scan));
  }

  Future<void> _verify(DiscoveryCandidate candidate, int scan) async {
    Object? error;
    try {
      error = await _probe(candidate.url);
    } on Object catch (e) {
      // A probe that throws instead of returning its error is still just
      // an unverified candidate — an unprovable case never reports a
      // false "right" (invariant 39's unknown rule).
      error = e;
    }
    if (scan != _scanId || _disposed) return;
    if (isProbeSuccess(error)) {
      // A3: verified marks are not window-gated.
      candidate.verified = true;
      notifyListeners();
    }
  }

  void _endWindow(int scan) {
    if (scan != _scanId || _disposed) return;
    _cancelInternals();
    _state =
        _candidates.isEmpty ? DiscoveryState.empty : DiscoveryState.candidates;
    notifyListeners();
  }

  void _cancelInternals() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _scanId++;
    _cancelInternals();
    super.dispose();
  }
}
