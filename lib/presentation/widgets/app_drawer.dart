import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final serverUrl = syncProvider.serverUrl;

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
              Navigator.of(context).pop();
              if (syncProvider.isConfigured &&
                  syncProvider.hasStoragePermission) {
                syncProvider.startSync();
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
