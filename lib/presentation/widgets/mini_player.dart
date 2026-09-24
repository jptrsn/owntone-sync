import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../controllers/playback_controller.dart';
import '../screens/player_screen.dart';

/// Docked playback bar. Renders entirely from the controller's streams and
/// occupies zero height while there is no current track.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  void _openNowPlaying(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();

    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () => _openNowPlaying(context),
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -100) {
              _openNowPlaying(context);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProgress(controller),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildAlbumArt(item.artUri),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            item.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    _buildPlayPauseButton(controller),
                    IconButton(
                      tooltip: 'Next',
                      icon: const Icon(Icons.skip_next, size: 32),
                      onPressed: () => controller.skipToNext(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgress(PlaybackController controller) {
    return StreamBuilder<PositionData>(
      stream: controller.positionData,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final duration = data?.duration;
        final position = data?.position ?? Duration.zero;
        final hasDuration = duration != null && duration > Duration.zero;
        final fraction = hasDuration
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : null;

        return ClipRect(
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 2,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }

  Widget _buildAlbumArt(Uri? artUri) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        image: DecorationImage(
          image: _artImageProvider(artUri),
          fit: BoxFit.cover,
        ),
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

  Widget _buildPlayPauseButton(PlaybackController controller) {
    return StreamBuilder<PlaybackState>(
      stream: controller.playbackState,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;

        return IconButton(
          tooltip: isPlaying ? 'Pause' : 'Play',
          icon: Icon(
            isPlaying ? Icons.pause_circle : Icons.play_circle,
            size: 32,
          ),
          onPressed: () {
            if (isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          },
        );
      },
    );
  }
}
