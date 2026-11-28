import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/data/services/server_discovery_service.dart';

/// Unit tests for the pure filter/dedupe/URL helpers and the
/// [ServerDiscoveryService] state machine (issue 13, plan TESTS T1–T8).
///
/// Network-free and platform-free by construction (invariant 36): the
/// service is fed by an injected [StreamController] and an injected probe
/// function — the EventChannel and dio are never touched. Each test cites
/// its AC / invariant. Exception shapes are built with dio's own factory
/// constructors, the `server_probe_test.dart` convention.
/// A fixture feed: every startBrowse re-listens to the same broadcast
/// controller; [emit] pushes one event.
class _Harness {
  final StreamController<Map<String, Object?>> controller =
      StreamController<Map<String, Object?>>.broadcast();
  final List<String> probedUrls = <String>[];
  Future<Object?> Function(String url)? probeFn;

  ServerDiscoveryService service({
    Future<Object?> Function(String url)? probe,
    Duration window = const Duration(milliseconds: 60),
  }) => ServerDiscoveryService(
    sourceFactory: () => controller.stream,
    probe: probe ?? probeFn ?? (url) async => null,
    browseWindow: window,
  );

  void emit(Map<String, Object?> e) => controller.add(e);

  Future<void> settle([Duration d = const Duration(milliseconds: 5)]) =>
      Future<void>.delayed(d);
}

