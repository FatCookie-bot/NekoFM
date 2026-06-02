import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/track.dart';
import '../server/music_server_client.dart';
import '../server/secure_server_profile_store.dart';
import 'download_repository.dart';
import 'downloaded_track.dart';

final downloadControllerProvider = Provider<DownloadController>((ref) {
  final controller = DownloadController();
  ref.onDispose(controller.dispose);
  return controller;
});

class DownloadController extends ChangeNotifier {
  DownloadController({
    DownloadRepository? repository,
    SecureServerProfileStore? profileStore,
    MusicServerClient? client,
  }) : _repository = repository ?? DownloadRepository(),
       _profileStore = profileStore ?? const SecureServerProfileStore(),
       _client = client ?? MusicServerClient();

  final DownloadRepository _repository;
  final SecureServerProfileStore _profileStore;
  final MusicServerClient _client;
  final Dio _dio = Dio();

  List<DownloadedTrack> _tracks = const [];
  bool _isLoaded = false;
  bool _isProcessingQueue = false;
  Future<void>? _loadFuture;
  String? _activeTrackId;
  CancelToken? _activeCancelToken;
  final Set<String> _cancelledTrackIds = {};
  DownloadRepairResult? _lastRepairResult;

  List<DownloadedTrack> get tracks => _tracks;
  bool get isLoaded => _isLoaded;
  DownloadRepairResult? get lastRepairResult => _lastRepairResult;
  int get failedCount =>
      _tracks.where((track) => track.state == DownloadState.failed).length;

