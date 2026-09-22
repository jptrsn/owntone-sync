import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart' show audioHandler;
import '../providers/player_provider.dart';
import '../screens/player_screen.dart';
import '../../data/repositories/local_database_repository.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final currentTrack = playerProvider.getCurrentlyPlayingTrack();
        if (currentTrack == null) {
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
                _buildAlbumArt(currentTrack),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentTrack.title,
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
                        currentTrack.artist,
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
                _buildPlayPauseButton(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumArt(SyncedTrack track) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        image: DecorationImage(
          image: track.artworkPath != null
              ? FileImage(File(track.artworkPath!))
              : const AssetImage('assets/images/placeholder_album_art.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(BuildContext context) {
    return StreamBuilder<bool>(
      stream: audioHandler!.playbackState.map((state) => state.playing),
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return IconButton(
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 24,
          ),
          onPressed: () {
            if (isPlaying) {
              audioHandler!.pause();
            } else {
              audioHandler!.play();
            }
          },
        );
      },
    );
  }
}
