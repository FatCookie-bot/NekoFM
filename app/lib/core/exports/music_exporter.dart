import 'dart:convert';
import 'dart:io';

import '../downloads/downloaded_track.dart';
import '../library/track.dart';

class MusicExporter {
  const MusicExporter();

  static const manifestFilename = '.nekofm_export_manifest.json';
  static const allDownloadsPlaylistName = 'NekoFM All Downloads';
  static const likedPlaylistName = 'Liked';

  Future<MusicLibraryExportResult> exportLibrary({
    required List<DownloadedTrack> downloads,
    required Directory targetRoot,
    List<String> likedTrackIds = const [],
    bool cleanFirst = false,
  }) async {
    if (cleanFirst) {
      await cleanExport(targetRoot);
    }

    final allDownloadsResult = await exportDownloads(
      downloads: downloads,
      targetRoot: targetRoot,
      writeManifest: false,
    );

    MusicExportResult? likedResult;
    if (likedTrackIds.isNotEmpty) {
      final downloadsById = {
        for (final download in downloads) download.trackId: download,
      };
      final likedDownloads = [
        for (final trackId in likedTrackIds)
          if (downloadsById[trackId] != null) downloadsById[trackId]!,
      ];
      if (likedDownloads.isNotEmpty) {
        likedResult = await exportDownloads(
          downloads: likedDownloads,
          targetRoot: targetRoot,
          playlistName: likedPlaylistName,
          preserveOrder: true,
          writeManifest: false,
        );
      }
    }

    await _writeManifest(targetRoot, [
      ...allDownloadsResult.relativePaths,
      if (likedResult != null) ...likedResult.relativePaths,
    ]);

    return MusicLibraryExportResult(
      allDownloads: allDownloadsResult,
      liked: likedResult,
    );
  }

  Future<MusicExportResult> exportDownloads({
    required List<DownloadedTrack> downloads,
    required Directory targetRoot,
    String playlistName = allDownloadsPlaylistName,
    bool preserveOrder = false,
    bool writeManifest = true,
  }) async {
    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }

    final completeDownloads = [
      for (final download in downloads)
        if (download.state == DownloadState.complete) download,
    ];
    if (!preserveOrder) {
      completeDownloads.sort(_compareDownloads);
    }

    final exportedTracks = <_ExportedTrack>[];
    final copiedCoverSources = <String>{};
    final exportedRelativePaths = <String>{};
    final artifactRelativePaths = <String>{};
    var skippedTrackCount = 0;
    var copiedCoverCount = 0;
    var collisionCount = 0;

    for (final download in completeDownloads) {
      final sourceFile = File(download.localPath);
      if (!await _isUsableFile(sourceFile, expectedBytes: download.bytes)) {
        skippedTrackCount += 1;
        continue;
      }

      final albumDirectory = Directory(
        '${targetRoot.path}/${_safeFilename(download.artist)}/${_safeFilename(download.albumName ?? 'Unknown Album')}',
      );
      if (!await albumDirectory.exists()) {
        await albumDirectory.create(recursive: true);
      }

      final destinationFile = _uniqueDestinationFile(
        albumDirectory: albumDirectory,
        download: download,
        root: targetRoot,
        reservedRelativePaths: exportedRelativePaths,
      );
      if (_exportFilename(download) != destinationFile.uri.pathSegments.last) {
        collisionCount += 1;
      }

      await _copyReplacing(sourceFile, destinationFile);
      final relativePath = _relativePlaylistPath(targetRoot, destinationFile);
      exportedRelativePaths.add(relativePath);
      artifactRelativePaths.add(relativePath);
      exportedTracks.add(
        _ExportedTrack(download: download, relativePath: relativePath),
      );

      final coverPath = download.localCoverPath;
      if (coverPath != null &&
          coverPath.isNotEmpty &&
          !copiedCoverSources.contains(coverPath)) {
        final coverFile = File(coverPath);
        if (await _isUsableFile(coverFile)) {
          final destinationCoverFile = File('${albumDirectory.path}/cover.jpg');
          await _copyReplacing(coverFile, destinationCoverFile);
          artifactRelativePaths.add(
            _relativePlaylistPath(targetRoot, destinationCoverFile),
          );
          copiedCoverSources.add(coverPath);
          copiedCoverCount += 1;
        }
      }
    }

    final playlistFile = File(
      '${targetRoot.path}/${_safeFilename(playlistName)}.m3u',
    );
    await playlistFile.writeAsString(_buildM3u(exportedTracks));
    artifactRelativePaths.add(_relativePlaylistPath(targetRoot, playlistFile));

