// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Playlist _$PlaylistFromJson(Map<String, dynamic> json) => Playlist(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  path: json['path'] as String,
  parentId: json['parent_id'] as String,
  type: json['type'] as String,
  smartPlaylist: json['smart_playlist'] as bool,
  random: json['random'] as bool,
  folder: json['folder'] as bool,
  itemCount: (json['item_count'] as num).toInt(),
  streamCount: (json['stream_count'] as num).toInt(),
  uri: json['uri'] as String,
);

Map<String, dynamic> _$PlaylistToJson(Playlist instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'path': instance.path,
  'parent_id': instance.parentId,
  'type': instance.type,
  'smart_playlist': instance.smartPlaylist,
  'random': instance.random,
  'folder': instance.folder,
  'item_count': instance.itemCount,
  'stream_count': instance.streamCount,
  'uri': instance.uri,
};

PlaylistsResponse _$PlaylistsResponseFromJson(Map<String, dynamic> json) =>
    PlaylistsResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
      offset: (json['offset'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
    );

Map<String, dynamic> _$PlaylistsResponseToJson(PlaylistsResponse instance) =>
    <String, dynamic>{
      'items': instance.items,
      'total': instance.total,
      'offset': instance.offset,
      'limit': instance.limit,
    };
