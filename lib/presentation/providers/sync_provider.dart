import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/playlist.dart';
import '../../data/models/sync_history.dart';
import '../../data/models/sync_progress.dart';
import '../../data/models/sync_schedule.dart';
import '../../data/repositories/file_system_repository.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/repositories/owntone_api_repository.dart';
import '../../domain/services/permissions_service.dart';

import '../../utils/connectivity_state.dart';
import '../../utils/logger.dart';
import 'dart:async';

class SyncProvider extends ChangeNotifier {
  final PermissionsService _permissionsService = PermissionsService();

  static const _progressChannel = EventChannel(
    'dev.educoder.owntone_sync/sync_progress',
  );
  StreamSubscription<dynamic>? _progressSubscription;
  final StreamController<String> _syncCompletedController =
      StreamController<String>.broadcast();

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
  // The raw failure text, kept for logs and future surfaces only (no
  // current reader). The UI reads [connectivityState], never this string
  // (U1 build item 1).
  String? _lastError;
  ConnectivityState _connectivity = ConnectivityState.unconfigured;
  // Whether the displayed playlist list came from a fetch that succeeded.
  // [connectivityState] says the server answered; this says the list shown
  // is what it just sent. A failed fetch - even one the server answered
  // with an HTTP error - drops it back to the local cache (invariant 40).
  bool _lastFetchSucceeded = false;
  SyncHistoryRecord? _lastSync;
  bool _isCancelling = false;
  bool _isLoadingPlaylists = false;
  SyncSchedule _syncSchedule = SyncSchedule();
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
  bool get isCancelling => _isCancelling;
  bool get isLoadingPlaylists => _isLoadingPlaylists;
  SyncSchedule get syncSchedule => _syncSchedule;
  bool get isBatteryOptimizationDisabled => _isBatteryOptimizationDisabled;
  DateTime? get missedSyncTime => _missedSyncTime;

  /// The four-state connectivity model the UI reads (U1 build item 1):
  /// [ConnectivityState.unconfigured] / [ConnectivityState.reachable] /
  /// [ConnectivityState.offline] / [ConnectivityState.unreachable].
  ///
  /// It is derived, never persisted: a fetch that reached the server, or a
  /// sync run completing with `success`/`partial`, establishes
  /// [ConnectivityState.reachable]; a failed fetch is classified by
  /// [classifySyncFailure]; saving a URL drops the state to the neutral
  /// unverified rendering ([ConnectivityState.offline] when configured),
  /// which looks identical to a genuinely offline session because offline
  /// shows nothing at all.
  ConnectivityState get connectivityState => _connectivity;

  /// Whether the currently displayed playlist list came from a fetch that
  /// succeeded (invariant 40). Reachability alone proves the server
  /// answered, not that the list shown is current: an HTTP-error fetch
  /// leaves the state [ConnectivityState.reachable] while the displayed
  /// list is the local cache again, and only this flag says so.
  bool get lastFetchSucceeded => _lastFetchSucceeded;

  /// The newest `sync_history` row: the source of the drawer's "last
  /// synced" line. Freshness, not fault, is the app's status signal
  /// (U1 build item 4).
  SyncHistoryRecord? get lastSync => _lastSync;

  /// Emits the worker's completion status ('success', 'partial', 'failed',
  /// 'cancelled', 'skipped', 'interrupted') each time a sync run ends.
  /// Library refresh and queue reconciliation hook off this (C2/C3).
  Stream<String> get syncCompleted => _syncCompletedController.stream;

  /// How [setServerUrl] builds the API repository. Production uses the
  /// default; tests inject a repository whose Dio rejects with the exact
  /// dio exception shapes they want classified (invariant 40 tests).
  final OwnToneApiRepository Function(String baseUrl) _createApiRepository;

  static OwnToneApiRepository _defaultApiRepository(String baseUrl) =>
      OwnToneApiRepository(baseUrl: baseUrl);

  SyncProvider({OwnToneApiRepository Function(String baseUrl)? apiRepository})
    : _createApiRepository = apiRepository ?? _defaultApiRepository {
    _initialize();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _syncCompletedController.close();
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
      try {
        await _permissionsService.requestNotificationPermission();
      } catch (e) {
        // Activity may not be ready yet; will retry later
      }
    }

    // Load saved playlists
    await _loadSavedPlaylists();

    // Load sync schedule
    await _loadSyncSchedule();

    // Load the newest sync run for the drawer's "last synced" line.
    await _loadLastSync();

    // Load cached playlist metadata. This is a background refresh, not a
    // boot gate: its failure only *classifies* the connectivity state, it
    // never sets a user-visible error (U1 build items 1 and 2; G2).
    await fetchPlaylists();

    // Check battery optimization status
    await checkBatteryOptimization();

    // Check for missed syncs
    _missedSyncTime = await checkForMissedSync();

    // Check for missed syncs
    await checkIfSyncRunning();

