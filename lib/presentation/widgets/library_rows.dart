import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';
import '../services/collection_playback.dart';
import '../screens/album_detail_screen.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/playlist_detail_screen.dart';

/// Up to two leading initials of an artist name, for generated avatar tiles.
String artistInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}

/// `m:ss` for tracks under an hour, `h:mm:ss` above it.
String formatTrackDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  return '${duration.inMinutes}:$seconds';
}

class _RowMenuAction {
  final IconData icon;
  final String label;
  final void Function() onTap;

  const _RowMenuAction({required this.icon, required this.label, required this.onTap});
}

/// The row context menu: one bottom sheet shared by the trailing button and
/// the row long-press, so both affordances always offer the same items.
Future<void> _showRowMenu(BuildContext context, List<_RowMenuAction> actions) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              onTap: () {
                Navigator.of(sheetContext).pop();
                action.onTap();
              },
            ),
        ],
      ),
    ),
  );
}

/// Shared artwork slot with a defined fallback (B7): every artwork path that
/// is missing or unreadable renders the placeholder tile, never throws.
class AlbumArtTile extends StatelessWidget {
  final String? artworkPath;
  final double size;
  final double borderRadius;

  const AlbumArtTile({
    super.key,
    this.artworkPath,
    this.size = 56,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (artworkPath != null && artworkPath!.isNotEmpty) {
      final file = File(artworkPath!);
      if (file.existsSync() && file.lengthSync() > 0) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(context),
          ),
        );
      }
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(Icons.album, size: size * 0.5),
    );
  }
}

