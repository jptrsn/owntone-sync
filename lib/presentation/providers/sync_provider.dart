import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/playlist.dart';
import '../../data/models/sync_schedule.dart';
import '../../data/models/sync_state.dart';
import '../../data/repositories/file_system_repository.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/repositories/owntone_api_repository.dart';
import '../../domain/services/permissions_service.dart';
import '../../domain/services/sync_service.dart';
import '../../utils/logger.dart';

class SyncProvider extends ChangeNotifier {
  final PermissionsService _permissionsService = PermissionsService();

  OwnToneApiRepository? _apiRepo;
  LocalDatabaseRepository? _dbRepo;
  FileSystemRepository? _fileRepo;
  SyncService? _syncService;

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
  SyncSchedule _syncSchedule = SyncSchedule();
  bool _eventTrackingEnabled = false;

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
  SyncSchedule get syncSchedule => _syncSchedule;
  bool get eventTrackingEnabled => _eventTrackingEnabled;

  SyncProvider() {
    _initialize();
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

    // Load saved playlists
    await _loadSavedPlaylists();

    // Load sync schedule
    await _loadSyncSchedule();

    // Load cached playlist metadata
    await fetchPlaylists();

    // Load event tracking preference (premium only)
    _eventTrackingEnabled = prefs.getBool('event_tracking_enabled') ?? false;
    logger.i('Event tracking preference loaded: $_eventTrackingEnabled');

    notifyListeners();
  }

  /// Update server URL
  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    _isConfigured = url.isNotEmpty;
    _apiRepo = OwnToneApiRepository(baseUrl: url);

    if (_dbRepo != null && _fileRepo != null) {
      _syncService = SyncService(
        apiRepo: _apiRepo!,
        dbRepo: _dbRepo!,
        fileRepo: _fileRepo!,
      );

      _syncService!.onProgress = (progress) {
        _syncProgress = progress;
        notifyListeners();
      };
    }

    // Save to persistent storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);

    notifyListeners();
  }

  /// Request storage permission
  Future<bool> requestStoragePermission() async {
    _hasStoragePermission = await _permissionsService
        .requestStoragePermission();
    notifyListeners();
    return _hasStoragePermission;
  }

  /// Fetch available playlists from server
  /// Fetch available playlists from server
  Future<void> fetchPlaylists() async {
    if (_apiRepo == null || _dbRepo == null) {
      _lastError = 'Server URL not configured';
      logger.i('Failed to fetch playlists - Server URL not configured');
      notifyListeners();
      return;
    }

    try {
      _lastError = null;
      final response = await _apiRepo!.getPlaylists(limit: 1000);
      _availablePlaylists = response.items;
      _isOnline = true;

      logger.i('Fetched ${_availablePlaylists.length} playlists from server');

      // Cache the playlists
      await _dbRepo!.clearPlaylistCache();
      for (final playlist in _availablePlaylists) {
        await _dbRepo!.cachePlaylist(playlist);
      }

      notifyListeners();
    } catch (e) {
      _lastError = 'Failed to fetch playlists: $e';
      _isOnline = false;

      logger.i('Failed to fetch playlists: $e');

      // Load from cache if server is unreachable
      await _loadPlaylistsFromCache();
      notifyListeners();
    }
  }

  /// Cancel ongoing sync
  void cancelSync() {
    if (_syncService != null && _isSyncing && !_isCancelling) {
      _isCancelling = true;
      _syncService!.cancelSync();
      notifyListeners();
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

  Future<void> _saveSelectedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'selected_playlist_ids',
      _selectedPlaylistIds.map((id) => id.toString()).toList(),
    );
  }

  /// Load saved playlists from database
  Future<void> _loadSavedPlaylists() async {
    if (_dbRepo == null) return;

    final savedPlaylists = await _dbRepo!.getAllPlaylists();
    _selectedPlaylistIds = savedPlaylists.map((p) => p.id).toSet();
    notifyListeners();
  }

  /// Toggle playlist selection
  Future<void> togglePlaylistSelection(int playlistId) async {
    if (_selectedPlaylistIds.contains(playlistId)) {
      _selectedPlaylistIds.remove(playlistId);
    } else {
      _selectedPlaylistIds.add(playlistId);
    }

    await _saveSelectedPlaylists();
    notifyListeners();
  }

  /// Toggle delete orphaned files setting
  Future<void> setDeleteOrphanedFiles(bool value) async {
    _deleteOrphanedFiles = value;
    if (_syncService != null) {
      _syncService!.deleteOrphanedFiles = value;
    }

    // Save to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('delete_orphaned_files', value);

    notifyListeners();
  }

  /// Start sync
  Future<void> startSync() async {
    if (_syncService == null) {
      _lastError = 'Sync service not initialized';
      notifyListeners();
      return;
    }

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
      _isCancelling = false;
      _lastError = null;
      _syncProgress = null;
      notifyListeners();

      // Mark sync as running
      final prefs = await SharedPreferences.getInstance();
      final runningSyncState = SyncState(isRunning: true);
      await prefs.setString(
        'sync_state',
        json.encode(runningSyncState.toJson()),
      );

      // Sync events back to server if tracking is enabled
      if (_eventTrackingEnabled && _syncService != null) {
        logger.i('Syncing events to server before playlist sync');
        await _syncService!.syncEvents();
      }

      final result = await _syncService!.syncPlaylists(
        _selectedPlaylistIds.toList(),
      );

      // Update sync state
      final completedSyncState = SyncState(
        isRunning: false,
        lastSyncTime: DateTime.now(),
        lastSyncSuccess: result.success,
      );
      await prefs.setString(
        'sync_state',
        json.encode(completedSyncState.toJson()),
      );

      if (result.success) {
        _lastError = null;
        logger.i('Sync completed successfully');

        // Refresh playlist metadata from server
        logger.i('Refreshing playlist metadata after sync');
        await fetchPlaylists();
      } else {
        // Don't show cancellation as an error
        if (result.error != 'Sync cancelled by user') {
          _lastError = result.error;
          logger.e('Sync failed: ${result.error}');
        }
      }
    } catch (e, stackTrace) {
      _lastError = 'Sync failed: $e';
      logger.e('Sync exception', error: e, stackTrace: stackTrace);

      // Mark sync as not running on error
      final prefs = await SharedPreferences.getInstance();
      final errorSyncState = SyncState(
        isRunning: false,
        lastSyncSuccess: false,
      );
      await prefs.setString('sync_state', json.encode(errorSyncState.toJson()));
    } finally {
      _isSyncing = false;
      _isCancelling = false;
      _syncProgress = null;
      notifyListeners();
    }
  }

  // Keep permission check methods (they open Android settings)
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

  // Simplify toggle - just save to SharedPreferences
  Future<void> setEventTracking(bool enabled) async {
    _eventTrackingEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('event_tracking_enabled', enabled);

    logger.i('Event tracking ${enabled ? "enabled" : "disabled"}');
    notifyListeners();
  }
}
