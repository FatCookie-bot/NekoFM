class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.trackNumber,
    required this.durationSeconds,
    this.albumId,
    this.albumName,
    this.coverArtId,
    this.coverArtUri,
    this.suffix,
  });

  final String id;
  final String title;
  final String artist;
  final int trackNumber;
  final int durationSeconds;
  final String? albumId;
  final String? albumName;
  final String? coverArtId;
  final Uri? coverArtUri;
  final String? suffix;

  factory Track.fromSubsonic(Map<String, dynamic> json) {
    return Track(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown track',
      artist: json['artist']?.toString() ?? 'Unknown artist',
      trackNumber: _asInt(json['track']),
      durationSeconds: _asInt(json['duration']),
      albumId: _optionalString(json['albumId']),
      albumName: _optionalString(json['album']),
      coverArtId: _optionalString(json['coverArt']),
      suffix: json['suffix']?.toString(),
    );
  }

  Track copyWith({Uri? coverArtUri}) {
    return Track(
      id: id,
      title: title,
      artist: artist,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      albumId: albumId,
      albumName: albumName,
      coverArtId: coverArtId,
      coverArtUri: coverArtUri ?? this.coverArtUri,
      suffix: suffix,
    );
  }

  static int _asInt(Object? value) {
    return switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value) ?? 0,
      _ => 0,
    };
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }
}
