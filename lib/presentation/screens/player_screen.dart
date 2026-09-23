import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../controllers/playback_controller.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () => _showQueueSheet(context, controller),
          ),
        ],
      ),
      body: StreamBuilder<MediaItem?>(
        stream: controller.mediaItem,
        builder: (context, itemSnapshot) {
          final item = itemSnapshot.data;
          if (item == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_note, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No track playing'),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildAlbumArt(item.artUri),
              const SizedBox(height: 24),
              _buildTrackInfo(context, item),
              const SizedBox(height: 32),
              _buildSeekControl(controller),
              const SizedBox(height: 32),
              _buildPlaybackControls(controller),
              const SizedBox(height: 48),
            ],
          );
        },
      ),
    );
  }

  ImageProvider _artImageProvider(Uri? artUri) {
    if (artUri != null && artUri.scheme == 'file') {
      final file = File(artUri.toFilePath());
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return const AssetImage('assets/images/placeholder_album_art.png');
  }

  Widget _buildAlbumArt(Uri? artUri) {
    return Container(
      width: double.infinity,
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image(
          image: _artImageProvider(artUri),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 300,
        ),
      ),
    );
  }

  Widget _buildTrackInfo(BuildContext context, MediaItem item) {
    return Column(
      children: [
        Text(
          item.title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          item.artist ?? '',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if ((item.album ?? '').isNotEmpty && item.album != item.artist) ...[
          const SizedBox(height: 4),
          Text(
            item.album!,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildSeekControl(PlaybackController controller) {
    return StreamBuilder<PositionData>(
      stream: controller.positionData,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final position = data?.position ?? Duration.zero;
        final decodedDuration = data?.duration;
        final effectiveDuration =
            (decodedDuration != null && decodedDuration > Duration.zero)
                ? decodedDuration
                : Duration.zero;
        final hasDuration = effectiveDuration > Duration.zero;
        final safePosition =
            position > effectiveDuration ? effectiveDuration : position;
        final max = hasDuration
            ? effectiveDuration.inMilliseconds.toDouble()
            : 1.0;
        final value = safePosition.inMilliseconds.toDouble().clamp(0.0, max);

        return Column(
          children: [
            Row(
              children: [
                Text(
                  _formatTime(safePosition),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  _formatTime(effectiveDuration),
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
                overlayColor:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                trackHeight: 4,
              ),
              child: Slider(
                value: value,
                max: max,
                // Seek once on release only; seeking on every onChanged tick
                // fights the player during a drag.
                onChanged: (value) {
                  // Intentionally inert: the drag is display-only until release.
                },
                onChangeEnd: (value) {
                  controller.seek(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaybackControls(PlaybackController controller) {
    return StreamBuilder<PlaybackState>(
      stream: controller.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final isPlaying = state?.playing ?? false;
        final shuffleOn = state?.shuffleMode == AudioServiceShuffleMode.all;
        final repeatMode = state?.repeatMode ?? AudioServiceRepeatMode.none;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlButton(
              context,
              icon: Icons.shuffle,
              isActive: shuffleOn,
              onPressed: () {
                controller.toggleShuffle();
              },
            ),
            _buildControlButton(
              context,
              icon: Icons.skip_previous,
              isActive: false,
              onPressed: () {
                controller.skipToPrevious();
              },
            ),
            _buildControlButton(
              context,
              icon: isPlaying ? Icons.pause : Icons.play_arrow,
              isActive: isPlaying,
              onPressed: () {
                if (isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              size: 72,
            ),
            _buildControlButton(
              context,
              icon: Icons.skip_next,
              isActive: false,
              onPressed: () {
                controller.skipToNext();
              },
            ),
            _buildControlButton(
              context,
              icon: repeatMode == AudioServiceRepeatMode.one
                  ? Icons.repeat_one
                  : Icons.repeat,
              isActive: repeatMode != AudioServiceRepeatMode.none,
              onPressed: () {
                controller.cycleRepeat();
              },
            ),
          ],
        );
      },
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
      child: ElevatedButton(
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
        child: Icon(icon, size: size / 2),
      ),
    );
  }

  void _showQueueSheet(BuildContext context, PlaybackController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        maxChildSize: 0.8,
        builder: (_, scrollController) => StreamBuilder<List<MediaItem>>(
          stream: controller.queue,
          builder: (context, queueSnapshot) {
            final items = queueSnapshot.data ?? [];

            return StreamBuilder<PlaybackState>(
              stream: controller.playbackState,
              builder: (context, stateSnapshot) {
                final currentIndex = stateSnapshot.data?.queueIndex;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            'Queue (${items.length})',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.clear_all),
                            onPressed: () {
                              // Clear queue
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: items.length,
                        itemBuilder: (ctx, i) {
                          final item = items[i];
                          final isCurrent = i == currentIndex;
                          return ListTile(
                            leading: Icon(
                              isCurrent ? Icons.equalizer : Icons.music_note,
                              color: isCurrent
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(item.title),
                            subtitle: Text(item.artist ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                // Remove from queue
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
