import '../library/track.dart';

class LikedTrack {
  const LikedTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.trackNumber,
    required this.durationSeconds,
    required this.likedAt,
    required this.position,
    this.albumId,
    this.albumName,
    this.coverArtId,
    this.coverArtUri,
    this.suffix,
  });

  final String trackId;
  final String title;
  final String artist;
  final int trackNumber;
  final int durationSeconds;
  final DateTime likedAt;
  final int position;
  final String? albumId;
  final String? albumName;
  final String? coverArtId;
  final String? coverArtUri;
  final String? suffix;

  Track toTrack() {
    return Track(
      id: trackId,
      title: title,
      artist: artist,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      albumId: albumId,
      albumName: albumName,
      coverArtId: coverArtId,
      coverArtUri: coverArtUri == null ? null : Uri.tryParse(coverArtUri!),
      suffix: suffix,
    );
  }

  factory LikedTrack.fromTrack(
    Track track, {
    DateTime? likedAt,
    int position = 0,
  }) {
    return LikedTrack(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      trackNumber: track.trackNumber,
      durationSeconds: track.durationSeconds,
      likedAt: likedAt ?? DateTime.now(),
      position: position,
      albumId: track.albumId,
      albumName: track.albumName,
      coverArtId: track.coverArtId,
      coverArtUri: track.coverArtUri?.toString(),
      suffix: track.suffix,
    );
  }
}
