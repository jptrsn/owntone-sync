import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sync_provider.dart';
import 'package:owntone_sync/data/repositories/local_database_repository.dart';

class PlayerProvider extends ChangeNotifier {
  static const _playerChannel = MethodChannel('dev.educoder.owntone_sync/player');

  final SyncProvider _syncProvider;

  int? _currentPlaylistId;
  bool _isPlaying = false;
  bool _shuffleMode = false;
  bool _repeatMode = false;
  int _queueVersion = 0;
  List<SyncedTrack> _queue = [];

  PlayerProvider({SyncProvider? syncProvider})
      : _syncProvider = syncProvider ?? SyncProvider() {
    _syncProvider.addListener(_onSyncProgress);
  }

  int? get currentPlaylistId => _currentPlaylistId;
  bool get isPlaying => _isPlaying;
  bool get shuffleMode => _shuffleMode;
  bool get repeatMode => _repeatMode;
  int get queueVersion => _queueVersion;
  List<SyncedTrack> get queue => _queue;

  Future<void> loadPlaylist(int playlistId) async {
    _currentPlaylistId = playlistId;
    await _buildQueueFromPlaylist(playlistId);
    notifyListeners();
  }

  Future<void> loadAllTracks() async {
    _currentPlaylistId = null;
    await _buildQueueFromAllTracks();
    notifyListeners();
  }

  Future<void> playTrack(int trackId) async {
    try {
      await _playerChannel.invokeMethod('playTrack', {'trackId': trackId});
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error playing track: $e');
      }
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _playerChannel.invokeMethod('seek', {'positionMs': position.inMilliseconds});
    } catch (e) {
      if (kDebugMode) {
        print('Error seeking: $e');
      }
    }
  }

  void toggleShuffle() {
    _shuffleMode = !_shuffleMode;
    notifyListeners();
  }

  void toggleRepeat() {
    _repeatMode = !_repeatMode;
    notifyListeners();
  }

  int getQueueTrackCount() {
    return _queue.length;
  }

  SyncedTrack? getCurrentlyPlayingTrack() {
    if (_isPlaying && _currentPlaylistId != null && _queue.isNotEmpty) {
      try {
        return _queue.firstWhere((t) => t.id == _currentPlaylistId);
      } catch (e) {
        return _queue.isNotEmpty ? _queue.first : null;
      }
    }
    return null;
  }

  Future<void> _buildQueueFromPlaylist(int playlistId) async {
    _queue = await _syncProvider.getTracksForPlaylist(playlistId) ?? [];
    _queueVersion = _queue.length;
    await _loadQueueIntoAudioHandler();
  }

  Future<void> _buildQueueFromAllTracks() async {
    _queue = await _syncProvider.getAllTracks() ?? [];
    _queueVersion = _queue.length;
    await _loadQueueIntoAudioHandler();
  }

  Future<void> _loadQueueIntoAudioHandler() async {
    if (_queue.isEmpty) return;

    final uris = _queue
        .where((t) => t.contentUri != null)
        .map((t) => t.contentUri!)
        .toList();

    if (uris.isNotEmpty) {
      try {
        await _playerChannel.invokeMethod('loadQueue', {'uris': uris});
      } catch (e) {
        if (kDebugMode) {
          print('Error loading queue: $e');
        }
      }
    }
  }

  void _onSyncProgress() {
    if (!_syncProvider.isSyncing && _syncProvider.syncProgress == null) {
      if (_currentPlaylistId != null) {
        loadPlaylist(_currentPlaylistId!);
      } else {
        loadAllTracks();
      }
    }
  }

  @override
  void dispose() {
    _syncProvider.removeListener(_onSyncProgress);
    super.dispose();
  }
}