    if (writeManifest) {
      await _writeManifest(targetRoot, artifactRelativePaths);
    }

    return MusicExportResult(
      exportedTrackCount: exportedTracks.length,
      copiedCoverCount: copiedCoverCount,
      skippedTrackCount: skippedTrackCount,
      collisionCount: collisionCount,
      playlistPath: playlistFile.path,
      relativePaths: List.unmodifiable(artifactRelativePaths),
    );
  }

  Future<MusicSelectionExportResult> exportSelection({
    required List<MusicExportTrackRequest> tracks,
    required Directory targetRoot,
    List<MusicExportPlaylistRequest> playlists = const [],
    bool cleanFirst = false,
    MusicExportRemoteDownloader? downloadRemoteTrack,
    MusicExportCoverDownloader? downloadRemoteCover,
  }) async {
    if (cleanFirst) {
      await cleanExport(targetRoot);
    }

    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }

    final uniqueTracks = <String, MusicExportTrackRequest>{};
    for (final request in tracks) {
      uniqueTracks.putIfAbsent(request.track.id, () => request);
    }
    for (final playlist in playlists) {
      for (final request in playlist.tracks) {
        uniqueTracks.putIfAbsent(request.track.id, () => request);
      }
    }

    final exportedTracksById = <String, _ExportedTrack>{};
    final copiedCoverSources = <String>{};
    final exportedRelativePaths = <String>{};
    final artifactRelativePaths = <String>{};
    var copiedTrackCount = 0;
    var downloadedTrackCount = 0;
    var skippedTrackCount = 0;
    var copiedCoverCount = 0;
    var downloadedCoverCount = 0;
    var collisionCount = 0;

    final sortedTracks = uniqueTracks.values.toList()
      ..sort((left, right) => _compareTracks(left.track, right.track));
    for (final request in sortedTracks) {
      final track = request.track;
      final albumDirectory = Directory(
        '${targetRoot.path}/Music/${_safeFilename(track.artist)}/${_safeFilename(track.albumName ?? 'Unknown Album')}',
      );
      if (!await albumDirectory.exists()) {
        await albumDirectory.create(recursive: true);
      }

      final destinationFile = _uniqueDestinationFileForTrack(
        albumDirectory: albumDirectory,
        track: track,
        root: targetRoot,
        reservedRelativePaths: exportedRelativePaths,
      );
      if (_exportFilenameForTrack(track) !=
          destinationFile.uri.pathSegments.last) {
        collisionCount += 1;
      }

      final localDownload = request.localDownload;
      var didExportTrack = false;
      if (localDownload != null &&
          localDownload.state == DownloadState.complete &&
          await _isUsableFile(
            File(localDownload.localPath),
            expectedBytes: localDownload.bytes,
          )) {
        final sourceFile = File(localDownload.localPath);
        await _copyReplacing(sourceFile, destinationFile);
        copiedTrackCount += 1;
        didExportTrack = true;
      } else if (downloadRemoteTrack != null) {
        final partialFile = File('${destinationFile.path}.partial');
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
        if (await downloadRemoteTrack(request, partialFile)) {
          if (await _isUsableFile(partialFile)) {
            await partialFile.rename(destinationFile.path);
            downloadedTrackCount += 1;
            didExportTrack = true;
          } else if (await partialFile.exists()) {
            await partialFile.delete();
          }
        } else if (await partialFile.exists()) {
          await partialFile.delete();
        }
      }

      if (!didExportTrack) {
        skippedTrackCount += 1;
        continue;
      }

      final relativePath = _relativePlaylistPath(targetRoot, destinationFile);
      exportedRelativePaths.add(relativePath);
      artifactRelativePaths.add(relativePath);
      exportedTracksById[track.id] = _ExportedTrack(
        track: track,
        relativePath: relativePath,
      );

      final localCoverPath = localDownload?.localCoverPath;
      if (localCoverPath != null &&
          localCoverPath.isNotEmpty &&
          !copiedCoverSources.contains(localCoverPath)) {
        final coverFile = File(localCoverPath);
        if (await _isUsableFile(coverFile)) {
          final destinationCoverFile = File('${albumDirectory.path}/cover.jpg');
          await _copyReplacing(coverFile, destinationCoverFile);
          artifactRelativePaths.add(
            _relativePlaylistPath(targetRoot, destinationCoverFile),
          );
          copiedCoverSources.add(localCoverPath);
          copiedCoverCount += 1;
          continue;
        }
      }

      if (downloadRemoteCover != null && track.coverArtUri != null) {
        final destinationCoverFile = File('${albumDirectory.path}/cover.jpg');
        if (!await _isUsableFile(destinationCoverFile) &&
            await downloadRemoteCover(request, destinationCoverFile)) {
          artifactRelativePaths.add(
            _relativePlaylistPath(targetRoot, destinationCoverFile),
          );
          downloadedCoverCount += 1;
        }
      }
    }

    var playlistCount = 0;
    var playlistEntryCount = 0;
    var skippedPlaylistEntryCount = 0;
    for (final playlist in playlists) {
      final exportedPlaylistTracks = <_ExportedTrack>[];
      for (final request in playlist.tracks) {
        final exportedTrack = exportedTracksById[request.track.id];
        if (exportedTrack == null) {
          skippedPlaylistEntryCount += 1;
          continue;
        }
        exportedPlaylistTracks.add(exportedTrack);
      }

      if (exportedPlaylistTracks.isEmpty) {
        continue;
      }

      final playlistDirectory = Directory('${targetRoot.path}/Playlists');
      if (!await playlistDirectory.exists()) {
        await playlistDirectory.create(recursive: true);
      }
      final playlistFile = File(
        '${playlistDirectory.path}/${_safeFilename(playlist.name)}.m3u',
      );
      await playlistFile.writeAsString(_buildM3u(exportedPlaylistTracks));
      artifactRelativePaths.add(
        _relativePlaylistPath(targetRoot, playlistFile),
      );
      playlistCount += 1;
      playlistEntryCount += exportedPlaylistTracks.length;
    }

    await _writeManifest(targetRoot, artifactRelativePaths);

    return MusicSelectionExportResult(
      exportedTrackCount: copiedTrackCount + downloadedTrackCount,
      copiedTrackCount: copiedTrackCount,
      downloadedTrackCount: downloadedTrackCount,
      skippedTrackCount: skippedTrackCount,
      copiedCoverCount: copiedCoverCount,
      downloadedCoverCount: downloadedCoverCount,
      collisionCount: collisionCount,
      playlistCount: playlistCount,
      playlistEntryCount: playlistEntryCount,
      skippedPlaylistEntryCount: skippedPlaylistEntryCount,
      relativePaths: List.unmodifiable(artifactRelativePaths),
    );
  }

  Future<bool> hasExistingExport(Directory targetRoot) async {
    return await File('${targetRoot.path}/$manifestFilename').exists() ||
        await File(
          '${targetRoot.path}/${_safeFilename(allDownloadsPlaylistName)}.m3u',
        ).exists() ||
        await File(
          '${targetRoot.path}/${_safeFilename(likedPlaylistName)}.m3u',
        ).exists();
  }

  Future<MusicExportCleanResult> cleanExport(Directory targetRoot) async {
    final paths = await _loadManifestPaths(targetRoot);
    paths.add('${_safeFilename(allDownloadsPlaylistName)}.m3u');
    paths.add('${_safeFilename(likedPlaylistName)}.m3u');
    paths.add(manifestFilename);

    var deletedFileCount = 0;
    for (final relativePath in paths) {
      final file = _fileForRelativePath(targetRoot, relativePath);
      if (await file.exists()) {
        await file.delete();
        deletedFileCount += 1;
      }
    }

    return MusicExportCleanResult(deletedFileCount: deletedFileCount);
  }

  static int _compareDownloads(DownloadedTrack left, DownloadedTrack right) {
    return _compareTracks(left.toTrack(), right.toTrack());
  }

  static int _compareTracks(Track left, Track right) {
    final artistCompare = left.artist.compareTo(right.artist);
    if (artistCompare != 0) {
      return artistCompare;
    }

    final albumCompare = (left.albumName ?? '').compareTo(
      right.albumName ?? '',
    );
    if (albumCompare != 0) {
      return albumCompare;
    }

    final trackCompare = left.trackNumber.compareTo(right.trackNumber);
    if (trackCompare != 0) {
      return trackCompare;
    }

    return left.title.compareTo(right.title);
  }

  static String _buildM3u(List<_ExportedTrack> tracks) {
    final lines = <String>['#EXTM3U'];
    for (final track in tracks) {
      final source = track.resolvedTrack;
      lines.add(
        '#EXTINF:${source.durationSeconds},${source.artist} - ${source.title}',
      );
      lines.add(track.relativePath);
    }

    return '${lines.join('\n')}\n';
  }

  static String _exportFilename(DownloadedTrack download) {
    return _exportFilenameForTrack(download.toTrack());
  }

  static String _exportFilenameForTrack(Track track) {
    final filename = _baseFilenameForTrack(track);
    return _safeFilename(filename);
  }

  static String _baseFilenameForTrack(Track track) {
    final extension = _cleanExtension(track.suffix);
    final title = _safeFilename(track.title);
    final number = track.trackNumber > 0
        ? '${track.trackNumber.toString().padLeft(2, '0')} - '
        : '';
    final filename = extension == null
        ? '$number$title'
        : '$number$title.$extension';
    return filename;
  }

  static File _uniqueDestinationFile({
    required Directory albumDirectory,
    required DownloadedTrack download,
    required Directory root,
    required Set<String> reservedRelativePaths,
  }) {
    final preferredFilename = _exportFilename(download);
    final preferredFile = File('${albumDirectory.path}/$preferredFilename');
    final preferredRelativePath = _relativePlaylistPath(root, preferredFile);
    if (!reservedRelativePaths.contains(preferredRelativePath)) {
      return preferredFile;
    }

    final extension = _cleanExtension(download.suffix);
    final title = _safeFilename(download.title);
    final number = download.trackNumber > 0
        ? '${download.trackNumber.toString().padLeft(2, '0')} - '
        : '';
    final trackId = _safeFilename(download.trackId);
    final fallbackName = extension == null
        ? '$number$title - $trackId'
        : '$number$title - $trackId.$extension';
    final fallbackFile = File(
      '${albumDirectory.path}/${_safeFilename(fallbackName)}',
    );
    final fallbackRelativePath = _relativePlaylistPath(root, fallbackFile);
    if (!reservedRelativePaths.contains(fallbackRelativePath)) {
      return fallbackFile;
    }

    var suffix = 2;
    while (true) {
      final numberedName = extension == null
          ? '$number$title - $trackId - $suffix'
          : '$number$title - $trackId - $suffix.$extension';
      final numberedFile = File(
        '${albumDirectory.path}/${_safeFilename(numberedName)}',
      );
      final numberedRelativePath = _relativePlaylistPath(root, numberedFile);
      if (!reservedRelativePaths.contains(numberedRelativePath)) {
        return numberedFile;
      }
      suffix += 1;
    }
  }

  static File _uniqueDestinationFileForTrack({
    required Directory albumDirectory,
    required Track track,
    required Directory root,
    required Set<String> reservedRelativePaths,
  }) {
    final preferredFilename = _exportFilenameForTrack(track);
    final preferredFile = File('${albumDirectory.path}/$preferredFilename');
    final preferredRelativePath = _relativePlaylistPath(root, preferredFile);
    if (!reservedRelativePaths.contains(preferredRelativePath)) {
      return preferredFile;
    }

    final extension = _cleanExtension(track.suffix);
    final title = _safeFilename(track.title);
    final number = track.trackNumber > 0
        ? '${track.trackNumber.toString().padLeft(2, '0')} - '
        : '';
    final trackId = _safeFilename(track.id);
    final fallbackName = extension == null
        ? '$number$title - $trackId'
        : '$number$title - $trackId.$extension';
    final fallbackFile = File(
      '${albumDirectory.path}/${_safeFilename(fallbackName)}',
    );
    final fallbackRelativePath = _relativePlaylistPath(root, fallbackFile);
    if (!reservedRelativePaths.contains(fallbackRelativePath)) {
      return fallbackFile;
    }

    var suffix = 2;
    while (true) {
      final numberedName = extension == null
          ? '$number$title - $trackId - $suffix'
          : '$number$title - $trackId - $suffix.$extension';
      final numberedFile = File(
        '${albumDirectory.path}/${_safeFilename(numberedName)}',
      );
      final numberedRelativePath = _relativePlaylistPath(root, numberedFile);
      if (!reservedRelativePaths.contains(numberedRelativePath)) {
        return numberedFile;
      }
      suffix += 1;
    }
  }

  static String _relativePlaylistPath(Directory root, File file) {
    final rootPath = _withoutTrailingSlash(root.path);
    final filePath = file.path;
    final relativePath = filePath.startsWith('$rootPath/')
        ? filePath.substring(rootPath.length + 1)
        : file.uri.pathSegments.last;
    return relativePath.replaceAll('\\', '/');
  }

  static Future<bool> _isUsableFile(File file, {int? expectedBytes}) async {
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

  static Future<void> _copyReplacing(File source, File destination) async {
    final parent = destination.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    if (await destination.exists()) {
      await destination.delete();
    }

    await source.copy(destination.path);
  }

  static Future<void> _writeManifest(
    Directory targetRoot,
    Iterable<String> relativePaths,
  ) async {
    if (!await targetRoot.exists()) {
      await targetRoot.create(recursive: true);
    }

    final uniquePaths =
        relativePaths
            .where((path) => path.isNotEmpty && !_isUnsafeRelativePath(path))
            .toSet()
            .toList()
          ..sort();
    final manifest = {
      'version': 1,
      'generatedBy': 'NekoFM',
      'paths': uniquePaths,
    };
    const encoder = JsonEncoder.withIndent('  ');
    await File(
      '${targetRoot.path}/$manifestFilename',
    ).writeAsString(encoder.convert(manifest));
  }

  static Future<Set<String>> _loadManifestPaths(Directory targetRoot) async {
    final manifestFile = File('${targetRoot.path}/$manifestFilename');
    if (!await manifestFile.exists()) {
      return {};
    }

    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return {};
      }

      final paths = decoded['paths'];
      if (paths is! List) {
        return {};
      }

      return {
        for (final path in paths)
          if (path is String && !_isUnsafeRelativePath(path)) path,
      };
    } on Object {
      return {};
    }
  }

  static File _fileForRelativePath(Directory root, String relativePath) {
    return File('${_withoutTrailingSlash(root.path)}/$relativePath');
  }

  static bool _isUnsafeRelativePath(String path) {
    return path.startsWith('/') ||
        path.startsWith('\\') ||
        path.split('/').contains('..') ||
        path.split('\\').contains('..');
  }

  static String _safeFilename(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'_+'), '_');
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') {
      return 'music';
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

  static String _withoutTrailingSlash(String path) {
    if (path.endsWith('/') && path.length > 1) {
      return path.substring(0, path.length - 1);
    }

    return path;
  }
}

