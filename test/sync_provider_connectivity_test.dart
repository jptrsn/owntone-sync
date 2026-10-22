import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/data/repositories/owntone_api_repository.dart';
import 'package:owntone_sync/presentation/providers/sync_provider.dart';
import 'package:owntone_sync/utils/connectivity_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase U1 (ux-refactor.md §6): the provider-side transitions of the
/// four-state model - which events set each state, and only those
/// (invariants 40-41). The pure classifier has its own suite
/// (connectivity_state_test.dart).
///
/// Fetch failures are driven through a real OwnToneApiRepository whose Dio
/// rejects every request with the exact shape dio 5.9.0 produces (its own
/// factory constructors, pub cache lib/src/dio_exception.dart) - never a
/// hand-rolled substitute.
///
/// Deliberately no platform database: on the host the permission checks
/// short-circuit, and platform DB calls throw an environmental error. On
/// the success path the code under test swallows it (the cache-write
/// catch - which is exactly what the fetch-success test below asserts
/// on); on the failure path it propagates out of fetchPlaylists and is
/// swallowed by this suite's catch in expectFetchState.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const syncChannel = 'dev.educoder.owntone_sync/sync';
  const progressChannel = 'dev.educoder.owntone_sync/sync_progress';

  MockStreamHandlerEventSink? progressSink;

  // The mocked worker's sync-work-state answer ('none' | 'pending' |
  // 'running'), mirroring the getSyncWorkState probe. Kept 'none' by
  // default: a running sync would set SyncProvider.isSyncing during
  // _initialize, which the refusal test must not see. emitCompletion turns
  // it to 'running' just long enough to establish the progress
  // subscription.
  String syncWorkState = 'none';

  // Set when a test's startSync actually reaches the worker channel. A
  // refused start must leave this false: no enqueue, no worker run, no
  // sync_history row (U2, build item 2).
  bool triggerBackgroundSyncInvoked = false;

  /// A provider whose getPlaylists rejects every request with
  /// [buildError].
  SyncProvider providerFailing(
    DioException Function(RequestOptions options) buildError,
  ) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(buildError(options));
        },
      ),
    );
    return SyncProvider(
      apiRepository: (baseUrl) =>
          OwnToneApiRepository(baseUrl: baseUrl, dio: dio),
    );
  }

  /// _initialize() is not awaited from the constructor; give it time to
  /// reach steady state (unconfigured, subscribed to progress events).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  /// The production connect-timeout shape (dio 5.9.0,
  /// adapters/io_adapter.dart): built by dio's own factory with `error`
  /// unset.
  DioException connectionTimeout(RequestOptions options) =>
      DioException.connectionTimeout(
        requestOptions: options,
        timeout: const Duration(seconds: 10),
      );

  /// A no-route connection error (errno 101): the shape that classifies
  /// [ConnectivityState.offline] - the normal away-from-LAN condition the
  /// U2 guard refuses to sync against.
  DioException netUnreachable(RequestOptions options) =>
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
      );

  /// Two playlists in the server's JSON shape (playlist.g.dart).
  const playlistsJson = <String, dynamic>{
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

  /// A provider whose getPlaylists resolves with [playlistsJson].
  SyncProvider providerSucceeding() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: playlistsJson,
            ),
          );
        },
      ),
    );
    return SyncProvider(
      apiRepository: (baseUrl) =>
          OwnToneApiRepository(baseUrl: baseUrl, dio: dio),
    );
  }

  /// A provider whose getPlaylists settles [delay] after the request -
  /// rejecting with [buildError], or resolving with [playlistsJson] when
  /// [succeed] - so a save can land while the fetch is in flight.
  SyncProvider providerDelayed(
    Duration delay, {
    bool succeed = false,
    required DioException Function(RequestOptions options) buildError,
  }) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          await Future<void>.delayed(delay);
          if (succeed) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: playlistsJson,
              ),
            );
          } else {
            handler.reject(buildError(options));
          }
        },
      ),
    );
    return SyncProvider(
      apiRepository: (baseUrl) =>
          OwnToneApiRepository(baseUrl: baseUrl, dio: dio),
    );
  }

  /// Drives one fetch against a failing server and asserts the resulting
  /// state and freshness. The post-classification cache load needs a
  /// platform DB (absent here) and throws after the state is set, so the
  /// environmental error is swallowed.
  Future<SyncProvider> expectFetchState(
    DioException Function(RequestOptions) buildError,
    ConnectivityState expected,
  ) async {
    final provider = providerFailing(buildError);
    addTearDown(provider.dispose);
    await settle();
    await provider.setServerUrl('http://192.168.1.13:3689');
    try {
      await provider.fetchPlaylists();
    } catch (_) {
      // Environmental: the cache load below the classification has no
      // platform DB in this suite. The state is set before it.
    }
    expect(provider.connectivityState, expected);
    expect(provider.lastFetchSucceeded, isFalse);
    return provider;
  }

  Future<void> emitCompletion(
    SyncProvider provider,
    String status, {
    String? message,
  }) async {
    if (progressSink == null) {
      // No progress subscription yet: report a running sync so the
      // provider subscribes, then report the run as complete below.
      syncWorkState = 'running';
      await provider.checkIfSyncRunning();
      await settle();
    }
    progressSink?.success(
      <String, Object?>{
        'syncComplete': true,
        'status': status,
        if (message != null) 'message': message,
      },
    );
    await settle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    progressSink = null;
    syncWorkState = 'none';
    triggerBackgroundSyncInvoked = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(syncChannel),
      (call) async {
        if (call.method == 'getSyncWorkState') return syncWorkState;
        if (call.method == 'triggerBackgroundSync') {
          triggerBackgroundSyncInvoked = true;
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel(progressChannel),
      MockStreamHandler.inline(
        onListen: (arguments, events) => progressSink = events,
      ),
    );
  });

  group('a classified fetch failure sets the state (invariants 39-40)', () {
    test('ECONNREFUSED: a connection error carrying the SocketException is '
        'unreachable', () async {
      await expectFetchState(
        (options) => DioException.connectionError(
          requestOptions: options,
          reason: 'Connection failed',
          error: SocketException(
            'Connection failed (OS Error: Connection refused, errno = 111), '
            'address = 192.168.1.13, port = 3689',
            address: InternetAddress('192.168.1.13'),
            port: 3689,
            osError: const OSError('Connection refused', 111),
          ),
        ),
        ConnectivityState.unreachable,
      );
    });

    test('ENETUNREACH: a connection error carrying the SocketException is '
        'offline', () async {
      await expectFetchState(
        (options) => DioException.connectionError(
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
        ConnectivityState.offline,
      );
    });

    test('the 10 s connect timeout (dio builds it with no error) is '
        'unreachable', () async {
      await expectFetchState(connectionTimeout,
          ConnectivityState.unreachable);
    });

    test('a receive timeout (dio builds it with no error) is unreachable',
        () async {
      await expectFetchState(
        (options) => DioException.receiveTimeout(
          timeout: const Duration(seconds: 30),
          requestOptions: options,
        ),
        ConnectivityState.unreachable,
      );
    });

    test('an HTTP error status is reachable - the server answered - and '
        'marks the list stale', () async {
      await expectFetchState(
        (options) => DioException.badResponse(
          statusCode: 500,
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 500),
        ),
        ConnectivityState.reachable,
      );
    });
  });

  group('saving a URL drops to the unverified rendering (invariant 40)', () {
    test('from unreachable, saving drops to offline and invalidates '
        'freshness', () async {
      final provider = await expectFetchState(
        connectionTimeout,
        ConnectivityState.unreachable,
      );
      await provider.setServerUrl('http://10.0.0.5:3689');
      expect(provider.connectivityState, ConnectivityState.offline);
      expect(provider.lastFetchSucceeded, isFalse);
    });

    test('saving an empty URL drops to unconfigured', () async {
      final provider = providerFailing(connectionTimeout);
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');
      await provider.setServerUrl('');
      expect(provider.connectivityState, ConnectivityState.unconfigured);
    });
  });

  group('a successful fetch earns reachable (invariant 40)', () {
    test('establishes reachable and marks the list fresh; a local '
        'cache-write failure does not demote it', () async {
      final provider = providerSucceeding();
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');
      // On the host the cache write below the fetch throws a platform
      // error (no sqflite): it must be swallowed and keep the state the
      // fetch earned - not fed to the network classifier.
      await provider.fetchPlaylists();
      expect(provider.connectivityState, ConnectivityState.reachable);
      expect(provider.lastFetchSucceeded, isTrue);
      expect(provider.availablePlaylists, hasLength(2));
    });
  });

  group('a 200 body that fails to parse is still classified (invariant 40)',
      () {
    test('valid JSON with the wrong shape throws from the generated '
        'fromJson and falls to offline - no response object is available '
        'to prove reachability', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: 'not a map',
              ),
            );
          },
        ),
      );
      final provider = SyncProvider(
        apiRepository: (baseUrl) =>
            OwnToneApiRepository(baseUrl: baseUrl, dio: dio),
      );
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');
      try {
        await provider.fetchPlaylists();
      } catch (_) {
        // Environmental: the post-classification cache load has no
        // platform DB in this suite. The state is set before it.
      }
      expect(provider.connectivityState, ConnectivityState.offline);
      expect(provider.lastFetchSucceeded, isFalse);
    });

    test('invalid JSON - the transformer re-wrap carries no response - '
        'falls to offline the same way', () async {
      await expectFetchState(
        (options) => DioException(
          requestOptions: options,
          error: const FormatException('Unexpected character'),
        ),
        ConnectivityState.offline,
      );
    });
  });

  group('a save beats an in-flight fetch (invariant 40)', () {
    test('an in-flight failure for the previous server does not re-arm '
        'unreachable after the save', () async {
      final provider = providerDelayed(
        const Duration(milliseconds: 300),
        buildError: connectionTimeout,
      );
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');
      final fetch = provider.fetchPlaylists(); // in flight for 300 ms
      // The documented retry->save recovery flow: the old server's timeout
      // is still running when the corrected URL is saved.
      await provider.setServerUrl('http://10.0.0.5:3689');
      await fetch;
      expect(provider.connectivityState, ConnectivityState.offline);
      expect(provider.lastFetchSucceeded, isFalse);
      expect(provider.availablePlaylists, isEmpty);
    });

    test('an in-flight success for the previous server does not assert '
        'reachable or freshness after the save', () async {
      final provider = providerDelayed(
        const Duration(milliseconds: 300),
        succeed: true,
        buildError: connectionTimeout,
      );
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');
      final fetch = provider.fetchPlaylists();
      await provider.setServerUrl('http://10.0.0.5:3689');
      await fetch;
      expect(provider.connectivityState, ConnectivityState.offline);
      expect(provider.lastFetchSucceeded, isFalse);
      expect(provider.availablePlaylists, isEmpty);
    });
  });

  group('a sync run proves reachability only on success (invariant 40)', () {
    test('success establishes reachable and clears the error string',
        () async {
      final provider = await expectFetchState(
        connectionTimeout,
        ConnectivityState.unreachable,
      );
      await emitCompletion(provider, 'success');
      expect(provider.connectivityState, ConnectivityState.reachable);
      expect(provider.lastError, isNull);
    });

    test('partial establishes reachable', () async {
      final provider = await expectFetchState(
        connectionTimeout,
        ConnectivityState.unreachable,
      );
      await emitCompletion(provider, 'partial');
      expect(provider.connectivityState, ConnectivityState.reachable);
    });

    test('a failed run keeps the previous state; its message is kept for '
        'logs, never rendered', () async {
      final provider = await expectFetchState(
        connectionTimeout,
        ConnectivityState.unreachable,
      );
      await emitCompletion(provider, 'failed', message: 'boom');
      expect(provider.connectivityState, ConnectivityState.unreachable);
      expect(provider.lastError, 'boom');
    });

    test('a cancelled run keeps a fresh reachable (it does not demote)',
        () async {
      final provider = await expectFetchState(
        connectionTimeout,
        ConnectivityState.unreachable,
      );
      await emitCompletion(provider, 'success');
      await emitCompletion(provider, 'cancelled');
      expect(provider.connectivityState, ConnectivityState.reachable);
    });
  });

  group('a pending (enqueued) sync still gets a subscriber (invariant 52)',
      () {
    test('the probe subscribes without claiming a run; the first progress '
        'event flips isSyncing on; completion still reconciles', () async {
      final provider = providerFailing(connectionTimeout);
      addTearDown(provider.dispose);
      await settle();
      // Settle the _initialize probe explicitly against 'none': no
      // subscription, nothing claimed.
      syncWorkState = 'none';
      await provider.checkIfSyncRunning();
      expect(progressSink, isNull);
      expect(provider.isSyncing, isFalse);

      // The work is enqueued (scheduled sync before its fire time). The
      // subscriber must exist or the worker's completion broadcast posts
      // to a null eventSink and is dropped — the stale-playlist-count
      // defect (blockers 2026-10-22).
      syncWorkState = 'pending';
      await provider.checkIfSyncRunning();
      expect(
        progressSink,
        isNotNull,
        reason: 'an enqueued work needs a subscriber before it fires',
      );
      expect(
        provider.isSyncing,
        isFalse,
        reason: 'nothing is running yet — the UI must not claim it',
      );

      // The worker starts: the first progress event flips the running UI
      // on (the subscription made this deliverable).
      progressSink!.success(<String, Object?>{
        'currentPlaylist': 'Brass',
        'totalPlaylists': 1,
        'currentPlaylistIndex': 0,
        'totalTracks': 2,
        'downloadedTracks': 1,
        'currentTrackTitle': 'a track',
        'downloadProgress': null,
      });
      await settle();
      expect(provider.isSyncing, isTrue);

      // Completion still reconciles: reachability and the syncCompleted
      // broadcast the LibraryScreen refresh rides on.
      final completed = <String>[];
      final subscription = provider.syncCompleted.listen(completed.add);
      addTearDown(subscription.cancel);
      await emitCompletion(provider, 'success');
      expect(completed, ['success']);
      expect(provider.connectivityState, ConnectivityState.reachable);
    });
  });

  group('startSync refusal (U1 build item 1)', () {
    test('no playlists selected returns the reason, sets no error state',
        () async {
      final provider = providerFailing(connectionTimeout);
      addTearDown(provider.dispose);
      await settle();
      expect(
        await provider.startSync(),
        'Select at least one playlist to sync',
      );
      expect(provider.connectivityState, ConnectivityState.unconfigured);
      expect(provider.isSyncing, isFalse);
    });
  });

  group('the manual sync guard (U2, build item 2; invariant 43)', () {
    test('a probe that classified offline refuses the start before the '
        'worker is reached', () async {
      final provider = await expectFetchState(
        netUnreachable,
        ConnectivityState.offline,
      );
      expect(provider.manualSyncBlocked, isTrue);
      expect(await provider.startSync(), offlineSyncRefusal);
      // No enqueue: no worker run, so no sync_history row can be written.
      expect(triggerBackgroundSyncInvoked, isFalse);
      expect(provider.isSyncing, isFalse);
    });

    test('saving a URL (unverified) does not refuse: no probe has '
        'established absence (invariants 39-40)', () async {
      final provider = providerFailing(netUnreachable);
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');
      expect(provider.connectivityState, ConnectivityState.offline);
      expect(provider.manualSyncBlocked, isFalse);
      await provider.togglePlaylistSelection(1);
      expect(await provider.startSync(), isNull);
      expect(triggerBackgroundSyncInvoked, isTrue);
      expect(provider.isSyncing, isTrue);
    });

    test('a save after an offline probe returns to unverified: the '
        'previous address\'s classification does not carry over', () async {
      final provider = await expectFetchState(
        netUnreachable,
        ConnectivityState.offline,
      );
      await provider.setServerUrl('http://10.0.0.5:3689');
      expect(provider.connectivityState, ConnectivityState.offline);
      expect(provider.manualSyncBlocked, isFalse);
    });

    test('unreachable keeps the manual attempt (U2, build item 2)',
        () async {
      final provider = await expectFetchState(
        connectionTimeout,
        ConnectivityState.unreachable,
      );
      expect(provider.manualSyncBlocked, isFalse);
      await provider.togglePlaylistSelection(1);
      expect(await provider.startSync(), isNull);
      expect(triggerBackgroundSyncInvoked, isTrue);
    });

    test('a stale completion establishing reachable does not refuse '
        '(blockers.md 2026-10-10)', () async {
      final provider = providerFailing(netUnreachable);
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');
      // A run started against the previous server completes after the
      // save and sets reachable without probing the new host.
      await emitCompletion(provider, 'success');
      expect(provider.connectivityState, ConnectivityState.reachable);
      expect(provider.manualSyncBlocked, isFalse);
      await provider.togglePlaylistSelection(1);
      expect(await provider.startSync(), isNull);
      expect(triggerBackgroundSyncInvoked, isTrue);
    });

    test('a stale completion after an offline probe does not re-arm the '
        'block (blockers.md 2026-10-10)', () async {
      // The probe classified offline; the stale completion flips the state
      // to reachable but leaves the probe. The guard reads both: the state
      // is no longer offline, so the attempt is allowed - at worst it
      // fails for a real reason, as the unreachable retry does.
      final provider = await expectFetchState(
        netUnreachable,
        ConnectivityState.offline,
      );
      await emitCompletion(provider, 'success');
      expect(provider.connectivityState, ConnectivityState.reachable);
      expect(provider.manualSyncBlocked, isFalse);
      await provider.togglePlaylistSelection(1);
      expect(await provider.startSync(), isNull);
    });

    test('a successful fetch after an offline probe lifts the block',
        () async {
      // The return-home flow: the probe that established offline is
      // superseded by a fetch that reaches the server.
      DioException Function(RequestOptions)? nextFetchError;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (nextFetchError != null) {
              handler.reject(nextFetchError(options));
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: playlistsJson,
                ),
              );
            }
          },
        ),
      );
      final provider = SyncProvider(
        apiRepository: (baseUrl) =>
            OwnToneApiRepository(baseUrl: baseUrl, dio: dio),
      );
      addTearDown(provider.dispose);
      await settle();
      await provider.setServerUrl('http://192.168.1.13:3689');

      nextFetchError = netUnreachable;
      try {
        await provider.fetchPlaylists();
      } catch (_) {
        // Environmental: the post-classification cache load has no
        // platform DB in this suite. The state is set before it.
      }
      expect(provider.connectivityState, ConnectivityState.offline);
      expect(provider.manualSyncBlocked, isTrue);

      nextFetchError = null;
      await provider.fetchPlaylists();
      expect(provider.connectivityState, ConnectivityState.reachable);
      expect(provider.manualSyncBlocked, isFalse);
      await provider.togglePlaylistSelection(1);
      expect(await provider.startSync(), isNull);
      expect(triggerBackgroundSyncInvoked, isTrue);
    });
  });
}
