import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/local_database_repository.dart';

enum BrowseCategory { playlists, artists, albums, tracks }

enum SortOrder { nameAsc, nameDesc, artistAsc, albumAsc, yearDesc, dateAddedDesc }

/// Sort options offered per category. The list is what the UI shows; any
/// persisted value not in the list falls back to [nameAsc].
const Map<BrowseCategory, List<SortOrder>> kSortOptionsByCategory = {
  BrowseCategory.playlists: [SortOrder.nameAsc, SortOrder.nameDesc],
  BrowseCategory.artists: [SortOrder.nameAsc, SortOrder.nameDesc],
  BrowseCategory.albums: [SortOrder.nameAsc, SortOrder.yearDesc],
  BrowseCategory.tracks: [
    SortOrder.nameAsc,
    SortOrder.artistAsc,
    SortOrder.albumAsc,
    SortOrder.yearDesc,
    SortOrder.dateAddedDesc,
  ],
};

const Map<SortOrder, String> kSortOrderLabels = {
  SortOrder.nameAsc: 'Name (A\u2013Z)',
  SortOrder.nameDesc: 'Name (Z\u2013A)',
  SortOrder.artistAsc: 'Artist',
  SortOrder.albumAsc: 'Album',
  SortOrder.yearDesc: 'Year (newest first)',
  SortOrder.dateAddedDesc: 'Date added (newest first)',
};

class BrowseProvider extends ChangeNotifier {
  final LocalDatabaseRepository _dbRepo = LocalDatabaseRepository();

  static const Map<BrowseCategory, String> _sortPrefKeys = {
    BrowseCategory.playlists: 'browse_sort_playlists',
    BrowseCategory.artists: 'browse_sort_artists',
    BrowseCategory.albums: 'browse_sort_albums',
    BrowseCategory.tracks: 'browse_sort_tracks',
  };

  final Map<BrowseCategory, SortOrder> _sortOrders = {
    for (final category in BrowseCategory.values) category: SortOrder.nameAsc,
  };
  Future<void>? _sortLoad;

  BrowseCategory _currentCategory = BrowseCategory.playlists;
  bool _isLoading = false;
  String? _error;

  // Data
  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _albums = [];
  List<SyncedTrack> _tracks = [];

  // Getters
  BrowseCategory get currentCategory => _currentCategory;
  SortOrder get sortOrder => _sortOrders[_currentCategory]!;
  List<SortOrder> get sortOptions => kSortOptionsByCategory[_currentCategory]!;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get playlists => _playlists;
  List<Map<String, dynamic>> get artists => _artists;
  List<Map<String, dynamic>> get albums => _albums;
  List<SyncedTrack> get tracks => _tracks;

  bool get hasContent =>
      _playlists.isNotEmpty ||
      _artists.isNotEmpty ||
      _albums.isNotEmpty ||
      _tracks.isNotEmpty;

  /// Loads the persisted per-category sort orders once.
  Future<void> _ensureSortLoaded() {
    _sortLoad ??= _loadSortOrders();
    return _sortLoad!;
  }

  Future<void> _loadSortOrders() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _sortPrefKeys.entries) {
      final raw = prefs.getString(entry.value);
      if (raw == null) continue;
      final order = SortOrder.values.firstWhere(
        (o) => o.name == raw,
        orElse: () => SortOrder.nameAsc,
      );
      final options = kSortOptionsByCategory[entry.key]!;
      if (options.contains(order)) {
        _sortOrders[entry.key] = order;
      }
    }
  }

  Future<void> _persistSort(BrowseCategory category, SortOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefKeys[category]!, order.name);
  }

  /// Load data for current category
  Future<void> loadData() async {
    await _ensureSortLoaded();
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _loadCategory(_currentCategory);
    } catch (e) {
      _error = 'Failed to load data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reloads every category, not just the current one.
  ///
  /// Used after the stored library changes underneath the UI (a server
  /// change wiped it): a current-category-only reload would leave the other
  /// tabs holding stale rows, and [hasContent] would keep the tabbed body up
  /// on lists that no longer exist in the database.
  Future<void> reloadAll() async {
    await _ensureSortLoaded();
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      for (final category in BrowseCategory.values) {
        await _loadCategory(category);
      }
    } catch (e) {
      _error = 'Failed to load data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCategory(BrowseCategory category) async {
    final order = _sortOrders[category]!;
    switch (category) {
      case BrowseCategory.playlists:
        _playlists = await _dbRepo.getAllPlaylistsWithCounts(
          nameDesc: order == SortOrder.nameDesc,
        );
        break;
      case BrowseCategory.artists:
        _artists = await _dbRepo.getAllArtists(
          sortBy: order == SortOrder.nameAsc ? 'artist' : 'artist DESC',
        );
        break;
      case BrowseCategory.albums:
        String sortBy = 'album';
        if (order == SortOrder.yearDesc) sortBy = 'year';
        _albums = await _dbRepo.getAllAlbums(sortBy: sortBy);
        break;
      case BrowseCategory.tracks:
        String sortBy = 'title';
        switch (order) {
          case SortOrder.nameAsc:
            sortBy = 'title';
            break;
          case SortOrder.artistAsc:
            sortBy = 'artist';
            break;
          case SortOrder.albumAsc:
            sortBy = 'album';
            break;
          case SortOrder.yearDesc:
            sortBy = 'year';
            break;
          case SortOrder.dateAddedDesc:
            sortBy = 'dateAdded';
            break;
          default:
            sortBy = 'title';
        }
        _tracks = await _dbRepo.getAllTracks(sortBy: sortBy);
        break;
    }
  }

  /// Change category
  void setCategory(BrowseCategory category) {
    if (_currentCategory != category) {
      _currentCategory = category;
      loadData();
    }
  }

  /// Change the sort order of the CURRENT category and persist it.
  Future<void> setSortOrder(SortOrder order) async {
    if (_sortOrders[_currentCategory] == order) return;
    _sortOrders[_currentCategory] = order;
    await _persistSort(_currentCategory, order);
    await loadData();
  }

  /// Refresh current data
  Future<void> refresh() async {
    await loadData();
  }
}
