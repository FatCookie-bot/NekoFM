import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/track.dart';
import 'playlist.dart';
import 'playlist_repository.dart';
import 'playlist_track.dart';

final playlistControllerProvider = Provider<PlaylistController>((ref) {
  final controller = PlaylistController();
  ref.onDispose(controller.dispose);
  return controller;
});

class PlaylistController extends ChangeNotifier {
  PlaylistController({PlaylistRepository? repository})
    : _repository = repository ?? PlaylistRepository();

  final PlaylistRepository _repository;

  List<Playlist> _playlists = const [];
  final Map<String, List<PlaylistTrack>> _tracksByPlaylist = {};
  bool _isLoaded = false;

  List<Playlist> get playlists => _playlists;
  bool get isLoaded => _isLoaded;

  List<PlaylistTrack> tracksFor(String playlistId) {
    return _tracksByPlaylist[playlistId] ?? const [];
  }

  Future<void> load() async {
    _playlists = List.unmodifiable(await _repository.loadPlaylists());
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> loadTracks(String playlistId) async {
    _tracksByPlaylist[playlistId] = List.unmodifiable(
      await _repository.loadTracks(playlistId),
    );
    notifyListeners();
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlist = await _repository.createPlaylist(name);
    await load();
    return playlist;
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _repository.deletePlaylist(playlistId);
    _tracksByPlaylist.remove(playlistId);
    await load();
  }

  Future<Playlist?> renamePlaylist(String playlistId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    await _repository.renamePlaylist(playlistId, trimmed);
    await load();
    for (final playlist in _playlists) {
      if (playlist.id == playlistId) {
        return playlist;
      }
    }
    return null;
  }

  Future<void> addTrack(String playlistId, Track track) async {
    await _repository.addTrack(playlistId, track);
    await load();
    await loadTracks(playlistId);
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    await _repository.removeTrack(playlistId, trackId);
    await load();
    await loadTracks(playlistId);
  }

  Future<void> removeEntry(String playlistId, String entryId) async {
    await _repository.removeEntry(playlistId, entryId);
    await load();
    await loadTracks(playlistId);
  }

  Future<void> reorderTracks(
    String playlistId,
    List<PlaylistTrack> tracks,
  ) async {
    await _repository.reorderTracks(playlistId, [
      for (final track in tracks) track.entryId,
    ]);
    await load();
    await loadTracks(playlistId);
  }
}
