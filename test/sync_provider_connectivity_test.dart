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
/// short-circuit, and the failure path's post-classification cache load
/// throws an environmental error that is swallowed after the state is set.
/// The one transition not covered here is fetch *success* -> reachable: its
/// cache writes need a platform DB. The equivalent "a run proved
/// reachability" transition is guarded below via the worker's completion
/// event, and the successful fetch is covered by on-device evidence
/// (reports/phase-u1-report.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const syncChannel = 'dev.educoder.owntone_sync/sync';
  const progressChannel = 'dev.educoder.owntone_sync/sync_progress';

  MockStreamHandlerEventSink? progressSink;

  // The mocked worker's "is a sync running" answer. Kept false by default:
  // a running sync would set SyncProvider.isSyncing during _initialize,
  // which the refusal test must not see. emitCompletion turns it on just
  // long enough to establish the progress subscription.
  bool syncRunning = false;

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
      syncRunning = true;
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
    syncRunning = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(syncChannel),
      (call) async {
        if (call.method == 'isSyncRunning') return syncRunning;
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
}