Future<void> showTrackInfoDialog(BuildContext context, SyncedTrack track) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(track.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(track.artist),
            if (track.album.isNotEmpty) Text(track.album),
            if (track.genre.isNotEmpty) Text(track.genre),
            if (track.year > 0) Text('${track.year}'),
            const SizedBox(height: 8),
            Text(
              'Duration: ${formatTrackDuration(track.lengthMs)}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            if (track.localPath.isNotEmpty)
              Text(
                'File: ${track.localPath}',
                style: Theme.of(dialogContext).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// A track row implementing the spec §5 grammar: one tap target (the whole
/// row, play in context), a laid-out trailing (duration + menu button, never
/// stacked over content), and the track menu on ⋮ or long-press.
///
/// The now-playing indicator is the first per-row consumer of playback state:
/// it is driven directly from the controller's `mediaItem` stream (a
/// broadcast subject), so no screen or list keeps its own copy of "which
/// track is playing".
class TrackRow extends StatelessWidget {
  final SyncedTrack track;

  /// The list [track] was tapped from; playing starts at [index] and the
  /// whole list becomes the queue (A1).
  final List<SyncedTrack> collection;
  final int index;
  final QueueOrigin origin;

  /// Optional leading widget (track number, disc, ...). Replaced by the
  /// now-playing indicator while this track is current.
  final Widget? leading;
  final String? secondary;
  final bool showContextMenu;

  const TrackRow({
    super.key,
    required this.track,
    required this.collection,
    required this.index,
    required this.origin,
    this.leading,
    this.secondary,
    this.showContextMenu = true,
  });

  Future<void> _playNext(BuildContext context) async {
    final controller = context.read<PlaybackController>();
    await controller.playNext(track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Next up: "${track.title}"')),
      );
    }
  }

  Future<void> _addToQueue(BuildContext context) async {
    final controller = context.read<PlaybackController>();
    await controller.enqueue(track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${track.title}" to queue')),
      );
    }
  }

  void _goToAlbum(BuildContext context) {
    if (track.album.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          albumName: track.album,
          artistName:
              track.albumArtist.isNotEmpty ? track.albumArtist : track.artist,
          artworkPath: track.artworkPath,
          albumArtist: track.albumArtist,
          year: track.year,
        ),
      ),
    );
  }

  void _goToArtist(BuildContext context) {
    if (track.artist.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArtistDetailScreen(artistName: track.artist)),
    );
  }

  List<_RowMenuAction> _menuActions(BuildContext context) {
    return [
      _RowMenuAction(
        icon: Icons.skip_next,
        label: 'Play next',
        onTap: () => _playNext(context),
      ),
      _RowMenuAction(
        icon: Icons.add,
        label: 'Add to queue',
        onTap: () => _addToQueue(context),
      ),
      _RowMenuAction(
        icon: Icons.album,
        label: 'Go to album',
        onTap: () => _goToAlbum(context),
      ),
      _RowMenuAction(
        icon: Icons.person,
        label: 'Go to artist',
        onTap: () => _goToArtist(context),
      ),
      _RowMenuAction(
        icon: Icons.info_outline,
        label: 'Track info',
        onTap: () => showTrackInfoDialog(context, track),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();
    return StreamBuilder<MediaItem?>(
      stream: controller.mediaItem,
      builder: (context, snapshot) {
        final current = snapshot.data;
        final isCurrent = current != null && current.id == track.id.toString();
        final primary = Theme.of(context).colorScheme.primary;

        return ListTile(
          onTap: () {
            controller.playCollection(origin, collection, startIndex: index);
          },
          onLongPress:
              showContextMenu ? () => _showRowMenu(context, _menuActions(context)) : null,
          leading: SizedBox(
            width: 40,
            child: isCurrent
                ? Semantics(
                    label: 'Now playing',
                    child: Icon(Icons.graphic_eq, color: primary, size: 20),
                  )
                : (leading ?? const SizedBox.shrink()),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isCurrent
                ? TextStyle(color: primary, fontWeight: FontWeight.w600)
                : null,
          ),
          subtitle: Text(
            secondary ?? '${track.artist} \u2022 ${track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatTrackDuration(track.lengthMs),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (showContextMenu)
                IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert, size: 22),
                  onPressed: () => _showRowMenu(context, _menuActions(context)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A playlist row: tap opens the detail screen, the menu plays it.
class PlaylistRow extends StatelessWidget {
  final int playlistId;
  final String playlistName;
  final int trackCount;

  const PlaylistRow({
    super.key,
    required this.playlistId,
    required this.playlistName,
    required this.trackCount,
  });

  QueueOrigin get _origin => QueueOrigin.playlist(playlistId, playlistName);

  Future<List<SyncedTrack>> _tracks() =>
      LocalDatabaseRepository().getTracksForPlaylist(playlistId);

  Future<void> _play(BuildContext context, {bool shuffle = false}) async {
    final controller = context.read<PlaybackController>();
    final tracks = await _tracks();
    if (shuffle) {
      await shuffleCollection(controller, _origin, tracks);
    } else {
      await playCollectionInOrder(controller, _origin, tracks);
    }
  }

  Future<void> _enqueue(BuildContext context) async {
    final controller = context.read<PlaybackController>();
    final tracks = await _tracks();
    await controller.enqueueCollection(tracks);
    if (context.mounted && tracks.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${tracks.length} tracks from $playlistName to queue')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailScreen(
              playlistId: playlistId,
              playlistName: playlistName,
            ),
          ),
        );
      },
      onLongPress: () => _showRowMenu(context, _menuActions(context)),
      leading: const Icon(Icons.queue_music),
      title: Text(
        playlistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$trackCount ${trackCount == 1 ? 'track' : 'tracks'}'),
      trailing: IconButton(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert, size: 22),
        onPressed: () => _showRowMenu(context, _menuActions(context)),
      ),
    );
  }

  List<_RowMenuAction> _menuActions(BuildContext context) {
    return [
      _RowMenuAction(
        icon: Icons.playlist_play,
        label: 'Play',
        onTap: () => _play(context),
      ),
      _RowMenuAction(
        icon: Icons.shuffle,
        label: 'Shuffle',
        onTap: () => _play(context, shuffle: true),
      ),
      _RowMenuAction(
        icon: Icons.add,
        label: 'Add to queue',
        onTap: () => _enqueue(context),
      ),
    ];
  }
}

/// An album row: artwork, name, secondary line, tap opens the detail screen.
class AlbumRow extends StatelessWidget {
  final String albumName;
  final String artistName;
  final int year;
  final String? artworkPath;
  final int trackCount;

  const AlbumRow({
    super.key,
    required this.albumName,
    required this.artistName,
    required this.year,
    required this.trackCount,
    this.artworkPath,
  });

  QueueOrigin get _origin => QueueOrigin.album(albumName);

  Future<List<SyncedTrack>> _tracks() => LocalDatabaseRepository()
      .getTracksByAlbum(albumName, albumArtist: artistName, year: year);

  Future<void> _play(BuildContext context, {bool shuffle = false}) async {
    final controller = context.read<PlaybackController>();
    final tracks = await _tracks();
    if (shuffle) {
      await shuffleCollection(controller, _origin, tracks);
    } else {
      await playCollectionInOrder(controller, _origin, tracks);
    }
  }

  Future<void> _enqueue(BuildContext context) async {
    final controller = context.read<PlaybackController>();
    final tracks = await _tracks();
    await controller.enqueueCollection(tracks);
    if (context.mounted && tracks.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${tracks.length} tracks from $albumName to queue')),
      );
    }
  }

  void _goToArtist(BuildContext context) {
    if (artistName.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArtistDetailScreen(artistName: artistName)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailScreen(
              albumName: albumName,
              artistName: artistName,
              artworkPath: artworkPath,
              albumArtist: artistName,
              year: year,
            ),
          ),
        );
      },
      onLongPress: () => _showRowMenu(context, _menuActions(context)),
      leading: AlbumArtTile(artworkPath: artworkPath),
      title: Text(
        albumName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        artistName.isNotEmpty
            ? (year > 0 ? '$artistName \u2022 $year' : artistName)
            : (year > 0 ? '$year' : ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, size: 22),
            onPressed: () => _showRowMenu(context, _menuActions(context)),
          ),
        ],
      ),
    );
  }

  List<_RowMenuAction> _menuActions(BuildContext context) {
    return [
      _RowMenuAction(
        icon: Icons.playlist_play,
        label: 'Play',
        onTap: () => _play(context),
      ),
      _RowMenuAction(
        icon: Icons.shuffle,
        label: 'Shuffle',
        onTap: () => _play(context, shuffle: true),
      ),
      _RowMenuAction(
        icon: Icons.add,
        label: 'Add to queue',
        onTap: () => _enqueue(context),
      ),
      _RowMenuAction(
        icon: Icons.person,
        label: 'Go to artist',
        onTap: () => _goToArtist(context),
      ),
    ];
  }
}

