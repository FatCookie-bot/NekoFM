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
    var recoveredCoverCount = 0;

    for (final track in tracks) {
      if (track.state == DownloadState.downloading) {
        repairedTracks.add(
          track.copyWith(
            state: DownloadState.queued,
            updatedAt: DateTime.now(),
          ),
        );
        continue;
      }

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
        final recoveredCoverPath = await _recoverAlbumCoverPath(track);
        if (recoveredCoverPath == null) {
          repairedTracks.add(track.copyWith(clearLocalCoverPath: true));
          clearedCoverCount += 1;
        } else {
          repairedTracks.add(
            track.copyWith(localCoverPath: recoveredCoverPath),
          );
          recoveredCoverCount += 1;
        }
        continue;
      }

      if (coverPath == null) {
        final recoveredCoverPath = await _recoverAlbumCoverPath(track);
        if (recoveredCoverPath != null) {
          repairedTracks.add(
            track.copyWith(localCoverPath: recoveredCoverPath),
          );
          recoveredCoverCount += 1;
          continue;
        }
      }

      repairedTracks.add(track);
    }

    final recoveredQueueCount = repairedTracks.any(
      (track) =>
          track.state == DownloadState.queued &&
          tracks.any(
            (oldTrack) =>
                oldTrack.trackId == track.trackId &&
                oldTrack.state == DownloadState.downloading,
          ),
    );

    if (removedAudioCount > 0 ||
        clearedCoverCount > 0 ||
        recoveredCoverCount > 0 ||
        recoveredQueueCount) {
      await saveTracks(repairedTracks);
    }

    return DownloadRepairResult(
      tracks: repairedTracks,
      removedAudioCount: removedAudioCount,
      clearedCoverCount: clearedCoverCount,
      recoveredCoverCount: recoveredCoverCount,
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
    return _localPathForTrackInDirectory(track, directory);
  }

  String _localPathForTrackInDirectory(Track track, Directory directory) {
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
    return albumDirectoryForTrackInRoot(track, root);
  }

  Future<Directory> albumDirectoryForTrackInRoot(
    Track track,
    Directory root,
  ) async {
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

  Future<DownloadFolderMoveResult> moveDownloadsToFolder(
    Directory targetRoot,
  ) async {
    await _migrateLegacyTracksIfNeeded();
    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }

    final tracks = await _database.loadTracks();
    final movedTracks = <DownloadedTrack>[];
    final movedCoverPaths = <String, String>{};
    var movedAudioCount = 0;
    var movedCoverCount = 0;
    var skippedCount = 0;

    for (final track in tracks) {
      if (track.state == DownloadState.downloading) {
        skippedCount += 1;
        movedTracks.add(track);
        continue;
      }

      final destinationDirectory = await albumDirectoryForTrackInRoot(
        track.toTrack(),
        targetRoot,
      );
      final destinationAudioPath = _localPathForTrackInDirectory(
        track.toTrack(),
        destinationDirectory,
      );
      var nextTrack = track.copyWith(
        localPath: destinationAudioPath,
        updatedAt: DateTime.now(),
      );

      if (track.state == DownloadState.complete) {
        final didMoveAudio = await _copyVerifiedFile(
          sourcePath: track.localPath,
          destinationPath: destinationAudioPath,
          expectedBytes: track.bytes,
        );
        if (didMoveAudio) {
          movedAudioCount += 1;
          await _deleteFileIfDifferent(track.localPath, destinationAudioPath);
          await _deleteFileIfPresent('${track.localPath}.partial');
        } else {
          skippedCount += 1;
          movedTracks.add(track);
          continue;
        }
      } else {
        await _deleteFileIfPresent('${track.localPath}.partial');
      }

      final coverPath = track.localCoverPath;
      if (coverPath != null && coverPath.isNotEmpty) {
        final destinationCoverPath = '${destinationDirectory.path}/cover.jpg';
        final movedCoverPath = movedCoverPaths[coverPath];
        if (movedCoverPath != null) {
          nextTrack = nextTrack.copyWith(localCoverPath: movedCoverPath);
        } else {
          final didMoveCover = await _copyVerifiedFile(
            sourcePath: coverPath,
            destinationPath: destinationCoverPath,
          );
          if (didMoveCover) {
            movedCoverPaths[coverPath] = destinationCoverPath;
            movedCoverCount += 1;
            await _deleteFileIfDifferent(coverPath, destinationCoverPath);
            await _deleteFileIfPresent('$coverPath.partial');
            nextTrack = nextTrack.copyWith(
              localCoverPath: destinationCoverPath,
            );
          } else {
            nextTrack = nextTrack.copyWith(clearLocalCoverPath: true);
          }
        }
      }

      movedTracks.add(nextTrack);
    }

    await saveTracks(movedTracks);
    return DownloadFolderMoveResult(
      movedAudioCount: movedAudioCount,
      movedCoverCount: movedCoverCount,
      skippedCount: skippedCount,
      totalCount: tracks.length,
    );
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

  Future<bool> _copyVerifiedFile({
    required String sourcePath,
    required String destinationPath,
    int? expectedBytes,
  }) async {
    if (sourcePath.isEmpty || destinationPath.isEmpty) {
      return false;
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return false;
    }

    final sourceSize = await sourceFile.length();
    if (sourceSize <= 0) {
      return false;
    }

    if (expectedBytes != null && sourceSize != expectedBytes) {
      return false;
    }

    if (sourceFile.path == destinationPath) {
      return true;
    }

    final destinationFile = File(destinationPath);
    if (await destinationFile.exists()) {
      final destinationSize = await destinationFile.length();
      if (destinationSize == sourceSize) {
        return true;
      }

      await destinationFile.delete();
    }

    final destinationDirectory = destinationFile.parent;
    if (!await destinationDirectory.exists()) {
      await destinationDirectory.create(recursive: true);
    }

    await sourceFile.copy(destinationPath);
    return _isUsableFile(destinationPath, expectedBytes: sourceSize);
  }

  Future<void> _deleteFileIfDifferent(
    String sourcePath,
    String destinationPath,
  ) async {
    if (sourcePath != destinationPath) {
      await _deleteFileIfPresent(sourcePath);
    }
  }

  Uri? _localCoverUri(DownloadedTrack track) {
    final path = _localCoverPath(track);
    if (path == null) {
      return null;
    }

    return Uri.file(path);
  }

  String? _localCoverPath(DownloadedTrack track) {
    final savedPath = track.localCoverPath;
    if (savedPath != null &&
        savedPath.isNotEmpty &&
        File(savedPath).existsSync()) {
      return savedPath;
    }

    final inferredPath = '${File(track.localPath).parent.path}/cover.jpg';
    if (File(inferredPath).existsSync()) {
      return inferredPath;
    }

    return null;
  }

  Future<String?> _recoverAlbumCoverPath(DownloadedTrack track) async {
    final inferredPath = '${File(track.localPath).parent.path}/cover.jpg';
    if (await _isUsableFile(inferredPath)) {
      return inferredPath;
    }

    return null;
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

class DownloadFolderMoveResult {
  const DownloadFolderMoveResult({
    required this.movedAudioCount,
    required this.movedCoverCount,
    required this.skippedCount,
    required this.totalCount,
  });

  final int movedAudioCount;
  final int movedCoverCount;
  final int skippedCount;
  final int totalCount;

  bool get movedAnything => movedAudioCount > 0 || movedCoverCount > 0;
}

class DownloadRepairResult {
  const DownloadRepairResult({
    required this.tracks,
    required this.removedAudioCount,
    required this.clearedCoverCount,
    required this.recoveredCoverCount,
  });

  final List<DownloadedTrack> tracks;
  final int removedAudioCount;
  final int clearedCoverCount;
  final int recoveredCoverCount;

  bool get changed =>
      removedAudioCount > 0 || clearedCoverCount > 0 || recoveredCoverCount > 0;
}
