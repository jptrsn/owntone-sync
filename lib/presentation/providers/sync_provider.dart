import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/playlist.dart';
import '../../data/models/sync_schedule.dart';
import '../../data/repositories/file_system_repository.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/repositories/owntone_api_repository.dart';
import '../../domain/services/permissions_service.dart';
import '../../domain/services/sync_service.dart';
import '../../utils/logger.dart';
import 'dart:async';

class SyncProvider extends ChangeNotifier {
  final PermissionsService _permissionsService = PermissionsService();

  static const _progressChannel = EventChannel(
    'dev.educoder.owntone_sync/sync_progress',
  );
  StreamSubscription<dynamic>? _progressSubscription;

  OwnToneApiRepository? _apiRepo;
  LocalDatabaseRepository? _dbRepo;
  FileSystemRepository? _fileRepo;

  String _serverUrl = '';
  bool _isConfigured = false;
  bool _hasStoragePermission = false;
  List<Playlist> _availablePlaylists = [];
  Set<int> _selectedPlaylistIds = {};
  bool _deleteOrphanedFiles = false;
  bool _isSyncing = false;
  SyncProgress? _syncProgress;
  String? _lastError;
  bool _isOnline = true;
  bool _isCancelling = false;
  bool _isLoadingPlaylists = false;
  SyncSchedule _syncSchedule = SyncSchedule();
  bool _eventTrackingEnabled = false;
  bool _isBatteryOptimizationDisabled = false;
  DateTime? _missedSyncTime;

  // Getters
  String get serverUrl => _serverUrl;
  bool get hasStoragePermission => _hasStoragePermission;
  List<Playlist> get availablePlaylists => _availablePlaylists;
  Set<int> get selectedPlaylistIds => _selectedPlaylistIds;
  bool get deleteOrphanedFiles => _deleteOrphanedFiles;
  bool get isSyncing => _isSyncing;
  SyncProgress? get syncProgress => _syncProgress;
  String? get lastError => _lastError;
  bool get isConfigured => _isConfigured;
  bool get isOnline => _isOnline;
  bool get isCancelling => _isCancelling;
  bool get isLoadingPlaylists => _isLoadingPlaylists;
  SyncSchedule get syncSchedule => _syncSchedule;
  bool get eventTrackingEnabled => _eventTrackingEnabled;
  bool get isBatteryOptimizationDisabled => _isBatteryOptimizationDisabled;
  DateTime? get missedSyncTime => _missedSyncTime;

  SyncProvider() {
    _initialize();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    _dbRepo = LocalDatabaseRepository();
    _fileRepo = FileSystemRepository();

    // Load saved server URL from preferences
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      await setServerUrl(savedUrl);
    }

    // Load delete orphaned files setting
    _deleteOrphanedFiles = prefs.getBool('delete_orphaned_files') ?? false;

    // Check permissions on startup
    _hasStoragePermission = await _permissionsService.hasStoragePermission();

    // Request notification permission for background sync
    if (!await _permissionsService.hasNotificationPermission()) {
      await _permissionsService.requestNotificationPermission();
    }

    // Load saved playlists
    await _loadSavedPlaylists();

    // Load sync schedule
    await _loadSyncSchedule();

    // Load cached playlist metadata
    await fetchPlaylists();

    // Check battery optimization status
    await checkBatteryOptimization();

    // Check for missed syncs
    _missedSyncTime = await checkForMissedSync();

    // Load event tracking preference (premium only)
    _eventTrackingEnabled = prefs.getBool('event_tracking_enabled') ?? false;
    logger.i('Event tracking preference loaded: $_eventTrackingEnabled');

    // Check if background sync is already running
    await checkIfSyncRunning();

