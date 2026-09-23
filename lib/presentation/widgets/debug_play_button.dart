import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:owntone_sync/data/repositories/local_database_repository.dart';
import '../services/audio_handler.dart';
import '../services/track_uri_resolver.dart';

class DebugPlayButton extends StatefulWidget {
  final OwnToneAudioHandler handler;

  const DebugPlayButton({super.key, required this.handler});

  @override
  State<DebugPlayButton> createState() => _DebugPlayButtonState();
}

class _DebugPlayButtonState extends State<DebugPlayButton> {
  bool _isLoading = false;
  String _status = 'Tap to load 10 tracks';

  Future<void> _playTest() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading tracks...';
    });

    try {
      final repo = LocalDatabaseRepository();
      final tracks = await repo.getAllTracks(sortBy: 'title');

      if (tracks.isEmpty) {
        setState(() {
          _status = 'No synced tracks found';
          _isLoading = false;
        });
        return;
      }

      final resolver = TrackUriResolver();
      final testTracks = tracks.take(10).toList();

      // Resolve URIs and skip tracks that fail
      final validTracks = <MediaItem>[];
      for (final track in testTracks) {
        final resolvedUri = await resolver.resolve(track.localPath);
        if (resolvedUri != null && resolvedUri.isNotEmpty) {
          validTracks.add(MediaItem(
            id: track.id.toString(),
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.lengthMs > 0
                ? Duration(milliseconds: track.lengthMs)
                : null,
            extras: {'uri': resolvedUri},
          ));
        } else {
          if (kDebugMode) {
            print('[DebugPlayButton] Skipped ${track.title} - no valid URI');
          }
        }
      }

      if (validTracks.isEmpty) {
        setState(() {
          _status = 'No tracks with valid URIs';
          _isLoading = false;
        });
        return;
      }

      await widget.handler.playCollection(validTracks, startIndex: 0);

      setState(() {
        _status = '${validTracks.length} tracks loaded, playing from "${validTracks.first.title}"';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _playTest,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: const Text('Debug: Play 10 Tracks'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _status,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
