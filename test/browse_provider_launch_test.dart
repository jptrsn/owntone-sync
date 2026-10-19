// Cites invariant 51 (blockers 2026-10-17 "launch dead end"): the load the
// launch path performs must populate EVERY category, not just the default
// tab. `hasContent` is an OR over all four in-memory lists while
// `loadData()` fills only the current one, so a current-category-only
// launch load leaves `hasContent` false when the default tab (Playlists)
// is empty but Artists/Albums/Tracks hold rows — the Library then swaps
// the tabbed body for the empty state and, with no TabBar rendered,
// removes every in-app route back to the data.
//
// The true dead-end state (playlists empty, tracks populated) cannot be
// expressed against the shared FFI DB file: constraint 2 (see
// widget_test_helpers.dart) forbids deleting the fixture playlists, and
// their presence keeps `hasContent` true either way. The tests below
// therefore pin what the harness CAN express:
//
// - the provider seam: `reloadAll()` — the launch load — populates all
//   four lists from a DB that holds all four (a pure data check that does
//   not depend on the pump harness; if the widget test's harness is broken,
//   this one still passes, which separates a harness failure from a real
//   regression — protocol §4);
// - the launch path itself: pumping `LibraryScreen` as `home` (the
//   production shape, main.dart) leaves all four lists populated — a
//   revert of the launch path to a current-category-only load leaves the
//   three non-default lists empty and fails the test.
//
// The device go/no-go exercises the true dead-end state
// (fix-launch-dead-end-report.md).
//
// Seeding runs in the one plain test() below (real zone, before the loads
// — constraint 1); the shared FFI DB file is check-and-insert only
// (constraint 2).

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/presentation/controllers/playback_controller.dart';
import 'package:owntone_sync/presentation/providers/browse_provider.dart';
import 'package:owntone_sync/presentation/providers/sync_provider.dart';
import 'package:owntone_sync/presentation/screens/library_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test_helpers.dart';

/// Pumps short frames until no transient frame callback (i.e. no running
/// ticker) remains, so the binding's end-of-test invariants see a settled
/// tree (the screen_smoke_test.dart pattern). The cap keeps a genuinely
/// persistent animation from hanging the test; the expect makes that a
/// loud, named failure instead.
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

  test('seed: launch fixtures (check-and-insert, never delete)', () async {
    await initWidgetTestDb();
    await seedDetailScreens();
  });

  setUp(() {
    mockAppChannels();
  });

  test('launch load (reloadAll) populates every category', () async {
    // BrowseProvider._ensureSortLoaded reads SharedPreferences.
    SharedPreferences.setMockInitialValues({});
    final provider = BrowseProvider();
    await provider.reloadAll();

    expect(provider.hasContent, isTrue);
    // Each list non-empty from the seeded fixture (playlists 101/102,
    // artists/albums/tracks from the fixture tracks).
    expect(provider.playlists, isNotEmpty);
    expect(provider.artists, isNotEmpty);
    expect(provider.albums, isNotEmpty);
    expect(provider.tracks, isNotEmpty);
  });

  testWidgets('launch renders the tabbed body and loads every category', (
    tester,
  ) async {
    // The production launch shape (main.dart: home: LibraryScreen()).
    final browse = BrowseProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SyncProvider>(
            create: (_) => SyncProvider(),
          ),
          ChangeNotifierProvider<BrowseProvider>(create: (_) => browse),
          Provider<PlaybackController>.value(value: makePlaybackController()),
        ],
        child: MaterialApp(
          title: 'Owntone Player',
          theme: appLightTheme(),
          home: const LibraryScreen(),
        ),
      ),
    );
    // The launch load is deferred to a post-frame callback in initState;
    // pump through it until the tabbed body is up (its TabBar labels).
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.text('Playlists').evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 400));

    // The launch load must have populated every category — not just the
    // default tab (invariant 51). A revert of the launch path to
    // loadData() leaves the three non-default lists empty while the DB
    // holds rows.
    expect(browse.playlists, isNotEmpty);
    expect(browse.artists, isNotEmpty);
    expect(browse.albums, isNotEmpty);
    expect(browse.tracks, isNotEmpty);
    expect(browse.hasContent, isTrue);

    // The tabbed body is up (positive control: the app bar title), and
    // the empty state is not.
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('No music yet'), findsNothing);

    await _settleTransitions(tester);
  });
}
