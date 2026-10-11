import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/data/repositories/owntone_api_repository.dart';
import 'package:owntone_sync/utils/connectivity_state.dart';

/// Phase U3 (ux-refactor.md §6, P5): the test-connection step of the
/// guided first-run flow reports right/wrong about the entered address
/// *before anything is saved*.
///
/// Behaviour guarded here:
/// - any HTTP answer is "right": the probe is a liveness check, and the
///   endpoint's own status (even 4xx/5xx) is not what is being tested;
/// - a connection-level failure is "wrong", classified by the same pure
///   function the rest of the app uses (invariant 39) - never by message
///   text;
/// - an unclassifiable failure is "wrong": an unprovable case never
///   reports a false "right" (invariant 39's unknown rule).
///
/// Exception shapes are built with dio's own factory constructors
/// (pub cache lib/src/dio_exception.dart) - never hand-rolled
/// substitutes (suite convention, sync_provider_connectivity_test.dart).
void main() {
  group('isProbeSuccess: the test-connection verdict (U3 build item)', () {
    test('a completed probe (2xx) is right', () {
      expect(isProbeSuccess(null), isTrue);
    });

    test('an HTTP error status is right - the server answered - even '
        'though the probe endpoint itself did not like the request',
        () {
      // The user's OwnTone version answers GET /api/now-playing with a
      // 400 page; the liveness conclusion must still be "right".
      final options = RequestOptions(
        path: 'http://192.168.1.13:3689/api/now-playing',
      );
      final error = DioException.badResponse(
        statusCode: 400,
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 400),
      );
      expect(classifySyncFailure(error), ConnectivityState.reachable);
      expect(isProbeSuccess(error), isTrue);
    });

    test('a refused connection is wrong', () {
      final options = RequestOptions(
        path: 'http://192.168.1.13:9999/api/now-playing',
      );
      final error = DioException.connectionError(
        requestOptions: options,
        reason: 'Connection failed',
        error: SocketException(
          'Connection failed (OS Error: Connection refused, errno = 111), '
          'address = 192.168.1.13, port = 9999',
          address: InternetAddress('192.168.1.13'),
          port: 9999,
          osError: const OSError('Connection refused', 111),
        ),
      );
      expect(classifySyncFailure(error), ConnectivityState.unreachable);
      expect(isProbeSuccess(error), isFalse);
    });

    test('a 10 s connect timeout is wrong (dio builds it with no error)',
        () {
      final options = RequestOptions(
        path: 'http://192.168.1.99:3689/api/now-playing',
      );
      final error = DioException.connectionTimeout(
        requestOptions: options,
        timeout: const Duration(seconds: 10),
      );
      expect(classifySyncFailure(error), ConnectivityState.unreachable);
      expect(isProbeSuccess(error), isFalse);
    });

    test('a no-route failure (errno 101) is wrong', () {
      final options = RequestOptions(
        path: 'http://192.168.1.13:3689/api/now-playing',
      );
      final error = DioException.connectionError(
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
      expect(classifySyncFailure(error), ConnectivityState.offline);
      expect(isProbeSuccess(error), isFalse);
    });

    test('an unclassifiable failure is wrong - never a false right', () {
      final error = const FormatException('Unexpected character');
      expect(classifySyncFailure(error), ConnectivityState.offline);
      expect(isProbeSuccess(error), isFalse);
    });
  });

  group('probeConnection: the probe is the cheap endpoint, not a fetch '
      '(U3 risk note: it must not be a full fetchPlaylists)', () {
    test('GETs /api/now-playing', () async {
      final paths = <String>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            paths.add(options.path);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{},
              ),
            );
          },
        ),
      );
      final repo = OwnToneApiRepository(
        baseUrl: 'http://192.168.1.13:3689',
        dio: dio,
      );
      await repo.probeConnection();
      expect(paths, ['/api/now-playing']);
    });

    test('lets an HTTP error status propagate for the classifier to read '
        'as an answer', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException.badResponse(
                statusCode: 404,
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
              ),
            );
          },
        ),
      );
      final repo = OwnToneApiRepository(
        baseUrl: 'http://192.168.1.13:3689',
        dio: dio,
      );
      Object? caught;
      try {
        await repo.probeConnection();
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<DioException>());
      // The screen's verdict reads it as a live server (the first group
      // asserts the same shape classifies reachable).
      expect(isProbeSuccess(caught), isTrue);
    });
  });
}