void main() {
  /// A resolved-service event in the Kotlin channel's shape:
  /// `{serviceType, instanceName, host, ipv4, port, txt:{...}}`.
  Map<String, Object?> event({
    String serviceType = '_http._tcp',
    String instanceName = 'My Music on hp-server',
    String? host = 'hp-server.local',
    String? ipv4 = '192.168.1.13',
    int port = 3689,
    Map<String, String> txt = const {
      'mtd-version': '29.3',
      'Machine Name': 'My Music on hp-server',
      'Machine ID': 'B20074A5',
    },
  }) => {
    'serviceType': serviceType,
    'instanceName': instanceName,
    'host': host,
    'ipv4': ipv4,
    'port': port,
    'txt': txt,
  };

  group('T1 candidate rule: mtd-version in decoded TXT, single-type feed '
      'still discoverable (AC3/AC10, maintainer candidate rule + invariant '
      '44 TXT-and-probe pairing)', () {
    test('ownTone-shape TXT is kept by isOwnToneTxt', () {
      expect(
        isOwnToneTxt(const {'mtd-version': '29.3', 'Machine Name': 'X'}),
        isTrue,
      );
    });

    test('non-OwnTone TXT is rejected even on _http._tcp', () {
      // The Brother-printer shape measured on the user's LAN: no
      // mtd-version key.
      expect(
        isOwnToneTxt(const {
          'pdl': 'application/postscript',
          'Product': 'Brother HL-L2405W series',
          'scan': 'true',
        }),
        isFalse,
      );
      expect(isOwnToneTxt(const {}), isFalse);
    });

    test('a _daap._tcp-only feed still yields the candidate '
        '(--mdns-no-web leg of AC10)', () async {
      final h = _Harness();
      final service = h.service();
      service.startBrowse();
      h.emit(event(serviceType: '_daap._tcp'));
      await h.settle();
      expect(service.state, DiscoveryState.candidates);
      expect(service.candidates, hasLength(1));
      expect(service.candidates.single.serviceType, '_daap._tcp');
      service.dispose();
    });

    test('an _http._tcp-only feed likewise (--mdns-no-daap leg of AC10)',
        () async {
      final h = _Harness();
      final service = h.service();
      service.startBrowse();
      h.emit(event(serviceType: '_http._tcp'));
      await h.settle();
      expect(service.candidates, hasLength(1));
      service.dispose();
    });

    test('the service drops non-OwnTone announcements before they become '
        'rows (filter is enforced, not just defined)', () async {
      final h = _Harness();
      final service = h.service();
      service.startBrowse();
      h.emit(
        event(
          instanceName: 'wled-1354d3',
          ipv4: '192.168.1.61',
          port: 80,
          txt: const {'id': '"wled-1354d3"', 'name': '"wled-hall"'},
        ),
      );
      h.emit(event());
      await h.settle();
      expect(service.candidates, hasLength(1));
      expect(service.candidates.single.instanceName, 'My Music on hp-server');
      service.dispose();
    });
  });

  group('T2 dedupe by (host, port) across the two types (AC6)', () {
    test('the same host:port on both types dedupes to exactly one '
        'candidate — dedupeCandidates', () {
      final a = DiscoveryCandidate(
        serviceType: '_http._tcp',
        instanceName: 'My Music on hp-server',
        host: 'hp-server.local',
        ipv4: '192.168.1.13',
        port: 3689,
        txt: const {'mtd-version': '29.3'},
      );
      final b = DiscoveryCandidate(
        serviceType: '_daap._tcp',
        instanceName: 'My Music on hp-server',
        host: 'hp-server.local',
        ipv4: '192.168.1.13',
        port: 3689,
        txt: const {'mtd-version': '29.3'},
      );
      expect(dedupeCandidates([a, b]), hasLength(1));
      // Two different ports on one host are two candidates.
      expect(
        dedupeCandidates([
          a,
          DiscoveryCandidate(
            serviceType: '_daap._tcp',
            instanceName: 'My Music on hp-server',
            host: 'hp-server.local',
            ipv4: '192.168.1.13',
            port: 3690,
            txt: const {'mtd-version': '29.3'},
          ),
        ]),
        hasLength(2),
      );
    });

    test('two channel events for one server dedupe through the service',
        () async {
      final h = _Harness();
      final service = h.service();
      service.startBrowse();
      h.emit(event(serviceType: '_http._tcp'));
      h.emit(event(serviceType: '_daap._tcp'));
      await h.settle();
      expect(service.candidates, hasLength(1));
      service.dispose();
    });
  });

  group('T3 candidate URL shape (AC6, maintainer IPv4 rule)', () {
    test('candidate URL is http://<resolved IPv4>:<port> exactly, host '
        'name never appears when ipv4 is present', () {
      expect(
        candidateUrl(ipv4: '192.168.1.13', host: 'hp-server.local', port: 3689),
        'http://192.168.1.13:3689',
      );
      final c = DiscoveryCandidate(
        serviceType: '_http._tcp',
        instanceName: 'x',
        host: 'hp-server.local',
        ipv4: '192.168.1.13',
        port: 3689,
        txt: const {},
      );
      expect(c.url, 'http://192.168.1.13:3689');
      expect(c.url.contains('hp-server.local'), isFalse);
    });

    test('host name is the fallback only when ipv4 is absent (A4)', () {
      expect(
        candidateUrl(ipv4: null, host: 'hp-server.local', port: 3689),
        'http://hp-server.local:3689',
      );
    });
  });

  group('T4/T5 probe verification semantics (invariants 44 and 39)', () {
    DioException badRequest(String url) => DioException.badResponse(
      statusCode: 400,
      requestOptions: RequestOptions(path: '$url/api/now-playing'),
      response: Response(
        requestOptions: RequestOptions(path: '$url/api/now-playing'),
        statusCode: 400,
      ),
    );

    DioException refused(String url) => DioException.connectionError(
      requestOptions: RequestOptions(path: '$url/api/now-playing'),
      reason: 'Connection failed',
      error: SocketException(
        'Connection failed (OS Error: Connection refused, errno = 111), '
        'address = 192.168.1.13, port = 3689',
        address: InternetAddress('192.168.1.13'),
        port: 3689,
        osError: const OSError('Connection refused', 111),
      ),
    );

    test('a 400-answer probe verifies the candidate — any HTTP answer '
        'counts (AC4; invariant 44: the 2xx-requiring bug is exactly the '
        'BREAKS-IF-UNDONE this pins)', () async {
      final h = _Harness();
      h.probeFn = (url) async => badRequest(url);
      final service = h.service();
      service.startBrowse();
      h.emit(event());
      await h.settle();
      expect(service.candidates.single.verified, isTrue);
      expect(h.probedUrls, isEmpty); // injected probe replaced the default
      service.dispose();
    });

    test('the probe is aimed at the candidate URL', () async {
      final h = _Harness();
      h.probeFn = (url) async {
        h.probedUrls.add(url);
        return null;
      };
      final service = h.service();
      service.startBrowse();
      h.emit(event());
      await h.settle();
      expect(h.probedUrls, ['http://192.168.1.13:3689']);
      service.dispose();
    });

    test('a connection-level probe failure never verifies; an '
        'unclassifiable error never verifies (AC5; invariant 39 unknown '
        'rule)', () async {
      for (final failing in <Future<Object?> Function(String)>[
        (url) async => refused(url),
        (url) async => throw refused(url),
        (url) async => const FormatException('Unexpected character'),
        (url) async => throw StateError('probe exploded'),
      ]) {
        final h = _Harness();
        h.probeFn = failing;
        final service = h.service();
        service.startBrowse();
        h.emit(event());
        await h.settle();
        expect(service.candidates.single.verified, isFalse);
        service.dispose();
      }
    });
  });

  group('T6/T7 scan lifecycle states (AC5, AC9)', () {
    test('an empty window ends in the explicit empty state, no error '
        '(AC5; AC10 both-suppressed leg)', () async {
      final h = _Harness();
      final service = h.service(window: const Duration(milliseconds: 40));
      service.startBrowse();
      expect(service.state, DiscoveryState.browsing);
      await h.settle(const Duration(milliseconds: 80));
      expect(service.state, DiscoveryState.empty);
      expect(service.candidates, isEmpty);
      expect(service.error, isNull);
      service.dispose();
    });

    test('a browse error surfaces the error state and a re-scan is '
        'possible (AC9 service-level shape)', () async {
      final h = _Harness();
      final service = h.service(window: const Duration(milliseconds: 40));
      service.startBrowse();
      h.controller.addError(Exception('NSD failure'));
      await h.settle();
      expect(service.state, DiscoveryState.error);
      service.startBrowse();
      expect(service.state, DiscoveryState.browsing);
      service.dispose();
    });

    test('stopBrowse returns to idle and invalidates the window', () async {
      final h = _Harness();
      final service = h.service(window: const Duration(milliseconds: 40));
      service.startBrowse();
      service.stopBrowse();
      expect(service.state, DiscoveryState.idle);
      await h.settle(const Duration(milliseconds: 80));
      expect(service.state, DiscoveryState.idle); // window did not fire
      service.dispose();
    });
  });

  group('T8 probes run in parallel and do not block the list (maintainer '
      '"rows render while probes pending")', () {
    test('three candidates render unverified while probes are pending; '
        'each verified flips independently as its probe answers', () async {
      final completers = <String, Completer<Object?>>{};
      final h = _Harness();
      h.probeFn = (url) {
        final c = Completer<Object?>();
        completers[url] = c;
        return c.future;
      };
      final service = h.service(window: const Duration(seconds: 30));
      service.startBrowse();
      h.emit(event(host: 'a.local', ipv4: '192.168.1.11'));
      h.emit(event(host: 'b.local', ipv4: '192.168.1.12'));
      h.emit(event(host: 'c.local', ipv4: '192.168.1.13'));
      await h.settle();
      // All three rows present while every probe is pending.
      expect(service.state, DiscoveryState.candidates);
      expect(service.candidates, hasLength(3));
      expect(service.candidates.every((c) => !c.verified), isTrue);
      // Answer them out of order; each flips independently.
      completers['http://192.168.1.13:3689']!.complete(null);
      await h.settle();
      expect(
        service.candidates.firstWhere((c) => c.ipv4 == '192.168.1.13').verified,
        isTrue,
      );
      expect(
        service.candidates.firstWhere((c) => c.ipv4 == '192.168.1.11').verified,
        isFalse,
      );
      completers['http://192.168.1.11:3689']!.complete(null);
      await h.settle();
      expect(service.candidates.where((c) => c.verified), hasLength(2));
      service.dispose();
    });
  });
}
