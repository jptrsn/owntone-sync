import 'package:json_annotation/json_annotation.dart';

part 'track.g.dart';

@JsonSerializable()
class Track {
  final int id;
  final String title;

  @JsonKey(name: 'title_sort')
  final String titleSort;

  final String artist;

  @JsonKey(name: 'artist_sort')
  final String artistSort;

  final String album;

  @JsonKey(name: 'album_sort')
  final String albumSort;

  @JsonKey(name: 'album_id')
  final String albumId;

  @JsonKey(name: 'album_artist')
  final String albumArtist;

  @JsonKey(name: 'album_artist_sort')
  final String albumArtistSort;

  @JsonKey(name: 'album_artist_id')
  final String albumArtistId;

  final String genre;
  final int year;

  @JsonKey(name: 'track_number')
  final int trackNumber;

  @JsonKey(name: 'disc_number')
  final int discNumber;

  @JsonKey(name: 'length_ms')
  final int lengthMs;

  final int rating;

  @JsonKey(name: 'play_count')
  final int playCount;

  @JsonKey(name: 'skip_count')
  final int skipCount;

  @JsonKey(name: 'time_played')
  final String? timePlayed;

  @JsonKey(name: 'time_skipped')
  final String? timeSkipped;

  @JsonKey(name: 'time_added')
  final String timeAdded;

  @JsonKey(name: 'date_released')
  final String? dateReleased;

  @JsonKey(name: 'seek_ms')
  final int seekMs;

  final String type;
  final int samplerate;
  final int bitrate;
  final int channels;
  final int usermark;

  @JsonKey(name: 'media_kind')
  final String mediaKind;

  @JsonKey(name: 'data_kind')
  final String dataKind;

  final String path;
  final String uri;

  @JsonKey(name: 'artwork_url')
  final String artworkUrl;

  Track({
    required this.id,
    required this.title,
    required this.titleSort,
    required this.artist,
    required this.artistSort,
    required this.album,
    required this.albumSort,
    required this.albumId,
    required this.albumArtist,
    required this.albumArtistSort,
    required this.albumArtistId,
    required this.genre,
    required this.year,
    required this.trackNumber,
    required this.discNumber,
    required this.lengthMs,
    required this.rating,
    required this.playCount,
    required this.skipCount,
    this.timePlayed,
    this.timeSkipped,
    required this.timeAdded,
    this.dateReleased,
    required this.seekMs,
    required this.type,
    required this.samplerate,
    required this.bitrate,
    required this.channels,
    required this.usermark,
    required this.mediaKind,
    required this.dataKind,
    required this.path,
    required this.uri,
    required this.artworkUrl,
  });

  factory Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);
  Map<String, dynamic> toJson() => _$TrackToJson(this);
}

@JsonSerializable()
class TracksResponse {
  final List<Track> items;
  final int total;
  final int offset;
  final int limit;

  TracksResponse({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory TracksResponse.fromJson(Map<String, dynamic> json) =>
      _$TracksResponseFromJson(json);
  Map<String, dynamic> toJson() => _$TracksResponseToJson(this);
}
