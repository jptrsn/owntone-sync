// Shared widget-test harness for the detail screens (Unit A of
// .agent/widget-test-task.md; Unit C reuses it for the remaining screens).
//
// Two constraints are documented here because they cost a session to
// discover; re-derivation is expensive, so read them before extending this
// harness:
//
// 1. FAKEASYNC. `testWidgets()` bodies run under a fake event loop, where
//    the FFI SQLite layer's real I/O (opening the file) never completes.
//    All database setup therefore happens in plain `test()` calls (the real
//    async zone) that run first, and a pump loop must never await a DB
//    future directly: the screen's own `_loadTracks()` completes during
//    pumping against the database already opened in the real zone, and the
//    test only pumps until the rendered output appears.
//
// 2. SHARED FFI DB FILE RACE. The FFI factory resolves to the fixed path
//    `.dart_tool/sqflite_common_ffi/databases/owntone_sync.db`
//    (`DatabaseHelper` hard-codes the file name), and
//    `test/database/database_migration_test.dart` drives that same file in
//    parallel isolates under `flutter test`'s default file parallelism.
//    Seeding here is check-and-insert: never delete or recreate the file,
//    and never delete rows. Stale rows left by another suite (e.g. the v3
//    migration fixture's track ids 1-3) are tolerated, not corrected — the
//    fixture ids below avoid that range.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:owntone_sync/data/database/database_helper.dart';
import 'package:owntone_sync/data/repositories/local_database_repository.dart';
import 'package:owntone_sync/presentation/controllers/playback_controller.dart';
import 'package:owntone_sync/presentation/providers/browse_provider.dart';
import 'package:owntone_sync/presentation/providers/sync_provider.dart';
import 'package:owntone_sync/presentation/services/audio_handler.dart';
import 'package:owntone_sync/presentation/services/track_uri_resolver.dart';

/// The app's real light theme, copied from `MyApp._buildApp`
/// (lib/main.dart) so the screens under test lay out as in production.
ThemeData appLightTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF37474F),
      brightness: Brightness.light,
      primary: const Color(0xFF37474F),
      secondary: const Color(0xFFF4511E),
      surface: Colors.white,
      onSurface: const Color(0xFF37474F),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

/// Sets `databaseFactory = databaseFactoryFfiNoIsolate` (the no-isolate FFI
/// factory is the one whose queries complete during `tester.pump()`; the
/// isolate-based factory cannot complete at all under FakeAsync).
///
/// Must be called from a plain `test()` — the real async zone — before the
/// `testWidgets` pumps (constraint 1).
///
/// Idempotent. Deliberately does NOT open the database: the open (and any
/// upgrade DDL it may run) is done by [seedDetailScreens], AFTER the shared
/// file has gone quiescent — opening mid-churn can race the parallel
/// migration suite's own transactions on the same path.
Future<void> initWidgetTestDb() async {
  databaseFactory = databaseFactoryFfiNoIsolate;
}

/// One check-and-insert row: insert [row] into [table] only if no row
/// matches [where] with [args].
class _SeedSpec {
  final String table;
  final String where;
  final List<Object?> args;
  final Map<String, Object?> row;

  const _SeedSpec(this.table, this.where, this.args, this.row);
}

