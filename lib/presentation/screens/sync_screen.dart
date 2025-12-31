import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import '../../domain/services/sync_service.dart';
import 'server_config_screen.dart';
import 'schedule_config_screen.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, provider, child) {
        if (!provider.hasStoragePermission) {
          return _buildPermissionRequest(context, provider);
        }

        if (!provider.isConfigured) {
          return _buildNotConfigured(context);
        }

        if (provider.availablePlaylists.isEmpty) {
          return _buildInitialSetup(context, provider);
        }

        return _buildPlaylistSelection(context, provider);
      },
    );
  }

  Widget _buildNotConfigured(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dns, size: 64),
            const SizedBox(height: 24),
            const Text(
              'Server Not Configured',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Configure your OwnTone server URL to get started.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ServerConfigScreen()),
                );
              },
              icon: const Icon(Icons.settings),
              label: const Text('Configure Server'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionRequest(BuildContext context, SyncProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 64),
            const SizedBox(height: 24),
            const Text(
              'Storage Permission Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'This app needs permission to save music files to your device.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await provider.requestStoragePermission();
              },
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialSetup(BuildContext context, SyncProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Server URL:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              provider.serverUrl,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.isSyncing
                  ? null
                  : () async {
                      await provider.fetchPlaylists();
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Load Playlists'),
            ),
            if (provider.lastError != null) ...[
              const SizedBox(height: 16),
              Text(
                provider.lastError!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistSelection(BuildContext context, SyncProvider provider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${provider.selectedPlaylistIds.length} playlists selected',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              ElevatedButton.icon(
                onPressed: provider.isSyncing
                    ? null
                    : () => provider.startSync(),
                icon: const Icon(Icons.sync),
                label: const Text('Sync'),
              ),
            ],
          ),
        ),
        if (!provider.isOnline)
          Container(
            width: double.infinity,
            color: Colors.orange.shade100,
            padding: const EdgeInsets.all(12),
            child: const Row(
              children: [
                Icon(Icons.cloud_off, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Offline - showing cached playlists',
                  style: TextStyle(color: Colors.orange),
                ),
              ],
            ),
          ),
        if (provider.isSyncing && provider.syncProgress != null)
          _buildSyncProgress(provider.syncProgress!),

        // Sync options section
        Card(
          margin: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sync Options',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              CheckboxListTile(
                title: const Text('Delete orphaned files'),
                subtitle: const Text('Remove files not in any synced playlist'),
                value: provider.deleteOrphanedFiles,
                onChanged: provider.isSyncing
                    ? null
                    : (value) =>
                          provider.setDeleteOrphanedFiles(value ?? false),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Sync Schedule'),
                subtitle: Text(provider.syncSchedule.getScheduleDescription()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ScheduleConfigScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Playlists',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: provider.availablePlaylists.length,
            itemBuilder: (context, index) {
              final playlist = provider.availablePlaylists[index];
              final isSelected = provider.selectedPlaylistIds.contains(
                playlist.id,
              );

              return CheckboxListTile(
                title: Text(
                  playlist.name,
                  style: provider.isOnline
                      ? null
                      : const TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                ),
                subtitle: Text(
                  provider.isOnline
                      ? '${playlist.itemCount} tracks'
                      : '${playlist.itemCount} tracks (offline)',
                  style: provider.isOnline
                      ? null
                      : const TextStyle(color: Colors.grey),
                ),
                value: isSelected,
                onChanged: provider.isSyncing
                    ? null
                    : (_) {
                        provider.togglePlaylistSelection(playlist.id);
                      },
              );
            },
          ),
        ),
        if (provider.lastError != null)
          Container(
            width: double.infinity,
            color: Colors.red.shade100,
            padding: const EdgeInsets.all(16),
            child: Text(
              provider.lastError!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }

  Widget _buildSyncProgress(SyncProgress progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Syncing: ${progress.currentPlaylist}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Consumer<SyncProvider>(
                builder: (context, provider, child) {
                  return TextButton.icon(
                    onPressed: provider.isCancelling
                        ? null
                        : () => provider.cancelSync(),
                    icon: const Icon(Icons.cancel, size: 16),
                    label: Text(
                      provider.isCancelling ? 'Cancelling...' : 'Cancel',
                    ),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (progress.currentTrackTitle != null)
            Text('Downloading: ${progress.currentTrackTitle}'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.downloadProgress),
          const SizedBox(height: 4),
          Text(
            'Playlist ${progress.currentPlaylistIndex + 1}/${progress.totalPlaylists} - '
            'Track ${progress.downloadedTracks}/${progress.totalTracks}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
