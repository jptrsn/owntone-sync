import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/server_url.dart';
import '../providers/browse_provider.dart';
import '../providers/sync_provider.dart';

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
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final String _originalServerUrl;

  @override
  void initState() {
    super.initState();
    final provider = context.read<SyncProvider>();
    _originalServerUrl = provider.serverUrl;
    _urlController = TextEditingController(
      text: provider.serverUrl.isNotEmpty
          ? provider.serverUrl
          : 'http://192.168.1.100:3689',
    );
  }

  @override
  void dispose() {
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

  /// Saves the URL, clears any surfaced error, and closes the screen.
  /// [confirmation] is a snackbar shown after the pop; null saves silently.
  Future<void> _saveUrl(
    SyncProvider provider,
    String url, {
    String? confirmation,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await provider.setServerUrl(url);
    provider.clearError();

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

      // Set new server URL
      await provider.setServerUrl(newUrl);
      provider.clearError();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  'Enter your OwnTone server URL',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.100:3689',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  validator: _validateServerUrl,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
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
