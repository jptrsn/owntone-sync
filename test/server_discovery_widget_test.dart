// Widget tests for the issue-13 server discovery UI (plan TESTS W1–W6).
//
// Harness notes (full constraints in widget_test_helpers.dart, precedent in
// screen_smoke_test.dart): seeding runs in the one plain test() below
// (constraint 1); the shared FFI DB file is check-and-insert only
// (constraint 2); every test ends with _settleTransitions so the binding's
// end-of-test invariant sees no live ticker; and the SyncScreen F1 dispose
// assert (documented in screen_smoke_test.dart) is tolerated exactly —
// only that framework error message, only from sync_screen.dart.
//
// No network and no platform channel anywhere (invariant 36): the scan is
// driven through ServerDiscoveryService's injected source/probe seams, and
// the screen's probe through ServerConfigScreen.probeOverride — the
// discovery EventChannel is never touched when a fake is injected
// (plan VERIFY-LIVE V5).

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/data/repositories/owntone_api_repository.dart';
import 'package:owntone_sync/data/services/server_discovery_service.dart';
import 'package:owntone_sync/presentation/providers/sync_provider.dart';
import 'package:owntone_sync/presentation/screens/server_config_screen.dart';
import 'package:owntone_sync/presentation/screens/sync_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test_helpers.dart';

Map<String, Object?> nsdEvent({
  String serviceType = '_http._tcp',
  String instanceName = 'My Music on hp-server',
  String? host = 'hp-server.local',
  String? ipv4 = '192.168.1.13',
  int port = 3689,
  String machineName = 'My Music',
}) => {
  'serviceType': serviceType,
  'instanceName': instanceName,
  'host': host,
  'ipv4': ipv4,
  'port': port,
  'txt': {'mtd-version': '29.3', 'Machine Name': machineName},
};

/// A screen-local fake: the real service fed by a broadcast controller and
/// an injected probe — no EventChannel, no dio, no network.
class _FakeDiscovery {
  final StreamController<Map<String, Object?>> controller =
      StreamController<Map<String, Object?>>.broadcast();
  final List<String> serviceProbedUrls = <String>[];
  late final ServerDiscoveryService service;

  _FakeDiscovery({
    Future<Object?> Function(String url)? probe,
    Duration window = const Duration(seconds: 30),
  }) {
    service = ServerDiscoveryService(
      sourceFactory: () => controller.stream,
      probe:
          probe ??
          (url) async {
            serviceProbedUrls.add(url);
            return null; // default: any-HTTP-answer verdict
          },
      browseWindow: window,
    );
  }

  void emit(Map<String, Object?> event) => controller.add(event);
}

/// Pumps short frames until no transient frame callback remains
/// (screen_smoke_test.dart's helper, same contract).
Future<void> _settleTransitions(WidgetTester tester) async {
  for (var i = 0;
      i < 20 && SchedulerBinding.instance.transientCallbackCount > 0;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    SchedulerBinding.instance.transientCallbackCount,
    0,
    reason: 'an animation is still running after the settle pumps',
  );
}

/// The screen's own probe seam: records the URL and answers with the
/// shape the user's server really gives — a 400 (invariant 44: any HTTP
/// answer counts).
Future<void> Function(String url) _probeThatAnswers400(List<String> probed) =>
    (url) async {
      probed.add(url);
      throw DioException.badResponse(
        statusCode: 400,
        requestOptions: RequestOptions(path: '$url/api/now-playing'),
        response: Response(
          requestOptions: RequestOptions(path: '$url/api/now-playing'),
          statusCode: 400,
        ),
      );
    };

