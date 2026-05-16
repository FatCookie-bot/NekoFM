import 'package:app/core/library/album.dart';
import 'package:app/core/library/album_detail.dart';
import 'package:app/core/library/library_search_result.dart';
import 'package:app/core/player/playback_preferences.dart';
import 'package:app/core/server/music_server_client.dart';
import 'package:app/core/server/secure_server_profile_store.dart';
import 'package:app/features/player/playback_formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Subsonic album summary', () {
    final album = Album.fromSubsonic(const {
      'id': 'album-1',
      'name': 'Blood Sugar Sex Magik',
      'artist': 'Red Hot Chili Peppers',
      'songCount': 17,
      'duration': 4432,
      'coverArt': 'cover-1',
      'year': 1991,
    });

    expect(album.id, 'album-1');
    expect(album.name, 'Blood Sugar Sex Magik');
    expect(album.artist, 'Red Hot Chili Peppers');
    expect(album.songCount, 17);
    expect(album.durationSeconds, 4432);
    expect(album.coverArtId, 'cover-1');
    expect(album.year, 1991);
  });

  test('parses Subsonic album detail tracks', () {
    final detail = AlbumDetail.fromSubsonic(const {
      'id': 'album-1',
      'name': 'Slipknot',
      'artist': 'Slipknot',
      'songCount': 2,
      'duration': 430,
      'song': [
        {
          'id': 'track-1',
          'title': '742617000027',
          'artist': 'Slipknot',
          'track': 1,
          'duration': 36,
          'suffix': 'flac',
        },
        {
          'id': 'track-2',
          'title': '(sic)',
          'artist': 'Slipknot',
          'track': 2,
          'duration': 199,
          'suffix': 'flac',
        },
      ],
    });

    expect(detail.album.name, 'Slipknot');
    expect(detail.tracks, hasLength(2));
    expect(detail.tracks.first.title, '742617000027');
    expect(detail.tracks.last.trackNumber, 2);
  });

  test('parses Subsonic search albums and tracks', () {
    final result = LibrarySearchResult.fromSubsonic(const {
      'album': [
        {
          'id': 'album-1',
          'name': 'Mutter',
          'artist': 'Rammstein',
          'songCount': 11,
          'duration': 2700,
          'coverArt': 'cover-album-1',
        },
      ],
      'song': [
        {
          'id': 'track-1',
          'title': 'Sonne',
          'artist': 'Rammstein',
          'album': 'Mutter',
          'albumId': 'album-1',
          'track': 3,
          'duration': 272,
          'coverArt': 'cover-album-1',
        },
      ],
    });

    expect(result.albums, hasLength(1));
    expect(result.albums.first.coverArtId, 'cover-album-1');
    expect(result.tracks, hasLength(1));
    expect(result.tracks.first.albumId, 'album-1');
    expect(result.tracks.first.albumName, 'Mutter');
    expect(result.tracks.first.coverArtId, 'cover-album-1');
  });

  test('parses Subsonic server scan status', () {
    final status = ServerScanResult.fromSubsonic(const {
      'scanning': true,
      'count': 49,
    });

    expect(status.isScanning, isTrue);
    expect(status.scannedCount, 49);
    expect(status.message, 'Server scan started. 49 items scanned so far.');
  });

  test('builds Subsonic stream URL for a track', () {
    final uri = MusicServerClient().streamUri(
      const SavedServerProfile(
        serverUrl: 'http://127.0.0.1:4533',
        username: 'user',
        password: 'password',
        rememberPassword: true,
      ),
      'track-1',
    );

    expect(uri.path, '/rest/stream.view');
    expect(uri.queryParameters['u'], 'user');
    expect(uri.queryParameters['id'], 'track-1');
    expect(uri.queryParameters['c'], 'NekoFM');
    expect(uri.queryParameters, containsPair('t', isNotEmpty));
    expect(uri.queryParameters, containsPair('s', isNotEmpty));
  });

  test('builds Subsonic cover art URL', () {
    final uri = MusicServerClient().coverArtUri(
      const SavedServerProfile(
        serverUrl: 'http://127.0.0.1:4533',
        username: 'user',
        password: 'password',
        rememberPassword: true,
      ),
      'cover-1',
      size: 256,
    );

    expect(uri?.path, '/rest/getCoverArt.view');
    expect(uri?.queryParameters['u'], 'user');
    expect(uri?.queryParameters['id'], 'cover-1');
    expect(uri?.queryParameters['size'], '256');
    expect(uri?.queryParameters, containsPair('t', isNotEmpty));
    expect(uri?.queryParameters, containsPair('s', isNotEmpty));
  });

  test('decides when back restarts the current track', () {
    const threshold = Duration(seconds: 3);

    expect(
      shouldRestartCurrentTrack(
        position: const Duration(seconds: 2),
        threshold: threshold,
      ),
      isFalse,
    );
    expect(
      shouldRestartCurrentTrack(
        position: const Duration(seconds: 3),
        threshold: threshold,
      ),
      isTrue,
    );
  });

  test('clamps previous track threshold preference', () {
    expect(
      PlaybackPreferences.thresholdFromSeconds(-1),
      PlaybackPreferences.minPreviousTrackThreshold,
    );
    expect(
      PlaybackPreferences.thresholdFromSeconds(99),
      PlaybackPreferences.maxPreviousTrackThreshold,
    );
  });

  test('formats playback durations', () {
    expect(formatPlaybackDuration(const Duration(seconds: 9)), '0:09');
    expect(
      formatPlaybackDuration(const Duration(minutes: 3, seconds: 5)),
      '3:05',
    );
    expect(
      formatPlaybackDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
