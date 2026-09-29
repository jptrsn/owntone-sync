import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

import '../../data/repositories/local_database_repository.dart';
import '../services/audio_handler.dart';
import '../services/track_uri_resolver.dart';

/// Where the current queue came from ("Playing from ...").
enum QueueOriginKind { playlist, album, artist, allTracks, search }

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

  const QueueOrigin.search(String query)
    : this(kind: QueueOriginKind.search, displayName: 'Search "$query"');

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
///
/// Also owns A8 persistence: [start] subscribes to the handler's sequence
/// and state streams and writes a [PlaybackStateRecord] on every queue,
/// track, shuffle/repeat, position, and app-lifecycle change;
/// [restorePlaybackState] brings it back (paused) on cold start.
class PlaybackController with WidgetsBindingObserver {
  PlaybackController({
    required OwnToneAudioHandler handler,
    required TrackUriResolver resolver,
    required LocalDatabaseRepository dbRepo,
  }) : _handler = handler,
       _resolver = resolver,
       _dbRepo = dbRepo,
       _originController = BehaviorSubject<QueueOrigin?>.seeded(null);

  final OwnToneAudioHandler _handler;
  final TrackUriResolver _resolver;
  final LocalDatabaseRepository _dbRepo;
  final BehaviorSubject<QueueOrigin?> _originController;

  bool _started = false;

  // A8 persistence state
  bool _hasQueue = false;
  SequenceSnapshot _latestSnapshot =
      const SequenceSnapshot(baseIds: [], shuffleIndices: []);
  int? _persistedCurrentId;
  Duration _latestPosition = Duration.zero;
  int _lastPersistedPositionMs = -1;
  AudioServiceShuffleMode _lastShuffleMode = AudioServiceShuffleMode.none;
  AudioServiceRepeatMode _lastRepeatMode = AudioServiceRepeatMode.none;
  bool _modesSeen = false;
  StreamSubscription<PositionData>? _positionDataSubscription;
  final BehaviorSubject<PositionData> _positionDataSubject =
      BehaviorSubject<PositionData>();

  Stream<MediaItem?> get mediaItem => _handler.mediaItem;

  Stream<PlaybackState> get playbackState => _handler.playbackState;

  /// The current playback state snapshot. The handler's subject is seeded,
  /// so this is safe to read any time (used to inspect shuffle/repeat mode
  /// without subscribing).
  PlaybackState get currentPlaybackState => _handler.playbackState.value;

  Stream<List<MediaItem>> get queue => _handler.queue;

  /// Base indices in play order. With shuffle off this list is a
  /// permutation that nothing plays by (play order is base order); with
  /// shuffle on it is the play order itself.
  Stream<List<int>> get shuffleIndices => _handler.shuffleIndicesStream;

  /// True while the NowPlayingSheet is presented. The sheet sets it in
  /// initState/dispose. The A9 skipped-track notice uses it to pick its
  /// owner: the sheet shows the notice while it is open, and the Library
  /// screen suppresses its own, so exactly one notice is ever shown.
  final ValueNotifier<bool> nowPlayingSheetOpen = ValueNotifier<bool>(false);

  Stream<QueueOrigin?> get queueOrigin => _originController.stream;

  /// Tracks that failed to play and were auto-advanced past (A9).
  Stream<MediaItem> get skippedTrack => _handler.skippedTrackStream;

  /// The queue stopped on its own because nothing left was playable (A9).
  Stream<QueueExhaustedReason> get queueExhausted =>
      _handler.queueExhaustedStream;

  /// Drops queued tracks whose id is not in [aliveTrackIds] (sync
  /// reconciliation on sync completion). Advances past the current track if
  /// it was dropped; never interrupts otherwise.
  Future<void> reconcileQueue(Set<int> aliveTrackIds) =>
      _handler.reconcileQueue(aliveTrackIds);

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

  /// Jumps to the queue item at base [baseIndex]. The caller performs the
  /// play-order -> base translation (shuffleIndices) before calling.
  Future<void> jumpTo(int baseIndex) => _handler.skipToQueueItem(baseIndex);

