import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/local_database_repository.dart';
import '../../utils/connectivity_state.dart';
import '../controllers/playback_controller.dart';
import '../providers/browse_provider.dart';
import '../providers/sync_provider.dart';
import '../services/audio_handler.dart';
import '../widgets/app_drawer.dart';
import '../widgets/album_list_view.dart';
import '../widgets/artist_list_view.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/playlist_list_view.dart';
import '../widgets/track_list_view.dart';
import 'search_screen.dart';
import 'sync_screen.dart';

/// The home screen: the library. Sync lives in the drawer and behind the
/// app-bar sync affordance, never in a tab.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<MediaItem>? _skippedTrackSubscription;
  StreamSubscription<String>? _syncCompletedSubscription;
  StreamSubscription<QueueExhaustedReason>? _queueExhaustedSubscription;

  String? _lastNoticeTrackId;
  DateTime? _lastNoticeAt;

  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // loadData() notifies listeners; running it in the first build phase
    // throws "setState() or markNeedsBuild() called during build".
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context
          .read<BrowseProvider>()
          .loadData()
          .then((_) {
            if (mounted) setState(() => _initialLoadDone = true);
          }),
    );

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        context.read<BrowseProvider>().setCategory(
          BrowseCategory.values[_tabController.index],
        );
      }
    });

    // The home route stays mounted for the app's lifetime, so this listener
    // survives while detail and Now Playing routes are pushed on top.
    _skippedTrackSubscription = context
        .read<PlaybackController>()
        .skippedTrack
        .listen(_onSkippedTrack);

    _queueExhaustedSubscription = context
        .read<PlaybackController>()
        .queueExhausted
        .listen(_onQueueExhausted);

    // On sync completion: reconcile the live queue against what the sync
    // left behind, then refresh the library so new content appears without a
    // restart (and the empty state leaves once the first sync lands).
    _syncCompletedSubscription = context
        .read<SyncProvider>()
        .syncCompleted
        .listen(_onSyncCompleted);
  }

  @override
  void dispose() {
    _skippedTrackSubscription?.cancel();
    _queueExhaustedSubscription?.cancel();
    _syncCompletedSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onSyncCompleted(String status) async {
    // 'partial' also synced some playlists, so the queue and library may
    // have changed; reconcile on it as well.
    if ((status != 'success' && status != 'partial') || !mounted) return;
    final controller = context.read<PlaybackController>();
    try {
      final allTracks = await LocalDatabaseRepository().getAllTracks();
      if (!mounted) return;
      final aliveIds = allTracks.map((t) => t.id).toSet();
      await controller.reconcileQueue(aliveIds);
    } catch (e) {
      debugPrint('Queue reconciliation after sync failed: $e');
    }
    if (!mounted) return;
    await context.read<BrowseProvider>().loadData();
  }

  /// A9: the queue ran out of playable tracks. While the NowPlayingSheet is
  /// open it owns this notice (its own ScaffoldMessenger is above the
  /// sheet's barrier); the library suppresses its own then.
  void _onQueueExhausted(QueueExhaustedReason reason) {
    if (!mounted) return;
    if (context.read<PlaybackController>().nowPlayingSheetOpen.value) return;
    final messenger = ScaffoldMessenger.of(context);
    if (reason == QueueExhaustedReason.allFailed) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'No playable tracks in the queue - sync again to repair missing files',
          ),
          action: SnackBarAction(
            label: 'Sync',
            onPressed: () => _openSync(context),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Queue ended - no more playable tracks'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _onSkippedTrack(MediaItem item) {
    if (!mounted) return;

    // While the NowPlayingSheet is open it owns the A9 notice (it renders on
    // its own ScaffoldMessenger, above the sheet); showing it here too would
    // paint a second notice behind the sheet barrier.
    if (context.read<PlaybackController>().nowPlayingSheetOpen.value) return;

    // The handler auto-advances, so a stuck failure can emit the same track
    // repeatedly; ignore repeats of the same track for a few seconds.
    final now = DateTime.now();
    final recent =
        _lastNoticeTrackId == item.id &&
        _lastNoticeAt != null &&
        now.difference(_lastNoticeAt!) < const Duration(seconds: 5);
    if (recent) return;
    _lastNoticeTrackId = item.id;
    _lastNoticeAt = now;
    _showSkipNotice(item.title);
  }

  /// Shows a one-line, non-blocking notice about a skipped track (A9).
  ///
  /// Hosted here because the home route stays mounted for the app's
  /// lifetime; the app-level ScaffoldMessenger renders the snackbar over the
  /// topmost route's scaffold, so it is visible while a detail or Now
  /// Playing route is on top.
  void _showSkipNotice(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Skipped "$title" - could not be played'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openSync(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SyncScreen()));
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BrowseProvider>();

    Widget body;
    if (provider.isLoading || !_initialLoadDone) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!provider.hasContent) {
      body = _buildEmptyState(context);
    } else {
      body = Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Artists'),
              Tab(text: 'Albums'),
              Tab(text: 'Tracks'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                PlaylistListView(),
                ArtistListView(),
                AlbumListView(),
                TrackListView(),
              ],
            ),
          ),
        ],
      );
    }

    return PlayerScaffold(
      appBar: AppBar(
        title: const Text('Library'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          _buildSortAction(context, provider),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => _openSearch(context),
          ),
          _buildSyncStatusAction(context),
          const SizedBox(width: 4),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          _buildConnectivityBanner(),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// The one persistent home banner: the `unreachable` state only.
  ///
  /// It is human-readable, names the host, and offers a working retry -
  /// never a raw exception (U1 build item 3). The `offline` state renders
  /// **nothing at all**: being away from the home LAN is the expected,
  /// normal condition, and settled decision 3 shows no banner, note or
  /// badge for it.
  Widget _buildConnectivityBanner() {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, _) {
        if (syncProvider.connectivityState !=
            ConnectivityState.unreachable) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.errorContainer,
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 12),
                  child: Icon(Icons.error_outline, size: 20),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      describeUnreachable(syncProvider.serverUrl),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => syncProvider.fetchPlaylists(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sort selector for the active tab. Each category keeps its own order
  /// across sessions (B2); the options shown depend on the current tab.
  Widget _buildSortAction(BuildContext context, BrowseProvider provider) {
    return PopupMenuButton<SortOrder>(
      tooltip: 'Sort by',
      icon: const Icon(Icons.sort),
      onSelected: (order) => provider.setSortOrder(order),
      itemBuilder: (context) => [
        for (final option in provider.sortOptions)
          PopupMenuItem<SortOrder>(
            value: option,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: option == provider.sortOrder
                      ? const Icon(Icons.check, size: 16)
                      : null,
                ),
                Text(kSortOrderLabels[option]!),
              ],
            ),
          ),
      ],
    );
  }

  /// The app-bar sync affordance, driven by the four-state connectivity
  /// model (U1 build item 3). `unreachable` is the only state that may
  /// carry the red badge; `offline` and `unconfigured` are neutral;
  /// `reachable` is the quiet confirmation.
  Widget _buildSyncStatusAction(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, provider, _) {
        Widget icon;
        String tooltip;
        if (provider.isSyncing) {
          final progress = provider.syncProgress;
          double? value;
          if (progress != null && progress.totalPlaylists > 0) {
            value =
                (progress.currentPlaylistIndex +
                    (progress.downloadProgress ?? 0.0)) /
                progress.totalPlaylists;
          }
          tooltip = 'Syncing';
          icon = SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, value: value),
          );
        } else {
          switch (provider.connectivityState) {
            case ConnectivityState.unreachable:
              tooltip = describeUnreachable(provider.serverUrl);
              icon = Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.cloud_off),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              );
            case ConnectivityState.reachable:
              tooltip = 'Sync';
              icon = const Icon(Icons.cloud_done);
            case ConnectivityState.offline:
            case ConnectivityState.unconfigured:
              // Neutral, no badge. Offline shows nothing at all (settled
              // decision 3); unconfigured is setup, not a fault.
              tooltip = provider.isConfigured ? 'Sync' : 'Set up sync';
              icon = const Icon(Icons.cloud_outlined);
          }
        }

        return IconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: () => _openSync(context),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note, size: 64, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'No Music Synced',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sync some playlists to start browsing your music.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openSync(context),
              icon: const Icon(Icons.sync),
              label: const Text('Set up sync'),
            ),
          ],
        ),
      ),
    );
  }
}
