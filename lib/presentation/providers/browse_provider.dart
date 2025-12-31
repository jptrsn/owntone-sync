import 'package:flutter/foundation.dart';
import '../../data/repositories/local_database_repository.dart';

enum BrowseCategory { playlists, artists, albums, tracks }

enum SortOrder { nameAsc, nameDesc, yearDesc, dateAddedDesc }

class BrowseProvider extends ChangeNotifier {
  final LocalDatabaseRepository _dbRepo = LocalDatabaseRepository();

  BrowseCategory _currentCategory = BrowseCategory.playlists;
  SortOrder _sortOrder = SortOrder.nameAsc;
  bool _isLoading = false;
  String? _error;

  // Data
  List<Map<String, dynamic>> _playlists = [];
  List<String> _artists = [];
  List<Map<String, dynamic>> _albums = [];
  List<SyncedTrack> _tracks = [];

  // Getters
  BrowseCategory get currentCategory => _currentCategory;
  SortOrder get sortOrder => _sortOrder;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Map<String, dynamic>> get playlists => _playlists;
  List<String> get artists => _artists;
  List<Map<String, dynamic>> get albums => _albums;
  List<SyncedTrack> get tracks => _tracks;

  bool get hasContent =>
      _playlists.isNotEmpty ||
      _artists.isNotEmpty ||
      _albums.isNotEmpty ||
      _tracks.isNotEmpty;

  /// Load data for current category
  Future<void> loadData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      switch (_currentCategory) {
        case BrowseCategory.playlists:
          _playlists = await _dbRepo.getAllPlaylistsWithCounts();
          break;
        case BrowseCategory.artists:
          _artists = await _dbRepo.getAllArtists(
            sortBy: _sortOrder == SortOrder.nameAsc ? 'artist' : 'artist DESC',
          );
          break;
        case BrowseCategory.albums:
          String sortBy = 'album';
          if (_sortOrder == SortOrder.yearDesc) sortBy = 'year';
          _albums = await _dbRepo.getAllAlbums(sortBy: sortBy);
          break;
        case BrowseCategory.tracks:
          String sortBy = 'title';
          switch (_sortOrder) {
            case SortOrder.nameAsc:
              sortBy = 'title';
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
    } catch (e) {
      _error = 'Failed to load data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Change category
  void setCategory(BrowseCategory category) {
    if (_currentCategory != category) {
      _currentCategory = category;
      loadData();
    }
  }

  /// Change sort order
  void setSortOrder(SortOrder order) {
    if (_sortOrder != order) {
      _sortOrder = order;
      loadData();
    }
  }

  /// Refresh current data
  Future<void> refresh() async {
    await loadData();
  }
}
