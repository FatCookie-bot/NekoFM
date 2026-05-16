import 'album.dart';
import 'track.dart';

class AlbumDetail {
  const AlbumDetail({required this.album, required this.tracks});

  final Album album;
  final List<Track> tracks;

  factory AlbumDetail.fromSubsonic(Map<String, dynamic> json) {
    final songs = json['song'];
    return AlbumDetail(
      album: Album.fromSubsonic(json),
      tracks: [
        if (songs is List)
          for (final song in songs)
            if (song is Map<String, dynamic>) Track.fromSubsonic(song),
      ],
    );
  }
}
