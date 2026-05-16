class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    required this.songCount,
    required this.durationSeconds,
    this.coverArtId,
    this.coverArtUri,
    this.year,
  });

  final String id;
  final String name;
  final String artist;
  final int songCount;
  final int durationSeconds;
  final String? coverArtId;
  final Uri? coverArtUri;
  final int? year;

  factory Album.fromSubsonic(Map<String, dynamic> json) {
    return Album(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown album',
      artist: json['artist']?.toString() ?? 'Unknown artist',
      songCount: _asInt(json['songCount']),
      durationSeconds: _asInt(json['duration']),
      coverArtId: _optionalString(json['coverArt']),
      year: json['year'] == null ? null : _asInt(json['year']),
    );
  }

  Album copyWith({Uri? coverArtUri}) {
    return Album(
      id: id,
      name: name,
      artist: artist,
      songCount: songCount,
      durationSeconds: durationSeconds,
      coverArtId: coverArtId,
      coverArtUri: coverArtUri ?? this.coverArtUri,
      year: year,
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