  /// Removes the first queue item whose id matches [item.id].
  Future<void> removeFromQueue(MediaItem item) =>
      _handler.removeQueueItem(item);

  /// Reorders the queue item at play-order row [fromRow] to row [toRow]
  /// (post-removal coordinates, as ReorderableListView reports).
  Future<void> moveQueueItem(int fromRow, int toRow) =>
      _handler.moveQueueItem(fromRow, toRow);

  /// Stops playback and empties the queue.
  Future<void> clearQueue() => _handler.clearQueue();

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

  /// Appends every resolvable track in [tracks] to the end of the queue,
  /// in the given order. URIs are resolved in one batch; the items are
  /// appended one at a time through the same verified per-item path as
  /// [enqueue] (the player exposes no batch-append API, and rebuilding the
  /// whole source list via `setAudioSources` would reset the shuffle order).
  Future<void> enqueueCollection(List<SyncedTrack> tracks) async {
    if (tracks.isEmpty) return;
    final uris = await _resolver.resolveCollection(tracks);
    for (final track in tracks) {
      final uri = uris[track.id];
      if (uri == null) continue;
      await _handler.addQueueItem(_toMediaItem(track, uri));
    }
  }

  // ---------------------------------------------------------------------------
  // A8: persistence and cold-start restore
  // ---------------------------------------------------------------------------

