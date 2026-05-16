import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/album.dart';
import '../library/album_detail.dart';
import '../library/library_search_result.dart';
import '../library/track.dart';
import 'download_database.dart';
import 'download_preferences.dart';
import 'downloaded_track.dart';

class DownloadRepository {
  DownloadRepository({
    SharedPreferencesAsync? preferences,
    DownloadPreferences? downloadPreferences,
    DownloadDatabase? database,
  }) : _preferences = preferences,
       _database = database ?? DownloadDatabase(),
       _downloadPreferences =
           downloadPreferences ?? DownloadPreferences(preferences: preferences);

  static const _tracksKey = 'downloads.tracks.v1';
  static const _sqliteMigrationKey = 'downloads.sqlite_migrated.v1';

  final SharedPreferencesAsync? _preferences;
  final DownloadDatabase _database;
  final DownloadPreferences _downloadPreferences;
  bool _hasCheckedLegacyMigration = false;

  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  Future<List<DownloadedTrack>> loadTracks() async {
    await _migrateLegacyTracksIfNeeded();
    return _database.loadTracks();
  }

  Future<List<DownloadedTrack>> _loadLegacyPreferenceTracks() async {
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

  Future<DownloadRepairResult> repairDownloads() async {
    final tracks = await loadTracks();
    final repairedTracks = <DownloadedTrack>[];
    var removedAudioCount = 0;
    var clearedCoverCount = 0;

    for (final track in tracks) {
      if (track.state != DownloadState.complete) {
        repairedTracks.add(track);
        continue;
      }

      if (!await _isUsableFile(track.localPath, expectedBytes: track.bytes)) {
        removedAudioCount += 1;
        await deleteDownloadedTrackFiles(track);
        continue;
      }

      final coverPath = track.localCoverPath;
      if (coverPath != null && !await _isUsableFile(coverPath)) {
        repairedTracks.add(track.copyWith(clearLocalCoverPath: true));
        clearedCoverCount += 1;
        continue;
      }

      repairedTracks.add(track);
    }

    if (removedAudioCount > 0 || clearedCoverCount > 0) {
      await saveTracks(repairedTracks);
    }

    return DownloadRepairResult(
      tracks: repairedTracks,
      removedAudioCount: removedAudioCount,
      clearedCoverCount: clearedCoverCount,
    );
  }

  Future<void> saveTracks(List<DownloadedTrack> tracks) async {
    await _migrateLegacyTracksIfNeeded();
    final sorted = [...tracks]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    await _database.replaceTracks(sorted);
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
    await _migrateLegacyTracksIfNeeded();
    return _database.trackById(trackId);
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

  Future<bool> _isUsableFile(String path, {int? expectedBytes}) async {
    if (path.isEmpty) {
      return false;
    }

    final file = File(path);
    if (!await file.exists()) {
      return false;
    }

    final size = await file.length();
    if (size <= 0) {
      return false;
    }

    if (expectedBytes != null && expectedBytes != size) {
      return false;
    }

    return true;
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
    final artistFolderName = _safeFilename(track.artist);
    final albumFolderName = _safeFilename(albumName);
    final directory = Directory(
      '${root.path}/$artistFolderName/$albumFolderName',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<void> _migrateLegacyTracksIfNeeded() async {
    if (_hasCheckedLegacyMigration) {
      return;
    }

    final alreadyMigrated = await _store.getBool(_sqliteMigrationKey) ?? false;
    if (alreadyMigrated) {
      _hasCheckedLegacyMigration = true;
      return;
    }

    final legacyTracks = await _loadLegacyPreferenceTracks();
    if (legacyTracks.isNotEmpty && await _database.isEmpty()) {
      final sorted = [...legacyTracks]
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      await _database.replaceTracks(sorted);
      await _writeFolderManifests(sorted);
    }

    await _store.setBool(_sqliteMigrationKey, true);
    _hasCheckedLegacyMigration = true;
  }

  Future<List<AlbumDetail>> loadDownloadedAlbumDetails() async {
    final tracks = <DownloadedTrack>[];
    for (final track in (await repairDownloads()).tracks) {
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

  Future<LibrarySearchResult> searchDownloaded(String query) async {
    final lowerQuery = query.toLowerCase().trim();
    final normalizedQuery = _normalizeSearchText(query);
    if (lowerQuery.length < 2) {
      return const LibrarySearchResult(albums: [], tracks: []);
    }

    final details = await loadDownloadedAlbumDetails();
    final albums = <Album>[];
    final tracks = <Track>[];

    for (final detail in details) {
      final album = detail.album;
      final albumMatches = _matchesSearch(
        lowerQuery,
        normalizedQuery,
        album.name,
        album.artist,
      );
      if (albumMatches) {
        albums.add(album);
      }

      for (final track in detail.tracks) {
        if (_matchesSearch(
          lowerQuery,
          normalizedQuery,
          track.title,
          track.artist,
          track.albumName ?? album.name,
        )) {
          tracks.add(track);
        }
      }
    }

    return LibrarySearchResult(albums: albums, tracks: tracks);
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
  }) => '${_safeFilename(artist)}/${_safeFilename(albumName)}';

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

  static bool _matchesSearch(
    String lowerQuery,
    String normalizedQuery,
    String first, [
    String? second,
    String? third,
  ]) {
    final normalizedMatches =
        normalizedQuery.isNotEmpty &&
        (_normalizeSearchText(first).contains(normalizedQuery) ||
            _normalizeSearchText(second ?? '').contains(normalizedQuery) ||
            _normalizeSearchText(third ?? '').contains(normalizedQuery));
    return first.toLowerCase().contains(lowerQuery) ||
        (second ?? '').toLowerCase().contains(lowerQuery) ||
        (third ?? '').toLowerCase().contains(lowerQuery) ||
        normalizedMatches;
  }

  static String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_.,:;()[\]{}]+'), ' ')
        .trim();
  }
}

class DownloadRepairResult {
  const DownloadRepairResult({
    required this.tracks,
    required this.removedAudioCount,
    required this.clearedCoverCount,
  });

  final List<DownloadedTrack> tracks;
  final int removedAudioCount;
  final int clearedCoverCount;

  bool get changed => removedAudioCount > 0 || clearedCoverCount > 0;
}
