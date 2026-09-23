import 'package:flutter/material.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';

class DebugPlayButton extends StatefulWidget {
  final PlaybackController controller;

  const DebugPlayButton({super.key, required this.controller});

  @override
  State<DebugPlayButton> createState() => _DebugPlayButtonState();
}

class _DebugPlayButtonState extends State<DebugPlayButton> {
  bool _isLoading = false;
  String _status = 'Tap to play the synced library';

  Future<void> _playAll() async {
    setState(() {
      _isLoading = true;
      _status = 'Resolving tracks...';
    });

    try {
      final repo = LocalDatabaseRepository();
      final tracks = await repo.getAllTracks(sortBy: 'title');

      if (tracks.isEmpty) {
        if (mounted) {
          setState(() {
            _status = 'No synced tracks found';
            _isLoading = false;
          });
        }
        return;
      }

      await widget.controller.playCollection(
        const QueueOrigin.allTracks(),
        tracks,
      );

      if (mounted) {
        setState(() {
          _status = '${tracks.length} tracks queued, playing from the top';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _playAll,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: const Text('Debug: Play All Tracks'),
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
