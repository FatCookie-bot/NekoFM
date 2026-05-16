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
    return _database.upsertLikedTrack(LikedTrack.fromTrack(track));
  }

  Future<void> unlikeTrack(String trackId) {
    return _database.deleteLikedTrack(trackId);
  }

  Future<void> toggleTrack(Track track) async {
    if (await isLiked(track.id)) {
      await unlikeTrack(track.id);
      return;
    }

    await likeTrack(track);
  }
}
