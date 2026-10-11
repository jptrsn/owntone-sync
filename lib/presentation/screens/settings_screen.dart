import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../widgets/player_scaffold.dart';
import 'about_screen.dart';
import 'schedule_config_screen.dart';
import 'server_config_screen.dart';
import 'storage_screen.dart';

/// The destination that groups the four configuration screens (U4 build
/// item 2): the drawer no longer lists them individually, it points here.
/// This is navigation only — each destination keeps its own screen and
/// behaviour, and the mini player is docked via PlayerScaffold like every
/// other destination (invariant 16).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _openRoute(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final chevron = const Icon(Icons.chevron_right);
    return PlayerScaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: ListView(
        children: [
          Consumer<SyncProvider>(
            builder: (context, provider, _) {
              return ListTile(
                leading: const Icon(Icons.dns),
                title: const Text('Server'),
                subtitle: Text(
                  provider.serverUrl.isEmpty
                      ? 'Not configured'
                      : provider.serverUrl,
                ),
                trailing: chevron,
                onTap: () => _openRoute(context, const ServerConfigScreen()),
              );
            },
          ),
          Consumer<SyncProvider>(
            builder: (context, provider, _) {
              return ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Storage'),
                subtitle: Text(
                  provider.hasStoragePermission
                      ? 'Folder access granted'
                      : 'No folder access',
                ),
                trailing: chevron,
                onTap: () => _openRoute(context, const StorageScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Schedule'),
            subtitle: const Text('Background sync'),
            trailing: chevron,
            onTap: () => _openRoute(context, const ScheduleConfigScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            trailing: chevron,
            onTap: () => _openRoute(context, const AboutScreen()),
          ),
        ],
      ),
    );
  }
}
