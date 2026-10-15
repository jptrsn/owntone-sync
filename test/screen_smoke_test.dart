// Smoke tests for the remaining screens (Unit C of
// .agent/widget-test-task.md): one focused test per screen — pump with
// seeded representative data, let a render exception (a RenderFlex overflow
// throws in tests) fail the test, and assert 1-2 key elements derived from
// .agent/player-ux-spec.md and .agent/invariants.md. This is a net for
// regressions, not a behaviour spec. No goldens.
//
// Harness notes (full constraints in widget_test_helpers.dart): seeding
// runs in the one plain test() below (real zone, before the pumps —
// constraint 1); the shared FFI DB file is check-and-insert only
// (constraint 2), and the quiescence wait is paid once per seed call, so
// this file seeds exactly once.
//
// Per-test SharedPreferences overrides go through
// SharedPreferences.setMockInitialValues, which also resets the cached
// instance (shared_preferences 2.5.4 legacy source: it nulls the
// completer), so each pumpScreen's fresh SyncProvider sees exactly the
// values the test seeds.
//
// Sync screen seam (pattern: sync_provider_connectivity_test.dart): the
// provider is built with an injected Dio whose interceptor resolves
// getPlaylists, so no real network contact is made and the configured
// playlist-selection view renders deterministically.
//
// Sync screen finding (F1, reported with Unit C): SyncScreen.dispose does
// `context.read<SyncProvider>()` (lib/presentation/screens/sync_screen.dart)
// — an ancestor lookup on a deactivated element, which Flutter asserts on
// when the widget tree is finalized. It is a pre-existing, debug-only lib
// defect (release is unaffected); it fires after the screen has rendered
// and been asserted on. The sync test tolerates exactly that one
// assertion so the smoke net keeps its render coverage; everything else
// still fails the test.
//
// Route-transition settling: pumpScreen pumps until its [ready] finder
// matches and then one 400 ms settle pump, but in the automated test
// binding the harness route's transition ticker (registered in a
// post-frame callback) is not guaranteed to have ticked by then — a
// pending transient frame callback would make the binding's end-of-test
// invariant fail with "An animation is still running even after the
// widget tree was disposed". Every test therefore finishes its body with
// _settleTransitions, which pumps until no transient frame callback
// remains (the animation has long since passed its 300 ms duration, so
// the first tick finishes it at once).
//
// The sync test additionally pops its screen route inside the test body
// (with its FlutterError.onError override still active). Otherwise the
// F1 assert above fires during the binding's end-of-test unmount, where
// BuildOwner.finalizeTree converts the throw into a report (swallowed by
// the override) but still interrupts the unmount — leaving the Navigator
// and its route un-unmounted; that half-state can resurface in later
// tests of the file. Popping inside the test keeps the F1 fallout
// contained where the override can swallow it.
//
// Schedule screen note: the screen captures the provider's schedule once
// in initState, but in the harness the provider is created fresh, so its
// async prefs load has not completed by the first frame (in the app the
// provider is long-lived and loaded before the screen is opened). The test
// therefore pre-warms the provider under a throwaway tree until the
// schedule is loaded, then hands the warmed provider to pumpScreen.
//
// Now Playing sheet limitation: just_audio's own platform channels are NOT
// mocked by the harness, so a playCollection-driven queue cannot load
// (the controller's mediaItem stream is fed by just_audio's
// sequenceStateStream, which needs the platform). The sheet is covered in
// its empty state; the loaded-track view is device-verified only.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/data/models/sync_schedule.dart';
import 'package:owntone_sync/data/repositories/owntone_api_repository.dart';
import 'package:owntone_sync/presentation/providers/sync_provider.dart';
import 'package:owntone_sync/presentation/screens/about_screen.dart';
import 'package:owntone_sync/presentation/screens/history_screen.dart';
import 'package:owntone_sync/presentation/screens/library_screen.dart';
import 'package:owntone_sync/presentation/screens/player_screen.dart';
import 'package:owntone_sync/presentation/screens/schedule_config_screen.dart';
import 'package:owntone_sync/presentation/screens/search_screen.dart';
import 'package:owntone_sync/presentation/screens/server_config_screen.dart';
import 'package:owntone_sync/presentation/screens/settings_screen.dart';
import 'package:owntone_sync/presentation/screens/storage_screen.dart';
import 'package:owntone_sync/presentation/screens/sync_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test_helpers.dart';

