import 'package:json_annotation/json_annotation.dart';

part 'playlist.g.dart';

@JsonSerializable()
class Playlist {
  final int id;
  final String name;
  final String path;

  @JsonKey(name: 'parent_id')
  final String parentId;

  final String type;

  @JsonKey(name: 'smart_playlist')
  final bool smartPlaylist;

  final bool random;
  final bool folder;

  @JsonKey(name: 'item_count')
  final int itemCount;

  @JsonKey(name: 'stream_count')
  final int streamCount;

  final String uri;

  Playlist({
    required this.id,
    required this.name,
    required this.path,
    required this.parentId,
    required this.type,
    required this.smartPlaylist,
    required this.random,
    required this.folder,
    required this.itemCount,
    required this.streamCount,
    required this.uri,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) =>
      _$PlaylistFromJson(json);
  Map<String, dynamic> toJson() => _$PlaylistToJson(this);
}

@JsonSerializable()
class PlaylistsResponse {
  final List<Playlist> items;
  final int total;
  final int offset;
  final int limit;

  PlaylistsResponse({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory PlaylistsResponse.fromJson(Map<String, dynamic> json) =>
      _$PlaylistsResponseFromJson(json);
  Map<String, dynamic> toJson() => _$PlaylistsResponseToJson(this);
}
