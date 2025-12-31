// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Track _$TrackFromJson(Map<String, dynamic> json) => Track(
  id: (json['id'] as num).toInt(),
  title: json['title'] as String,
  titleSort: json['title_sort'] as String,
  artist: json['artist'] as String,
  artistSort: json['artist_sort'] as String,
  album: json['album'] as String,
  albumSort: json['album_sort'] as String,
  albumId: json['album_id'] as String,
  albumArtist: json['album_artist'] as String,
  albumArtistSort: json['album_artist_sort'] as String,
  albumArtistId: json['album_artist_id'] as String,
  genre: json['genre'] as String,
  year: (json['year'] as num).toInt(),
  trackNumber: (json['track_number'] as num).toInt(),
  discNumber: (json['disc_number'] as num).toInt(),
  lengthMs: (json['length_ms'] as num).toInt(),
  rating: (json['rating'] as num).toInt(),
  playCount: (json['play_count'] as num).toInt(),
  skipCount: (json['skip_count'] as num).toInt(),
  timePlayed: json['time_played'] as String?,
  timeSkipped: json['time_skipped'] as String?,
  timeAdded: json['time_added'] as String,
  dateReleased: json['date_released'] as String?,
  seekMs: (json['seek_ms'] as num).toInt(),
  type: json['type'] as String,
  samplerate: (json['samplerate'] as num).toInt(),
  bitrate: (json['bitrate'] as num).toInt(),
  channels: (json['channels'] as num).toInt(),
  usermark: (json['usermark'] as num).toInt(),
  mediaKind: json['media_kind'] as String,
  dataKind: json['data_kind'] as String,
  path: json['path'] as String,
  uri: json['uri'] as String,
  artworkUrl: json['artwork_url'] as String,
);

Map<String, dynamic> _$TrackToJson(Track instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'title_sort': instance.titleSort,
  'artist': instance.artist,
  'artist_sort': instance.artistSort,
  'album': instance.album,
  'album_sort': instance.albumSort,
  'album_id': instance.albumId,
  'album_artist': instance.albumArtist,
  'album_artist_sort': instance.albumArtistSort,
  'album_artist_id': instance.albumArtistId,
  'genre': instance.genre,
  'year': instance.year,
  'track_number': instance.trackNumber,
  'disc_number': instance.discNumber,
  'length_ms': instance.lengthMs,
  'rating': instance.rating,
  'play_count': instance.playCount,
  'skip_count': instance.skipCount,
  'time_played': instance.timePlayed,
  'time_skipped': instance.timeSkipped,
  'time_added': instance.timeAdded,
  'date_released': instance.dateReleased,
  'seek_ms': instance.seekMs,
  'type': instance.type,
  'samplerate': instance.samplerate,
  'bitrate': instance.bitrate,
  'channels': instance.channels,
  'usermark': instance.usermark,
  'media_kind': instance.mediaKind,
  'data_kind': instance.dataKind,
  'path': instance.path,
  'uri': instance.uri,
  'artwork_url': instance.artworkUrl,
};

TracksResponse _$TracksResponseFromJson(Map<String, dynamic> json) =>
    TracksResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
      offset: (json['offset'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
    );

Map<String, dynamic> _$TracksResponseToJson(TracksResponse instance) =>
    <String, dynamic>{
      'items': instance.items,
      'total': instance.total,
      'offset': instance.offset,
      'limit': instance.limit,
    };
