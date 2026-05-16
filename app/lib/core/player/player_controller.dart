import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../downloads/download_repository.dart';
import '../downloads/downloaded_track.dart';
import '../library/album.dart';
import '../library/track.dart';
import '../server/music_server_client.dart';
import '../server/secure_server_profile_store.dart';
import 'playback_preferences.dart';

final playerControllerProvider = Provider<PlayerController>((ref) {
  final controller = PlayerController();
  ref.onDispose(controller.dispose);
  return controller;
});

class PlayerController extends ChangeNotifier {
  PlayerController({
    AudioPlayer? audioPlayer,
    SecureServerProfileStore? profileStore,
    MusicServerClient? client,
    DownloadRepository? downloadRepository,
    PlaybackPreferences? playbackPreferences,
  }) : audioPlayer = audioPlayer ?? AudioPlayer(),
       _profileStore = profileStore ?? const SecureServerProfileStore(),
       _client = client ?? MusicServerClient(),
       _downloadRepository = downloadRepository ?? DownloadRepository(),
       _playbackPreferences = playbackPreferences ?? PlaybackPreferences();

  final AudioPlayer audioPlayer;
  final SecureServerProfileStore _profileStore;
  final MusicServerClient _client;
  final DownloadRepository _downloadRepository;
  final PlaybackPreferences _playbackPreferences;

  List<Track> _queue = const [];
  Album? _album;
  String? _errorMessage;
  bool _isLoading = false;

  List<Track> get queue => _queue;
  Album? get album => _album;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get hasQueue => _queue.isNotEmpty;

  Track? trackAt(int? index) {
    if (index == null || index < 0 || index >= _queue.length) {
      return null;
    }

    return _queue[index];
  }

  Future<void> playAlbum({
    required Album album,
    required List<Track> tracks,
    required int startIndex,
  }) async {
    if (tracks.isEmpty) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _album = album;
    _queue = List.unmodifiable(tracks);
    notifyListeners();

    try {
      final sources = [
        for (final track in tracks)
          AudioSource.uri(await _sourceUriForTrack(track), tag: track.id),
      ];

      await audioPlayer.setAudioSources(
        sources,
        initialIndex: startIndex.clamp(0, tracks.length - 1),
        initialPosition: Duration.zero,
      );
      await audioPlayer.play();
    } on MusicServerException catch (error) {
      _errorMessage = error.message;
    } on PlayerException catch (error) {
      _errorMessage = error.message ?? 'The track could not be loaded.';
    } on PlayerInterruptedException {
      _errorMessage = null;
    } on Object catch (error) {
      _errorMessage = 'Playback failed: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playDownloadedTracks({
    required List<DownloadedTrack> downloads,
    required int startIndex,
  }) async {
    final completeDownloads = downloads
        .where((download) => download.state == DownloadState.complete)
        .toList(growable: false);
    if (completeDownloads.isEmpty) {
      return;
    }

    final safeStartIndex = startIndex.clamp(0, completeDownloads.length - 1);
    final tracks = [
      for (final download in completeDownloads) download.toTrack(),
    ];
    final album = Album(
      id: 'downloads',
      name: 'Downloads',
      artist: completeDownloads[safeStartIndex].artist,
      songCount: completeDownloads.length,
      durationSeconds: completeDownloads.fold(
        0,
        (total, download) => total + download.durationSeconds,
      ),
      coverArtUri: completeDownloads[safeStartIndex].coverArtUri == null
          ? null
          : Uri.tryParse(completeDownloads[safeStartIndex].coverArtUri!),
    );

    _isLoading = true;
    _errorMessage = null;
    _album = album;
    _queue = List.unmodifiable(tracks);
    notifyListeners();

    try {
      final sources = [
        for (final download in completeDownloads)
          AudioSource.uri(
            await _localDownloadUri(download),
            tag: download.trackId,
          ),
      ];

      await audioPlayer.setAudioSources(
        sources,
        initialIndex: safeStartIndex,
        initialPosition: Duration.zero,
      );
      await audioPlayer.play();
    } on FileSystemException catch (error) {
      _errorMessage = error.message;
    } on PlayerException catch (error) {
      _errorMessage =
          error.message ?? 'The downloaded track could not be loaded.';
    } on PlayerInterruptedException {
      _errorMessage = null;
    } on Object catch (error) {
      _errorMessage = 'Offline playback failed: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (audioPlayer.playing) {
      await audioPlayer.pause();
      return;
    }

    await audioPlayer.play();
  }

  Future<void> seek(Duration position) {
    return audioPlayer.seek(position);
  }

  Future<void> seekBack() async {
    final threshold = await _playbackPreferences.loadPreviousTrackThreshold();
    if (shouldRestartCurrentTrack(
      position: audioPlayer.position,
      threshold: threshold,
    )) {
      await audioPlayer.seek(Duration.zero);
      return;
    }

    await audioPlayer.seekToPrevious();
  }

  Future<void> seekToNext() {
    return audioPlayer.seekToNext();
  }

  Future<SavedServerProfile> _loadProfile() async {
    final profile = await _profileStore.load().timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );

    if (profile == null) {
      throw const MusicServerException(
        'Connect to your server in Settings first.',
      );
    }

    if (profile.password.isEmpty) {
      throw const MusicServerException(
        'Saved credentials do not include a password. Reconnect in Settings.',
      );
    }

    return profile;
  }

  Future<Uri> _sourceUriForTrack(Track track) async {
    final localPath = await _downloadRepository.localFileForTrack(track.id);
    if (localPath != null) {
      return Uri.file(localPath);
    }

    final profile = await _loadProfile();
    return _client.streamUri(profile, track.id);
  }

  Future<Uri> _localDownloadUri(DownloadedTrack download) async {
    final file = File(download.localPath);
    if (!await file.exists()) {
      throw const FileSystemException('Downloaded file is missing.');
    }

    final size = await file.length();
    if (size <= 0) {
      throw const FileSystemException('Downloaded file is empty.');
    }

    if (download.bytes != null && download.bytes != size) {
      throw const FileSystemException('Downloaded file size changed.');
    }

    return Uri.file(file.path);
  }

  @override
  Future<void> dispose() async {
    await audioPlayer.dispose();
    super.dispose();
  }
}
