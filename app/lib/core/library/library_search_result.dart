import 'album.dart';
import 'track.dart';

class LibrarySearchResult {
  const LibrarySearchResult({required this.albums, required this.tracks});

  final List<Album> albums;
  final List<Track> tracks;

  bool get isEmpty => albums.isEmpty && tracks.isEmpty;

  factory LibrarySearchResult.fromSubsonic(Map<String, dynamic> json) {
    return LibrarySearchResult(
      albums: [
        for (final album in _asList(json['album']))
          if (album is Map<String, dynamic>) Album.fromSubsonic(album),
      ],
      tracks: [
        for (final song in _asList(json['song']))
          if (song is Map<String, dynamic>) Track.fromSubsonic(song),
      ],
    );
  }

  static List<Object?> _asList(Object? value) {
    if (value is List) {
      return value;
    }

    return const [];
  }
}
