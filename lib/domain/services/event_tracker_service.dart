import 'package:flutter/services.dart';
import '../../data/repositories/local_database_repository.dart';

class EventTrackerService {
  static const MethodChannel _channel = MethodChannel(
    'dev.educoder.owntone_sync/events',
  );
  final LocalDatabaseRepository _dbRepo;
  bool _isEnabled = false;

  EventTrackerService({required LocalDatabaseRepository dbRepo})
    : _dbRepo = dbRepo {
    _setupEventListener();
  }

  void _setupEventListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPlaybackEvent') {
        await _handlePlaybackEvent(call.arguments);
      }
    });
  }

  Future<void> _handlePlaybackEvent(dynamic arguments) async {
    if (!_isEnabled) return;

    final data = Map<String, dynamic>.from(arguments);
    final eventType = data['eventType'] as String;
    final title = data['title'] as String;
    final artist = data['artist'] as String;
    final album = data['album'] as String;
    final duration = data['duration'] as int;

    // Try to find matching track in our synced tracks
    final track = await _findMatchingTrack(title, artist, album, duration);

    if (track != null) {
      // Insert event into pending_events table
      await _dbRepo.insertEvent(
        PendingEvent(
          trackId: track.id,
          eventType: eventType,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          synced: false,
        ),
      );
    }
  }

  Future<SyncedTrack?> _findMatchingTrack(
    String title,
    String artist,
    String album,
    int durationMs,
  ) async {
    // Get all tracks and find best match
    final allTracks = await _dbRepo.getAllTracks();

    for (final track in allTracks) {
      // Match by title and artist (case insensitive)
      final titleMatch = track.title.toLowerCase() == title.toLowerCase();
      final artistMatch =
          track.artist.toLowerCase() == artist.toLowerCase() ||
          track.albumArtist.toLowerCase() == artist.toLowerCase();

      // Duration match within 5 seconds tolerance
      final durationDiff = (track.lengthMs - durationMs).abs();
      final durationMatch = durationDiff < 5000;

      if (titleMatch && artistMatch && durationMatch) {
        return track;
      }
    }

    return null;
  }

  Future<bool> checkPermission() async {
    try {
      final result = await _channel.invokeMethod(
        'isNotificationPermissionGranted',
      );
      return result as bool;
    } catch (e) {
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      // Handle error
    }
  }

  void enable() {
    _isEnabled = true;
  }

  void disable() {
    _isEnabled = false;
  }

  bool get isEnabled => _isEnabled;
}
