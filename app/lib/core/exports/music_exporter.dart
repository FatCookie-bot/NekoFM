import 'dart:io';

import '../downloads/downloaded_track.dart';

class MusicExporter {
  const MusicExporter();

  Future<MusicLibraryExportResult> exportLibrary({
    required List<DownloadedTrack> downloads,
    required Directory targetRoot,
    List<String> likedTrackIds = const [],
  }) async {
    final allDownloadsResult = await exportDownloads(
      downloads: downloads,
      targetRoot: targetRoot,
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
          playlistName: 'Liked',
          preserveOrder: true,
        );
      }
    }

    return MusicLibraryExportResult(
      allDownloads: allDownloadsResult,
      liked: likedResult,
    );
  }

  Future<MusicExportResult> exportDownloads({
    required List<DownloadedTrack> downloads,
    required Directory targetRoot,
    String playlistName = 'NekoFM All Downloads',
    bool preserveOrder = false,
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
    var skippedTrackCount = 0;
    var copiedCoverCount = 0;

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

      final destinationFile = File(
        '${albumDirectory.path}/${_exportFilename(download)}',
      );
      await _copyReplacing(sourceFile, destinationFile);
      exportedTracks.add(
        _ExportedTrack(
          download: download,
          relativePath: _relativePlaylistPath(targetRoot, destinationFile),
        ),
      );

      final coverPath = download.localCoverPath;
      if (coverPath != null &&
          coverPath.isNotEmpty &&
          !copiedCoverSources.contains(coverPath)) {
        final coverFile = File(coverPath);
        if (await _isUsableFile(coverFile)) {
          await _copyReplacing(
            coverFile,
            File('${albumDirectory.path}/cover.jpg'),
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

    return MusicExportResult(
      exportedTrackCount: exportedTracks.length,
      copiedCoverCount: copiedCoverCount,
      skippedTrackCount: skippedTrackCount,
      playlistPath: playlistFile.path,
    );
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
    final extension = _cleanExtension(download.suffix);
    final title = _safeFilename(download.title);
    final number = download.trackNumber > 0
        ? '${download.trackNumber.toString().padLeft(2, '0')} - '
        : '';
    final filename = extension == null
        ? '$number$title'
        : '$number$title.$extension';
    return _safeFilename(filename);
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
    required this.playlistPath,
  });

  final int exportedTrackCount;
  final int copiedCoverCount;
  final int skippedTrackCount;
  final String playlistPath;
}

class _ExportedTrack {
  const _ExportedTrack({required this.download, required this.relativePath});

  final DownloadedTrack download;
  final String relativePath;
}
