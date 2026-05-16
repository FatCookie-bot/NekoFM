import '../library/album.dart';
import '../library/track.dart';

enum DownloadState {
  queued,
  downloading,
  complete,
  failed;

  static DownloadState fromName(String? name) {
    return DownloadState.values.firstWhere(
      (state) => state.name == name,
      orElse: () => DownloadState.failed,
    );
  }
}

class DownloadedTrack {
  const DownloadedTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.trackNumber,
    required this.durationSeconds,
    required this.localPath,
    required this.state,
    required this.updatedAt,
    this.albumId,
    this.albumName,
    this.coverArtUri,
    this.localCoverPath,
    this.suffix,
    this.bytes,
    this.receivedBytes,
    this.totalBytes,
    this.errorMessage,
  });

  final String trackId;
  final String title;
  final String artist;
  final int trackNumber;
  final int durationSeconds;
  final String localPath;
  final DownloadState state;
  final DateTime updatedAt;
  final String? albumId;
  final String? albumName;
  final String? coverArtUri;
  final String? localCoverPath;
  final String? suffix;
  final int? bytes;
  final int? receivedBytes;
  final int? totalBytes;
  final String? errorMessage;

  Track toTrack() {
    return Track(
      id: trackId,
      title: title,
      artist: artist,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      albumId: albumId,
      albumName: albumName,
      coverArtUri: _coverUri(),
      suffix: suffix,
    );
  }

  Album toAlbum() {
    return Album(
      id: albumId ?? 'downloads',
      name: albumName ?? 'Downloads',
      artist: artist,
      songCount: 1,
      durationSeconds: durationSeconds,
      coverArtUri: _coverUri(),
    );
  }

  Uri? _coverUri() {
    final localPath = localCoverPath;
    if (localPath != null && localPath.isNotEmpty) {
      return Uri.file(localPath);
    }

    return coverArtUri == null ? null : Uri.tryParse(coverArtUri!);
  }

  double? get progress {
    final received = receivedBytes;
    final total = totalBytes;
    if (received == null || total == null || total <= 0) {
      return null;
    }

    return (received / total).clamp(0, 1).toDouble();
  }

  factory DownloadedTrack.fromTrack({
    required Track track,
    required String localPath,
    required DownloadState state,
    DateTime? updatedAt,
  }) {
    return DownloadedTrack(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      trackNumber: track.trackNumber,
      durationSeconds: track.durationSeconds,
      localPath: localPath,
      state: state,
      updatedAt: updatedAt ?? DateTime.now(),
      albumId: track.albumId,
      albumName: track.albumName,
      coverArtUri: track.coverArtUri?.toString(),
      suffix: track.suffix,
    );
  }

  factory DownloadedTrack.fromJson(Map<String, dynamic> json) {
    return DownloadedTrack(
      trackId: json['trackId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown track',
      artist: json['artist']?.toString() ?? 'Unknown artist',
      trackNumber: _asInt(json['trackNumber']),
      durationSeconds: _asInt(json['durationSeconds']),
      localPath: json['localPath']?.toString() ?? '',
      state: DownloadState.fromName(json['state']?.toString()),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      albumId: _optionalString(json['albumId']),
      albumName: _optionalString(json['albumName']),
      coverArtUri: _optionalString(json['coverArtUri']),
      localCoverPath: _optionalString(json['localCoverPath']),
      suffix: _optionalString(json['suffix']),
      bytes: _optionalInt(json['bytes']),
      receivedBytes: _optionalInt(json['receivedBytes']),
      totalBytes: _optionalInt(json['totalBytes']),
      errorMessage: _optionalString(json['errorMessage']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'trackNumber': trackNumber,
      'durationSeconds': durationSeconds,
      'localPath': localPath,
      'state': state.name,
      'updatedAt': updatedAt.toIso8601String(),
      if (albumId != null) 'albumId': albumId,
      if (albumName != null) 'albumName': albumName,
      if (coverArtUri != null) 'coverArtUri': coverArtUri,
      if (localCoverPath != null) 'localCoverPath': localCoverPath,
      if (suffix != null) 'suffix': suffix,
      if (bytes != null) 'bytes': bytes,
      if (receivedBytes != null) 'receivedBytes': receivedBytes,
      if (totalBytes != null) 'totalBytes': totalBytes,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  DownloadedTrack copyWith({
    String? localPath,
    DownloadState? state,
    DateTime? updatedAt,
    int? bytes,
    int? receivedBytes,
    int? totalBytes,
    String? localCoverPath,
    bool clearLocalCoverPath = false,
    String? errorMessage,
  }) {
    return DownloadedTrack(
      trackId: trackId,
      title: title,
      artist: artist,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      localPath: localPath ?? this.localPath,
      state: state ?? this.state,
      updatedAt: updatedAt ?? this.updatedAt,
      albumId: albumId,
      albumName: albumName,
      coverArtUri: coverArtUri,
      localCoverPath: clearLocalCoverPath
          ? null
          : localCoverPath ?? this.localCoverPath,
      suffix: suffix,
      bytes: bytes ?? this.bytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage,
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

  static int? _optionalInt(Object? value) {
    return switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value),
      _ => null,
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
