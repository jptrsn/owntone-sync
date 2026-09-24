import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../data/repositories/local_database_repository.dart';
import '../services/audio_handler.dart';
import '../services/track_uri_resolver.dart';

/// Where the current queue came from ("Playing from ...").
enum QueueOriginKind { playlist, album, artist, allTracks }

/// A small value type identifying the origin of the current queue.
class QueueOrigin {
  final QueueOriginKind kind;
  final int? id;
  final String displayName;

  const QueueOrigin({required this.kind, this.id, required this.displayName});

  const QueueOrigin.playlist(int id, String name)
    : this(kind: QueueOriginKind.playlist, id: id, displayName: name);

  const QueueOrigin.album(String name)
    : this(kind: QueueOriginKind.album, displayName: name);

  const QueueOrigin.artist(String name)
    : this(kind: QueueOriginKind.artist, displayName: name);

  const QueueOrigin.allTracks([String name = 'All tracks'])
    : this(kind: QueueOriginKind.allTracks, displayName: name);

  @override
  bool operator ==(Object other) =>
      other is QueueOrigin &&
      other.kind == kind &&
      other.id == id &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(kind, id, displayName);

  @override
  String toString() => displayName;
}

/// Position + buffered position + duration for the seek bar.
class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration? duration;

  const PositionData({
    required this.position,
    required this.bufferedPosition,
    this.duration,
  });
}

/// Thin Dart facade over [OwnToneAudioHandler].
///
/// The handler owns the queue; this controller forwards intents and
/// re-exposes the handler's streams. It never holds a Dart-side queue list.
class PlaybackController {
  PlaybackController({
    required OwnToneAudioHandler handler,
    required TrackUriResolver resolver,
  }) : _handler = handler,
       _resolver = resolver,
       _originController = BehaviorSubject<QueueOrigin?>.seeded(null);

  final OwnToneAudioHandler _handler;
  final TrackUriResolver _resolver;
  final BehaviorSubject<QueueOrigin?> _originController;
  StreamSubscription<PositionData>? _positionDataSubscription;
  final BehaviorSubject<PositionData> _positionDataSubject =
      BehaviorSubject<PositionData>();

  Stream<MediaItem?> get mediaItem => _handler.mediaItem;

  Stream<PlaybackState> get playbackState => _handler.playbackState;

  Stream<List<MediaItem>> get queue => _handler.queue;

  Stream<QueueOrigin?> get queueOrigin => _originController.stream;

  /// Tracks that failed to play and were auto-advanced past (A9).
  Stream<MediaItem> get skippedTrack => _handler.skippedTrackStream;

  /// The origin of the queue currently loaded into the handler.
  QueueOrigin? get currentOrigin => _originController.value;

  /// Position + buffered + duration for the seek bar.
  ///
  /// Position comes from [AudioService.position] (which extrapolates between
  /// platform events). Duration prefers the player's decoded duration and
  /// falls back to the media item's metadata duration.
  ///
  /// The rxdart combineLatest result is a single-subscription stream that
  /// cannot be listened to again once a listener has cancelled (reopening
  /// PlayerScreen threw "Bad state: Stream has already been listened to"),
  /// so the controller subscribes exactly once and re-exposes the values
  /// through a broadcast subject.
  Stream<PositionData> get positionData {
    _positionDataSubscription ??= _buildPositionDataStream().listen(
      _positionDataSubject.add,
      onError: _positionDataSubject.addError,
      onDone: _positionDataSubject.close,
    );
    return _positionDataSubject.stream;
  }

  Stream<PositionData> _buildPositionDataStream() {
    final position = AudioService.position;
    final buffered = _handler.playbackState.map((s) => s.bufferedPosition);
    final duration = Rx.combineLatest2<Duration?, Duration?, Duration?>(
      _handler.durationStream,
      _handler.mediaItem.map((m) => m?.duration),
      (decoded, fromItem) => decoded ?? fromItem,
    );

    return Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      position,
      buffered,
      duration,
      (pos, buffered, duration) => PositionData(
        position: pos,
        bufferedPosition: buffered,
        duration: duration,
      ),
    );
  }

  /// The only way to start playback: load [tracks] (with [origin]) into the
  /// handler's queue and start at [startIndex]. Tracks that cannot be
  /// resolved to a playable URI are filtered out, and [startIndex] is remapped
  /// to the same track in the filtered list.
  Future<void> playCollection(
    QueueOrigin origin,
    List<SyncedTrack> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;

    final uris = await _resolver.resolveCollection(tracks);

    final playable = <SyncedTrack>[];
    for (final track in tracks) {
      if (uris[track.id] != null) playable.add(track);
    }

    if (playable.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PlaybackController] playCollection: '
          'no resolvable tracks in ${tracks.length}',
        );
      }
      return;
    }

    var adjustedStart = 0;
    if (startIndex >= 0 && startIndex < tracks.length) {
      final startId = tracks[startIndex].id;
      adjustedStart = playable.indexWhere((t) => t.id == startId);
      if (adjustedStart < 0) adjustedStart = 0;
    }

    final items = playable.map((t) => _toMediaItem(t, uris[t.id]!)).toList();

    _originController.add(origin);
    await _handler.playCollection(items, startIndex: adjustedStart);
  }

  Future<void> play() => _handler.play();

  Future<void> pause() => _handler.pause();

  Future<void> stop() => _handler.stop();

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> skipToNext() => _handler.skipToNext();

  Future<void> skipToPrevious() => _handler.skipToPrevious();

  /// Toggles shuffle. The player owns the shuffle mode; this just flips it.
  Future<void> toggleShuffle() async {
    final current = _handler.playbackState.value.shuffleMode;
    final next = current == AudioServiceShuffleMode.all
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    await _handler.setShuffleMode(next);
  }

  /// Cycles repeat: off -> all -> one -> off.
  Future<void> cycleRepeat() async {
    final current = _handler.playbackState.value.repeatMode;
    final next = switch (current) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
      AudioServiceRepeatMode.group => AudioServiceRepeatMode.none,
    };
    await _handler.setRepeatMode(next);
  }

  /// Inserts [track] immediately after the current track. If nothing is
  /// loaded yet, the track is appended.
  Future<void> playNext(SyncedTrack track) async {
    final uris = await _resolver.resolveCollection([track]);
    final uri = uris[track.id];
    if (uri == null) return;
    final item = _toMediaItem(track, uri);
    final index = _handler.playbackState.value.queueIndex;
    if (index == null || index < 0) {
      await _handler.addQueueItem(item);
    } else {
      await _handler.insertQueueItem(index + 1, item);
    }
  }

  /// Appends [track] to the end of the queue.
  Future<void> enqueue(SyncedTrack track) async {
    final uris = await _resolver.resolveCollection([track]);
    final uri = uris[track.id];
    if (uri == null) return;
    await _handler.addQueueItem(_toMediaItem(track, uri));
  }

  MediaItem _toMediaItem(SyncedTrack track, String uri) {
    final artworkPath = track.artworkPath;
    return MediaItem(
      id: track.id.toString(),
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.lengthMs > 0
          ? Duration(milliseconds: track.lengthMs)
          : null,
      artUri: (artworkPath != null && artworkPath.isNotEmpty)
          ? Uri.file(artworkPath)
          : null,
      extras: {'uri': uri},
    );
  }
}
