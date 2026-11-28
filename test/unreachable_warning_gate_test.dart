// The issue-12 red-gate widget net (invariant 57, amended invariant 41):
// the four red 'server unreachable' surfaces (home banner, app-bar red
// badge, drawer 'Server not responding' line, Sync screen red banner)
// render together only after a USER-INITIATED fetch failed classified
// unreachable, and never from the unrequested launch probe; offline stays
// silent and the orange 'Offline - showing cached playlists' banner keeps
// its non-empty condition (invariant 41's honesty rule).
//
// Harness: the `test/widget_test_helpers.dart` + `test/screen_smoke_test.dart`
// pattern — DB seeding in one plain test() first (FakeAsync constraint 1),
// the shared FFI DB file check-and-insert only (constraint 2), the provider
// injected with an interceptor Dio (no network, per the sync_provider
// pattern), and `SharedPreferences.setMockInitialValues` seeding
// `server_url` so the banner names a deterministic host without contact.
//
// Fire-and-forget drives: `fetchPlaylists` awaits the post-classification
// cache load, a DB future — which only completes while pumping (constraint
// 1), so the drives are not awaited from the test body; the pumps advance
// them. The Sync screen's F1 dispose assert (see screen_smoke_test.dart)
// is tolerated exactly as there, with the route popped inside the body.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/data/repositories/owntone_api_repository.dart';
import 'package:owntone_sync/presentation/providers/sync_provider.dart';
import 'package:owntone_sync/presentation/screens/library_screen.dart';
import 'package:owntone_sync/presentation/screens/sync_screen.dart';
import 'package:owntone_sync/utils/connectivity_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test_helpers.dart';

const serverUrl = 'http://192.168.1.13:3689';
final redSentence = describeUnreachable(serverUrl);
const orangeSentence = 'Offline - showing cached playlists';

/// Two playlists in the server's JSON shape (the sync_provider_connectivity
/// / screen_smoke fixture).
const _playlistsJson = <String, dynamic>{
  'items': [
    {
      'id': 1,
      'name': 'radio',
      'path': '/music/radio.m3u',
      'parent_id': '0',
      'type': 'regular',
      'smart_playlist': false,
      'random': false,
      'folder': false,
      'item_count': 12,
      'stream_count': 0,
      'uri': 'library:playlist:1',
    },
    {
      'id': 2,
      'name': 'jazz',
      'path': '/music/jazz.m3u',
      'parent_id': '0',
      'type': 'regular',
      'smart_playlist': false,
      'random': false,
      'folder': false,
      'item_count': 30,
      'stream_count': 0,
      'uri': 'library:playlist:2',
    },
  ],
  'total': 2,
  'offset': 0,
  'limit': 1000,
};

/// The flippable seam: 'refused' rejects with the errno-111 shape
/// (unreachable), 'noRoute' with the errno-101 shape (offline), 'succeed'
/// resolves the two-playlist fixture.
class _GateMode {
  String value;
  _GateMode(this.value);
}

Dio _gateDio(_GateMode mode) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        switch (mode.value) {
          case 'succeed':
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _playlistsJson,
              ),
            );
          case 'noRoute':
            handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: 'Connection failed',
                error: SocketException(
                  'Connection failed (OS Error: Network is unreachable, '
                  'errno = 101), address = 192.168.1.13, port = 3689',
                  address: InternetAddress('192.168.1.13'),
                  port: 3689,
                  osError: const OSError('Network is unreachable', 101),
                ),
              ),
            );
          default:
            handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: 'Connection failed',
                error: SocketException(
                  'Connection failed (OS Error: Connection refused, '
                  'errno = 111), address = 192.168.1.13, port = 3689',
                  address: InternetAddress('192.168.1.13'),
                  port: 3689,
                  osError: const OSError('Connection refused', 111),
                ),
              ),
            );
        }
      },
    ),
  );
  return dio;
}

SyncProvider _providerFor(_GateMode mode) => SyncProvider(
  apiRepository: (baseUrl) =>
      OwnToneApiRepository(baseUrl: baseUrl, dio: _gateDio(mode)),
);

/// Pumps short frames until [condition] holds (never awaiting a DB future
/// directly - constraint 1: the pumps are what let DB work complete).
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition never held within 2 s');
}

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