/// Two playlists in the server's JSON shape (playlist.g.dart), the same
/// fixture sync_provider_connectivity_test.dart drives through getPlaylists.
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

/// The sync-screen Dio seam: every request resolves with [_playlistsJson].
Dio _playlistsDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: _playlistsJson,
          ),
        );
      },
    ),
  );
  return dio;
}

/// The route the Now Playing sheet is opened over: a plain screen with one
/// button, so the only meaningful content on screen is the sheet itself.
class _SheetHost extends StatelessWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sheet host')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => showNowPlayingSheet(context),
          child: const Text('Open sheet'),
        ),
      ),
    );
  }
}

/// Pumps short frames until no transient frame callback (i.e. no running
/// ticker) remains, so the binding's end-of-test invariants see a fully
/// settled tree. See the route-transition note in the header. The cap
/// keeps a genuinely persistent animation (e.g. an indeterminate
/// spinner in a resting state) from hanging the test; the expect makes
/// that a loud, named failure instead.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One seed call for the whole file: the shared-file quiescence wait is
  // paid per plain-test() seed call (constraint 2).
  test('seed: screen fixtures (check-and-insert, never delete)', () async {
    await initWidgetTestDb();
    await seedDetailScreens();
  });

  setUp(() {
    mockAppChannels();
  });

  group('Library screen (home route)', () {
    testWidgets(
      'renders the four category tabs over the seeded playlists',
      (tester) async {
        // Invariant 17: the home route mounts for the app's lifetime;
        // pushing it in the harness is fine for a smoke test.
        await pumpScreen(tester, const LibraryScreen(), ready: find.text('Brass'));

        // Spec B1: the app opens on the Library screen, not on a sync
        // screen.
        expect(find.text('Library'), findsOneWidget);

        // Spec B2: four categories — Playlists, Artists, Albums, Tracks —
        // switched by tabs.
        expect(find.text('Playlists'), findsOneWidget);
        expect(find.text('Artists'), findsOneWidget);
        expect(find.text('Albums'), findsOneWidget);
        expect(find.text('Tracks'), findsOneWidget);

        // Seeded representative data (helper playlist id 101) renders with
        // its track-count secondary line (spec B2 row grammar).
        // `findsWidgets`, not `findsOneWidget`: if the parallel migration
        // suite's v3 fixture (its own 'Brass' with 2 tracks) is live in the
        // shared DB file, the row renders twice — the count is not the spec
        // point (PR #7 review finding).
        expect(find.text('2 tracks'), findsWidgets);

        // Invariant 41: the unconfigured state is the neutral setup icon —
        // no badge, no error text, anywhere.
        expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);

        await _settleTransitions(tester);
      },
    );
  });

  group('Search screen', () {
    testWidgets('renders the search field and the empty-query state', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SearchScreen(),
        ready: find.byType(TextField),
      );

      // Invariant 38: the field must actually render. The historical
      // defect was `title: Expanded(child: TextField(...))` — a red error
      // widget in debug, an inert grey box in release — so a rendered
      // TextField is the guard, not an assumption.
      expect(find.byType(TextField), findsOneWidget);

      // Spec B6: the field searches track, artist, album, and playlist
      // name across synced content; the empty-query state says so.
      expect(
        find.text(
          'Search your library by track, artist, album, or playlist.',
        ),
        findsOneWidget,
      );

      await _settleTransitions(tester);
    });
  });

  group('Sync screen', () {
    testWidgets(
      'renders the configured playlist-selection view with the seeded '
      'pending-event count',
      (tester) async {
        // Tolerate finding F1 (see the header): exactly the
        // deactivated-ancestor assertion thrown from
        // SyncScreen.dispose at tree finalization. Everything else
        // propagates to the original handler and fails the test.
        // The match is the framework's exact error summary
        // (framework.dart:5050, Flutter 3.41.7), not a prefix, so a
        // different deactivated-ancestor lookup introduced into
        // sync_screen.dart later is still caught (PR #7 review finding).
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          final text = details.toString();
          if (text.contains(
                "Looking up a deactivated widget's ancestor is unsafe.",
              ) && text.contains('sync_screen.dart')) {
            return;
          }
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        // Configured provider: the URL comes from preferences, the Dio is
        // injected (seam pattern: sync_provider_connectivity_test.dart),
        // and the storage check short-circuits to granted on a
        // non-Android host.
        SharedPreferences.setMockInitialValues({
          'server_url': 'http://192.168.1.13:3689',
          'selected_playlist_ids': ['1', '2'],
        });
        final provider = SyncProvider(
          apiRepository: (baseUrl) =>
              OwnToneApiRepository(baseUrl: baseUrl, dio: _playlistsDio()),
        );
        await pumpScreen(
          tester,
          const SyncScreen(),
          ready: find.text('2 playlists selected'),
          syncProvider: provider,
        );

        // Spec C2: the Sync screen is where sync state and the playlist
        // selection live; both playlists from the injected fetch render.
        expect(find.text('radio'), findsOneWidget);
        expect(find.text('jazz'), findsOneWidget);

        // Spec D3: a pending-events count is visible on the Sync screen so
        // the user can tell events are queued rather than lost — the helper
        // seeded exactly one unsynced playback event. Matched by substring:
        // if the parallel migration suite's v3 fixture (its own unsynced
        // event) is live in the shared DB file, the count renders as 2 and
        // the plural form differs (PR #7 review finding).
        expect(find.textContaining('playback event'), findsOneWidget);

        // Settle the push transition, then pop the screen inside this
        // test so finding F1's fallout is contained here (header note).
        await _settleTransitions(tester);
        Navigator.of(tester.element(find.byType(SyncScreen))).pop();
        await tester.pump(const Duration(milliseconds: 400));
        await _settleTransitions(tester);
      },
    );
  });

  group('Schedule screen', () {
    testWidgets(
      'renders the persisted schedule and the battery warning',
      (tester) async {
        // The schedule is persisted as JSON in preferences, per the
        // SyncSchedule model; SyncProvider loads it during init.
        SharedPreferences.setMockInitialValues({
          'sync_schedule': jsonEncode(
            SyncSchedule(enabled: true, hour: 3, minute: 15).toJson(),
          ),
        });

        // Pre-warm the provider until its async init has loaded the
        // schedule (see the header note): the screen captures it once in
        // initState, so it must already be loaded by the first frame. The
        // provider element uses the same `create` constructor as
        // pumpScreen's, because updating one provider element with a
        // different constructor (e.g. .value) is unsupported by the
        // provider package.
        final provider = SyncProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SyncProvider>(create: (_) => provider),
            ],
            child: const MaterialApp(home: SizedBox()),
          ),
        );
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          if (provider.syncSchedule.enabled) break;
        }
        await pumpScreen(
          tester,
          const ScheduleConfigScreen(),
          ready: find.textContaining('Battery optimization is enabled'),
          syncProvider: provider,
        );

        // Spec C1: the schedule keeps its capability, reached through the
        // Settings hub (invariant 45); the persisted values render.
        expect(find.text('Sync Schedule'), findsOneWidget);
        expect(find.text('Enable Automatic Sync'), findsOneWidget);

        // The events-channel mock reports battery optimization NOT
        // disabled, so an enabled schedule renders its warning row — the
        // screen exercising the provider's checkBatteryOptimization seam.
        expect(
          find.textContaining('Battery optimization is enabled'),
          findsOneWidget,
        );

        await _settleTransitions(tester);
      },
    );
  });

  group('Server configuration screen', () {
    testWidgets(
      'renders the form; the example URL is a hint, not pre-filled text',
      (tester) async {
        await pumpScreen(
          tester,
          const ServerConfigScreen(),
          ready: find.byType(TextFormField),
        );

        // Invariant 44: the example URL is a hint (hintText), never
        // pre-filled text — pre-filled text is saveable, and an unattended
        // Save would configure a dead server.
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, isEmpty);
        expect(field.decoration?.hintText, 'http://192.168.1.100:3689');

        // Invariant 44: the test-connection step and the Save action both
        // render (the probe reports right/wrong before anything is saved).
        expect(
          find.widgetWithText(OutlinedButton, 'Test connection'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ElevatedButton, 'Save'),
          findsOneWidget,
        );

        await _settleTransitions(tester);
      },
    );
  });

  group('Settings screen', () {
    testWidgets('renders the four configuration destinations', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const SettingsScreen(),
        ready: find.text('Settings'),
      );

      // Invariant 45: Settings is the navigation hub — Server, Storage,
      // Schedule and About are reached only through it, and each keeps its
      // own screen.
      expect(find.widgetWithText(ListTile, 'Server'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Storage'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Schedule'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'About'), findsOneWidget);

      // No server_url seeded in this test: the hub shows the setup state,
      // not a fault (invariant 41: unconfigured is never an error
      // surface).
      expect(find.text('Not configured'), findsOneWidget);

      await _settleTransitions(tester);
    });
  });

  group('About screen', () {
    testWidgets('renders the app name and the package-provided version', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const AboutScreen(),
        ready: find.text('Version 0.0.0-test'),
      );

      // Invariant 45: the user-facing name is "Owntone Player".
      expect(find.text('Owntone Player'), findsOneWidget);

      // Invariant 45: the version comes from the package — the
      // getAppVersion channel (mocked to the test version in
      // mockAppChannels), never a literal in the UI.
      expect(find.text('Version 0.0.0-test'), findsOneWidget);

      await _settleTransitions(tester);
    });
  });

  group('Sync history screen', () {
    testWidgets('renders the seeded sync runs', (tester) async {
      await pumpScreen(
        tester,
        const HistoryScreen(),
        ready: find.text('Sync Completed with Errors'),
      );

      // Spec D3 / invariant 41: per-sync-run status is the screen's
      // content — the helper seeded one success and one partial run.
      expect(find.text('Sync Completed'), findsOneWidget);
      expect(find.text('Sync Completed with Errors'), findsOneWidget);

      // The partial run's run-level error message renders in its card.
      expect(find.text('One playlist failed'), findsOneWidget);

      await _settleTransitions(tester);
    });
  });

  group('Storage screen', () {
    testWidgets('renders the folder status and grant action', (tester) async {
      await pumpScreen(
        tester,
        const StorageScreen(),
        ready: find.text('Music folder'),
      );

      // Spec C1: the music-folder grant is reachable (through the Settings
      // hub, invariant 45); the permission check is granted on a
      // non-Android host, so the granted state renders.
      expect(find.text('Folder access granted'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Change folder'),
        findsOneWidget,
      );

      await _settleTransitions(tester);
    });
  });

  group('Now Playing sheet', () {
    testWidgets('renders the empty-queue state', (tester) async {
        await pumpScreen(
          tester,
          const _SheetHost(),
          ready: find.text('Open sheet'),
        );
        await _settleTransitions(tester);
        await tester.tap(find.text('Open sheet'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

      // Spec B5: the sheet shows the current track or, with no current
      // track, its empty state. A loaded queue is not feasible in this
      // harness: just_audio's own platform channels are not mocked, so
      // the controller's mediaItem stream (fed by just_audio's
      // sequenceStateStream) stays empty. The loaded-track view
      // (artwork, origin, seek bar, controls) is device-verified only.
      expect(find.byType(NowPlayingSheet), findsOneWidget);
      expect(find.text('No track playing'), findsOneWidget);

      // Dismiss the sheet (B5: dismissed by the back gesture / drag) and
      // settle the exit transition, so the route finalizes cleanly.
      Navigator.of(tester.element(find.byType(NowPlayingSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _settleTransitions(tester);
    });
  });
}
