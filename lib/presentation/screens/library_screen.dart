import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../controllers/playback_controller.dart';
import '../providers/browse_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/album_list_view.dart';
import '../widgets/artist_list_view.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/playlist_list_view.dart';
import '../widgets/track_list_view.dart';
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
  }

  @override
  void dispose() {
    _skippedTrackSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onSkippedTrack(MediaItem item) {
    if (!mounted) return;

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
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Search is coming in a later update'),
                ),
              );
            },
          ),
          _buildSyncStatusAction(context),
          const SizedBox(width: 4),
        ],
      ),
      drawer: const AppDrawer(),
      body: body,
    );
  }

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
        } else if (provider.lastError != null) {
          tooltip = provider.lastError!;
          icon = Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.cloud_done_outlined),
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
        } else {
          tooltip = 'Sync';
          icon = const Icon(Icons.cloud_done);
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
