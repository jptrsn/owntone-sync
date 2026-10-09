import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'server_url.dart';

/// The four connectivity states the UI reads (ux-refactor §6, Phase U1).
///
/// - [unconfigured]: no server URL saved. First run is setup, not failure.
/// - [reachable]: the last contact with the server succeeded.
/// - [offline]: no path to the network. The *normal* state away from the
///   home LAN - it is never rendered as an error: no banner, no note,
///   no badge (settled decision 3).
/// - [unreachable]: a path to the network exists but the server is not
///   answering. The one state that may render red.
enum ConnectivityState { unconfigured, reachable, offline, unreachable }

// POSIX (Linux/Android) errno values. Classified by these numbers, never
// by message text - see [classifySyncFailure].
const int _kENETUNREACH = 101;
const int _kECONNREFUSED = 111;
const int _kETIMEDOUT = 110;
const int _kEHOSTUNREACH = 113;

/// Classifies a fetch failure into a [ConnectivityState].
///
/// This is the single place in the app that interprets a network failure,
/// and it is pure on purpose: unit-testable without a device, and if errno
/// classification ever proves unreliable there is exactly one place to swap
/// in a connectivity package (ux-refactor §6, Phase U1, build item 2).
///
/// **It classifies on exception TYPE and `OSError.errorCode` only (the
/// errno the OS returned, distinct from the human-readable `message`
/// field it sits beside). It never reads message text.** The OS-reported
/// address and port inside a `SocketException` message have been observed
/// to be wrong (the Dart VM reports a port the user did not configure -
/// ux-refactor §3, State 3), so substring matching would pass in testing
/// and fail in the field.
///
/// Mapping:
/// - no route to the network (ENETUNREACH, EHOSTUNREACH) -> [offline]:
///   the phone simply has no path to the LAN, the expected condition away
///   from home;
/// - a route exists but the server did not answer (ECONNREFUSED,
///   ETIMEDOUT, a Dart [TimeoutException]) -> [unreachable]: the one
///   genuine fault;
/// - the server answered with an HTTP status (a [DioException] carrying a
///   [DioException.response]) -> [reachable]: the connection worked, so
///   the failure is not a connectivity problem and must not render as one;
/// - anything that cannot be classified -> [offline]: unknown is never
///   presented as a server fault (the Phase U0 rule: an unprovable case
///   resolves to the non-destructive conclusion, never the destructive
///   one).
ConnectivityState classifySyncFailure(Object error) {
  Object cause = error;
  if (error is DioException) {
    // A response means the server spoke back: whatever went wrong, the
    // connection itself worked.
    if (error.response != null) return ConnectivityState.reachable;
    cause = error.error ?? error;
  }

  // A Dio-level or platform timeout: a network path existed, the server
  // did not answer in time.
  if (cause is TimeoutException) return ConnectivityState.unreachable;

  if (cause is SocketException) {
    // The errno the OS returned, not the human-readable message beside it.
    final errno = cause.osError?.errorCode;
    switch (errno) {
      case _kENETUNREACH:
      case _kEHOSTUNREACH:
        return ConnectivityState.offline;
      case _kECONNREFUSED:
      case _kETIMEDOUT:
        return ConnectivityState.unreachable;
      default:
        // No errno, or an errno this classifier does not know: it cannot
        // prove a server fault, so it does not report one.
        return ConnectivityState.offline;
    }
  }

  return ConnectivityState.offline;
}

/// The one user-facing sentence for the [ConnectivityState.unreachable]
/// surfaces: a specific, human message that names the host. Raw exceptions
/// never reach the UI (ux-refactor §4, P1).
String describeUnreachable(String serverUrl) {
  final identity = parseServerUrlIdentity(serverUrl);
  final host = (identity?.host ?? serverUrl).trim();
  return "Can't reach $host - is your server running?";
}
