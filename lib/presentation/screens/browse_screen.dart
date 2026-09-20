import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../widgets/playlist_list_view.dart';
import '../widgets/artist_list_view.dart';
import '../widgets/album_list_view.dart';
import '../widgets/track_list_view.dart';
import '../widgets/mini_player.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late BrowseProvider _browseProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _browseProvider = BrowseProvider();
    _browseProvider.loadData();

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _browseProvider.setCategory(
          BrowseCategory.values[_tabController.index],
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _browseProvider,
      child: Consumer<BrowseProvider>(
        builder: (context, provider, child) {
          if (!provider.hasContent && !provider.isLoading) {
            return _buildEmptyState(context);
          }

          return Scaffold(
            body: Column(
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
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
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
            ),
            bottomSheet: const MiniPlayer(),
          );
        },
      ),
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
              onPressed: () {
                // Navigate to sync tab
                DefaultTabController.of(context).animateTo(0);
              },
              icon: const Icon(Icons.sync),
              label: const Text('Go to Sync'),
            ),
          ],
        ),
      ),
    );
  }
}