Future<void> _expandAdvanced(WidgetTester tester) async {
  await tester.tap(find.text('Advanced: enter address manually'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String _urlFieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One seed for the file (constraint 1/2): SyncScreen's initState reads
  // the pending-event count from the DB.
  test('seed: screen fixtures (check-and-insert, never delete)', () async {
    await initWidgetTestDb();
    await seedDetailScreens();
  });

  setUp(() {
    mockAppChannels();
  });

  group('W1 first run is scan-first (AC1; invariants 44, 41/57)', () {
    testWidgets(
      'unconfigured first run renders scan-first actions, order intact, '
      'nothing red',
      (tester) async {
        // Tolerate exactly the documented SyncScreen F1 dispose assert
        // (screen_smoke_test.dart header); everything else propagates.
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          final text = details.toString();
          if (text.contains(
                "Looking up a deactivated widget's ancestor is unsafe.",
              ) &&
              text.contains('sync_screen.dart')) {
            return;
          }
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        SharedPreferences.setMockInitialValues({});
        await pumpScreen(
          tester,
          const SyncScreen(),
          ready: find.text('Scan for servers'),
        );

        // Primary: ElevatedButton 'Scan for servers'; secondary: a visible
        // manual-entry action (maintainer UI decision).
        expect(
          find.widgetWithText(ElevatedButton, 'Scan for servers'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            TextButton,
            'Enter address manually (advanced)',
          ),
          findsOneWidget,
        );
        expect(find.text('Server Not Configured'), findsOneWidget);

        // Invariant 41/57: the unconfigured step is neutral setup — no
        // unreachable wording, no error-coloured text anywhere.
        expect(find.textContaining("Can't reach"), findsNothing);
        final ctx = tester.element(find.text('Server Not Configured'));
        final errorColor = Theme.of(ctx).colorScheme.error;
        expect(
          find.descendant(
            of: find.byType(SyncScreen),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text && widget.style?.color == errorColor,
            ),
          ),
          findsNothing,
        );

        // Invariant 44 order: this is still the unconfigured URL step of
        // the guided flow (folder/playlist steps render only once a URL
        // exists — unchanged container).
        expect(find.text('Storage Permission Required'), findsNothing);

        await _settleTransitions(tester);
        Navigator.of(tester.element(find.byType(SyncScreen))).pop();
        await tester.pump(const Duration(milliseconds: 400));
        await _settleTransitions(tester);
      },
    );
  });

  group('W2 Server screen leads with Scan; manual entry lives under the '
      'Advanced tile (AC9, maintainer UI decision)', () {
    testWidgets(
      'URL field + Test connection absent until the Advanced tile is '
      'tapped, then present',
      (tester) async {
        final fake = _FakeDiscovery();
        addTearDown(fake.service.dispose);
        SharedPreferences.setMockInitialValues({});
        await pumpScreen(
          tester,
          ServerConfigScreen(discovery: fake.service),
          ready: find.text('Scan for servers'),
        );

        expect(
          find.widgetWithText(ElevatedButton, 'Scan for servers'),
          findsOneWidget,
        );
        // Collapsed by default: the manual path is not on screen yet.
        expect(find.text('Test connection'), findsNothing);
        expect(find.text('Server URL'), findsNothing);
        // But always reachable: the tile itself is rendered.
        expect(
          find.text('Advanced: enter address manually'),
          findsOneWidget,
        );

        await _expandAdvanced(tester);
        expect(find.text('Test connection'), findsOneWidget);
        expect(find.text('Server URL'), findsOneWidget);

        // Save is outside the tile (reachable from both modes).
        expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
        await _settleTransitions(tester);
      },
    );
  });

  group('W3 candidate rows (AC2 rendering; AC3/AC5 selectability)', () {
    testWidgets(
      'rows render Machine Name — host:port, verified mark gated, '
      'unverified rows inert',
      (tester) async {
        final serviceProbed = <String>[];
        final fake = _FakeDiscovery(
          // hp-server answers the probe (400 counts, invariant 44); the
          // other announced host never answers at connection level.
          probe: (url) async {
            serviceProbed.add(url);
            if (url == 'http://192.168.1.99:3689') {
              return DioException.connectionError(
                requestOptions: RequestOptions(path: '$url/api/now-playing'),
                reason: 'Connection failed',
                error: SocketException(
                  'Connection failed (OS Error: Connection refused, '
                  'errno = 111), address = 192.168.1.99, port = 3689',
                  address: InternetAddress('192.168.1.99'),
                  port: 3689,
                  osError: const OSError('Connection refused', 111),
                ),
              );
            }
            return null;
          },
        );
        addTearDown(fake.service.dispose);
        SharedPreferences.setMockInitialValues({});
        await pumpScreen(
          tester,
          ServerConfigScreen(discovery: fake.service),
          ready: find.text('Scan for servers'),
        );

        await tester.tap(find.text('Scan for servers'));
        await tester.pump();
        fake.emit(nsdEvent(machineName: 'My Music'));
        fake.emit(
          nsdEvent(
            instanceName: 'ghost',
            host: 'ghost.local',
            ipv4: '192.168.1.99',
            machineName: 'Ghost Server',
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Row grammar: `Machine Name — host:port`.
        expect(
          find.textContaining('My Music — 192.168.1.13:3689'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Ghost Server — 192.168.1.99:3689'),
          findsOneWidget,
        );

        // The verified mark sits on exactly the verified row.
        expect(find.byIcon(Icons.check_circle), findsOneWidget);

        // The unverified row is inert: tapping it changes nothing.
        await tester.tap(find.textContaining('Ghost Server — '));
        await tester.pump();
        await _expandAdvanced(tester);
        expect(_urlFieldText(tester), isEmpty);
        // Close the browse window inside the body (the fake window is 30 s;
        // FakeAsync asserts on timers pending at test end).
        fake.service.stopBrowse();
        await tester.pump();
        await _settleTransitions(tester);
      },
    );
  });

  group('W4 tap fills the field, runs the probe — and saves NOTHING '
      '(AC7; new invariant 58; invariants 37/40)', () {
    testWidgets(
      'tapping a verified row fills the URL field, runs _runProbe with '
      'any-HTTP-answer semantics, and writes no provider/prefs state',
      (tester) async {
        final fake = _FakeDiscovery();
        addTearDown(fake.service.dispose);
        final screenProbed = <String>[];
        SharedPreferences.setMockInitialValues({});
        final provider = SyncProvider();
        await pumpScreen(
          tester,
          ServerConfigScreen(
            discovery: fake.service,
            probeOverride: _probeThatAnswers400(screenProbed),
          ),
          ready: find.text('Scan for servers'),
          syncProvider: provider,
        );

        await tester.tap(find.text('Scan for servers'));
        await tester.pump();
        fake.emit(nsdEvent());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byIcon(Icons.check_circle), findsOneWidget);

        await tester.tap(find.textContaining('My Music — '));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // The tap filled the field (the Advanced tile expanded itself to
        // show it) and the screen's own _runProbe ran against that URL.
        expect(_urlFieldText(tester), 'http://192.168.1.13:3689');
        expect(screenProbed, ['http://192.168.1.13:3689']);
        // The usual verdict renders — the injected 400 is a pass
        // (invariant 44's any-HTTP-answer leg).
        expect(find.text('Connected to 192.168.1.13'), findsOneWidget);

        // ...and NOTHING was saved (the contract under test): the
        // provider never left unconfigured and prefs never gained the
        // key — invariant 58/37.
        expect(provider.serverUrl, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('server_url'), isFalse);
        fake.service.stopBrowse();
        await tester.pump();
        await _settleTransitions(tester);
      },
    );
  });

  group('W5 discovery pick then Save on a different host routes into the '
      'invariant-37 dialog (AC8)', () {
    testWidgets(
      '"Different server?" appears only after Save, "Keep library" is the '
      'primary action, and a tap alone never wipes',
      (tester) async {
        // Sanctioned save in test setup (the only save owner): provider
        // pre-saved to a different host. The apiRepository stub keeps the
        // launch probe off the network (seam pattern:
        // sync_provider_connectivity_test.dart).
        final provider = SyncProvider(
          apiRepository: (baseUrl) => OwnToneApiRepository(
            baseUrl: baseUrl,
            dio: _emptyPlaylistsDio(),
          ),
        );
        await provider.setServerUrl('http://10.0.0.1:3689');

        final fake = _FakeDiscovery();
        addTearDown(fake.service.dispose);
        await pumpScreen(
          tester,
          ServerConfigScreen(
            discovery: fake.service,
            probeOverride: (url) async {},
          ),
          ready: find.text('Scan for servers'),
          syncProvider: provider,
        );

        await tester.tap(find.text('Scan for servers'));
        await tester.pump();
        fake.emit(nsdEvent());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.textContaining('My Music — '));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // A tap alone is not a save and never reaches the wipe machinery:
        // no dialog, and the reset-error negative witness (an
        // uninitialized-provider resetAppData throw would surface as the
        // 'Error resetting data' snackbar) is absent.
        expect(find.text('Different server?'), findsNothing);
        expect(find.textContaining('Error resetting data'), findsNothing);
        expect(provider.serverUrl, 'http://10.0.0.1:3689');

        await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Invariant 37's dialog, with Keep library the primary (Elevated)
        // action.
        expect(find.text('Different server?'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Keep library'),
          findsOneWidget,
        );
        // The wipe dialogs are not up yet — both confirmations are
        // required, in order.
        expect(find.text('Start fresh?'), findsNothing);

        // Cancel routes back without saving.
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(provider.serverUrl, 'http://10.0.0.1:3689');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('server_url'), 'http://10.0.0.1:3689');
        fake.service.stopBrowse();
        await tester.pump();
        await _settleTransitions(tester);
      },
    );
  });

  group('W6 empty and error scans end honestly with the advanced path '
      'usable (AC5 + AC9)', () {
    testWidgets(
      'empty scan: explicit empty state, no leftover spinner, manual '
      'entry still usable',
      (tester) async {
        final fake = _FakeDiscovery(window: const Duration(milliseconds: 60));
        addTearDown(fake.service.dispose);
        SharedPreferences.setMockInitialValues({});
        await pumpScreen(
          tester,
          ServerConfigScreen(discovery: fake.service),
          ready: find.text('Scan for servers'),
        );

        await tester.tap(find.text('Scan for servers'));
        await tester.pump();
        expect(find.textContaining('Scanning the network'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.text('No OwnTone servers found'), findsOneWidget);
        expect(find.textContaining('enter address manually'), findsWidgets);
        // No spinner left spinning, no dead end (AC5).
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // The advanced path never dead-ends (AC9).
        await _expandAdvanced(tester);
        expect(find.text('Test connection'), findsOneWidget);
        expect(find.text('Server URL'), findsOneWidget);
        await _settleTransitions(tester);
      },
    );

    testWidgets(
      'scan error: neutral error text, manual entry still usable',
      (tester) async {
        final fake = _FakeDiscovery(window: const Duration(seconds: 30));
        addTearDown(fake.service.dispose);
        SharedPreferences.setMockInitialValues({});
        await pumpScreen(
          tester,
          ServerConfigScreen(discovery: fake.service),
          ready: find.text('Scan for servers'),
        );

        await tester.tap(find.text('Scan for servers'));
        await tester.pump();
        fake.controller.addError(Exception('NSD start failed'));
        await tester.pump();

        expect(
          find.textContaining('The server scan failed'),
          findsOneWidget,
        );
        // Neutral, not red (invariants 41/57): the scan error text uses
        // no error colour.
        final errorColor = Theme.of(
          tester.element(find.text('Scan for servers')),
        ).colorScheme.error;
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data?.startsWith('The server scan failed') == true &&
                widget.style?.color == errorColor,
          ),
          findsNothing,
        );

        await _expandAdvanced(tester);
        expect(find.text('Test connection'), findsOneWidget);
        expect(find.text('Server URL'), findsOneWidget);
        await _settleTransitions(tester);
      },
    );
  });
}

/// A Dio whose only endpoint resolves the playlists list to empty — the
/// screen-under-test performs no other request.
Dio _emptyPlaylistsDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: <String, dynamic>{'items': <dynamic>[], 'total': 0},
          ),
        );
      },
    ),
  );
  return dio;
}
