import 'package:flutter/services.dart';

import '../../data/repositories/local_database_repository.dart';
import '../../utils/logger.dart';

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
        logger.d('Received playback event from native: ${call.arguments}');
        await _handlePlaybackEvent(call.arguments);
      }
    });
  }

  Future<void> _handlePlaybackEvent(dynamic arguments) async {
    if (!_isEnabled) {
      logger.w('Event tracking is disabled, ignoring event');
      return;
    }

    try {
      final data = Map<String, dynamic>.from(arguments);
      final eventType = data['eventType'] as String;
      final title = data['title'] as String;
      final artist = data['artist'] as String;
      final album = data['album'] as String;
      final duration = data['duration'] as int;

      logger.i('Processing $eventType event: "$title" by "$artist"');

      // Try to find matching track in our synced tracks
      final track = await _findMatchingTrack(title, artist, album, duration);

      if (track != null) {
        logger.i('Matched to track ID ${track.id}: ${track.title}');

        // Insert event into pending_events table
        await _dbRepo.insertEvent(
          PendingEvent(
            trackId: track.id,
            eventType: eventType,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            synced: false,
          ),
        );

        logger.d('Event saved to database');
      } else {
        logger.w(
          'No matching track found for: "$title" by "$artist" (album: "$album", duration: ${duration}ms)',
        );
      }
    } catch (e, stackTrace) {
      logger.e(
        'Error handling playback event',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<SyncedTrack?> _findMatchingTrack(
    String title,
    String artist,
    String album,
    int durationMs,
  ) async {
    try {
      // Get all tracks and find best match
      final allTracks = await _dbRepo.getAllTracks();
      logger.d('Searching through ${allTracks.length} synced tracks');

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
    } catch (e, stackTrace) {
      logger.e(
        'Error finding matching track',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<bool> checkPermission() async {
    try {
      final result = await _channel.invokeMethod(
        'isNotificationPermissionGranted',
      );
      logger.d('Notification permission check: $result');
      return result as bool;
    } catch (e, stackTrace) {
      logger.e(
        'Error checking notification permission',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      logger.i('Requesting notification permission');
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e, stackTrace) {
      logger.e(
        'Error requesting notification permission',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void enable() {
    _isEnabled = true;
    logger.i('Event tracking enabled');
  }

  void disable() {
    _isEnabled = false;
    logger.i('Event tracking disabled');
  }

  bool get isEnabled => _isEnabled;
}
