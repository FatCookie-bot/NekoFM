import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/core/downloads/download_database.dart';
import 'package:app/core/downloads/download_repository.dart';
import 'package:app/core/downloads/downloaded_track.dart';
import 'package:app/core/library/album.dart';
import 'package:app/core/library/album_detail.dart';
import 'package:app/core/library/library_search_result.dart';
import 'package:app/core/library/track.dart';
import 'package:app/core/likes/liked_repository.dart';
import 'package:app/core/player/playback_preferences.dart';
import 'package:app/core/server/music_server_client.dart';
import 'package:app/core/server/secure_server_profile_store.dart';
import 'package:app/features/player/playback_formatting.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

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

  test('attaches cover art URLs to album detail tracks', () async {
    final dio = Dio()
      ..httpClientAdapter = _JsonAdapter({
        'subsonic-response': {
          'status': 'ok',
          'album': {
            'id': 'album-1',
            'name': 'Mutter',
            'artist': 'Rammstein',
            'songCount': 1,
            'duration': 272,
            'coverArt': 'cover-album-1',
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
          },
        },
      });

    final fixedDetail = await MusicServerClient(dio: dio).getAlbum(
      const SavedServerProfile(
        serverUrl: 'http://127.0.0.1:4533',
        username: 'user',
        password: 'password',
        rememberPassword: true,
      ),
      'album-1',
    );

    expect(
      fixedDetail.tracks.first.coverArtUri?.path,
      '/rest/getCoverArt.view',
    );
    expect(
      fixedDetail.tracks.first.coverArtUri?.queryParameters['id'],
      'cover-album-1',
    );
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

  test('builds Subsonic download URL for a track', () {
    final uri = MusicServerClient().downloadUri(
      const SavedServerProfile(
        serverUrl: 'http://127.0.0.1:4533',
        username: 'user',
        password: 'password',
        rememberPassword: true,
      ),
      'track-1',
    );

    expect(uri.path, '/rest/download.view');
    expect(uri.queryParameters['u'], 'user');
    expect(uri.queryParameters['id'], 'track-1');
    expect(uri.queryParameters['c'], 'NekoFM');
    expect(uri.queryParameters, containsPair('t', isNotEmpty));
    expect(uri.queryParameters, containsPair('s', isNotEmpty));
  });

  test('sanitizes download filenames', () {
    expect(
      DownloadRepository.safeFilenameForTest('../Album:Track?.flac'),
      '.._Album_Track_.flac',
    );
    expect(DownloadRepository.safeFilenameForTest(''), 'track');
  });

  test('sanitizes album download folder names', () {
    expect(
      DownloadRepository.albumFolderNameForTest(
        artist: 'Red Hot Chili Peppers',
        albumName: 'Blood Sugar Sex Magik',
      ),
      'Red_Hot_Chili_Peppers/Blood_Sugar_Sex_Magik',
    );
  });

  test('parses downloaded track offline metadata', () {
    final download = DownloadedTrack.fromJson(const {
      'trackId': 'track-1',
      'title': 'Sonne',
      'artist': 'Rammstein',
      'trackNumber': 3,
      'durationSeconds': 272,
      'localPath': '/tmp/Sonne.flac',
      'localCoverPath': '/tmp/Sonne.cover',
      'state': 'complete',
      'updatedAt': '2026-05-16T12:00:00.000',
      'albumId': 'album-1',
      'albumName': 'Mutter',
      'suffix': 'flac',
    });

    final track = download.toTrack();

    expect(download.localCoverPath, '/tmp/Sonne.cover');
    expect(track.trackNumber, 3);
    expect(track.albumName, 'Mutter');
    expect(track.coverArtUri?.isScheme('file'), isTrue);
  });

  test('can clear stale downloaded cover metadata', () {
    final download = DownloadedTrack.fromJson(const {
      'trackId': 'track-1',
      'title': 'Sonne',
      'artist': 'Rammstein',
      'trackNumber': 3,
      'durationSeconds': 272,
      'localPath': '/tmp/Sonne.flac',
      'localCoverPath': '/tmp/cover.jpg',
      'state': 'complete',
      'updatedAt': '2026-05-16T12:00:00.000',
    });

    expect(download.localCoverPath, '/tmp/cover.jpg');
    expect(download.copyWith(clearLocalCoverPath: true).localCoverPath, isNull);
  });

  test('recovers album cover beside downloaded audio', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final directory = await Directory.systemTemp.createTemp('nekofm-test-');
    addTearDown(() async {
      SharedPreferencesAsyncPlatform.instance = null;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final audioFile = File('${directory.path}/01 - Sonne.flac');
    final coverFile = File('${directory.path}/cover.jpg');
    await audioFile.writeAsBytes([1, 2, 3, 4]);
    await coverFile.writeAsBytes([5, 6, 7, 8]);
    final database = DownloadDatabase(database: sqlite3.openInMemory());
    addTearDown(database.close);
    final repository = DownloadRepository(
      preferences: SharedPreferencesAsync(),
      database: database,
    );
    await repository.saveTracks([
      DownloadedTrack(
        trackId: 'track-1',
        title: 'Sonne',
        artist: 'Rammstein',
        trackNumber: 3,
        durationSeconds: 272,
        localPath: audioFile.path,
        state: DownloadState.complete,
        updatedAt: DateTime(2026, 5, 16),
        albumId: 'album-1',
        albumName: 'Mutter',
        suffix: 'flac',
        bytes: 4,
      ),
    ]);

    final repairResult = await repository.repairDownloads();
    final details = await repository.loadDownloadedAlbumDetails();

    expect(repairResult.recoveredCoverCount, 1);
    expect(repairResult.tracks.single.localCoverPath, coverFile.path);
    expect(details.single.album.coverArtUri, Uri.file(coverFile.path));
    expect(details.single.tracks.single.coverArtUri, Uri.file(coverFile.path));
  });

  test('searches downloaded album metadata offline', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final directory = await Directory.systemTemp.createTemp('nekofm-test-');
    addTearDown(() async {
      SharedPreferencesAsyncPlatform.instance = null;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final audioFile = File('${directory.path}/01 - Sonne.flac');
    await audioFile.writeAsBytes([1, 2, 3, 4]);
    final database = DownloadDatabase(database: sqlite3.openInMemory());
    addTearDown(database.close);
    final repository = DownloadRepository(
      preferences: SharedPreferencesAsync(),
      database: database,
    );
    await repository.saveTracks([
      DownloadedTrack(
        trackId: 'track-1',
        title: 'Sonne',
        artist: 'Rammstein',
        trackNumber: 3,
        durationSeconds: 272,
        localPath: audioFile.path,
        state: DownloadState.complete,
        updatedAt: DateTime(2026, 5, 16),
        albumId: 'album-1',
        albumName: 'Mutter',
        suffix: 'flac',
        bytes: 4,
      ),
    ]);

    final result = await repository.searchDownloaded('mutter');

    expect(result.albums.single.name, 'Mutter');
    expect(result.tracks.single.title, 'Sonne');
  });

  test('migrates legacy downloaded metadata into sqlite', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() {
      SharedPreferencesAsyncPlatform.instance = null;
    });

    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'downloads.tracks.v1',
      jsonEncode([
        {
          'trackId': 'track-1',
          'title': 'Sonne',
          'artist': 'Rammstein',
          'trackNumber': 3,
          'durationSeconds': 272,
          'localPath': '/tmp/Sonne.flac',
          'state': 'complete',
          'updatedAt': '2026-05-16T12:00:00.000',
          'albumId': 'album-1',
          'albumName': 'Mutter',
          'suffix': 'flac',
          'bytes': 4,
        },
      ]),
    );
    final database = DownloadDatabase(database: sqlite3.openInMemory());
    addTearDown(database.close);
    final repository = DownloadRepository(
      preferences: preferences,
      database: database,
    );

    final tracks = await repository.loadTracks();
    final byId = await repository.trackById('track-1');
    final migrated = await database.loadTracks();

    expect(tracks.single.trackId, 'track-1');
    expect(byId?.title, 'Sonne');
    expect(migrated.single.albumName, 'Mutter');
    expect(await preferences.getBool('downloads.sqlite_migrated.v1'), isTrue);
  });

  test('persists liked tracks in sqlite', () async {
    final database = DownloadDatabase(database: sqlite3.openInMemory());
    addTearDown(database.close);
    final repository = LikedRepository(database: database);

    const track = Track(
      id: 'track-1',
      title: 'Sonne',
      artist: 'Rammstein',
      trackNumber: 3,
      durationSeconds: 272,
      albumId: 'album-1',
      albumName: 'Mutter',
      suffix: 'flac',
    );

    await repository.likeTrack(track);
    expect(await repository.isLiked(track.id), isTrue);
    expect((await repository.loadTracks()).single.toTrack().title, 'Sonne');

    await repository.unlikeTrack(track.id);
    expect(await repository.isLiked(track.id), isFalse);
    expect(await repository.loadTracks(), isEmpty);
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

class _JsonAdapter implements HttpClientAdapter {
  const _JsonAdapter(this.body);

  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