    notifyListeners();
  }

  /// Update server URL.
  ///
  /// Saving an address does not prove it works: the state drops to the
  /// neutral unverified rendering (which, like a genuinely offline session,
  /// shows nothing). Only a fetch that reaches the server, or a sync run
  /// completing with `success`/`partial`, establishes
  /// [ConnectivityState.reachable]; a failed fetch classifies the failure.
  ///
  /// This is the only save-transition owner (invariant 40): it also
  /// invalidates list freshness - whatever is displayed, if anything,
  /// predates the new address.
  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    _isConfigured = url.isNotEmpty;
    _apiRepo = _createApiRepository(url);

    // Save to persistent storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);

    _connectivity = _isConfigured
        ? ConnectivityState.offline
        : ConnectivityState.unconfigured;
    _lastFetchSucceeded = false;

    notifyListeners();
  }

  /// Loads the newest `sync_history` row into [lastSync]. The drawer's
  /// "last synced" line renders from it; a failed read just hides the line.
  Future<void> _loadLastSync() async {
    final dbRepo = _dbRepo;
    if (dbRepo == null) return;
    try {
      final history = await dbRepo.getSyncHistory(limit: 1);
      _lastSync = history.isEmpty ? null : history.first;
    } catch (e) {
      logger.e('Failed to load last sync run', error: e);
      _lastSync = null;
    }
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
            final status = (event['status'] ?? 'unknown').toString();
            logger.i('Sync completed with status: $status');
            _isSyncing = false;
            _syncProgress = null;
            _isCancelling = false;
            // A successful or partial run proves the server answered, so it
            // establishes reachability and clears any surfaced error. A run
            // that does not complete with success/partial keeps the
            // connectivity state as it is - including a fresh reachable
            // (its message goes to logs, never to the UI - U1 build items 1
            // and 5); re-arming a red banner from a worker string is
            // exactly the pre-U1 defect this phase removes.
            if (status == 'success' || status == 'partial') {
              _lastError = null;
              _connectivity = ConnectivityState.reachable;
            } else {
              final message = event['message'];
              _lastError = (message is String && message.isNotEmpty)
                  ? message
                  : 'Sync $status';
            }
            notifyListeners();
            _syncCompletedController.add(status);
            // The drawer's "last synced" line reads the newest history row;
            // a run just ended, so refresh it.
            unawaited(_loadLastSync());
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

  /// Fetch available playlists from server.
  ///
  /// The one contact that classifies the connectivity state. A fetch that
  /// reaches the server establishes [ConnectivityState.reachable] (an HTTP
  /// error status is still an answer - the connection worked) and marks the
  /// displayed list fresh; failure is classified by [classifySyncFailure]
  /// (type and errno only, never message text) and marks the displayed list
  /// stale again. The raw failure string is kept in [lastError] for logs
  /// and future surfaces; no UI reads it.
  Future<void> fetchPlaylists() async {
    if (!_isConfigured || _apiRepo == null || _dbRepo == null) {
      // Not configured is a state, not an error: the Library empty state is
      // the setup entry (U1 build item 3), and it must never render red.
      _connectivity = ConnectivityState.unconfigured;
      logger.i('Fetch playlists skipped - server URL not configured');
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
      _connectivity = ConnectivityState.reachable;
      // The displayed list is what the server just sent: fresh.
      _lastFetchSucceeded = true;

      logger.i('Fetched ${_availablePlaylists.length} playlists from server');

      // Cache the playlists
      await _dbRepo!.clearPlaylistCache();
      for (final playlist in _availablePlaylists) {
        await _dbRepo!.cachePlaylist(playlist);
      }
    } catch (e) {
      _lastError = 'Failed to fetch playlists: $e';
      _connectivity = classifySyncFailure(e);
      // The displayed list is the local cache again: not fresh.
      _lastFetchSucceeded = false;

      logger.i('Failed to fetch playlists: $e (state: $_connectivity)');

      // Load from cache so browsing and selection still work
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

  /// Update sync schedule. Throws if the schedule could not be registered
  /// on the native side, so callers do not report a save that did not take
  /// effect.
  Future<void> updateSyncSchedule(SyncSchedule schedule) async {
    _syncSchedule = schedule;

    // Save to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_schedule', json.encode(schedule.toJson()));

    // Update native worker. The native side reports false when the
    // WorkManager enqueue threw; a channel error throws on its own.
    const channel = MethodChannel('dev.educoder.owntone_sync/sync');
    final registered = await channel.invokeMethod<bool>('updateSyncSchedule');
    if (registered != true) {
      logger.e('Sync schedule was not registered on the native side');
      throw Exception('Could not register sync schedule');
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

  /// Start a manual sync.
  ///
  /// Returns null when the sync was started, or a human-readable reason
  /// when it was not. Callers surface the reason locally (a snackbar at the
  /// tap site); it must never become a global error state - the four
  /// connectivity states are the only error surfaces (U1 build item 1).
  Future<String?> startSync() async {
    if (!_hasStoragePermission) {
      logger.i('Sync not started - storage permission not granted');
      return 'Storage permission not granted';
    }

    if (_selectedPlaylistIds.isEmpty) {
      logger.i('Sync not started - no playlists selected');
      return 'Select at least one playlist to sync';
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
      return null;
    } catch (e, stackTrace) {
      _lastError = 'Failed to start sync: $e';
      _isSyncing = false;
      _syncProgress = null;
      logger.e('Error triggering sync', error: e, stackTrace: stackTrace);
      notifyListeners();
      return 'Could not start sync - try again';
    }
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

  Future<List<SyncedTrack>?> getTracksForPlaylist(int playlistId) async {
    await _initializeIfNeeded();
    return _dbRepo?.getTracksForPlaylist(playlistId);
  }

  Future<List<SyncedTrack>?> getTracksByArtist(String artistName) async {
    await _initializeIfNeeded();
    return _dbRepo?.getTracksByArtist(artistName);
  }

  Future<List<SyncedTrack>?> getTracksByAlbum(String albumName) async {
    await _initializeIfNeeded();
    return _dbRepo?.getTracksByAlbum(albumName);
  }

  Future<SyncedTrack?> getTrackById(int id) async {
    await _initializeIfNeeded();
    return _dbRepo?.getTrackById(id);
  }

  Future<List<SyncedTrack>?> getAllTracks() async {
    await _initializeIfNeeded();
    return _dbRepo?.getAllTracks();
  }

  Future<void> _initializeIfNeeded() async {
    _dbRepo ??= LocalDatabaseRepository();
  }
}
