import '../server/music_server_client.dart';
import '../server/secure_server_profile_store.dart';
import 'album.dart';
import 'album_detail.dart';
import 'library_search_result.dart';

class MusicLibraryRepository {
  MusicLibraryRepository({
    this.profileStore = const SecureServerProfileStore(),
    MusicServerClient? client,
  }) : _client = client ?? MusicServerClient();

  final SecureServerProfileStore profileStore;
  final MusicServerClient _client;

  Future<List<Album>> getAlbums() async {
    final profile = await _requireProfile();
    return _client.getAlbums(profile);
  }

  Future<AlbumDetail> getAlbum(String albumId) async {
    final profile = await _requireProfile();
    return _client.getAlbum(profile, albumId);
  }

  Future<LibrarySearchResult> search(String query) async {
    final profile = await _requireProfile();
    return _client.search(profile, query);
  }

  Future<SavedServerProfile> _requireProfile() async {
    final profile = await profileStore.load().timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );

    if (profile == null) {
      throw const MusicLibraryException(
        'Connect to your server in Settings first.',
      );
    }

    if (profile.password.isEmpty) {
      throw const MusicLibraryException(
        'Saved credentials do not include a password. Reconnect in Settings.',
      );
    }

    return profile;
  }
}

class MusicLibraryException implements Exception {
  const MusicLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}
