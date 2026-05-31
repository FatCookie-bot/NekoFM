import '../downloads/download_database.dart';
import '../library/track.dart';
import 'liked_track.dart';

class LikedRepository {
  LikedRepository({DownloadDatabase? database})
    : _database = database ?? DownloadDatabase();

  final DownloadDatabase _database;

  Future<List<LikedTrack>> loadTracks() {
    return _database.loadLikedTracks();
  }

  Future<bool> isLiked(String trackId) {
    return _database.isTrackLiked(trackId);
  }

  Future<void> likeTrack(Track track) {
    return _likeTrack(track);
  }

  Future<void> _likeTrack(Track track) async {
    final position = await _database.nextLikedPosition();
    await _database.upsertLikedTrack(
      LikedTrack.fromTrack(track, position: position),
    );
  }

  Future<void> unlikeTrack(String trackId) {
    return _database.deleteLikedTrack(trackId);
  }

  Future<void> toggleTrack(Track track) async {
    if (await isLiked(track.id)) {
      await unlikeTrack(track.id);
      return;
    }

    await _likeTrack(track);
  }

  Future<void> reorderTracks(List<String> trackIds) {
    return _database.reorderLikedTracks(trackIds);
  }
}
