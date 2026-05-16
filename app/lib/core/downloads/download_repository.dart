import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/album.dart';
import '../library/album_detail.dart';
import '../library/track.dart';
import 'download_preferences.dart';
import 'downloaded_track.dart';

class DownloadRepository {
  DownloadRepository({
    SharedPreferencesAsync? preferences,
    DownloadPreferences? downloadPreferences,
  }) : _preferences = preferences,
       _downloadPreferences =
           downloadPreferences ?? DownloadPreferences(preferences: preferences);

  static const _tracksKey = 'downloads.tracks.v1';

  final SharedPreferencesAsync? _preferences;
  final DownloadPreferences _downloadPreferences;

  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  Future<List<DownloadedTrack>> loadTracks() async {
    final raw = await _store.getString(_tracksKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) DownloadedTrack.fromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveTracks(List<DownloadedTrack> tracks) async {
    final sorted = [...tracks]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    await _store.setString(
      _tracksKey,
      jsonEncode([for (final track in sorted) track.toJson()]),
    );
    await _writeFolderManifests(sorted);
  }

  Future<void> deleteDownloadedTrackFiles(
    DownloadedTrack track, {
    bool deleteCover = true,
  }) async {
    await _deleteFileIfPresent(track.localPath);
    await _deleteFileIfPresent('${track.localPath}.partial');
    final coverPath = track.localCoverPath;
    if (deleteCover && coverPath != null) {
      await _deleteFileIfPresent(coverPath);
      await _deleteFileIfPresent('$coverPath.partial');
    }
  }

  Future<DownloadedTrack?> trackById(String trackId) async {
    for (final track in await loadTracks()) {
      if (track.trackId == trackId) {
        return track;
      }
    }

    return null;
  }

  Future<String?> localFileForTrack(String trackId) async {
    final downloaded = await trackById(trackId);
    if (downloaded == null || downloaded.state != DownloadState.complete) {
      return null;
    }

    final file = File(downloaded.localPath);
    if (!await file.exists()) {
      return null;
    }

    final size = await file.length();
    if (size <= 0) {
      return null;
    }

    if (downloaded.bytes != null && downloaded.bytes != size) {
      return null;
    }

    return file.path;
  }

  Future<Directory> downloadsDirectory() async {
    final directory = await _downloadPreferences.activeDownloadFolder();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<String> localPathForTrack(Track track) async {
    final directory = await albumDirectoryForTrack(track);
    final extension = _cleanExtension(track.suffix);
    final title = _safeFilename(track.title);
    final number = track.trackNumber > 0
        ? '${track.trackNumber.toString().padLeft(2, '0')} - '
        : '';
    final filename = extension == null
        ? '$number$title - ${track.id}'
        : '$number$title - ${track.id}.$extension';
    return '${directory.path}/${_safeFilename(filename)}';
  }

  Future<String> localCoverPathForTrack(Track track) async {
    final directory = await albumDirectoryForTrack(track);
    return '${directory.path}/cover.jpg';
  }

  Future<Directory> albumDirectoryForTrack(Track track) async {
    final root = await downloadsDirectory();
    final albumName = track.albumName ?? 'Unknown Album';
    final folderName = _safeFilename('${track.artist} - $albumName');
    final directory = Directory('${root.path}/$folderName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<List<AlbumDetail>> loadDownloadedAlbumDetails() async {
    final tracks = <DownloadedTrack>[];
    for (final track in await loadTracks()) {
      if (track.state != DownloadState.complete) {
        continue;
      }

      final localFile = await localFileForTrack(track.trackId);
      if (localFile != null) {
        tracks.add(track);
      }
    }

    final grouped = <String, List<DownloadedTrack>>{};
    for (final track in tracks) {
      final key = track.albumId ?? track.albumName ?? 'downloads';
      grouped.putIfAbsent(key, () => []).add(track);
    }

    final details = <AlbumDetail>[];
    for (final entry in grouped.entries) {
      final albumTracks = [...entry.value]
        ..sort((left, right) {
          final numberCompare = left.trackNumber.compareTo(right.trackNumber);
          if (numberCompare != 0) {
            return numberCompare;
          }

          return left.title.compareTo(right.title);
        });
      final first = albumTracks.first;
      final durationSeconds = albumTracks.fold(
        0,
        (total, track) => total + track.durationSeconds,
      );
      details.add(
        AlbumDetail(
          album: Album(
            id: first.albumId ?? entry.key,
            name: first.albumName ?? 'Downloads',
            artist: first.artist,
            songCount: albumTracks.length,
            durationSeconds: durationSeconds,
            coverArtUri: _localCoverUri(first),
          ),
          tracks: [for (final track in albumTracks) track.toTrack()],
        ),
      );
    }

    details.sort((left, right) => left.album.name.compareTo(right.album.name));
    return details;
  }

  Future<void> _writeFolderManifests(List<DownloadedTrack> tracks) async {
    final grouped = <String, List<DownloadedTrack>>{};
    for (final track in tracks) {
      if (track.localPath.isEmpty) {
        continue;
      }

      final parentPath = File(track.localPath).parent.path;
      grouped.putIfAbsent(parentPath, () => []).add(track);
    }

    for (final entry in grouped.entries) {
      final directory = Directory(entry.key);
      if (!await directory.exists()) {
        continue;
      }

      final manifest = File('${directory.path}/nekofm_downloads_manifest.json');
      const encoder = JsonEncoder.withIndent('  ');
      await manifest.writeAsString(
        encoder.convert([for (final track in entry.value) track.toJson()]),
      );
    }
  }

  Future<void> _deleteFileIfPresent(String path) async {
    if (path.isEmpty) {
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Uri? _localCoverUri(DownloadedTrack track) {
    final path = track.localCoverPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return null;
    }

    return Uri.file(path);
  }

  @visibleForTesting
  static String safeFilenameForTest(String value) => _safeFilename(value);

  @visibleForTesting
  static String albumFolderNameForTest({
    required String artist,
    required String albumName,
  }) => _safeFilename('$artist - $albumName');

  static String _safeFilename(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'_+'), '_');
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
      return 'track';
    }

    return trimmed;
  }

  static String? _cleanExtension(String? value) {
    final extension = value?.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    if (extension == null || extension.isEmpty) {
      return null;
    }

    return extension;
  }
}
