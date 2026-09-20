import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../data/repositories/local_database_repository.dart';
import '../providers/player_provider.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {
        _isScrolled = _scrollController.offset > 0;
      });
    });

    AudioService.playbackStateStream.listen((state) {
      setState(() {
        _position = state.position ?? Duration.zero;
        _duration = state.bufferedPosition ?? Duration.zero;
      });
    });

    AudioService.currentMediaItemStream.listen((item) {
      if (item != null) {
        setState(() {
          _duration = item.duration ?? Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTime(Duration position) {
    final minutes = position.inMinutes;
    final seconds = (position.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Now Playing'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {},
          ),
        ],
      ),
      body: Consumer<PlayerProvider>(
        builder: (context, playerProvider, child) {
          final currentTrack = playerProvider.getCurrentlyPlayingTrack();
          if (currentTrack == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_note, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No track playing'),
                ],
              ),
            );
          }

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildAlbumArt(context, currentTrack),
                    const SizedBox(height: 24),
                    _buildTrackInfo(currentTrack),
                    const SizedBox(height: 32),
                    _buildSeekControl(_position, _duration, playerProvider),
                    const SizedBox(height: 32),
                    _buildPlaybackControls(context, playerProvider),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, SyncedTrack track) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 300,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FadeInImage(
              placeholder: const AssetImage(
                'assets/images/placeholder_album_art.png',
              ),
              image: track.artworkPath != null
                  ? FileImage(File(track.artworkPath!))
                  : const AssetImage('assets/images/placeholder_album_art.png'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: 300,
              fadeInDuration: const Duration(milliseconds: 300),
            ),
          ),
        ),
        if (!_isScrolled)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Now Playing',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTrackInfo(SyncedTrack track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            track.title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            track.artist,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (track.album != track.artist) ...[
            const SizedBox(height: 4),
            Text(
              track.album,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeekControl(Duration position, Duration duration, PlayerProvider playerProvider) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    _formatTime(position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  inactiveTrackColor: Colors.grey[300],
                  thumbColor: Theme.of(context).colorScheme.primary,
                  overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: position.inMilliseconds.toDouble(),
                  max: duration.inMilliseconds.toDouble(),
                  onChanged: (value) {
                    playerProvider.seek(Duration(milliseconds: value.toInt()));
                  },
                  onChangeEnd: (value) {
                    playerProvider.seek(Duration(milliseconds: value.toInt()));
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaybackControls(BuildContext context, PlayerProvider playerProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            context,
            icon: Icons.shuffle,
            isActive: playerProvider.shuffleMode,
            onPressed: playerProvider.toggleShuffle,
          ),
          _buildControlButton(
            context,
            icon: Icons.skip_previous,
            isActive: false,
            onPressed: () {
              AudioService.skipToPrevious();
            },
          ),
          StreamBuilder<bool>(
            stream: AudioService.playbackStateStream
                .map((state) => state.playing)
                .distinct(),
            builder: (context, snapshot) {
              final isPlaying = snapshot.data ?? false;
              return _buildControlButton(
                context,
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                isActive: isPlaying,
                onPressed: () {
                  if (isPlaying) {
                    AudioService.pause();
                  } else {
                    AudioService.play();
                  }
                },
                size: 72,
              );
            },
          ),
          _buildControlButton(
            context,
            icon: Icons.skip_next,
            isActive: false,
            onPressed: () {
              AudioService.skipToNext();
            },
          ),
          _buildControlButton(
            context,
            icon: Icons.repeat,
            isActive: playerProvider.repeatMode,
            onPressed: playerProvider.toggleRepeat,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
    double size = 48,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(size / 2),
          ),
          backgroundColor: isActive
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          foregroundColor: isActive
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
          padding: EdgeInsets.all(size / 4),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: size / 2),
        label: const SizedBox.shrink(),
      ),
    );
  }
}