    notifyListeners();
  }

  /// Update server URL
  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    _isConfigured = url.isNotEmpty;
    _apiRepo = OwnToneApiRepository(baseUrl: url);

    // Save to persistent storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);

    notifyListeners();
  }

  /// Clear server-specific settings and allow user to set up fresh
  Future<void> resetAppData({required bool deleteFiles}) async {
    if (_dbRepo == null || _fileRepo == null) {
      throw Exception('Repositories not initialized');
    }

    try {
      // Get all playlists and tracks before deleting
      final allPlaylists = await _dbRepo!.getAllPlaylists();
      final allTracks = await _dbRepo!.getAllTracks();

      // Delete music files if requested
      if (deleteFiles) {
        for (final track in allTracks) {
          try {
            await _fileRepo!.deleteTrack(track.localPath);
          } catch (e) {
            logger.e('Error deleting track file: ${track.localPath}', error: e);
            // Continue even if file deletion fails
          }

          // Delete artwork if it exists
          if (track.artworkPath != null) {
            try {
              await _fileRepo!.deleteTrack(track.artworkPath!);
            } catch (e) {
              logger.e(
                'Error deleting artwork: ${track.artworkPath}',
                error: e,
              );
            }
          }
        }

        // Delete playlist files
        for (final playlist in allPlaylists) {
          try {
            await _fileRepo!.deletePlaylistFile(playlist.name);
          } catch (e) {
            logger.e(
              'Error deleting playlist file: ${playlist.name}',
              error: e,
            );
          }
        }
      }

      // Clear database - order matters due to foreign keys

      // 1. Clear playlist-track relationships for all playlists
      for (final playlist in allPlaylists) {
        await _dbRepo!.clearPlaylistTracks(playlist.id);
      }

      // 2. Delete all playlists
      for (final playlist in allPlaylists) {
        await _dbRepo!.deletePlaylist(playlist.id);
      }

      // 3. Delete all tracks
      for (final track in allTracks) {
        await _dbRepo!.deleteTrack(track.id);
      }

      // 4. Clear playlist cache
      await _dbRepo!.clearPlaylistCache();

      // 5. Clear pending events
      final unsyncedEvents = await _dbRepo!.getUnsyncedEvents();
      for (final event in unsyncedEvents) {
        if (event.id != null) {
          await _dbRepo!.deleteEvent(event.id!);
        }
      }
      await _dbRepo!.deleteSyncedEvents();

      // Note: We're NOT clearing sync history - user might want to see what was synced before

      // Clear in-memory state
      _selectedPlaylistIds.clear();
      _availablePlaylists.clear();

      notifyListeners();

      logger.i('App data reset completed. Files deleted: $deleteFiles');
    } catch (e, stackTrace) {
      logger.e('Error resetting app data', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Request storage permission
  Future<bool> requestStoragePermission() async {
    _hasStoragePermission = await _permissionsService
        .requestStoragePermission();
    notifyListeners();
    return _hasStoragePermission;
  }

  /// Check if a background sync is running
  Future<void> checkIfSyncRunning() async {
    try {
      const channel = MethodChannel('dev.educoder.owntone_sync/sync');
      final isRunning = await channel.invokeMethod<bool>('isSyncRunning');

      if (isRunning == true) {
        logger.i('Background sync is currently running');
        _isSyncing = true;
        _subscribeToSyncProgress();
        notifyListeners();
      } else {
        logger.d('No background sync running');
      }
    } catch (e) {
      logger.e('Error checking sync state', error: e);
    }
  }

  void _subscribeToSyncProgress() {
    // Cancel existing subscription if any
    _progressSubscription?.cancel();

    _progressSubscription = _progressChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        // logger.d('Received progress event: $event');
        if (event is Map) {
          // Check if this is a completion event
          if (event['syncComplete'] == true) {
            logger.i('Sync completed with status: ${event['status']}');
            _isSyncing = false;
            _syncProgress = null;
            _isCancelling = false;
            notifyListeners();
            return;
          }

          // Otherwise it's a progress event
          _syncProgress = SyncProgress(
            currentPlaylist: event['currentPlaylist'] as String,
            totalPlaylists: event['totalPlaylists'] as int,
            currentPlaylistIndex: event['currentPlaylistIndex'] as int,
            totalTracks: event['totalTracks'] as int,
            downloadedTracks: event['downloadedTracks'] as int,
            currentTrackTitle: event['currentTrackTitle'] as String?,
            downloadProgress: event['downloadProgress'] as double?,
          );
          _isSyncing = true;
          notifyListeners();
        }
      },
      onError: (error) {
        logger.e('Error receiving sync progress', error: error);
        _isSyncing = false;
        _syncProgress = null;
        _isCancelling = false;
        notifyListeners();
      },
      onDone: () {
        logger.i('Sync progress stream closed - sync completed or cancelled');
        _isSyncing = false;
        _syncProgress = null;
        _isCancelling = false;
        notifyListeners();
      },
    );

    logger.d('Subscribed to sync progress events');
  }

  /// Fetch available playlists from server
  Future<void> fetchPlaylists() async {
    if (_apiRepo == null || _dbRepo == null) {
      _lastError = 'Server URL not configured';
      logger.i('Failed to fetch playlists - Server URL not configured');
      notifyListeners();
      return;
    }

    // Prevent concurrent fetches
    if (_isLoadingPlaylists) {
      logger.d('Already fetching playlists, ignoring request');
      return;
    }

    try {
      _isLoadingPlaylists = true;
      _lastError = null;
      notifyListeners();

      final response = await _apiRepo!.getPlaylists(limit: 1000);
      _availablePlaylists = response.items;
      _isOnline = true;

      logger.i('Fetched ${_availablePlaylists.length} playlists from server');

      // Cache the playlists
      await _dbRepo!.clearPlaylistCache();
      for (final playlist in _availablePlaylists) {
        await _dbRepo!.cachePlaylist(playlist);
      }
    } catch (e) {
      _lastError = 'Failed to fetch playlists: $e';
      _isOnline = false;

      logger.i('Failed to fetch playlists: $e');

      // Load from cache if server is unreachable
      await _loadPlaylistsFromCache();
    } finally {
      _isLoadingPlaylists = false;
      notifyListeners();
    }
  }

  /// Cancel ongoing sync
  Future<void> cancelSync() async {
    if (_isSyncing && !_isCancelling) {
      _isCancelling = true;
      notifyListeners();

      try {
        const channel = MethodChannel('dev.educoder.owntone_sync/sync');
        await channel.invokeMethod('cancelSync');
        logger.i('Sync cancelled');

        // Clean up state
        _isSyncing = false;
        _isCancelling = false;
        _syncProgress = null;
        notifyListeners();
      } catch (e) {
        logger.e('Error cancelling sync', error: e);
        _isCancelling = false;
        notifyListeners();
      }
    }
  }

  /// Load sync schedule from preferences
  Future<void> _loadSyncSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final scheduleJson = prefs.getString('sync_schedule');
    if (scheduleJson != null) {
      _syncSchedule = SyncSchedule.fromJson(json.decode(scheduleJson));
    }
  }

  /// Update sync schedule
  Future<void> updateSyncSchedule(SyncSchedule schedule) async {
    _syncSchedule = schedule;

    // Save to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_schedule', json.encode(schedule.toJson()));

    // Update native worker
    try {
      const channel = MethodChannel('dev.educoder.owntone_sync/sync');
      await channel.invokeMethod('updateSyncSchedule');
    } catch (e) {
      logger.e('Error updating sync schedule', error: e);
    }

    notifyListeners();
  }

  /// Check for missed background syncs that did not execute as scheduled
  Future<DateTime?> checkForMissedSync() async {
    if (!_syncSchedule.enabled) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final expectedSyncStr = prefs.getString('expected_next_sync');

    if (expectedSyncStr == null) {
      return null;
    }

    final expectedSyncMs = int.tryParse(expectedSyncStr);
    if (expectedSyncMs == null) {
      return null;
    }

    final expectedTime = DateTime.fromMillisecondsSinceEpoch(expectedSyncMs);
    final now = DateTime.now();

    // If expected time hasn't passed yet, no missed sync
    if (now.isBefore(expectedTime)) {
      return null;
    }

    // Give a 2-hour grace period for WorkManager delays
    final gracePeriod = expectedTime.add(const Duration(hours: 2));
    if (now.isBefore(gracePeriod)) {
      return null;
    }

    // Check if a sync actually ran after the expected time
    if (_dbRepo != null) {
      final history = await _dbRepo!.getSyncHistory(limit: 1);
      if (history.isNotEmpty) {
        final lastSync = history.first;
        final lastSyncTime = DateTime.fromMillisecondsSinceEpoch(
          lastSync.timestamp,
        );

        // If a sync ran after the expected time, it didn't miss
        if (lastSyncTime.isAfter(expectedTime)) {
          // Clear the expected time since we've moved past it
          await prefs.remove('expected_next_sync');
          return null;
        }
      }
    }

    logger.w('Possible missed sync detected. Expected: $expectedTime');
    return expectedTime;
  }

  /// Hide warning about missed sync
  Future<void> dismissMissedSyncWarning() async {
    _missedSyncTime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('expected_next_sync');
    notifyListeners();
  }

  /// Load playlists from local cache
  Future<void> _loadPlaylistsFromCache() async {
    if (_dbRepo == null) return;

    final cached = await _dbRepo!.getCachedPlaylists();
    _availablePlaylists = cached.map((map) {
      return Playlist(
        id: map['id'] as int,
        name: map['name'] as String,
        path: map['path'] as String,
        parentId: '0',
        type: map['type'] as String,
        smartPlaylist: map['type'] == 'smart',
        random: false,
        folder: false,
        itemCount: map['item_count'] as int,
        streamCount: 0,
        uri: 'library:playlist:${map['id']}',
      );
    }).toList();
  }

  /// Save user-selected playlists to include in sync
  Future<void> _saveSelectedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'selected_playlist_ids',
      _selectedPlaylistIds.map((id) => id.toString()).toList(),
    );
  }

  /// Load saved playlists from database
  Future<void> _loadSavedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList('selected_playlist_ids');

    if (savedIds != null) {
      _selectedPlaylistIds = savedIds.map((id) => int.parse(id)).toSet();
    }

    notifyListeners();
  }

  /// Toggle playlist selection
  /// Returns true if a playlist file was deleted, false otherwise
  Future<bool> togglePlaylistSelection(int playlistId) async {
    final wasSelected = _selectedPlaylistIds.contains(playlistId);
    bool fileWasDeleted = false;

    if (wasSelected) {
      // User is UNCHECKING - clean up playlist file and database
      _selectedPlaylistIds.remove(playlistId);

      // Get playlist info from database - only proceed if it exists
      final playlist = await _dbRepo?.getPlaylistById(playlistId);
      if (playlist != null) {
        try {
          // Delete playlist file
          if (_fileRepo != null) {
            await _fileRepo!.deletePlaylistFile(playlist.name);
            logger.i('Deleted playlist file for: ${playlist.name}');
            fileWasDeleted = true;
          }

          // Clear playlist-track relationships
          await _dbRepo!.clearPlaylistTracks(playlistId);

          // Delete from synced_playlists table
          await _dbRepo!.deletePlaylist(playlistId);
          logger.i('Removed playlist from database: ${playlist.name}');
        } catch (e) {
          logger.e('Error cleaning up playlist: ${playlist.name}', error: e);
          // Continue anyway - we've still deselected it
        }
      }
    } else {
      // User is CHECKING - just add to selection
      _selectedPlaylistIds.add(playlistId);
    }

    await _saveSelectedPlaylists();
    notifyListeners();

    return fileWasDeleted;
  }

  /// Toggle delete orphaned files setting
  Future<void> setDeleteOrphanedFiles(bool value) async {
    _deleteOrphanedFiles = value;

    // Save to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('delete_orphaned_files', value);

    notifyListeners();
  }

  /// Start sync
  Future<void> startSync() async {
    if (!_hasStoragePermission) {
      _lastError = 'Storage permission not granted';
      notifyListeners();
      return;
    }

    if (_selectedPlaylistIds.isEmpty) {
      _lastError = 'No playlists selected';
      notifyListeners();
      return;
    }

    try {
      _isSyncing = true;
      _lastError = null;
      _syncProgress = null;
      notifyListeners();

      // Trigger background sync via WorkManager
      const channel = MethodChannel('dev.educoder.owntone_sync/sync');
      await channel.invokeMethod('triggerBackgroundSync');

      logger.i('Background sync triggered');

      // Subscribe to progress events
      _subscribeToSyncProgress();
    } catch (e, stackTrace) {
      _lastError = 'Failed to start sync: $e';
      _isSyncing = false;
      _syncProgress = null;
      logger.e('Error triggering sync', error: e, stackTrace: stackTrace);
      notifyListeners();
    }
  }

  Future<bool> checkEventTrackingPermission() async {
    try {
      // Just check Android settings, no EventTracker service needed
      const channel = MethodChannel('dev.educoder.owntone_sync/events');
      final result = await channel.invokeMethod(
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

  Future<void> requestEventTrackingPermission() async {
    try {
      logger.i('Requesting notification permission');
      const channel = MethodChannel('dev.educoder.owntone_sync/events');
      await channel.invokeMethod('requestNotificationPermission');
    } catch (e, stackTrace) {
      logger.e(
        'Error requesting notification permission',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setEventTracking(bool enabled) async {
    _eventTrackingEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('event_tracking_enabled', enabled);

    logger.i('Event tracking ${enabled ? "enabled" : "disabled"}');
    notifyListeners();
  }

  Future<bool> checkBatteryOptimization() async {
    try {
      const channel = MethodChannel('dev.educoder.owntone_sync/events');
      final result = await channel.invokeMethod<bool>(
        'isBatteryOptimizationDisabled',
      );
      _isBatteryOptimizationDisabled = result ?? false;
      notifyListeners();
      return _isBatteryOptimizationDisabled;
    } catch (e) {
      logger.e('Error checking battery optimization', error: e);
      return false;
    }
  }

  Future<void> requestBatteryOptimizationExemption() async {
    try {
      logger.i('Requesting battery optimization exemption');
      const channel = MethodChannel('dev.educoder.owntone_sync/events');
      final result = await channel.invokeMethod(
        'requestBatteryOptimizationExemption',
      );
      logger.i('Battery optimization exemption result: $result');
    } catch (e, stackTrace) {
      logger.e(
        'Error requesting battery optimization exemption',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
