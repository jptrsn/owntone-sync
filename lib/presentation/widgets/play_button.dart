import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';

class PlayButton extends StatelessWidget {
  final SyncedTrack track;

  /// The collection [track] belongs to. When provided together with
  /// [index], tapping plays the whole collection in context with [track]
  /// as the current item. When omitted, only [track] is queued.
  final List<SyncedTrack>? collection;
  final int? index;

  /// The origin to report for in-context playback ("Playing from ...").
  final QueueOrigin? origin;

  final bool showNextIcon;
  final bool showContextMenu;

  const PlayButton({
    super.key,
    required this.track,
    this.collection,
    this.index,
    this.origin,
    this.showNextIcon = false,
    this.showContextMenu = false,
  });

  Future<void> _playInContext(BuildContext context) async {
    final controller = context.read<PlaybackController>();
    final list =
        (collection != null && collection!.isNotEmpty) ? collection! : [track];
    final i =
        (index != null && index! >= 0 && index! < list.length) ? index! : 0;
    final source = origin ?? const QueueOrigin.allTracks();
    await controller.playCollection(source, list, startIndex: i);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();

    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItem,
      builder: (context, snapshot) {
        final current = snapshot.data;
        final isCurrent =
            current != null && current.id == track.id.toString();

        return GestureDetector(
          onLongPress: showContextMenu
              ? () => _showPlayMenu(context, track)
              : null,
          child: IconButton(
            onPressed: () {
              _playInContext(context);
            },
            icon: _buildIcon(isCurrent),
            tooltip: isCurrent ? 'Playing' : 'Play track',
          ),
        );
      },
    );
  }

  void _showPlayMenu(BuildContext context, SyncedTrack track) {
    final controller = context.read<PlaybackController>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('Play'),
            onTap: () {
              Navigator.of(ctx).pop();
              _playInContext(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.skip_next),
            title: const Text('Play Next'),
            onTap: () {
              Navigator.of(ctx).pop();
              controller.playNext(track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add to Queue'),
            onTap: () {
              Navigator.of(ctx).pop();
              controller.enqueue(track);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(bool isCurrent) {
    if (showNextIcon) {
      return const Icon(Icons.skip_next);
    }
    return const Icon(Icons.play_arrow);
  }
}

class PlayableTile extends StatelessWidget {
  final Widget child;
  final SyncedTrack track;
  final List<SyncedTrack>? collection;
  final int? index;
  final QueueOrigin? origin;
  final bool showNextIcon;
  final bool showContextMenu;

  const PlayableTile({
    super.key,
    required this.child,
    required this.track,
    this.collection,
    this.index,
    this.origin,
    this.showNextIcon = false,
    this.showContextMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: PlayButton(
            track: track,
            collection: collection,
            index: index,
            origin: origin,
            showNextIcon: showNextIcon,
            showContextMenu: showContextMenu,
          ),
        ),
      ],
    );
  }
}
