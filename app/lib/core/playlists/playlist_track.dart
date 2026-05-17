import '../library/track.dart';

class PlaylistTrack {
  const PlaylistTrack({
    required this.entryId,
    required this.playlistId,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.trackNumber,
    required this.durationSeconds,
    required this.position,
    required this.addedAt,
    this.albumId,
    this.albumName,
    this.coverArtId,
    this.coverArtUri,
    this.suffix,
  });

  final String entryId;
  final String playlistId;
  final String trackId;
  final String title;
  final String artist;
  final int trackNumber;
  final int durationSeconds;
  final int position;
  final DateTime addedAt;
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

  factory PlaylistTrack.fromTrack({
    required String playlistId,
    required Track track,
    required int position,
    DateTime? addedAt,
  }) {
    return PlaylistTrack(
      entryId: 'entry-${DateTime.now().microsecondsSinceEpoch}-$position',
      playlistId: playlistId,
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      trackNumber: track.trackNumber,
      durationSeconds: track.durationSeconds,
      position: position,
      addedAt: addedAt ?? DateTime.now(),
      albumId: track.albumId,
      albumName: track.albumName,
      coverArtId: track.coverArtId,
      coverArtUri: track.coverArtUri?.toString(),
      suffix: track.suffix,
    );
  }
}
