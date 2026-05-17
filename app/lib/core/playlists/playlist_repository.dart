import '../downloads/download_database.dart';
import '../library/track.dart';
import 'playlist.dart';
import 'playlist_track.dart';

class PlaylistRepository {
  PlaylistRepository({DownloadDatabase? database})
    : _database = database ?? DownloadDatabase();

  final DownloadDatabase _database;

  Future<List<Playlist>> loadPlaylists() {
    return _database.loadPlaylists();
  }

  Future<List<PlaylistTrack>> loadTracks(String playlistId) {
    return _database.loadPlaylistTracks(playlistId);
  }

  Future<Playlist> createPlaylist(String name) async {
    final now = DateTime.now();
    final playlist = Playlist(
      id: 'playlist-${now.microsecondsSinceEpoch}',
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
      trackCount: 0,
    );
    await _database.upsertPlaylist(playlist);
    return playlist;
  }

  Future<void> deletePlaylist(String playlistId) {
    return _database.deletePlaylist(playlistId);
  }

  Future<void> addTrack(String playlistId, Track track) async {
    final nextPosition = await _database.nextPlaylistPosition(playlistId);
    await _database.upsertPlaylistTrack(
      PlaylistTrack.fromTrack(
        playlistId: playlistId,
        track: track,
        position: nextPosition,
      ),
    );
  }

  Future<void> removeTrack(String playlistId, String trackId) {
    return _database.deletePlaylistTrack(playlistId, trackId);
  }

  Future<void> removeEntry(String playlistId, String entryId) {
    return _database.deletePlaylistTrackEntry(playlistId, entryId);
  }
}
