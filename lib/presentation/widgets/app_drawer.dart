import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/sync_history.dart';
import '../providers/sync_provider.dart';
import '../screens/about_screen.dart';
import '../screens/history_screen.dart';
import '../screens/schedule_config_screen.dart';
import '../screens/server_config_screen.dart';
import '../screens/storage_screen.dart';
import '../screens/sync_screen.dart';

/// The app drawer: sync, schedule, server, storage, history, about, and a
/// Sync now action.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _openRoute(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// The header's status line: freshness, not fault. The wording follows
  /// the history row's status and the time is relative (U1 build item 4).
  /// The header is deliberately a plain column of status lines so the U4
  /// settings regroup is additive to it.
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

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final serverUrl = syncProvider.serverUrl;
    final lastSync = syncProvider.lastSync;

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
                  'OwnTone',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  serverUrl.isEmpty ? 'Server not configured' : serverUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
            leading: const Icon(Icons.schedule),
            title: const Text('Schedule'),
            onTap: () => _openRoute(context, const ScheduleConfigScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('Server'),
            onTap: () => _openRoute(context, const ServerConfigScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Storage'),
            onTap: () => _openRoute(context, const StorageScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () => _openRoute(context, const HistoryScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () => _openRoute(context, const AboutScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('Sync now'),
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
