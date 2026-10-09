/// The parts of a server URL that decide which server it points at.
///
/// Used to decide whether a change to the server URL invalidates the stored
/// library. OwnTone track IDs are assigned by the server, so the metadata
/// only becomes meaningless when the *server* changes - not when the text in
/// the field changes. Whitespace, scheme or host case, trailing slashes, and
/// an omitted default port (80 for http, 443 for https) are cosmetic
/// differences that must not look like a server change.
///
/// [host] is the identity that matters most: two URLs with the same host are
/// the same machine even if the port or scheme differs.
class ServerUrlIdentity {
  final String scheme;
  final String host;
  final int port;
  final String path;

  const ServerUrlIdentity({
    required this.scheme,
    required this.host,
    required this.port,
    required this.path,
  });

  @override
  bool operator ==(Object other) =>
      other is ServerUrlIdentity &&
      other.scheme == scheme &&
      other.host == host &&
      other.port == port &&
      other.path == path;

  @override
  int get hashCode => Object.hash(scheme, host, port, path);
}

/// Parses [url] into a [ServerUrlIdentity], normalising the cosmetic
/// differences described on [ServerUrlIdentity].
///
/// Returns null when [url] is empty, does not parse, is not an absolute
/// http(s) URL, or has no host. Callers must treat a null result as "cannot
/// prove the server is the same" - never as "the server changed".
ServerUrlIdentity? parseServerUrlIdentity(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } on FormatException {
    return null;
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;

  const defaultPorts = {'http': 80, 'https': 443};
  final port = uri.hasPort ? uri.port : defaultPorts[scheme]!;

  final path = uri.path.replaceAll(RegExp(r'/+$'), '');

  return ServerUrlIdentity(
    scheme: scheme,
    host: host,
    port: port,
    path: path,
  );
}
