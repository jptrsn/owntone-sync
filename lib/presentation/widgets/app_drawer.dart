import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/sync_history.dart';
import '../../utils/connectivity_state.dart';
import '../../utils/server_url.dart';
import '../providers/sync_provider.dart';
import '../screens/history_screen.dart';
import '../screens/server_config_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sync_screen.dart';

/// The app drawer: a status header, then Sync / History / Settings, and a
/// Sync now action (U4 build item 2, ux-refactor P8). Server, Storage,
/// Schedule and About are reached through Settings, not listed here.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _openRoute(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// The header's status line: freshness, not fault. The wording follows
  /// the history row's status and the time is relative (U1 build item 4).
  /// The header is a plain column of status lines: the server line is a
  /// tap target that opens the Server screen, "Server not responding"
  /// appears only in the one fault state, and `offline` adds nothing
  /// (settled decision 3).
  static String describeLastSync(SyncHistoryRecord record) {
    final when = relativeTime(
      DateTime.fromMillisecondsSinceEpoch(record.timestamp),
    );
    switch (record.status) {
      case 'success':
      case 'partial':
        return 'Last synced $when';
      case 'failed':
        return 'Last sync failed $when';
      case 'cancelled':
        return 'Last sync cancelled $when';
      case 'skipped':
        return 'Last sync skipped $when';
      case 'interrupted':
        return 'Last sync interrupted $when';
      default:
        return 'Last sync $when';
    }
  }

  /// Compact relative time for the drawer header: "just now", "5m ago",
  /// "2h ago", "3d ago".
  static String relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// The drawer's server line: the address, demoted from a full-URL
  /// headline to a host (plus the port only when one was typed) that opens
  /// the Server screen on tap (U4 build item 2, ux-refactor P8).
  ///
  /// A value that cannot be proved to be an address falls back to the raw
  /// text: the line must never blank out, and unknown is shown as-is, not
  /// resolved to something cleaner (invariant 39's unknown rule).
  static String serverAddress(String serverUrl) {
    final identity = parseServerUrlIdentity(serverUrl);
    if (identity == null) return serverUrl.trim();
    final uri = Uri.tryParse(serverUrl.trim());
    return uri != null && uri.hasPort
        ? '${identity.host}:${identity.port}'
        : identity.host;
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final serverUrl = syncProvider.serverUrl;
    final lastSync = syncProvider.lastSync;
    final isUnreachable =
        syncProvider.connectivityState == ConnectivityState.unreachable;

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Owntone Player',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        _openRoute(context, const ServerConfigScreen()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        serverUrl.isEmpty
                            ? 'Not set up yet'
                            : serverAddress(serverUrl),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
                if (isUnreachable) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Server not responding',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (lastSync != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    describeLastSync(lastSync),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('Sync'),
            onTap: () => _openRoute(context, const SyncScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () => _openRoute(context, const HistoryScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () => _openRoute(context, const SettingsScreen()),
          ),
          const Divider(),
          // Phase U2 build item 2: a verified-offline probe disables the
          // quick sync with helper text (and startSync() refuses it as the
          // belt-and-braces guarantee). Unreachable stays enabled.
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('Sync now'),
            subtitle: syncProvider.manualSyncBlocked
                ? const Text(offlineSyncRefusal)
                : null,
            enabled: !syncProvider.manualSyncBlocked,
            onTap: () {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop();
              if (syncProvider.isConfigured &&
                  syncProvider.hasStoragePermission) {
                // A reason for not starting is surfaced here at the tap
                // site, never as a global error state (U1 build item 1).
                syncProvider.startSync().then((reason) {
                  if (reason != null) {
                    messenger.showSnackBar(SnackBar(content: Text(reason)));
                  }
                });
              } else {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SyncScreen()));
              }
            },
          ),
        ],
      ),
    );
  }
}
