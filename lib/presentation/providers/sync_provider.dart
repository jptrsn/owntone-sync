import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/owntone_api_repository.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/repositories/file_system_repository.dart';
import '../../domain/services/sync_service.dart';
import '../../domain/services/permissions_service.dart';
import '../../data/models/playlist.dart';

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

    // Check permissions on startup
    _hasStoragePermission = await _permissionsService.hasStoragePermission();

    // Load saved playlists
    await _loadSavedPlaylists();

    // Load cached playlist metadata
    await _loadPlaylistsFromCache();

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
      notifyListeners();
      return;
    }

    try {
      _lastError = null;
      final response = await _apiRepo!.getPlaylists(limit: 1000);
      _availablePlaylists = response.items;
      _isOnline = true;

      // Cache the playlists
      await _dbRepo!.clearPlaylistCache();
      for (final playlist in _availablePlaylists) {
        await _dbRepo!.cachePlaylist(playlist);
      }

      notifyListeners();
    } catch (e) {
      _lastError = 'Failed to fetch playlists: $e';
      _isOnline = false;

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
  void togglePlaylistSelection(int playlistId) {
    if (_selectedPlaylistIds.contains(playlistId)) {
      _selectedPlaylistIds.remove(playlistId);
    } else {
      _selectedPlaylistIds.add(playlistId);
    }
    notifyListeners();
  }

  /// Toggle delete orphaned files setting
  void setDeleteOrphanedFiles(bool value) {
    _deleteOrphanedFiles = value;
    if (_syncService != null) {
      _syncService!.deleteOrphanedFiles = value;
    }
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

      final result = await _syncService!.syncPlaylists(
        _selectedPlaylistIds.toList(),
      );

      if (result.success) {
        _lastError = null;
      } else {
        // Don't show cancellation as an error
        if (result.error != 'Sync cancelled by user') {
          _lastError = result.error;
        }
      }
    } catch (e) {
      _lastError = 'Sync failed: $e';
    } finally {
      _isSyncing = false;
      _isCancelling = false;
      _syncProgress = null;
      notifyListeners();
    }
  }
}