/// The drawer's open/close animation ticks on a post-frame-registered
/// ticker: a single pump does not advance it (the drawer stays parked
/// off-screen while `isDrawerOpen` is already true) - the transition must
/// be pumped to rest, bounded so a rogue persistent ticker fails loudly
/// instead of hanging the suite.
Future<void> _settleDrawer(WidgetTester tester) async {
  for (var i = 0;
      i < 40 && SchedulerBinding.instance.transientCallbackCount > 0;
      i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openDrawer(WidgetTester tester) async {
  final scaffold = find.descendant(
    of: find.byType(LibraryScreen),
    matching: find.byType(Scaffold),
  );
  tester.state<ScaffoldState>(scaffold).openDrawer();
  await _settleDrawer(tester);
  // Witness that the drawer really is on screen (its content is built
  // even while parked off-screen, so text finds alone prove nothing
  // about visibility).
  expect(
    tester.getTopLeft(find.text('Owntone Player')).dx,
    greaterThan(0),
    reason: 'the drawer never opened on screen',
  );
}

Future<void> _closeDrawer(WidgetTester tester) async {
  final scaffold = find.descendant(
    of: find.byType(LibraryScreen),
    matching: find.byType(Scaffold),
  );
  tester.state<ScaffoldState>(scaffold).closeDrawer();
  await _settleDrawer(tester);
}

/// Open the Sync screen the user's way: drawer → 'Sync' (AC2 names the
/// app-bar icon and the drawer row as the ungated entries; the drawer row
/// is the one that hit-tests reliably here — the badge-icon tap derived an
/// offset the hit test reported as not landing on the icon, and per the
/// harness-blindness rule the reliable sanctioned path is used; the badge
/// itself is asserted by presence, its tap is device row D2's job).
Future<void> _openSyncViaDrawer(WidgetTester tester) async {
  await _openDrawer(tester);
  // Positive control: the drawer is actually on screen
  // (`isDrawerOpen` flips before the ticker moves the panel, so it is
  // not the witness - observed while building this harness).
  expect(
    tester.getTopLeft(find.widgetWithText(ListTile, 'Sync')).dx,
    greaterThanOrEqualTo(0),
    reason: 'the drawer never opened on screen',
  );
  await tester.tap(find.widgetWithText(ListTile, 'Sync'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tolerates the documented F1 dispose assert for every test that pushes
/// the SyncScreen (screen_smoke_test.dart header).
void _tolerateSyncScreenDispose() {
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
}

Future<void> _popSyncScreen(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(SyncScreen))).pop();
  await tester.pump(const Duration(milliseconds: 400));
  await _settleTransitions(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One seed call for the whole file (constraint 2: the quiescence wait is
  // per seed call, and the seeded rows are what 'Brass' renders from).
  test('seed: gate fixtures (check-and-insert, never delete)', () async {
    await initWidgetTestDb();
    await seedDetailScreens();
  });

  setUp(() {
    mockAppChannels();
  });

  testWidgets(
    'W1: unrequested refused fetch at launch renders no red surface while '
    'the state is unreachable (issue 12, AC1; amended invariant 41, '
    'invariant 57)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'server_url': serverUrl});
      final mode = _GateMode('refused');
      final provider = _providerFor(mode);
      await pumpScreen(
        tester,
        const LibraryScreen(),
        ready: find.text('Brass'),
        syncProvider: provider,
      );

      // Harness witness FIRST (AGENTS.md trap): confirm the classifier ran
      // before concluding absence - the unrequested launch probe completed
      // and earned the state (invariant 40).
      await _pumpUntil(
        tester,
        () => provider.connectivityState == ConnectivityState.unreachable,
      );
      expect(provider.connectivityState, ConnectivityState.unreachable);
      expect(provider.unreachableWarningVisible, isFalse);

      // Then the absence: no banner sentence, no red badge icon. The
      // neutral cloud_outlined badge is the positive control proving the
      // badge slot itself renders (harness can see a known-present thing).
      expect(find.text(redSentence), findsNothing);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);

      await _openDrawer(tester);
      // Positive control inside the drawer: the server line renders.
      expect(find.text('192.168.1.13:3689'), findsOneWidget);
      expect(find.text('Server not responding'), findsNothing);
      await _closeDrawer(tester);

      await _settleTransitions(tester);
    },
  );

  testWidgets(
    'W2: a failing user-initiated fetch raises all four surfaces together '
    '(issue 12, AC2/AC8; amended invariant 41, invariant 57)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'server_url': serverUrl});
      final mode = _GateMode('refused');
      final provider = _providerFor(mode);
      await pumpScreen(
        tester,
        const LibraryScreen(),
        ready: find.text('Brass'),
        syncProvider: provider,
      );
      await _pumpUntil(
        tester,
        () => provider.connectivityState == ConnectivityState.unreachable,
      );
      expect(find.text(redSentence), findsNothing, reason: 'W1 control');

      // The provider seam of the Sync-screen tap (the tap itself is the
      // device row D2's job): fire without awaiting (header note).
      provider.fetchPlaylists(userInitiated: true);
      await _pumpUntil(tester, () => provider.unreachableWarningVisible);
      expect(provider.connectivityState, ConnectivityState.unreachable);

      // Surface 1: the home banner with the exact wording + working Retry.
      expect(find.text(redSentence), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

      // Surface 2: the red-dotted cloud_off badge (icon + error-coloured
      // dot, not just any cloud_off).
      final scheme = Theme.of(tester.element(find.byType(LibraryScreen)))
          .colorScheme;
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == scheme.error &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
        findsWidgets,
        reason: 'the badge carries the error-coloured dot',
      );

      // Surface 3: the drawer line.
      await _openDrawer(tester);
      expect(find.text('Server not responding'), findsOneWidget);
      await _closeDrawer(tester);

      // Surface 4: the Sync screen red banner - reached through the
      // ungated drawer 'Sync' entry (AC2; navigation is never gated).
      _tolerateSyncScreenDispose();
      await _openSyncViaDrawer(tester);
      expect(
        find.descendant(
          of: find.byType(SyncScreen),
          matching: find.text(redSentence),
        ),
        findsOneWidget,
      );
      // Co-present: the home banner and Retry are still mounted beneath.
      expect(find.text(redSentence), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

      // AC8 (invariant 41 G2): no dismiss affordance - the gate governs
      // appearance only.
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
      expect(find.byType(Dismissible), findsNothing);

      await _popSyncScreen(tester);
    },
  );

  testWidgets(
    'W3: a user-initiated fetch that reaches the server clears all four '
    '(issue 12, AC3; invariants 39/40/57)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'server_url': serverUrl});
      final mode = _GateMode('refused');
      final provider = _providerFor(mode);
      await pumpScreen(
        tester,
        const LibraryScreen(),
        ready: find.text('Brass'),
        syncProvider: provider,
      );
      await _pumpUntil(
        tester,
        () => provider.connectivityState == ConnectivityState.unreachable,
      );
      provider.fetchPlaylists(userInitiated: true);
      await _pumpUntil(tester, () => provider.unreachableWarningVisible);
      expect(find.text(redSentence), findsOneWidget);

      // The server answers (200 fixture - an HTTP status would count as
      // reached too, invariant 39): tap the banner's Retry.
      mode.value = 'succeed';
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await _pumpUntil(
        tester,
        () => provider.connectivityState == ConnectivityState.reachable,
      );

      expect(find.text(redSentence), findsNothing);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      await _openDrawer(tester);
      expect(find.text('Server not responding'), findsNothing);
      await _closeDrawer(tester);

      await _settleTransitions(tester);
    },
  );

  testWidgets(
    'W4: a requested offline fetch never presents red; the orange offline '
    'banner keeps its non-empty condition (issue 12, AC5; invariant 41)',
    (tester) async {
      SharedPreferences.setMockInitialValues({'server_url': serverUrl});
      final mode = _GateMode('succeed');
      final provider = _providerFor(mode);
      await pumpScreen(
        tester,
        const LibraryScreen(),
        ready: find.text('Brass'),
        syncProvider: provider,
      );
      await _pumpUntil(
        tester,
        () => provider.connectivityState == ConnectivityState.reachable,
      );

      // Flip to the errno-101 shape and request a fetch: even REQUESTED,
      // offline never arms the gate (it arms only on unreachable).
      mode.value = 'noRoute';
      provider.fetchPlaylists(userInitiated: true);
      await _pumpUntil(
        tester,
        () => provider.connectivityState == ConnectivityState.offline,
      );
      expect(provider.unreachableWarningVisible, isFalse);
      expect(find.text(redSentence), findsNothing);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      await _openDrawer(tester);
      expect(find.text('Server not responding'), findsNothing);
      await _closeDrawer(tester);

      // The orange banner renders while the list is non-empty (the
      // honesty rule's satisfied side).
      expect(provider.availablePlaylists, isNotEmpty);
      _tolerateSyncScreenDispose();
      await _openSyncViaDrawer(tester);
      expect(find.text(orangeSentence), findsOneWidget);

      await _popSyncScreen(tester);
    },
  );

  testWidgets(
    'W4b: right after a save with nothing cached the orange banner is '
    'absent (issue 12, AC5; invariant 41 honesty rule)',
    (tester) async {
      // The second half of the honesty rule: unverified, nothing cached -
      // a fresh provider (no server_url pref, no fetch has run, so the
      // in-memory list is empty). The in-memory list is what the banner's
      // non-empty condition reads (setServerUrl never clears or loads it),
      // so this is the scenario the rule was written for; the sibling W4
      // covers the populated side.
      SharedPreferences.setMockInitialValues({});
      final mode = _GateMode('succeed');
      final provider = _providerFor(mode);
      await pumpScreen(
        tester,
        const LibraryScreen(),
        ready: find.text('Library'),
        syncProvider: provider,
      );
      provider.setServerUrl('http://127.0.0.1:9');
      await _pumpUntil(
        tester,
        () =>
            provider.isConfigured &&
            provider.connectivityState == ConnectivityState.offline,
      );
      expect(provider.availablePlaylists, isEmpty);

      _tolerateSyncScreenDispose();
      await _openSyncViaDrawer(tester);

      // Positive control: the right Sync-screen branch rendered (the
      // banner would render here if its condition were wrong).
      expect(find.widgetWithText(ElevatedButton, 'Load Playlists'),
          findsOneWidget);
      expect(find.text(orangeSentence), findsNothing);
      expect(find.text(redSentence), findsNothing);
      expect(find.byIcon(Icons.cloud_off), findsNothing);

      await _popSyncScreen(tester);
    },
  );
}