  Future<void> load() async {
    if (_isLoaded) {
      return;
    }

    final existingLoad = _loadFuture;
    if (existingLoad != null) {
      return existingLoad;
    }

    final loadFuture = _load();
    _loadFuture = loadFuture;
    try {
      await loadFuture;
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> repair() async {
    var repairResult = await _repository.repairDownloads();
    final coverRepairResult = await _downloadMissingAlbumCovers(
      repairResult.tracks,
    );
    _tracks = coverRepairResult.tracks;
    repairResult = repairResult.copyWith(
      tracks: _tracks,
      downloadedCoverCount: coverRepairResult.downloadedCoverCount,
    );
    _lastRepairResult = repairResult;
    _isLoaded = true;
    notifyListeners();
    if (coverRepairResult.downloadedCoverCount > 0) {
      await _repository.saveTracks(_tracks);
    }
    _processQueue();
  }

  Future<void> reloadFromStorage() async {
    _tracks = await _repository.loadTracks();
    _isLoaded = true;
    notifyListeners();
    _processQueue();
  }

  Future<void> _load() async {
    var repairResult = await _repository.repairDownloads();
    final coverRepairResult = await _downloadMissingAlbumCovers(
      repairResult.tracks,
    );
    _tracks = coverRepairResult.tracks;
    repairResult = repairResult.copyWith(
      tracks: _tracks,
      downloadedCoverCount: coverRepairResult.downloadedCoverCount,
    );
    _lastRepairResult = repairResult;
    _isLoaded = true;
    notifyListeners();
    if (coverRepairResult.downloadedCoverCount > 0) {
      await _repository.saveTracks(_tracks);
    }
    _processQueue();
  }

  DownloadedTrack? trackState(String trackId) {
    for (final track in _tracks) {
      if (track.trackId == trackId) {
        return track;
      }
    }

    return null;
  }

  Future<void> downloadTrack(Track track) async {
    if (!_isLoaded) {
      await load();
    }

    final existing = trackState(track.id);
    if (existing?.state == DownloadState.queued ||
        existing?.state == DownloadState.downloading) {
      _processQueue();
      return;
    }

    if (existing?.state == DownloadState.complete) {
      final localCoverPath = await _downloadCover(track);
      if (localCoverPath == null) {
        return;
      }

      final updated = existing!.copyWith(
        updatedAt: DateTime.now(),
        localCoverPath: localCoverPath,
      );
      _upsert(updated);
      await _repository.saveTracks(_tracks);
      return;
    }

    final item = DownloadedTrack.fromTrack(
      track: track,
      localPath: await _repository.localPathForTrack(track),
      state: DownloadState.queued,
    ).copyWith(errorMessage: null);
    _upsert(item);
    await _repository.saveTracks(_tracks);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (!_isLoaded || _isProcessingQueue) {
      return;
    }

    _isProcessingQueue = true;
    try {
      while (true) {
        final nextItem = _tracks
            .where((track) => track.state == DownloadState.queued)
            .firstOrNull;
        if (nextItem == null) {
          return;
        }

        await _downloadQueuedTrack(nextItem);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _downloadQueuedTrack(DownloadedTrack queuedItem) async {
    if (trackState(queuedItem.trackId)?.state != DownloadState.queued) {
      return;
    }

    final profile = await _profileStore.load();
    if (profile == null || profile.password.isEmpty) {
      await _markFailed(
        queuedItem,
        'Connect to your server in Settings first.',
      );
      return;
    }

    final track = queuedItem.toTrack();
    final cancelToken = CancelToken();
    _activeTrackId = queuedItem.trackId;
    _activeCancelToken = cancelToken;
    final localCoverPath = await _downloadCover(track, cancelToken);
    if (_isCancelled(queuedItem.trackId)) {
      await _discardDownload(queuedItem);
      _clearActiveDownload(queuedItem.trackId);
      return;
    }

    final partialPath = '${queuedItem.localPath}.partial';
    var item = queuedItem.copyWith(
      state: DownloadState.downloading,
      updatedAt: DateTime.now(),
      localCoverPath: localCoverPath,
      receivedBytes: 0,
      totalBytes: null,
      errorMessage: null,
    );
    _upsert(item);
    await _repository.saveTracks(_tracks);

    try {
      final partialFile = File(partialPath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      await _client.downloadTrack(
        profile,
        queuedItem.trackId,
        partialPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (_isCancelled(queuedItem.trackId)) {
            return;
          }

          item = item.copyWith(
            state: DownloadState.downloading,
            updatedAt: DateTime.now(),
            receivedBytes: received,
            totalBytes: total <= 0 ? null : total,
          );
          _upsert(item);
        },
      );

      if (_isCancelled(queuedItem.trackId)) {
        await _discardDownload(item);
        return;
      }

      final completedFile = File(queuedItem.localPath);
      if (await completedFile.exists()) {
        await completedFile.delete();
      }

      await partialFile.rename(queuedItem.localPath);
      final size = await completedFile.length();
      if (size <= 0) {
        throw const FileSystemException('Downloaded file was empty.');
      }

      item = item.copyWith(
        state: DownloadState.complete,
        updatedAt: DateTime.now(),
        bytes: size,
        receivedBytes: size,
        totalBytes: size,
        localCoverPath: localCoverPath,
      );
      _upsert(item);
      await _repository.saveTracks(_tracks);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || _isCancelled(queuedItem.trackId)) {
        await _discardDownload(item);
        return;
      }

      await _markFailed(item, error.message ?? 'Download failed.');
    } on Object catch (error) {
      if (_isCancelled(queuedItem.trackId)) {
        await _discardDownload(item);
        return;
      }

      await _markFailed(item, 'Download failed: $error');
    } finally {
      _clearActiveDownload(queuedItem.trackId);
    }
  }

  Future<void> downloadTracks(List<Track> tracks) async {
    for (final track in tracks) {
      await downloadTrack(track);
    }
  }

  Future<void> retryDownload(DownloadedTrack download) {
    return downloadTrack(download.toTrack());
  }

  Future<void> retryFailedDownloads() async {
    final failedTracks = [
      for (final track in _tracks)
        if (track.state == DownloadState.failed) track.toTrack(),
    ];

    for (final track in failedTracks) {
      await downloadTrack(track);
    }
  }

  Future<void> cancelDownload(String trackId) async {
    if (!_isLoaded) {
      await load();
    }

    final existing = trackState(trackId);
    if (existing == null ||
        (existing.state != DownloadState.queued &&
            existing.state != DownloadState.downloading)) {
      return;
    }

    final isActiveDownload = _activeTrackId == trackId;
    if (isActiveDownload) {
      _cancelledTrackIds.add(trackId);
      _activeCancelToken?.cancel('Download cancelled.');
    } else if (existing.state == DownloadState.queued) {
      await _discardDownload(existing);
      return;
    } else {
      _cancelledTrackIds.add(trackId);
    }

    await _discardDownload(existing);
  }

  Future<void> deleteTrack(String trackId) async {
    if (!_isLoaded) {
      await load();
    }

    final existing = trackState(trackId);
    if (existing == null) {
      return;
    }

    final nextTracks = [
      for (final track in _tracks)
        if (track.trackId != trackId) track,
    ];
    final existingCoverPath = _repository.coverPathForDownloadedTrack(existing);
    final keepCover =
        existingCoverPath != null &&
        nextTracks.any(
          (track) =>
              _repository.coverPathForDownloadedTrack(track) ==
              existingCoverPath,
        );

    await _repository.deleteDownloadedTrackFiles(
      existing,
      deleteCover: !keepCover,
    );
    _tracks = List.unmodifiable(nextTracks);
    notifyListeners();
    await _repository.saveTracks(_tracks);
  }

  Future<void> deleteTracks(List<Track> tracks) async {
    for (final track in tracks) {
      await deleteTrack(track.id);
    }
  }

  Future<void> _discardDownload(DownloadedTrack item) async {
    final existing = trackState(item.trackId) ?? item;
    final nextTracks = [
      for (final track in _tracks)
        if (track.trackId != item.trackId) track,
    ];
    final existingCoverPath = _repository.coverPathForDownloadedTrack(existing);
    final keepCover =
        existingCoverPath != null &&
        nextTracks.any(
          (track) =>
              _repository.coverPathForDownloadedTrack(track) ==
              existingCoverPath,
        );

    await _repository.deleteDownloadedTrackFiles(
      existing,
      deleteCover: !keepCover,
    );
    _tracks = List.unmodifiable(nextTracks);
    notifyListeners();
    await _repository.saveTracks(_tracks);
  }

  bool _isCancelled(String trackId) => _cancelledTrackIds.contains(trackId);

  void _clearActiveDownload(String trackId) {
    if (_activeTrackId != trackId) {
      return;
    }

    _activeTrackId = null;
    _activeCancelToken = null;
    _cancelledTrackIds.remove(trackId);
  }

  Future<void> _markFailed(DownloadedTrack item, String message) async {
    _upsert(
      item.copyWith(
        state: DownloadState.failed,
        updatedAt: DateTime.now(),
        errorMessage: message,
      ),
    );
    await _repository.saveTracks(_tracks);
  }

  Future<String?> _downloadCover(
    Track track, [
    CancelToken? cancelToken,
  ]) async {
    final coverUri = track.coverArtUri;
    if (coverUri == null) {
      return null;
    }

    final coverPath = await _repository.localCoverPathForTrack(track);
    final partialPath = '$coverPath.partial';
    try {
      final existingCover = File(coverPath);
      if (await existingCover.exists() && await existingCover.length() > 0) {
        return coverPath;
      }

      final partialFile = File(partialPath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      await _dio.downloadUri(
        coverUri,
        partialPath,
        cancelToken: cancelToken,
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );

      final completedFile = File(coverPath);
      if (await completedFile.exists()) {
        await completedFile.delete();
      }

      await partialFile.rename(coverPath);
      return coverPath;
    } on Object {
      return null;
    }
  }

  Future<_MissingCoverRepairResult> _downloadMissingAlbumCovers(
    List<DownloadedTrack> tracks,
  ) async {
    final coverPathsByFolder = <String, String>{};
    final repairedTracks = <DownloadedTrack>[];
    var downloadedCoverCount = 0;

    for (final track in tracks) {
      if (track.state != DownloadState.complete ||
          track.localCoverPath != null ||
          track.coverArtUri == null) {
        repairedTracks.add(track);
        continue;
      }

      final albumFolder = File(track.localPath).parent.path;
      final existingCoverPath = coverPathsByFolder[albumFolder];
      if (existingCoverPath != null) {
        repairedTracks.add(track.copyWith(localCoverPath: existingCoverPath));
        continue;
      }

      final inferredCoverPath = _repository.coverPathForDownloadedTrack(track);
      if (inferredCoverPath != null) {
        final inferredCover = File(inferredCoverPath);
        if (await inferredCover.exists() && await inferredCover.length() > 0) {
          coverPathsByFolder[albumFolder] = inferredCoverPath;
          repairedTracks.add(track.copyWith(localCoverPath: inferredCoverPath));
          continue;
        }
      }

      final downloadedCoverPath = await _downloadCover(track.toTrack());
      if (downloadedCoverPath == null) {
        repairedTracks.add(track);
        continue;
      }

      coverPathsByFolder[albumFolder] = downloadedCoverPath;
      downloadedCoverCount += 1;
      repairedTracks.add(track.copyWith(localCoverPath: downloadedCoverPath));
    }

    return _MissingCoverRepairResult(
      tracks: List.unmodifiable(repairedTracks),
      downloadedCoverCount: downloadedCoverCount,
    );
  }

  void _upsert(DownloadedTrack item) {
    final next = [
      item,
      for (final track in _tracks)
        if (track.trackId != item.trackId) track,
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    _tracks = List.unmodifiable(next);
    notifyListeners();
  }

  @override
  void dispose() {
    _activeCancelToken?.cancel('Download controller disposed.');
    _dio.close(force: true);
    super.dispose();
  }
}

class _MissingCoverRepairResult {
  const _MissingCoverRepairResult({
    required this.tracks,
    required this.downloadedCoverCount,
  });

  final List<DownloadedTrack> tracks;
  final int downloadedCoverCount;
}
