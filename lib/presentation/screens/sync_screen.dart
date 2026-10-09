import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/sync_progress.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../utils/connectivity_state.dart';
import '../providers/sync_provider.dart';
import 'server_config_screen.dart';
import 'schedule_config_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final LocalDatabaseRepository _dbRepo = LocalDatabaseRepository();
  int? _pendingEventCount;

  @override
  void initState() {
    super.initState();
    _loadPendingEventCount();
    // Events are recorded while playing and uploaded by a sync; reload the
    // count whenever the sync state changes.
    context.read<SyncProvider>().addListener(_loadPendingEventCount);
  }

  @override
  void dispose() {
    context.read<SyncProvider>().removeListener(_loadPendingEventCount);
    super.dispose();
  }

  Future<void> _loadPendingEventCount() async {
    try {
      final count = await _dbRepo.getPendingEventCount();
      if (mounted) setState(() => _pendingEventCount = count);
    } catch (_) {
      // Count is informational; a failed read just leaves it hidden.
    }
  }

  /// The one state-driven banner on this screen (U1 build item 5):
  /// `offline` keeps the wording the review rated good; `unreachable` gets
  /// the human sentence that names the host. `reachable` and
  /// `unconfigured` show nothing. The raw failure string is never rendered
  /// here - it lives in History and logs only.
  ///
  /// The offline text is a claim about the list below ("showing cached
  /// playlists"), so it is only shown when the list actually has rows.
  /// Right after saving a URL no fetch has run yet and there is no cache:
  /// the banner would be a lie. The unreachable text is only ever set by a
  /// classified fetch failure, so it is always a true claim.
  Widget _buildStateBanner(BuildContext context, SyncProvider provider) {
    final state = provider.connectivityState;
    if (state == ConnectivityState.reachable ||
        state == ConnectivityState.unconfigured) {
      return const SizedBox.shrink();
    }
    final offline = state == ConnectivityState.offline;
    if (offline && provider.availablePlaylists.isEmpty) {
      return const SizedBox.shrink();
    }
    final color = offline ? Colors.orange : Colors.red;
    return Container(
      width: double.infinity,
      color: offline ? Colors.orange.shade100 : Colors.red.shade100,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              offline
                  ? 'Offline - showing cached playlists'
                  : describeUnreachable(provider.serverUrl),
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Consumer<SyncProvider>(
        builder: (context, provider, child) {
          if (provider.isSyncing) {
            return _buildSyncingView(context, provider);
          }

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
      ),
    );
  }

  Widget _buildSyncingView(BuildContext context, SyncProvider provider) {
    return Column(
      children: [
        if (provider.syncProgress != null)
          _buildSyncProgress(context, provider.syncProgress!),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    provider.syncProgress != null
                        ? 'Syncing ${provider.syncProgress!.currentPlaylist}...'
                        : 'Preparing sync...',
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
            // The fetch outcome renders through the state banner, never as
            // raw red text under the button (U1 build items 1 and 5).
            _buildStateBanner(context, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistSelection(BuildContext context, SyncProvider provider) {
    // The rows are "live" only when the last fetch reached the server; in
    // every other state the list is the local cache.
    final live = provider.connectivityState == ConnectivityState.reachable;
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
                       : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          // A reason for not starting is surfaced here at
                          // the tap site, never as a global error state.
                          final reason = await provider.startSync();
                          if (reason != null && mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(reason)),
                            );
                          }
                        },
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync'),
                ),
              ],
            ),
          ),
          if (_pendingEventCount != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.queue_music,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pendingEventCount! > 0
                          ? '$_pendingEventCount playback event'
                              '${_pendingEventCount! == 1 ? '' : 's'} '
                              'waiting to sync'
                          : 'No playback events waiting to sync',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildStateBanner(context, provider),
        if (provider.isSyncing && provider.syncProgress != null)
          _buildSyncProgress(context, provider.syncProgress!),

        // Sync options section
        Card(
          margin: const EdgeInsets.all(16),
          child: ExpansionTile(
            title: const Text(
              'Sync Options',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            initiallyExpanded: false,
            children: [
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
          child: RefreshIndicator(
            // The fetch outcome renders through the state banner; a raw
            // failure string was never the right refresh feedback.
            onRefresh: () => provider.fetchPlaylists(),
            child: Stack(
              children: [
                ListView.builder(
                  itemCount: provider.availablePlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = provider.availablePlaylists[index];
                    final isSelected = provider.selectedPlaylistIds.contains(
                      playlist.id,
                    );

                    return CheckboxListTile(
                      title: Text(
                        playlist.name,
                        style: live
                            ? null
                            : const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                      ),
                      subtitle: Text(
                        live
                            ? '${playlist.itemCount} tracks'
                            : '${playlist.itemCount} tracks (offline)',
                        style: live
                            ? null
                            : const TextStyle(color: Colors.grey),
                      ),
                      value: isSelected,
                      onChanged: provider.isSyncing
                          ? null
                          : (_) async {
                              final fileWasDeleted = await provider
                                  .togglePlaylistSelection(playlist.id);

                              // Only show snackbar if a file was actually deleted
                              if (fileWasDeleted && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Removed "${playlist.name}" playlist file',
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                    );
                  },
                ),
                if (provider.isLoadingPlaylists)
                  Container(
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(top: 16),
                    child: const CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncProgress(BuildContext context, SyncProgress progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Syncing: ${progress.currentPlaylist}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
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
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (progress.currentTrackTitle != null)
            Text(
              '${progress.currentTrackTitle}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.downloadProgress),
          const SizedBox(height: 4),
          Text(
            'Playlist ${progress.currentPlaylistIndex + 1}/${progress.totalPlaylists} - '
            'Track ${progress.downloadedTracks}/${progress.totalTracks}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
