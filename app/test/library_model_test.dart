import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/core/downloads/download_database.dart';
import 'package:app/core/downloads/download_repository.dart';
import 'package:app/core/downloads/downloaded_track.dart';
import 'package:app/core/exports/music_exporter.dart';
import 'package:app/core/library/album.dart';
import 'package:app/core/library/album_detail.dart';
import 'package:app/core/library/library_search_result.dart';
import 'package:app/core/library/track.dart';
import 'package:app/core/likes/liked_repository.dart';
import 'package:app/core/player/playback_preferences.dart';
import 'package:app/core/playlists/playlist_repository.dart';
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

  test('parses queued download state', () {
    final download = DownloadedTrack.fromJson(const {
      'trackId': 'track-1',
      'title': 'Sonne',
      'artist': 'Rammstein',
      'trackNumber': 3,
      'durationSeconds': 272,
      'localPath': '/tmp/Sonne.flac',
      'state': 'queued',
      'updatedAt': '2026-05-16T12:00:00.000',
    });

    expect(download.state, DownloadState.queued);
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

  test('repairs interrupted downloads back to queued', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() {
      SharedPreferencesAsyncPlatform.instance = null;
    });

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
        localPath: '/tmp/Sonne.flac',
        state: DownloadState.downloading,
        updatedAt: DateTime(2026, 5, 16),
      ),
    ]);

    final repairResult = await repository.repairDownloads();

    expect(repairResult.tracks.single.state, DownloadState.queued);
    expect((await repository.loadTracks()).single.state, DownloadState.queued);
  });

  test('moves downloaded files and metadata to a new folder', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() {
      SharedPreferencesAsyncPlatform.instance = null;
    });

    final tempRoot = await Directory.systemTemp.createTemp('nekofm_move_test_');
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final oldAlbumDirectory = Directory('${tempRoot.path}/old/Artist/Album');
    await oldAlbumDirectory.create(recursive: true);
    final oldAudioFile = File('${oldAlbumDirectory.path}/01 - Song - t1.flac');
    final oldCoverFile = File('${oldAlbumDirectory.path}/cover.jpg');
    await oldAudioFile.writeAsBytes([1, 2, 3, 4]);
    await oldCoverFile.writeAsBytes([5, 6, 7]);

    final database = DownloadDatabase(database: sqlite3.openInMemory());
    addTearDown(database.close);
    final repository = DownloadRepository(
      preferences: SharedPreferencesAsync(),
      database: database,
    );
    await repository.saveTracks([
      DownloadedTrack(
        trackId: 't1',
        title: 'Song',
        artist: 'Artist',
        trackNumber: 1,
        durationSeconds: 120,
        localPath: oldAudioFile.path,
        state: DownloadState.complete,
        updatedAt: DateTime(2026, 5, 16),
        albumName: 'Album',
        suffix: 'flac',
        bytes: 4,
        localCoverPath: oldCoverFile.path,
      ),
    ]);

    final result = await repository.moveDownloadsToFolder(
      Directory('${tempRoot.path}/new'),
    );
    final movedTrack = (await repository.loadTracks()).single;

    expect(result.movedAudioCount, 1);
    expect(result.movedCoverCount, 1);
    expect(result.skippedCount, 0);
    expect(movedTrack.localPath, contains('/new/Artist/Album/'));
    expect(movedTrack.localCoverPath, contains('/new/Artist/Album/cover.jpg'));
    expect(await File(movedTrack.localPath).readAsBytes(), [1, 2, 3, 4]);
    expect(await File(movedTrack.localCoverPath!).readAsBytes(), [5, 6, 7]);
    expect(await oldAudioFile.exists(), isFalse);
    expect(await oldCoverFile.exists(), isFalse);
  });

  test('exports downloaded tracks with relative m3u playlist paths', () async {
    final tempRoot = await Directory.systemTemp.createTemp('nekofm_export_');
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final sourceDirectory = Directory('${tempRoot.path}/source');
    await sourceDirectory.create(recursive: true);
    final audioFile = File('${sourceDirectory.path}/song.flac');
    final coverFile = File('${sourceDirectory.path}/cover.jpg');
    await audioFile.writeAsBytes([1, 2, 3, 4]);
    await coverFile.writeAsBytes([5, 6, 7]);

    final exporter = const MusicExporter();
    final targetRoot = Directory('${tempRoot.path}/export');
    final result = await exporter.exportDownloads(
      targetRoot: targetRoot,
      downloads: [
        DownloadedTrack(
          trackId: 'track-1',
          title: 'First Song',
          artist: 'Test Artist',
          trackNumber: 1,
          durationSeconds: 123,
          localPath: audioFile.path,
          state: DownloadState.complete,
          updatedAt: DateTime(2026, 5, 17),
          albumName: 'Test Album',
          suffix: 'flac',
          bytes: 4,
          localCoverPath: coverFile.path,
        ),
      ],
    );

    final exportedAudio = File(
      '${targetRoot.path}/Test_Artist/Test_Album/01_-_First_Song.flac',
    );
    final exportedCover = File(
      '${targetRoot.path}/Test_Artist/Test_Album/cover.jpg',
    );
    final playlist = File(result.playlistPath);
    final playlistText = await playlist.readAsString();

    expect(result.exportedTrackCount, 1);
    expect(result.copiedCoverCount, 1);
    expect(result.skippedTrackCount, 0);
    expect(result.collisionCount, 0);
    expect(await exportedAudio.readAsBytes(), [1, 2, 3, 4]);
    expect(await exportedCover.readAsBytes(), [5, 6, 7]);
    expect(playlistText, contains('#EXTM3U'));
    expect(playlistText, contains('#EXTINF:123,Test Artist - First Song'));
    expect(
      playlistText,
      contains('Test_Artist/Test_Album/01_-_First_Song.flac'),
    );
    expect(playlistText, isNot(contains(targetRoot.path)));
  });

  test('exports liked m3u in supplied playlist order', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'nekofm_liked_export_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final sourceDirectory = Directory('${tempRoot.path}/source');
    await sourceDirectory.create(recursive: true);
    final firstAudio = File('${sourceDirectory.path}/z.flac');
    final secondAudio = File('${sourceDirectory.path}/a.flac');
    await firstAudio.writeAsBytes([1]);
    await secondAudio.writeAsBytes([2]);

    final result = await const MusicExporter().exportDownloads(
      targetRoot: Directory('${tempRoot.path}/export'),
      playlistName: 'Liked',
      preserveOrder: true,
      downloads: [
        DownloadedTrack(
          trackId: 'z',
          title: 'Z Song',
          artist: 'Later Artist',
          trackNumber: 1,
          durationSeconds: 10,
          localPath: firstAudio.path,
          state: DownloadState.complete,
          updatedAt: DateTime(2026, 5, 17),
          albumName: 'Album',
          suffix: 'flac',
          bytes: 1,
        ),
        DownloadedTrack(
          trackId: 'a',
          title: 'A Song',
          artist: 'Earlier Artist',
          trackNumber: 1,
          durationSeconds: 10,
          localPath: secondAudio.path,
          state: DownloadState.complete,
          updatedAt: DateTime(2026, 5, 17),
          albumName: 'Album',
          suffix: 'flac',
          bytes: 1,
        ),
      ],
    );

    final playlistText = await File(result.playlistPath).readAsString();
    final firstIndex = playlistText.indexOf(
      'Later_Artist/Album/01_-_Z_Song.flac',
    );
    final secondIndex = playlistText.indexOf(
      'Earlier_Artist/Album/01_-_A_Song.flac',
    );

    expect(result.playlistPath, endsWith('/Liked.m3u'));
    expect(firstIndex, greaterThanOrEqualTo(0));
    expect(secondIndex, greaterThanOrEqualTo(0));
    expect(firstIndex, lessThan(secondIndex));
  });

  test(
    'selection export copies local tracks and downloads missing playlist tracks',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'nekofm_selection_export_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final sourceDirectory = Directory('${tempRoot.path}/source');
      await sourceDirectory.create(recursive: true);
      final localAudio = File('${sourceDirectory.path}/local.flac');
      final localCover = File('${sourceDirectory.path}/cover.jpg');
      await localAudio.writeAsBytes([1, 2, 3]);
      await localCover.writeAsBytes([7, 8, 9]);

      final localTrack = Track(
        id: 'local-track',
        title: 'Local Song',
        artist: 'Artist',
        trackNumber: 1,
        durationSeconds: 11,
        albumName: 'Album',
        suffix: 'flac',
      );
      final remoteTrack = Track(
        id: 'remote-track',
        title: 'Remote Song',
        artist: 'Artist',
        trackNumber: 2,
        durationSeconds: 22,
        albumName: 'Album',
        suffix: 'flac',
        coverArtUri: Uri.parse('http://example.test/cover.jpg'),
      );
      final missingTrack = Track(
        id: 'missing-track',
        title: 'Missing Song',
        artist: 'Artist',
        trackNumber: 3,
        durationSeconds: 33,
        albumName: 'Album',
        suffix: 'flac',
      );

      final targetRoot = Directory('${tempRoot.path}/export');
      final result = await const MusicExporter().exportSelection(
        targetRoot: targetRoot,
        tracks: [
          MusicExportTrackRequest(
            track: localTrack,
            localDownload: DownloadedTrack(
              trackId: 'local-track',
              title: 'Local Song',
              artist: 'Artist',
              trackNumber: 1,
              durationSeconds: 11,
              localPath: localAudio.path,
              state: DownloadState.complete,
              updatedAt: DateTime(2026, 5, 17),
              albumName: 'Album',
              suffix: 'flac',
              bytes: 3,
              localCoverPath: localCover.path,
            ),
          ),
        ],
        playlists: [
          MusicExportPlaylistRequest(
            name: 'Road',
            tracks: [
              MusicExportTrackRequest(track: localTrack),
              MusicExportTrackRequest(track: remoteTrack),
              MusicExportTrackRequest(track: remoteTrack),
              MusicExportTrackRequest(track: missingTrack),
            ],
          ),
        ],
        downloadRemoteTrack: (request, destination) async {
          if (request.track.id != 'remote-track') {
            return false;
          }
          await destination.writeAsBytes([4, 5, 6]);
          return true;
        },
        downloadRemoteCover: (request, destination) async {
          await destination.writeAsBytes([10, 11]);
          return true;
        },
      );

      final localExport = File(
        '${targetRoot.path}/Music/Artist/Album/01_-_Local_Song.flac',
      );
      final remoteExport = File(
        '${targetRoot.path}/Music/Artist/Album/02_-_Remote_Song.flac',
      );
      final playlistText = await File(
        '${targetRoot.path}/Playlists/Road.m3u',
      ).readAsString();

      expect(result.exportedTrackCount, 2);
      expect(result.copiedTrackCount, 1);
      expect(result.downloadedTrackCount, 1);
      expect(result.skippedTrackCount, 1);
      expect(result.playlistCount, 1);
      expect(result.playlistEntryCount, 3);
      expect(result.skippedPlaylistEntryCount, 1);
      expect(await localExport.readAsBytes(), [1, 2, 3]);
      expect(await remoteExport.readAsBytes(), [4, 5, 6]);
      expect(playlistText, contains('Music/Artist/Album/01_-_Local_Song.flac'));
      expect(
        playlistText,
        contains('Music/Artist/Album/02_-_Remote_Song.flac'),
      );
      expect('Remote_Song'.allMatches(playlistText).length, 2);
      expect(playlistText, isNot(contains('Missing_Song')));
    },
  );

  test(
    'export avoids overwriting tracks with matching visible metadata',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'nekofm_export_collision_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final sourceDirectory = Directory('${tempRoot.path}/source');
      await sourceDirectory.create(recursive: true);
      final firstAudio = File('${sourceDirectory.path}/first.flac');
      final secondAudio = File('${sourceDirectory.path}/second.flac');
      await firstAudio.writeAsBytes([1, 1, 1]);
      await secondAudio.writeAsBytes([2, 2, 2]);

      final targetRoot = Directory('${tempRoot.path}/export');
      final result = await const MusicExporter().exportDownloads(
        targetRoot: targetRoot,
        downloads: [
          DownloadedTrack(
            trackId: 'first-id',
            title: 'Same Song',
            artist: 'Same Artist',
            trackNumber: 1,
            durationSeconds: 10,
            localPath: firstAudio.path,
            state: DownloadState.complete,
            updatedAt: DateTime(2026, 5, 17),
            albumName: 'Same Album',
            suffix: 'flac',
            bytes: 3,
          ),
          DownloadedTrack(
            trackId: 'second-id',
            title: 'Same Song',
            artist: 'Same Artist',
            trackNumber: 1,
            durationSeconds: 10,
            localPath: secondAudio.path,
            state: DownloadState.complete,
            updatedAt: DateTime(2026, 5, 17),
            albumName: 'Same Album',
            suffix: 'flac',
            bytes: 3,
          ),
        ],
      );

      final preferredFile = File(
        '${targetRoot.path}/Same_Artist/Same_Album/01_-_Same_Song.flac',
      );
      final collisionFile = File(
        '${targetRoot.path}/Same_Artist/Same_Album/01_-_Same_Song_-_second-id.flac',
      );
      final playlistText = await File(result.playlistPath).readAsString();

      expect(result.exportedTrackCount, 2);
      expect(result.collisionCount, 1);
      expect(await preferredFile.readAsBytes(), [1, 1, 1]);
      expect(await collisionFile.readAsBytes(), [2, 2, 2]);
      expect(playlistText, contains('01_-_Same_Song.flac'));
      expect(playlistText, contains('01_-_Same_Song_-_second-id.flac'));
    },
  );

  test(
    'library export includes liked m3u when liked downloads exist',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'nekofm_library_export_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final sourceDirectory = Directory('${tempRoot.path}/source');
      await sourceDirectory.create(recursive: true);
      final likedAudio = File('${sourceDirectory.path}/liked.flac');
      final otherAudio = File('${sourceDirectory.path}/other.flac');
      await likedAudio.writeAsBytes([1]);
      await otherAudio.writeAsBytes([2]);

      final result = await const MusicExporter().exportLibrary(
        targetRoot: Directory('${tempRoot.path}/export'),
        likedTrackIds: const ['liked-track'],
        downloads: [
          DownloadedTrack(
            trackId: 'other-track',
            title: 'Other Song',
            artist: 'Artist',
            trackNumber: 1,
            durationSeconds: 10,
            localPath: otherAudio.path,
            state: DownloadState.complete,
            updatedAt: DateTime(2026, 5, 17),
            albumName: 'Album',
            suffix: 'flac',
            bytes: 1,
          ),
          DownloadedTrack(
            trackId: 'liked-track',
            title: 'Liked Song',
            artist: 'Artist',
            trackNumber: 2,
            durationSeconds: 10,
            localPath: likedAudio.path,
            state: DownloadState.complete,
            updatedAt: DateTime(2026, 5, 17),
            albumName: 'Album',
            suffix: 'flac',
            bytes: 1,
          ),
        ],
      );

      final allPlaylistText = await File(
        result.allDownloads.playlistPath,
      ).readAsString();
      final likedPlaylistText = await File(
        result.liked!.playlistPath,
      ).readAsString();

      expect(result.allDownloads.exportedTrackCount, 2);
      expect(result.liked?.exportedTrackCount, 1);
      expect(result.liked?.playlistPath, endsWith('/Liked.m3u'));
      expect(allPlaylistText, contains('Other_Song.flac'));
      expect(allPlaylistText, contains('Liked_Song.flac'));
      expect(likedPlaylistText, contains('Liked_Song.flac'));
      expect(likedPlaylistText, isNot(contains('Other_Song.flac')));
    },
  );

  test('clean export removes only previous NekoFM manifest files', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'nekofm_export_clean_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final sourceDirectory = Directory('${tempRoot.path}/source');
    await sourceDirectory.create(recursive: true);
    final oldAudio = File('${sourceDirectory.path}/old.flac');
    final newAudio = File('${sourceDirectory.path}/new.flac');
    await oldAudio.writeAsBytes([1]);
    await newAudio.writeAsBytes([2]);

    final targetRoot = Directory('${tempRoot.path}/export');
    final exporter = const MusicExporter();
    await exporter.exportLibrary(
      targetRoot: targetRoot,
      downloads: [
        DownloadedTrack(
          trackId: 'old',
          title: 'Old Song',
          artist: 'Artist',
          trackNumber: 1,
          durationSeconds: 10,
          localPath: oldAudio.path,
          state: DownloadState.complete,
          updatedAt: DateTime(2026, 5, 17),
          albumName: 'Album',
          suffix: 'flac',
          bytes: 1,
        ),
      ],
    );
    final unrelatedFile = File('${targetRoot.path}/do-not-touch.txt');
    await unrelatedFile.writeAsString('mine');

    expect(await exporter.hasExistingExport(targetRoot), isTrue);

    await exporter.exportLibrary(
      targetRoot: targetRoot,
      cleanFirst: true,
      downloads: [
        DownloadedTrack(
          trackId: 'new',
          title: 'New Song',
          artist: 'Artist',
          trackNumber: 2,
          durationSeconds: 10,
          localPath: newAudio.path,
          state: DownloadState.complete,
          updatedAt: DateTime(2026, 5, 17),
          albumName: 'Album',
          suffix: 'flac',
          bytes: 1,
        ),
      ],
    );

    final oldExport = File(
      '${targetRoot.path}/Artist/Album/01_-_Old_Song.flac',
    );
    final newExport = File(
      '${targetRoot.path}/Artist/Album/02_-_New_Song.flac',
    );
    final manifest = File(
      '${targetRoot.path}/${MusicExporter.manifestFilename}',
    );

    expect(await oldExport.exists(), isFalse);
    expect(await newExport.readAsBytes(), [2]);
    expect(await unrelatedFile.readAsString(), 'mine');
    expect(await manifest.exists(), isTrue);
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

    final track = Track(
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

  test('reorders liked tracks in sqlite', () async {
    final database = DownloadDatabase(database: sqlite3.openInMemory());
    addTearDown(database.close);
    final repository = LikedRepository(database: database);

    await repository.likeTrack(
      const Track(
        id: 'first',
        title: 'First',
        artist: 'Artist',
        trackNumber: 1,
        durationSeconds: 10,
      ),
    );
    await repository.likeTrack(
      const Track(
        id: 'second',
        title: 'Second',
        artist: 'Artist',
        trackNumber: 2,
        durationSeconds: 10,
      ),
    );
    await repository.likeTrack(
      const Track(
        id: 'third',
        title: 'Third',
        artist: 'Artist',
        trackNumber: 3,
        durationSeconds: 10,
      ),
    );

    await repository.reorderTracks(const ['third', 'first', 'second']);
    final reordered = await repository.loadTracks();

    expect(
      [for (final track in reordered) track.trackId],
      ['third', 'first', 'second'],
    );
    expect([for (final track in reordered) track.position], [0, 1, 2]);
  });

  test('persists custom playlists and tracks in sqlite', () async {
    final database = DownloadDatabase(database: sqlite3.openInMemory());
    addTearDown(database.close);
    final repository = PlaylistRepository(database: database);

    final track = Track(
      id: 'track-1',
      title: 'Sonne',
      artist: 'Rammstein',
      trackNumber: 3,
      durationSeconds: 272,
      albumId: 'album-1',
      albumName: 'Mutter',
      coverArtUri: Uri.parse('https://example.test/cover.jpg'),
      suffix: 'flac',
    );

    final playlist = await repository.createPlaylist('Driving');
    await repository.addTrack(playlist.id, track);
    await repository.addTrack(playlist.id, track);

    final playlists = await repository.loadPlaylists();
    final tracks = await repository.loadTracks(playlist.id);

    expect(playlists.single.name, 'Driving');
    expect(playlists.single.trackCount, 2);
    expect(tracks, hasLength(2));
    expect(tracks.first.toTrack().title, 'Sonne');
    expect(tracks.first.position, 0);
    expect(tracks.last.position, 1);
    expect(tracks.first.entryId, isNot(tracks.last.entryId));
    expect(tracks.first.coverArtUri, 'https://example.test/cover.jpg');

    await repository.reorderTracks(playlist.id, [
      tracks.last.entryId,
      tracks.first.entryId,
    ]);
    final reorderedTracks = await repository.loadTracks(playlist.id);
    expect(reorderedTracks.first.entryId, tracks.last.entryId);
    expect(reorderedTracks.last.entryId, tracks.first.entryId);
    expect(reorderedTracks.first.position, 0);
    expect(reorderedTracks.last.position, 1);

    await repository.renamePlaylist(playlist.id, 'Night Drive');
    final renamedPlaylists = await repository.loadPlaylists();
    expect(renamedPlaylists.single.name, 'Night Drive');
    expect(renamedPlaylists.single.trackCount, 2);
    expect(await repository.loadTracks(playlist.id), hasLength(2));

    await repository.removeEntry(playlist.id, tracks.first.entryId);
    expect(await repository.loadTracks(playlist.id), hasLength(1));

    await repository.deletePlaylist(playlist.id);
    expect(await repository.loadPlaylists(), isEmpty);
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
