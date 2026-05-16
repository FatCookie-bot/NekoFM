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

  List<DownloadedTrack> get tracks => _tracks;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _tracks = await _repository.loadTracks();
    _isLoaded = true;
    notifyListeners();
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
    if (existing?.state == DownloadState.downloading) {
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

    final profile = await _profileStore.load();
    if (profile == null || profile.password.isEmpty) {
      _upsert(
        DownloadedTrack.fromTrack(
          track: track,
          localPath: await _repository.localPathForTrack(track),
          state: DownloadState.failed,
        ).copyWith(errorMessage: 'Connect to your server in Settings first.'),
      );
      await _repository.saveTracks(_tracks);
      return;
    }

    final localPath = await _repository.localPathForTrack(track);
    final localCoverPath = await _downloadCover(track);
    final partialPath = '$localPath.partial';
    var item = DownloadedTrack.fromTrack(
      track: track,
      localPath: localPath,
      state: DownloadState.downloading,
    ).copyWith(localCoverPath: localCoverPath);
    _upsert(item);
    await _repository.saveTracks(_tracks);

    try {
      final partialFile = File(partialPath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      await _client.downloadTrack(
        profile,
        track.id,
        partialPath,
        onReceiveProgress: (received, total) {
          item = item.copyWith(
            state: DownloadState.downloading,
            updatedAt: DateTime.now(),
            receivedBytes: received,
            totalBytes: total <= 0 ? null : total,
          );
          _upsert(item);
        },
      );

      final completedFile = File(localPath);
      if (await completedFile.exists()) {
        await completedFile.delete();
      }

      await partialFile.rename(localPath);
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
      await _markFailed(item, error.message ?? 'Download failed.');
    } on Object catch (error) {
      await _markFailed(item, 'Download failed: $error');
    }
  }

  Future<void> downloadTracks(List<Track> tracks) async {
    for (final track in tracks) {
      await downloadTrack(track);
    }
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
    final keepCover =
        existing.localCoverPath != null &&
        nextTracks.any(
          (track) => track.localCoverPath == existing.localCoverPath,
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

  Future<String?> _downloadCover(Track track) async {
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

  void _upsert(DownloadedTrack item) {
    final next = [
      item,
      for (final track in _tracks)
        if (track.trackId != item.trackId) track,
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    _tracks = List.unmodifiable(next);
    notifyListeners();
  }
}
