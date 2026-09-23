import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../controllers/playback_controller.dart';
import '../screens/player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();
    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItem,
      builder: (context, itemSnapshot) {
        final item = itemSnapshot.data;
        if (item == null) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PlayerScreen(),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black87,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.artist ?? '',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _buildPlayPauseButton(controller),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumArt(Uri? artUri) {
    return Container(
      width: 48,
      height: 48,
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
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 24,
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
