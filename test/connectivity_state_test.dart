import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/utils/connectivity_state.dart';

/// Phase U1 (ux-refactor.md §6): the failure classifier is the load-bearing
/// decision of the phase. It is pure and unit-tested here so the four-state
/// connectivity model holds without a device, and so there is exactly one
/// place to change if errno classification ever proves unreliable.
///
/// The behaviours guarded, straight from build item 2:
/// - ENETUNREACH / no route          -> [ConnectivityState.offline]
/// - ECONNREFUSED or timeout (route) -> [ConnectivityState.unreachable]
/// - server answered with an HTTP status -> [ConnectivityState.reachable]
/// - unclassifiable                  -> [ConnectivityState.offline]
///   (unknown is never presented as a server fault - the Phase U0 rule that
///   an unprovable case resolves to the non-destructive conclusion)
/// - **type and errno only, never message text** - the OS-reported address
///   and port in a SocketException message have been observed to be wrong
///   (ux-refactor §3, State 3), so a classifier that reads text would pass
///   here and fail in the field.
void main() {
  SocketException socket(int errno, {String message = 'Connection failed'}) {
    return SocketException(
      message,
      address: InternetAddress('192.168.1.13'),
      port: 3689,
      // OSError is (message, errorCode); errorCode is the errno.
      osError: OSError('error $errno', errno),
    );
  }

  DioException wrap(Object cause,
      {DioExceptionType type = DioExceptionType.connectionError}) {
    return DioException(
      requestOptions: RequestOptions(path: '/api/library/playlists'),
      type: type,
      error: cause,
    );
  }

  group('no route to the network is offline (U1, build item 2)', () {
    test('ENETUNREACH (101) is offline', () {
      expect(classifySyncFailure(socket(101)),
          ConnectivityState.offline);
    });

    test('EHOSTUNREACH (113) is offline', () {
      expect(classifySyncFailure(socket(113)),
          ConnectivityState.offline);
    });

    test('the same failures stay offline inside a DioException', () {
      // fetchPlaylists throws what Dio wraps; the classifier must see
      // through the wrapper to the errno.
      expect(classifySyncFailure(wrap(socket(101))),
          ConnectivityState.offline);
      expect(classifySyncFailure(wrap(socket(113))),
          ConnectivityState.offline);
    });
  });

  group('a route that the server does not answer is unreachable '
      '(U1, build item 2)', () {
    test('ECONNREFUSED (111) is unreachable', () {
      expect(classifySyncFailure(socket(111)),
          ConnectivityState.unreachable);
    });

    test('ETIMEDOUT (110) is unreachable', () {
      expect(classifySyncFailure(socket(110)),
          ConnectivityState.unreachable);
    });

    test('a Dart TimeoutException is unreachable', () {
      expect(classifySyncFailure(TimeoutException('connect')),
          ConnectivityState.unreachable);
    });

    test('the same failures stay unreachable inside a DioException', () {
      expect(classifySyncFailure(wrap(socket(111))),
          ConnectivityState.unreachable);
      expect(
        classifySyncFailure(
          wrap(TimeoutException('connect'),
              type: DioExceptionType.connectionTimeout),
        ),
        ConnectivityState.unreachable,
      );
    });
  });

  group('a server that answered is reachable (U1, build item 2)', () {
    test('a DioException carrying a response classifies reachable', () {
      final response = Response(
        requestOptions: RequestOptions(path: '/api/library/playlists'),
        statusCode: 500,
      );
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/library/playlists'),
        type: DioExceptionType.badResponse,
        response: response,
      );
      // An HTTP error is not a connectivity problem: the connection worked.
      expect(classifySyncFailure(error), ConnectivityState.reachable);
    });
  });

  group('the message text is never consulted (U1, build item 2, load-bearing)',
      () {
    test('a lying "unreachable" message does not win over errno 111', () {
      // The text claims the network is down; the errno says the host
      // refused. The errno is the ground truth the kernel gave the VM,
      // and the text has been observed to report the wrong port.
      final liar = SocketException(
        'Connection failed (OS Error: Network is unreachable, '
        'errno = 101), address = 192.168.1.13, port = 37830',
        address: InternetAddress('192.168.1.13'),
        port: 37830,
        osError: const OSError('Connection refused', 111),
      );
      expect(classifySyncFailure(liar), ConnectivityState.unreachable);
    });

    test('a lying "refused" message does not win over errno 101', () {
      final liar = SocketException(
        'Connection failed (OS Error: Connection refused, '
        'errno = 111), address = 127.0.0.1, port = 9999',
        address: InternetAddress('127.0.0.1'),
        port: 9999,
        osError: const OSError('Network is unreachable', 101),
      );
      expect(classifySyncFailure(liar), ConnectivityState.offline);
    });
  });

  group('unknown is not a fault (U1, build item 2; the U0 rule)', () {
    test('a SocketException with no errno cannot prove a fault', () {
      expect(
        classifySyncFailure(
          SocketException('Connection reset by peer'),
        ),
        ConnectivityState.offline,
      );
    });

    test('an errno this classifier does not know cannot prove a fault', () {
      expect(classifySyncFailure(socket(104)), ConnectivityState.offline);
    });

    test('a bare HttpException cannot prove a fault', () {
      expect(
        classifySyncFailure(const HttpException('Connection reset')),
        ConnectivityState.offline,
      );
    });

    test('an unrecognised object cannot prove a fault', () {
      expect(
        classifySyncFailure(Exception('something unclassifiable')),
        ConnectivityState.offline,
      );
    });

    test('a DioException with no cause and no response cannot prove a fault',
        () {
      expect(
        classifySyncFailure(
          DioException(
            requestOptions:
                RequestOptions(path: '/api/library/playlists'),
          ),
        ),
        ConnectivityState.offline,
      );
    });
  });

  group('the unreachable sentence (U1, build item 3)', () {
    test('names the host, never a raw exception', () {
      expect(
        describeUnreachable('http://192.168.1.13:3689'),
        "Can't reach 192.168.1.13 - is your server running?",
      );
    });

    test('falls back to the raw URL only when no host can be parsed', () {
      // The form validator keeps such values out of the app, but the
      // sentence must not crash on one: name what we were given.
      expect(
        describeUnreachable('not a url at all'),
        "Can't reach not a url at all - is your server running?",
      );
    });
  });
}