class MusicLibraryExportResult {
  const MusicLibraryExportResult({required this.allDownloads, this.liked});

  final MusicExportResult allDownloads;
  final MusicExportResult? liked;
}

class MusicExportResult {
  const MusicExportResult({
    required this.exportedTrackCount,
    required this.copiedCoverCount,
    required this.skippedTrackCount,
    required this.collisionCount,
    required this.playlistPath,
    required this.relativePaths,
  });

  final int exportedTrackCount;
  final int copiedCoverCount;
  final int skippedTrackCount;
  final int collisionCount;
  final String playlistPath;
  final List<String> relativePaths;
}

class MusicExportCleanResult {
  const MusicExportCleanResult({required this.deletedFileCount});

  final int deletedFileCount;
}

typedef MusicExportRemoteDownloader =
    Future<bool> Function(MusicExportTrackRequest request, File destination);

typedef MusicExportCoverDownloader =
    Future<bool> Function(MusicExportTrackRequest request, File destination);

class MusicExportTrackRequest {
  const MusicExportTrackRequest({required this.track, this.localDownload});

  final Track track;
  final DownloadedTrack? localDownload;
}

class MusicExportPlaylistRequest {
  const MusicExportPlaylistRequest({required this.name, required this.tracks});

  final String name;
  final List<MusicExportTrackRequest> tracks;
}

class MusicSelectionExportResult {
  const MusicSelectionExportResult({
    required this.exportedTrackCount,
    required this.copiedTrackCount,
    required this.downloadedTrackCount,
    required this.skippedTrackCount,
    required this.copiedCoverCount,
    required this.downloadedCoverCount,
    required this.collisionCount,
    required this.playlistCount,
    required this.playlistEntryCount,
    required this.skippedPlaylistEntryCount,
    required this.relativePaths,
  });

  final int exportedTrackCount;
  final int copiedTrackCount;
  final int downloadedTrackCount;
  final int skippedTrackCount;
  final int copiedCoverCount;
  final int downloadedCoverCount;
  final int collisionCount;
  final int playlistCount;
  final int playlistEntryCount;
  final int skippedPlaylistEntryCount;
  final List<String> relativePaths;
}

class _ExportedTrack {
  const _ExportedTrack({this.download, this.track, required this.relativePath})
    : assert(download != null || track != null);

  final DownloadedTrack? download;
  final Track? track;
  final String relativePath;

  Track get resolvedTrack => track ?? download!.toTrack();
}