/// Seeds the rows the detail screens need (and, for Unit C, the history and
/// pending-event rows).
///
/// Check-and-insert only (constraint 2): a row that already exists —
/// including one left by another suite sharing the file — is kept, not
/// replaced, and the file is never deleted or recreated.
///
/// The checks are read-only, and all missing rows are inserted in ONE
/// short transaction; the whole attempt is retried on transient FFI
/// errors.
///
/// Before writing, it waits for the shared file to go quiescent. A parallel
/// isolate (`test/database/database_migration_test.dart`, in the same suite
/// run) deletes and recreates this file repeatedly for a few seconds after
/// the suite starts, and two SQLite connections at one path with different
/// inodes are not safe to write from concurrently: the path-based rollback
/// journal collides, and the commit surfaces as `database is locked`,
/// `disk I/O error` (observed: `SqfliteFfiException(sqlite_error: 5898)`)
/// or `attempt to write a readonly database` (code 1032) — the last of
/// which can poison the connection, which is why retrying a colliding
/// commit is a backstop, not the primary defence. Waiting for the quiescent
/// file (a stable `mtime` across two polls after observed churn, or after a
/// 7 s no-churn observation; a file that never appears within a few seconds
/// means this file runs alone, e.g. a standalone `flutter test <this
/// file>`, and the open will create it) lands the seed after the churn.
///
/// The open happens here, after the wait — not in `initWidgetTestDb` —
/// because opening a mid-migration v3 file would run the upgrade DDL into
/// the parallel suite's active file.
Future<void> seedDetailScreens() async {
  await _waitForSharedDbQuiescence();
  for (var attempt = 0; ; attempt++) {
    try {
      final db = await DatabaseHelper.instance.database;
      final specs = _seedSpecs(DateTime.now().millisecondsSinceEpoch);
      final missing = <_SeedSpec>[];
      for (final spec in specs) {
        final existing = await db.query(
          spec.table,
          where: spec.where,
          whereArgs: spec.args,
          limit: 1,
        );
        if (existing.isEmpty) missing.add(spec);
      }
      if (missing.isEmpty) return;
      await db.transaction((txn) async {
        for (final spec in missing) {
          await txn.insert(spec.table, spec.row);
        }
      });
      return;
    } on DatabaseException catch (e) {
      if (attempt >= 5 || !_isTransientDbError(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}

/// `DatabaseException` keeps its message private; `toString()` is
/// `DatabaseException(<message>)`. Transient means another process holds
/// or churning the shared file (constraint 2) — retryable. Anything else
/// (constraint violations, malformed db) is not.
bool _isTransientDbError(DatabaseException e) {
  final text = e.toString();
  return text.contains('locked') ||
      text.contains('I/O error') ||
      text.contains('readonly') ||
      text.contains('busy');
}

/// The fixed file `DatabaseHelper` opens (mirrors `dbFilePath()` in
/// `test/database/db_lifecycle_helpers.dart`).
String widgetTestDbPath() => p.join(
  p.absolute(p.join('.dart_tool', 'sqflite_common_ffi', 'databases')),
  'owntone_sync.db',
);

/// Polls the shared DB file until it is safe to write to. A parallel
/// isolate (`test/database/database_migration_test.dart`, same suite run)
/// deletes and recreates the file repeatedly for a few seconds after the
/// suite starts, and two SQLite connections at one path with different
/// inodes are not safe to write from concurrently (the path-based rollback
/// journal collides; commits surface as `database is locked`, `disk I/O
/// error`, or `attempt to write a readonly database`).
///
/// A delete/recreate/DDL cycle rewrites the file, so the churn is visible
/// as `mtime` changes. Quiescence = the `mtime` unchanged across two
/// consecutive polls, and only then:
///
/// * if churn (an mtime change) was observed first, or
/// * if 7 s passed with no churn at all — a file that has been stable
///   since t=0 may simply be a leftover from an earlier run, with the
///   churn not started yet; it must be given time to start.
///
/// Also returns when the file never appeared within 3 s (no parallel
/// writer — a standalone run of this test file; the open will create it),
/// or at a 30 s deadline (pathological churn; the seed's retry loop takes
/// over rather than hanging the suite).
Future<void> _waitForSharedDbQuiescence() async {
  final start = DateTime.now();
  const deadline = Duration(seconds: 30);
  const standaloneGrace = Duration(seconds: 3);
  const noChurnObservation = Duration(seconds: 7);

  DateTime? lastModified;
  var seenStable = false;
  var everSeen = false;
  var sawChurn = false;

  while (true) {
    final elapsed = DateTime.now().difference(start);

    DateTime? modified;
    try {
      modified = (await File(widgetTestDbPath()).stat()).modified;
      everSeen = true;
    } on FileSystemException {
      modified = null; // deleted between exists and stat — churn in progress
    }

    if (modified != null) {
      if (lastModified == null || modified.isAfter(lastModified)) {
        if (lastModified != null) sawChurn = true;
        lastModified = modified;
        seenStable = false;
      } else if (!seenStable) {
        seenStable = true; // unchanged since the previous poll
      } else if (sawChurn || elapsed >= noChurnObservation) {
        return; // stable, with the churn either done or given up
      }
    } else if (!everSeen && elapsed >= standaloneGrace) {
      return; // no parallel writer: proceed and let the open create it
    }
    // everSeen && modified == null: a delete is in progress — keep waiting.

    if (elapsed >= deadline) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

List<_SeedSpec> _seedSpecs(int now) {
  return [
    // `path` is UNIQUE on synced_playlists (and on the v3 fixture's rows,
    // which own '/playlists/brass' and '/playlists/soul'), so the fixture
    // paths are distinct too — a path collision would fail the insert
    // outright, not just double a count.
    _SeedSpec(
      'synced_playlists',
      'id = ?',
      [101],
      {
        'id': 101,
        'name': 'Brass',
        'path': '/playlists/brass-fixture',
        'type': 'static',
        'last_synced': now,
      },
    ),
    _SeedSpec(
      'synced_playlists',
      'id = ?',
      [102],
      {
        'id': 102,
        'name': 'Soul',
        'path': '/playlists/soul-fixture',
        'type': 'static',
        'last_synced': now,
      },
    ),
    // Track ids 101+ and playlist ids 101/102 deliberately avoid the 1-3
    // range the v3 migration fixture (this same shared file, during a
    // full-suite run) uses — that fixture seeds playlists id 1 'Brass' /
    // id 2 'Soul', tracks 1-3, and one unsynced pending event, so a
    // collision there would survive the check-and-insert and double the
    // counts the smoke tests read (PR #7 review finding).
    // Fixture names must not collide with each other: no track is titled
    // 'Brass', 'Soul', 'Album X' or 'Solo Artist'.
    _SeedSpec(
      'synced_tracks',
      'id = ?',
      [101],
      {
        'id': 101,
        'title': 'Brass Track One',
        'artist': 'Brass Band',
        'album': 'Brass Album',
        'album_artist': 'Brass Band',
        'local_path': '/music/brass_one.mp3',
        'server_path': '/media/brass_one.mp3',
        'download_timestamp': 101,
        'file_size': 1000000,
        'length_ms': 210000,
        'track_number': 1,
      },
    ),
    _SeedSpec(
      'synced_tracks',
      'id = ?',
      [102],
      {
        'id': 102,
        'title': 'Brass Track Two',
        'artist': 'Brass Band',
        'album': 'Brass Album',
        'album_artist': 'Brass Band',
        'local_path': '/music/brass_two.mp3',
        'server_path': '/media/brass_two.mp3',
        'download_timestamp': 102,
        'file_size': 1100000,
        'length_ms': 195000,
        'track_number': 2,
      },
    ),
    _SeedSpec(
      'synced_tracks',
      'id = ?',
      [103],
      {
        'id': 103,
        'title': 'Soul Track One',
        'artist': 'Soul Band',
        'album': 'Soul Album',
        'album_artist': 'Soul Band',
        'local_path': '/music/soul_one.mp3',
        'server_path': '/media/soul_one.mp3',
        'download_timestamp': 103,
        'file_size': 1200000,
        'length_ms': 240000,
        'track_number': 1,
      },
    ),
    _SeedSpec(
      'synced_tracks',
      'id = ?',
      [111],
      {
        'id': 111,
        'title': 'Album X One',
        'artist': 'Artist A',
        'album': 'Album X',
        'album_artist': 'Artist A',
        'local_path': '/music/album_x_one.mp3',
        'server_path': '/media/album_x_one.mp3',
        'download_timestamp': 111,
        'file_size': 1300000,
        'length_ms': 60000,
        'track_number': 1,
        'year': 1970,
      },
    ),
    _SeedSpec(
      'synced_tracks',
      'id = ?',
      [112],
      {
        'id': 112,
        'title': 'Album X Two',
        'artist': 'Artist A',
        'album': 'Album X',
        'album_artist': 'Artist A',
        'local_path': '/music/album_x_two.mp3',
        'server_path': '/media/album_x_two.mp3',
        'download_timestamp': 112,
        'file_size': 1400000,
        'length_ms': 45000,
        'track_number': 2,
      },
    ),
    _SeedSpec(
      'synced_tracks',
      'id = ?',
      [121],
      {
        'id': 121,
        'title': 'Solo Track One',
        'artist': 'Solo Artist',
        'album': 'Other Album',
        'album_artist': 'Solo Artist',
        'local_path': '/music/solo_one.mp3',
        'server_path': '/media/solo_one.mp3',
        'download_timestamp': 121,
        'file_size': 1500000,
        'length_ms': 180000,
        'track_number': 1,
      },
    ),
    // Playlist 101 'Brass' holds two tracks; playlist 102 'Soul' holds one.
    // (playlist_tracks has a composite primary key and no id column.)
    const _SeedSpec(
      'playlist_tracks',
      'playlist_id = ? AND track_id = ?',
      [101, 101],
      {'playlist_id': 101, 'track_id': 101},
    ),
    const _SeedSpec(
      'playlist_tracks',
      'playlist_id = ? AND track_id = ?',
      [101, 102],
      {'playlist_id': 101, 'track_id': 102},
    ),
    const _SeedSpec(
      'playlist_tracks',
      'playlist_id = ? AND track_id = ?',
      [102, 103],
      {'playlist_id': 102, 'track_id': 103},
    ),
    // Two sync runs: one success, one partial (the partial run's playlist
    // child carries the error_message). Timestamps are recent so
    // `getSyncHistory`'s 30-day window includes them.
    _SeedSpec(
      'sync_history',
      'id = ?',
      [501],
      {
        'id': 501,
        'timestamp': now - 7200 * 1000,
        'status': 'success',
        'playlists_synced': 2,
        'tracks_downloaded': 6,
        'tracks_deleted': 0,
        'error_message': null,
        'duration_ms': 120000,
        'trigger_type': 'manual',
        'plays_synced': 3,
        'skips_synced': 1,
      },
    ),
    _SeedSpec(
      'sync_history',
      'id = ?',
      [502],
      {
        'id': 502,
        'timestamp': now - 3600 * 1000,
        'status': 'partial',
        'playlists_synced': 1,
        'tracks_downloaded': 1,
        'tracks_deleted': 0,
        'error_message': 'One playlist failed',
        'duration_ms': 60000,
        'trigger_type': 'scheduled',
        'plays_synced': 0,
        'skips_synced': 0,
      },
    ),
    _SeedSpec(
      'sync_history_playlists',
      'id = ?',
      [501],
      {
        'id': 501,
        'sync_id': 501,
        'playlist_id': 101,
        'playlist_name': 'Brass',
        'tracks_in_playlist': 2,
        'error_message': null,
      },
    ),
    _SeedSpec(
      'sync_history_playlists',
      'id = ?',
      [502],
      {
        'id': 502,
        'sync_id': 502,
        'playlist_id': 102,
        'playlist_name': 'Soul',
        'tracks_in_playlist': 1,
        'error_message': 'Simulated download failure',
      },
    ),
    _SeedSpec(
      'pending_events',
      'id = ?',
      [501],
      {
        'id': 501,
        'track_id': 101,
        'event_type': 'play',
        'timestamp': now - 1800 * 1000,
        'synced': 0,
        'retry_count': 0,
      },
    ),
  ];
}

/// A `PlaybackController` constructible in a pure Dart-VM test: no
/// `AudioService.init` (that needs a real platform) and no `start()` (A8
/// persistence is not needed for the geometry guards). Verified
/// constructible for this program (widget-test-task, Unit A).
PlaybackController makePlaybackController() {
  final dbRepo = LocalDatabaseRepository();
  return PlaybackController(
    handler: OwnToneAudioHandler(),
    resolver: TrackUriResolver(dbRepo: dbRepo),
    dbRepo: dbRepo,
  );
}

/// Prewires every platform channel the app's screens and providers talk to,
/// so a pump never reaches the (absent) real platform and dies with a
/// `MissingPluginException` — a harness error, not an assertion. Pattern
/// from `test/sync_provider_connectivity_test.dart`.
///
/// Returns the `sync_progress` event sink so a later test (Unit C) can emit
/// worker events; the geometry tests never emit, so the stream stays empty.
MockStreamHandlerEventSink? mockAppChannels() {
  SharedPreferences.setMockInitialValues({});

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.educoder.owntone_sync/sync'),
    (call) async {
      switch (call.method) {
        case 'getSyncWorkState':
          return 'none';
        case 'getAppVersion':
          // The About screen reads the version from this channel
          // (invariant 45): a test version, never a literal.
          return '0.0.0-test';
        case 'updateSyncSchedule':
          return true;
        case 'triggerBackgroundSync':
        case 'cancelSync':
        default:
          return null;
      }
    },
  );

  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.educoder.owntone_sync/events'),
    (call) async {
      switch (call.method) {
        case 'isBatteryOptimizationDisabled':
          return false;
        case 'requestBatteryOptimizationExemption':
          return true;
        default:
          return null;
      }
    },
  );

  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.educoder.owntone_sync/storage'),
    (call) async {
      switch (call.method) {
        case 'hasMusicFolderAccess':
        case 'requestMusicFolderAccess':
        case 'fileExists':
          return false;
        case 'getFileSize':
          return 0;
        case 'deleteFile':
        case 'writeFile':
        default:
          return null;
      }
    },
  );

  MockStreamHandlerEventSink? sink;
  messenger.setMockStreamHandler(
    const EventChannel('dev.educoder.owntone_sync/sync_progress'),
    MockStreamHandler.inline(
      onListen: (arguments, events) => sink = events,
    ),
  );

  return sink;
}

/// Pumps [screen] under the app's real light theme and the real
/// `SyncProvider` / `BrowseProvider` / `PlaybackController`, with the screen
/// pushed via the Navigator above a simple home route so a real back button
/// exists.
///
/// [ready] is the finder that proves the screen has loaded (typically the
/// header's track-count meta): the loop pumps through the route transition
/// and until it appears, then settles the 300 ms transition so the header
/// is at rest when geometry is measured.
///
/// [syncProvider] overrides the provider the tree watches (Unit C,
/// widget-test-task.md): the Sync screen seam needs a provider whose Dio is
/// injected with an interceptor, which the constructor-only
/// `SyncProvider()` cannot produce. When provided, the tree disposes it
/// like any other provider.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required Finder ready,
  SyncProvider? syncProvider,
}) async {
  final controller = makePlaybackController();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncProvider>(
          create: (_) => syncProvider ?? SyncProvider(),
        ),
        ChangeNotifierProvider<BrowseProvider>(create: (_) => BrowseProvider()),
        Provider<PlaybackController>.value(value: controller),
      ],
      child: MaterialApp(
        title: 'Owntone Player',
        theme: appLightTheme(),
        home: _HarnessHome(screen: screen),
      ),
    ),
  );
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (ready.evaluate().isNotEmpty) break;
  }
  // Settle the route transition so the header sits at rest.
  await tester.pump(const Duration(milliseconds: 400));
}

/// The global rect of a finder's render box (the probe's extraction). The
/// finder must match exactly one widget; `renderObject` fails otherwise.
Rect globalRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

/// [globalRect] scoped to the detail screen's header (constraint 3): the
/// list rows below the header contain their own 'tracks' texts and
/// avatars, which an unscoped finder would pick up.
Rect headerRect(WidgetTester tester, Finder matching) => globalRect(
  tester,
  find.descendant(of: find.byType(FlexibleSpaceBar), matching: matching),
);

/// The overlap guard. Failure messages print both rects, like the probe's
/// output did.
void expectNoOverlap(String what, Rect a, Rect b) {
  expect(
    a.overlaps(b),
    isFalse,
    reason: '$what: $a overlaps $b',
  );
}

/// The home route a guard screen is pushed above: plain, so the only
/// geometry on screen comes from the screen under test.
class _HarnessHome extends StatefulWidget {
  final Widget screen;

  const _HarnessHome({required this.screen});

  @override
  State<_HarnessHome> createState() => _HarnessHomeState();
}

class _HarnessHomeState extends State<_HarnessHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => widget.screen),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Harness home')),
    );
  }
}
