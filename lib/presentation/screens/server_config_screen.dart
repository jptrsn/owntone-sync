import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/owntone_api_repository.dart';
import '../../data/services/server_discovery_service.dart';
import '../../utils/connectivity_state.dart';
import '../../utils/server_url.dart';
import '../providers/browse_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/player_scaffold.dart';

/// The test-connection step's phase (Phase U3, ux-refactor §6 P5): the
/// result is shown inline, before anything is saved.
enum _ProbePhase { idle, testing, ok, failedUnreachable, failedOffline }

/// What saving this URL actually does, decided by comparing the
/// normalised old and new values (see [parseServerUrlIdentity]).
enum _ChangeKind {
  /// No URL was configured before; there is nothing to wipe.
  firstSetup,

  /// The values differ only cosmetically (whitespace, case, trailing
  /// slash, omitted default port): the same server.
  unchanged,

  /// Same host, different port or scheme: the same machine.
  sameHost,

  /// Different host, and the user confirmed it is the same server at a
  /// new address: keep the library.
  sameServerNewAddress,

  /// Different host, and the user confirmed it is a different server:
  /// wipe the library.
  differentServer,
}

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({
    super.key,
    this.startAdvancedExpanded = false,
    @visibleForTesting this.discovery,
    @visibleForTesting this.probeOverride,
  });

  /// First run's secondary "Enter address manually (advanced)" button
  /// pushes the screen with the Advanced tile already open (issue 13):
  /// the manual path must never dead-end behind a collapsed control.
  final bool startAdvancedExpanded;

  /// Test seam: inject a fake discovery service so widget tests drive a
  /// scan with no platform channel (the EventChannel is only touched when
  /// the screen owns its service). Production passes nothing.
  @visibleForTesting
  final ServerDiscoveryService? discovery;

  /// Test seam mirroring `SyncProvider`'s `apiRepository` seam: replaces
  /// [OwnToneApiRepository.probeConnection] for `_runProbe` so widget
  /// tests assert the probe contract with no network. Production passes
  /// nothing and the default below runs byte-for-byte the old call.
  @visibleForTesting
  final Future<void> Function(String url)? probeOverride;

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final String _originalServerUrl;

  _ProbePhase _probe = _ProbePhase.idle;

  late final ServerDiscoveryService _discovery;
  late final bool _ownsDiscovery;
  final ExpansibleController _advancedController = ExpansibleController();

  static Future<void> _defaultProbe(String url) =>
      OwnToneApiRepository(baseUrl: url).probeConnection();

  @override
  void initState() {
    super.initState();
    final provider = context.read<SyncProvider>();
    _originalServerUrl = provider.serverUrl;
    // The example URL is a hint, never pre-filled text (U3, P5 change 3):
    // a pre-filled example is saveable text, and an unattended Save would
    // configure a dead server (ux-refactor §3, State 4).
    _urlController = TextEditingController(text: provider.serverUrl);
    _discovery = widget.discovery ?? ServerDiscoveryService();
    _ownsDiscovery = widget.discovery == null;
    _discovery.addListener(_onDiscoveryChanged);
  }

  void _onDiscoveryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _discovery.removeListener(_onDiscoveryChanged);
    if (_ownsDiscovery) _discovery.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String? _validateServerUrl(String? url) {
    if (url == null || url.isEmpty) {
      return 'Please enter a server URL';
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'URL must start with http:// or https://';
    }

    try {
      final uri = Uri.parse(url);
      final host = uri.host;

      if (url.startsWith('http://') && !_isLocalAddress(host)) {
        return 'HTTP is only allowed for local network addresses.\n'
            'Use HTTPS for remote servers, or use a local IP like:\n'
            '• 192.168.x.x\n'
            '• 10.x.x.x\n'
            '• 172.16-31.x.x\n'
            '• localhost / 127.0.0.1';
      }

      return null;
    } catch (e) {
      return 'Invalid URL format';
    }
  }

  /// The test-connection step (Phase U3, ux-refactor §6 P5): probe the
  /// URL currently in the field — not the saved one — with one cheap GET
  /// and show the verdict inline before anything is saved. The verdict
  /// reuses the four-state vocabulary (U1): any HTTP answer is a live
  /// server (isProbeSuccess), and a connection-level failure gets the
  /// same human sentence the unreachable state uses. Raw exceptions never
  /// reach the UI. A result that lands after the field text changed is
  /// discarded: it belongs to the URL it tested.
  Future<void> _runProbe() async {
    final url = _urlController.text.trim();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _probe = _ProbePhase.testing);
    Object? error;
    try {
      await (widget.probeOverride ?? _defaultProbe)(url);
    } on Object catch (e) {
      error = e;
    }
    if (!mounted) return;
    // The field may have been edited while the probe was in flight: the
    // onChanged below already reset the phase to idle, but this result
    // still belongs to the URL it tested. Re-rendering it against the
    // current field text would be a claim about an address that was
    // never probed (invariant 44's invalidation, invariant 41's honesty
    // rule) - so discard it. The mounted check alone does not cover the
    // screen still being open with edited text (review round 1, finding 1).
    if (_urlController.text.trim() != url) return;
    if (isProbeSuccess(error)) {
      setState(() => _probe = _ProbePhase.ok);
    } else {
      setState(
        () => _probe = classifySyncFailure(error!) ==
                ConnectivityState.unreachable
            ? _ProbePhase.failedUnreachable
            : _ProbePhase.failedOffline,
      );
    }
  }

  /// The inline probe result. The failure wording is the one the rest of
  /// the app uses for the same classification (invariant 41's honesty
  /// rule): a claim shown to the user must be true.
  Widget _buildProbeResult(BuildContext context, String url) {
    switch (_probe) {
      case _ProbePhase.idle:
        return const SizedBox.shrink();
      case _ProbePhase.testing:
        return Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Text('Testing connection…'),
          ],
        );
      case _ProbePhase.ok:
        final host = parseServerUrlIdentity(url)?.host ?? url;
        return Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Connected to $host',
                style: TextStyle(color: Colors.green.shade700),
              ),
            ),
          ],
        );
      case _ProbePhase.failedUnreachable:
        final color = Theme.of(context).colorScheme.error;
        return Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                describeUnreachable(url),
                style: TextStyle(color: color),
              ),
            ),
          ],
        );
      case _ProbePhase.failedOffline:
        final color = Colors.orange.shade800;
        return Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No network route to that address - check your connection.',
                style: TextStyle(color: color),
              ),
            ),
          ],
        );
    }
  }

  bool _isLocalAddress(String host) {
    if (host.endsWith('.local')) {
      return true;
    }

    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }

    try {
      final parts = host.split('.');
      if (parts.length != 4) return false;

      final octets = parts.map(int.parse).toList();

      if (octets[0] == 10) return true;
      if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
      if (octets[0] == 192 && octets[1] == 168) return true;
      if (octets[0] == 169 && octets[1] == 254) return true;

      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _handleServerChange() async {
    final newUrl = _urlController.text.trim();
    final original = _originalServerUrl;

    _ChangeKind change = _ChangeKind.firstSetup;
    if (original.isNotEmpty) {
      final oldIdentity = parseServerUrlIdentity(original);
      final newIdentity = parseServerUrlIdentity(newUrl);
      if (oldIdentity != null &&
          newIdentity != null &&
          oldIdentity == newIdentity) {
        change = _ChangeKind.unchanged;
      } else if (oldIdentity != null &&
          newIdentity != null &&
          oldIdentity.host == newIdentity.host) {
        change = _ChangeKind.sameHost;
      } else {
        // A different host - or a value that could not be normalised,
        // which must never trigger a wipe without asking.
        final keepLibrary = await _confirmHostChange();
        if (keepLibrary == null) return; // Cancelled: nothing saved.
        if (!mounted) return;
        change = keepLibrary
            ? _ChangeKind.sameServerNewAddress
            : _ChangeKind.differentServer;
      }
    }

    if (!mounted) return;
    final provider = context.read<SyncProvider>();

    switch (change) {
      case _ChangeKind.firstSetup:
      case _ChangeKind.unchanged:
        await _saveUrl(provider, newUrl);
      case _ChangeKind.sameHost:
      case _ChangeKind.sameServerNewAddress:
        await _saveUrl(
          provider,
          newUrl,
          confirmation: change == _ChangeKind.sameHost
              ? 'Server address updated.'
              : 'Server address updated. Your library was kept.',
        );
      case _ChangeKind.differentServer:
        await _wipeAndSave(provider, newUrl);
    }
  }

  /// Saves the URL (which drops any surfaced error state to the unverified
  /// rendering - invariant 40) and closes the screen.
  /// [confirmation] is a snackbar shown after the pop; null saves silently.
  Future<void> _saveUrl(
    SyncProvider provider,
    String url, {
    String? confirmation,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await provider.setServerUrl(url);

    if (!mounted) return;
    navigator.pop();
    if (confirmation != null) {
      messenger.showSnackBar(SnackBar(content: Text(confirmation)));
    }
  }

  /// Asks whether a changed host means a different server. Returns true to
  /// keep the library (the non-destructive default - a home server getting a
  /// new DHCP address is at least as likely as a genuinely different server),
  /// false for a different server, or null if the user cancels.
  Future<bool?> _confirmHostChange() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Different server?'),
        content: Text(
          'The server address is changing from $_originalServerUrl '
          'to ${_urlController.text.trim()}.\n\n'
          'If this is the same server at a new address - for example after '
          'your router assigned it a new IP - your synced library can stay. '
          'If it is a different server, the library must be reset, because '
          'the track IDs from the old server will not match there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Start fresh'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keep library'),
          ),
        ],
      ),
    );
  }

  /// The wipe path, reached only after the user confirmed the new host is a
  /// different server. Asks about the music files, resets the app data,
  /// saves the new URL, and reloads the browse data so the Library matches
  /// the database immediately.
  Future<void> _wipeAndSave(SyncProvider provider, String newUrl) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start fresh?'),
        content: const Text(
          'All synced playlists, tracks, and sync history will be deleted.\n\n'
          'Do you want to delete the downloaded music files as well?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep_files'),
            child: const Text('Keep Files'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('delete_files'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete Files'),
          ),
        ],
      ),
    );

    if (result == 'cancel' || result == null) {
      return;
    }

    if (!mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Reset app data
      await provider.resetAppData(deleteFiles: result == 'delete_files');

      // Set new server URL (drops the surfaced error state - invariant 40)
      await provider.setServerUrl(newUrl);

      if (!mounted) return;

      // The library is now empty in the database: reload every browse
      // category so the Library matches it immediately. A current-tab-only
      // reload would leave the other tabs showing stale rows.
      await context.read<BrowseProvider>().reloadAll();

      if (!mounted) return;

      navigator.pop(); // Close loading dialog
      navigator.pop(); // Close server config screen

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == 'delete_files'
                ? 'Server changed. All data deleted.'
                : 'Server changed. Music files kept.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error resetting data: $e'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  /// Tapping a probe-verified row is a fill-and-probe, never a save
  /// (invariant 58 — discovery is never a save path; invariant 37 owns
  /// every save): it sets the field text and runs the existing
  /// [_runProbe]. No provider write, no prefs write. The Advanced tile is
  /// expanded so the user sees the field and the verdict the tap produced.
  void _useCandidate(DiscoveryCandidate candidate) {
    _urlController.text = candidate.url;
    setState(() => _probe = _ProbePhase.idle);
    _advancedController.expand();
    _runProbe();
  }

  void _startScan() {
    _discovery.startBrowse();
  }

  Widget _buildScanSection(BuildContext context) {
    switch (_discovery.state) {
      case DiscoveryState.idle:
        return _buildScanButton(label: 'Scan for servers');
      case DiscoveryState.browsing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Scanning the network for OwnTone servers…'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _discovery.stopBrowse,
                child: const Text('Stop scanning'),
              ),
            ),
          ],
        );
      case DiscoveryState.error:
        // Neutral wording, no error colour: a scan surface is not an
        // `unreachable` surface (invariants 41/57 — only 'unreachable'
        // may be red, and only when the user asked — 57).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The server scan failed. Try again, or open "Advanced: enter '
              'address manually" below to type the address.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _buildScanButton(label: 'Scan for servers'),
          ],
        );
      case DiscoveryState.empty:
        // An explicit empty state, never a spinner or a dead end (AC5);
        // the advanced path below stays reachable either way (AC9).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'No OwnTone servers found',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Nothing on this network answered the scan. Open "Advanced: '
              'enter address manually" below to type the address.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _buildScanButton(label: 'Scan again'),
          ],
        );
      case DiscoveryState.candidates:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final candidate in _discovery.candidates)
              _buildCandidateRow(candidate),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _startScan,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Scan again'),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildScanButton({required String label}) {
    return ElevatedButton.icon(
      onPressed: _startScan,
      icon: const Icon(Icons.search, size: 18),
      label: Text(label),
    );
  }

  Widget _buildCandidateRow(DiscoveryCandidate candidate) {
    // Row grammar (maintainer): `Machine Name — host:port`, verified mark
    // only once the probe answered. An unverified row is inert — no
    // onTap — so a candidate whose probe never answers is never
    // selectable (AC5).
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: candidate.verified ? () => _useCandidate(candidate) : null,
      title: Text(
        '${candidate.displayName} — ${candidate.displayHost}:${candidate.port}',
      ),
      trailing: candidate.verified
          ? Icon(Icons.check_circle, size: 18, color: Colors.green.shade700)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // PlayerScaffold: the mini player survives navigating here (Phase U2
    // build item 1); zero-height at idle.
    return PlayerScaffold(
      appBar: AppBar(
        title: const Text('Server Configuration'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.dns, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'OwnTone Server',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scan for your OwnTone server on the network, or enter '
                  'the address manually.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Scan is the screen's lead action (issue 13): rows always
                // render and a row needs a deliberate tap — no scan
                // result is ever saved without one (maintainer rule 3,
                // invariant 58).
                _buildScanSection(context),
                const SizedBox(height: 24),
                // The manual path lives here, always reachable: an empty
                // scan, a scan error, an odd permission state or a
                // captive-portal network must never dead-end (AC9, same
                // honesty rule as the hint-text rule in invariant 44).
                ExpansionTile(
                  controller: _advancedController,
                  initiallyExpanded: widget.startAdvancedExpanded,
                  title: const Text('Advanced: enter address manually'),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _urlController,
                          // A result belongs to the URL it tested: editing
                          // the field invalidates it, or a stale
                          // "Connected" would be a claim about an address
                          // the user no longer has (the same honesty rule
                          // as invariant 41's banners).
                          onChanged: (_) {
                            if (_probe != _ProbePhase.idle) {
                              setState(() => _probe = _ProbePhase.idle);
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'http://192.168.1.100:3689',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.url,
                          validator: _validateServerUrl,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed:
                              _probe == _ProbePhase.testing
                                  ? null
                                  : _runProbe,
                          icon: const Icon(Icons.wifi_tethering, size: 18),
                          label: const Text('Test connection'),
                        ),
                        const SizedBox(height: 12),
                        _buildProbeResult(
                          context,
                          _urlController.text.trim(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Save stays outside the tile — the single save path stays
                // reachable from both modes, and its behaviour is
                // unchanged: Save -> _handleServerChange -> invariant 37.
                ElevatedButton(
                  onPressed: () async {
                    // The field may sit inside the collapsed Advanced tile,
                    // where it is unmounted and unregistered from the Form:
                    // validate its text through the same validator so
                    // collapsing cannot bypass validation, and reveal the
                    // field (and its inline error) when the text is invalid.
                    if (_validateServerUrl(_urlController.text.trim()) !=
                        null) {
                      _advancedController.expand();
                      _formKey.currentState?.validate();
                      return;
                    }
                    if (_formKey.currentState!.validate()) {
                      await _handleServerChange();
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Save', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