  /// Begins persistence. Idempotent; call once at startup, before
  /// [restorePlaybackState] so a restored queue is tracked from its first
  /// mutation. The controller is a process-lifetime object (like the
  /// handler), so the subscriptions are never cancelled.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _handler.sequenceSnapshotStream.listen(_onSequenceSnapshot);
    _handler.playbackState.listen(_onPlaybackStateChanged);
    positionData.listen(_onPositionTick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The process may die in paused/hidden; flush the current state first.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      unawaited(_persist());
    }
  }

  void _onSequenceSnapshot(SequenceSnapshot snap) {
    final wasNonEmpty = _hasQueue;
    _hasQueue = snap.baseIds.isNotEmpty;
    _latestSnapshot = snap;
    if (!_hasQueue) {
      // A non-empty queue becoming empty (clear queue, or the last track was
      // reconciled away) clears the persisted state. An empty snapshot with
      // no prior queue is the cold-start seed and must not wipe a row that
      // [restorePlaybackState] has not read yet.
      _persistedCurrentId = null;
      if (wasNonEmpty) unawaited(_dbRepo.clearPlaybackState());
      return;
    }
    final i = snap.currentIndex;
    _persistedCurrentId =
        (i != null && i >= 0 && i < snap.baseIds.length)
            ? snap.baseIds[i]
            : null;
    // A track change resets the live position; do not persist the previous
    // track's position under the new one.
    _latestPosition = Duration.zero;
    _lastPersistedPositionMs = -1;
    unawaited(_persist());
  }

  void _onPlaybackStateChanged(PlaybackState state) {
    if (!_modesSeen) {
      _lastShuffleMode = state.shuffleMode;
      _lastRepeatMode = state.repeatMode;
      _modesSeen = true;
      return;
    }
    if (state.shuffleMode == _lastShuffleMode &&
        state.repeatMode == _lastRepeatMode) {
      return;
    }
    _lastShuffleMode = state.shuffleMode;
    _lastRepeatMode = state.repeatMode;
    unawaited(_persist());
  }

  void _onPositionTick(PositionData data) {
    _latestPosition = data.position;
    if (!_hasQueue || _lastPersistedPositionMs < 0) return;
    final delta = (data.position.inMilliseconds - _lastPersistedPositionMs).abs();
    if (delta < 5000) return;
    unawaited(_persist());
  }

  Future<void> _persist() async {
    if (!_hasQueue) return;
    final snap = _latestSnapshot;
    final state = _handler.playbackState.value;
    final origin = currentOrigin;
    try {
      await _dbRepo.savePlaybackState(
        PlaybackStateRecord(
          queueIds: List<int>.unmodifiable(snap.baseIds),
          currentTrackId: _persistedCurrentId,
          positionMs: _latestPosition.inMilliseconds,
          shuffleEnabled: state.shuffleMode == AudioServiceShuffleMode.all,
          shuffleIndices: List<int>.unmodifiable(snap.shuffleIndices),
          repeatMode: state.repeatMode.name,
          originKind: origin?.kind.name,
          originId: origin?.id,
          originName: origin?.displayName,
        ),
      );
      _lastPersistedPositionMs = _latestPosition.inMilliseconds;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlaybackController] persist failed: $e');
      }
    }
  }

  /// A8 cold-start restore: reloads the persisted queue, origin, current
  /// track, position, shuffle permutation, and repeat mode, and leaves the
  /// player paused. No-op when nothing is persisted; never throws. Tracks
  /// that no longer exist are dropped, and the permutation is remapped onto
  /// the surviving tracks.
  Future<void> restorePlaybackState() async {
    try {
      final record = await _dbRepo.loadPlaybackState();
      if (record == null || record.queueIds.isEmpty) return;

      final tracks = <SyncedTrack>[];
      for (final id in record.queueIds) {
        if (id <= 0) continue;
        final track = await _dbRepo.getTrackById(id);
        if (track != null) tracks.add(track);
      }
      if (tracks.isEmpty) {
        await _dbRepo.clearPlaybackState();
        return;
      }

      final uris = await _resolver.resolveCollection(tracks);
      final playable = tracks.where((t) => uris[t.id] != null).toList();
      if (playable.isEmpty) {
        await _dbRepo.clearPlaybackState();
        return;
      }

      var startIndex = 0;
      final currentId = record.currentTrackId;
      if (currentId != null) {
        final i = playable.indexWhere((t) => t.id == currentId);
        if (i >= 0) startIndex = i;
      }

      // Remap the persisted permutation (old base indices) onto the
      // surviving tracks, which keep their relative base order.
      final newBaseOf = <int, int>{
        for (var i = 0; i < playable.length; i++) playable[i].id: i,
      };
      final perm = <int>[];
      for (final oldIdx in record.shuffleIndices) {
        if (oldIdx < record.queueIds.length) {
          final newIdx = newBaseOf[record.queueIds[oldIdx]];
          if (newIdx != null) perm.add(newIdx);
        }
      }
      for (var i = 0; i < playable.length; i++) {
        if (!perm.contains(i)) perm.add(i);
      }

      final items = playable.map((t) => _toMediaItem(t, uris[t.id]!)).toList();
      final origin = _originFromRecord(record);
      if (origin != null) _originController.add(origin);
      await _handler.restoreCollection(
        tracks: items,
        startIndex: startIndex,
        position: Duration(milliseconds: record.positionMs),
        repeatMode: AudioServiceRepeatMode.values.firstWhere(
          (m) => m.name == record.repeatMode,
          orElse: () => AudioServiceRepeatMode.none,
        ),
        shuffleEnabled: record.shuffleEnabled &&
            perm.length == playable.length,
        shuffleIndices: perm,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlaybackController] restore failed: $e');
      }
    }
  }

  QueueOrigin? _originFromRecord(PlaybackStateRecord record) {
    final QueueOriginKind kind;
    switch (record.originKind) {
      case 'playlist':
        kind = QueueOriginKind.playlist;
        break;
      case 'album':
        kind = QueueOriginKind.album;
        break;
      case 'artist':
        kind = QueueOriginKind.artist;
        break;
      case 'allTracks':
        kind = QueueOriginKind.allTracks;
        break;
      case 'search':
        kind = QueueOriginKind.search;
        break;
      default:
        return null;
    }
    return QueueOrigin(
      kind: kind,
      id: record.originId,
      displayName: record.originName ?? '',
    );
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
      // Album identity rides along so "Go to album" can disambiguate
      // same-named albums (name + album artist + year).
      extras: {'uri': uri, 'albumArtist': track.albumArtist, 'year': track.year},
    );
  }
}
