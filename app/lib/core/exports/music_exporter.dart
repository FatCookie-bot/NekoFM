import 'dart:convert';
import 'dart:io';

import '../downloads/downloaded_track.dart';

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
      final download = track.download;
      lines.add(
        '#EXTINF:${download.durationSeconds},${download.artist} - ${download.title}',
      );
      lines.add(track.relativePath);
    }

    return '${lines.join('\n')}\n';
  }

  static String _exportFilename(DownloadedTrack download) {
    final filename = _baseFilename(download);
    return _safeFilename(filename);
  }

  static String _baseFilename(DownloadedTrack download) {
    final extension = _cleanExtension(download.suffix);
    final title = _safeFilename(download.title);
    final number = download.trackNumber > 0
        ? '${download.trackNumber.toString().padLeft(2, '0')} - '
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

class _ExportedTrack {
  const _ExportedTrack({required this.download, required this.relativePath});

  final DownloadedTrack download;
  final String relativePath;
}
