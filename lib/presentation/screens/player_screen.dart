import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../controllers/playback_controller.dart';
import '../widgets/queue_sheet.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';

/// Hero tag shared by the mini player artwork and the sheet artwork.
const String nowPlayingArtworkHeroTag = 'now_playing_artwork_hero';

/// Presents the Now Playing sheet as a modal bottom sheet (never a pushed
/// route): drag-to-dismiss, back gesture dismisses, and the artwork can
/// hero from the mini player.
void showNowPlayingSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const NowPlayingSheet(),
  );
}

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  late final PlaybackController _controller;
  StreamSubscription<MediaItem>? _skippedTrackSubscription;
  String? _lastNoticeTrackId;
  DateTime? _lastNoticeAt;
  // The sheet's OWN messenger. `ScaffoldMessenger.of(this.context)` would
  // resolve to an ancestor messenger (the nearest one above the route),
  // whose snackbar renders behind this sheet's barrier — invisible. The key
  // captures the messenger created in build(), which is a DESCENDANT of
  // this.context and therefore invisible to findAncestorStateOfType.
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Captured here (not read in dispose): looking up an ancestor during
    // dispose is unsafe once the element tree is deactivated.
    _controller = context.read<PlaybackController>();
    // While this sheet is open it owns the A9 skipped-track notice; the
    // Library screen suppresses its own so exactly one notice is shown.
    _controller.nowPlayingSheetOpen.value = true;
    _skippedTrackSubscription = _controller.skippedTrack.listen(_onSkippedTrack);
  }

  @override
  void dispose() {
    _skippedTrackSubscription?.cancel();
    _controller.nowPlayingSheetOpen.value = false;
    super.dispose();
  }

  /// A9: one-line, non-blocking notice naming the skipped track, rendered on
  /// this sheet's own ScaffoldMessenger (via [_messengerKey]) so it is
  /// visible while the sheet is open (the ancestor messenger's snackbar
  /// renders behind the sheet).
  void _onSkippedTrack(MediaItem item) {
    if (!mounted) return;
    final now = DateTime.now();
    final recent =
        _lastNoticeTrackId == item.id &&
        _lastNoticeAt != null &&
        now.difference(_lastNoticeAt!) < const Duration(seconds: 5);
    if (recent) return;
    _lastNoticeTrackId = item.id;
    _lastNoticeAt = now;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Skipped "${item.title}" - could not be played'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _goToAlbum(MediaItem item) {
    final album = item.album ?? '';
    if (album.isEmpty) return;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          albumName: album,
          artistName: item.artist ?? '',
          artworkPath: _artFilePath(item.artUri),
        ),
      ),
    );
  }

  void _goToArtist(MediaItem item) {
    final artist = item.artist ?? '';
    if (artist.isEmpty) return;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute(builder: (_) => ArtistDetailScreen(artistName: artist)),
    );
  }

  void _showTrackInfo(MediaItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.artist ?? ''),
            if ((item.album ?? '').isNotEmpty) Text(item.album!),
            const SizedBox(height: 8),
            if (item.duration != null)
              Text('Duration: ${_formatTime(item.duration!)}'),
            if (item.artUri != null)
              Text('File: ${item.artUri!.toFilePath()}',
                  style: Theme.of(dialogContext).textTheme.bodySmall),
          ],
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

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();
    final screenHeight = MediaQuery.sizeOf(context).height;

    // An explicit height makes the framework lay this out as a true bottom
    // sheet (bottom-aligned, rounded top, barrier, drag-to-dismiss). A
    // full-height child would instead become a full-screen page with the
    // content top-aligned.
    return ScaffoldMessenger(
      key: _messengerKey,
      child: SizedBox(
        width: double.infinity,
        height: screenHeight * 0.92,
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            top: false,
            child: StreamBuilder<MediaItem?>(
              stream: controller.mediaItem,
              builder: (context, itemSnapshot) {
                final item = itemSnapshot.data;
                if (item == null) {
                  return const Center(child: Text('No track playing'));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildAlbumArt(item.artUri),
                    const SizedBox(height: 24),
                    _buildTrackInfo(context, item),
                    const SizedBox(height: 16),
                    _buildOrigin(controller),
                    const SizedBox(height: 24),
                    _SeekControl(controller: controller),
                    const SizedBox(height: 24),
                    _buildPlaybackControls(context, controller, item),
                  ],
                );
              },
            ),
          ),
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

  String? _artFilePath(Uri? artUri) {
    if (artUri != null && artUri.scheme == 'file') {
      final path = artUri.toFilePath();
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Widget _buildAlbumArt(Uri? artUri) {
    final width = MediaQuery.sizeOf(context).width * 0.55;
    return Hero(
      tag: nowPlayingArtworkHeroTag,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image(
          image: _artImageProvider(artUri),
          fit: BoxFit.cover,
          width: width,
          height: width,
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          item.artist ?? '',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if ((item.album ?? '').isNotEmpty && item.album != item.artist) ...[
          const SizedBox(height: 4),
          Text(
            item.album!,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildOrigin(PlaybackController controller) {
    return StreamBuilder<QueueOrigin?>(
      stream: controller.queueOrigin,
      builder: (context, snapshot) {
        final origin = snapshot.data;
        if (origin == null) return const SizedBox.shrink();
        return Text(
          'Playing from ${origin.displayName}',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        );
      },
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    PlaybackController controller,
    MediaItem item,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return StreamBuilder<PlaybackState>(
      stream: controller.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final isPlaying = state?.playing ?? false;
        final shuffleOn = state?.shuffleMode == AudioServiceShuffleMode.all;
        final repeatMode = state?.repeatMode ?? AudioServiceRepeatMode.none;

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: shuffleOn ? 'Shuffle off' : 'Shuffle on',
                  icon: Icon(
                    Icons.shuffle,
                    size: 30,
                    color: shuffleOn ? primary : onSurface,
                  ),
                  onPressed: () => controller.toggleShuffle(),
                ),
                IconButton(
                  tooltip: 'Previous',
                  icon: const Icon(Icons.skip_previous, size: 44),
                  onPressed: () => controller.skipToPrevious(),
                ),
                IconButton(
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  icon: Icon(
                    isPlaying ? Icons.pause_circle : Icons.play_circle,
                    size: 68,
                    color: primary,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Next',
                  icon: const Icon(Icons.skip_next, size: 44),
                  onPressed: () => controller.skipToNext(),
                ),
                IconButton(
                  tooltip: switch (repeatMode) {
                    AudioServiceRepeatMode.one => 'Repeat one',
                    AudioServiceRepeatMode.all => 'Repeat all',
                    _ => 'Repeat off',
                  },
                  icon: Icon(
                    switch (repeatMode) {
                      AudioServiceRepeatMode.one => Icons.repeat_one,
                      AudioServiceRepeatMode.all => Icons.repeat,
                      _ => Icons.repeat_outlined,
                    },
                    size: 28,
                    color:
                        repeatMode == AudioServiceRepeatMode.none
                            ? onSurface
                            : primary,
                  ),
                  onPressed: () => controller.cycleRepeat(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Queue',
                  icon: const Icon(Icons.queue_music, size: 28),
                  onPressed: () => showQueueSheet(context),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (value) {
                    switch (value) {
                      case 'album':
                        _goToAlbum(item);
                      case 'artist':
                        _goToArtist(item);
                      case 'info':
                        _showTrackInfo(item);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'album', child: Text('Go to album')),
                    const PopupMenuItem(value: 'artist', child: Text('Go to artist')),
                    const PopupMenuItem(value: 'info', child: Text('Track info')),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Seek bar built on [PositionData]: max is the duration, the seek happens
/// once on release, and the scrub target time is shown while dragging.
class _SeekControl extends StatefulWidget {
  const _SeekControl({required this.controller});

  final PlaybackController controller;

  @override
  State<_SeekControl> createState() => _SeekControlState();
}

class _SeekControlState extends State<_SeekControl> {
  Duration? _scrubTarget;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: widget.controller.positionData,
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
        final displayPosition = _scrubTarget ?? safePosition;
        final max =
            hasDuration ? effectiveDuration.inMilliseconds.toDouble() : 1.0;
        final value =
            (_scrubTarget ?? safePosition).inMilliseconds
                .toDouble()
                .clamp(0.0, max);

        return Column(
          children: [
            Row(
              children: [
                Text(
                  _formatTime(displayPosition),
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
                onChanged: (value) {
                  // Display-only while dragging; the seek happens on release.
                  setState(() => _scrubTarget = Duration(milliseconds: value.toInt()));
                },
                onChangeEnd: (value) {
                  final target = Duration(milliseconds: value.toInt());
                  setState(() => _scrubTarget = null);
                  widget.controller.seek(target);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatTime(Duration duration) {
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  return '${duration.inMinutes}:$seconds';
}