/// An artist row: initials tile, name, album/track counts, tap opens detail.
class ArtistRow extends StatelessWidget {
  final String artistName;
  final int trackCount;
  final int albumCount;

  const ArtistRow({
    super.key,
    required this.artistName,
    required this.trackCount,
    this.albumCount = 0,
  });

  QueueOrigin get _origin => QueueOrigin.artist(artistName);

  Future<List<SyncedTrack>> _tracks() =>
      LocalDatabaseRepository().getTracksByArtist(artistName);

  Future<void> _play(BuildContext context, {bool shuffle = false}) async {
    final controller = context.read<PlaybackController>();
    final tracks = await _tracks();
    if (shuffle) {
      await shuffleCollection(controller, _origin, tracks);
    } else {
      await playCollectionInOrder(controller, _origin, tracks);
    }
  }

  Future<void> _enqueue(BuildContext context) async {
    final controller = context.read<PlaybackController>();
    final tracks = await _tracks();
    await controller.enqueueCollection(tracks);
    if (context.mounted && tracks.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${tracks.length} tracks from $artistName to queue')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArtistDetailScreen(artistName: artistName),
          ),
        );
      },
      onLongPress: () => _showRowMenu(context, _menuActions(context)),
      leading: CircleAvatar(child: Text(artistInitials(artistName))),
      title: Text(
        artistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        albumCount > 0
            ? '$albumCount ${albumCount == 1 ? 'album' : 'albums'} \u2022 $trackCount ${trackCount == 1 ? 'track' : 'tracks'}'
            : '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
      ),
      trailing: IconButton(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert, size: 22),
        onPressed: () => _showRowMenu(context, _menuActions(context)),
      ),
    );
  }

  List<_RowMenuAction> _menuActions(BuildContext context) {
    return [
      _RowMenuAction(
        icon: Icons.playlist_play,
        label: 'Play all',
        onTap: () => _play(context),
      ),
      _RowMenuAction(
        icon: Icons.shuffle,
        label: 'Shuffle all',
        onTap: () => _play(context, shuffle: true),
      ),
      _RowMenuAction(
        icon: Icons.add,
        label: 'Add to queue',
        onTap: () => _enqueue(context),
      ),
    ];
  }
}
