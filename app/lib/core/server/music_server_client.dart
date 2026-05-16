import 'package:dio/dio.dart';

import '../library/album.dart';
import '../library/album_detail.dart';
import '../library/library_search_result.dart';
import '../library/track.dart';
import 'secure_server_profile_store.dart';
import 'server_profile.dart';
import 'subsonic_auth.dart';

class MusicServerClient {
  MusicServerClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<ServerConnectionResult> testConnection(ServerProfile profile) async {
    final auth = SubsonicAuth.fromPassword(profile.password);
    final uri = profile.normalizedBaseUri.replace(
      path: _joinPath(profile.normalizedBaseUri.path, 'rest/ping.view'),
      queryParameters: {
        'u': profile.username,
        't': auth.token,
        's': auth.salt,
        'v': '1.16.1',
        'c': 'NekoFM',
        'f': 'json',
      },
    );

    try {
      final response = await _dio
          .getUri<Map<String, dynamic>>(
            uri,
            options: Options(
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              throw DioException.connectionTimeout(
                timeout: const Duration(seconds: 12),
                requestOptions: RequestOptions(path: uri.toString()),
              );
            },
          );
      final body = response.data;
      final subsonicResponse = body?['subsonic-response'];

      if (subsonicResponse is! Map<String, dynamic>) {
        return const ServerConnectionResult.failure(
          'The server did not return a Subsonic response.',
        );
      }

      if (subsonicResponse['status'] == 'ok') {
        return const ServerConnectionResult.success();
      }

      final error = subsonicResponse['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) {
          return ServerConnectionResult.failure(message);
        }
      }

      return const ServerConnectionResult.failure(
        'The server rejected the connection.',
      );
    } on DioException catch (error) {
      return ServerConnectionResult.failure(_formatDioError(error));
    } on FormatException catch (error) {
      return ServerConnectionResult.failure(error.message);
    } on Object catch (error) {
      return ServerConnectionResult.failure('Connection failed: $error');
    }
  }

  Future<List<Album>> getAlbums(SavedServerProfile savedProfile) async {
    final response = await _getSubsonic(
      savedProfile,
      'getAlbumList2.view',
      const {'type': 'alphabeticalByName', 'size': '500', 'offset': '0'},
    );
    final albumList = response['albumList2'];
    final albums = albumList is Map<String, dynamic>
        ? albumList['album']
        : null;

    if (albums is! List) {
      return const [];
    }

    return [
      for (final album in albums)
        if (album is Map<String, dynamic>)
          _attachCoverArtUri(savedProfile, Album.fromSubsonic(album)),
    ];
  }

  Future<AlbumDetail> getAlbum(
    SavedServerProfile savedProfile,
    String albumId,
  ) async {
    final response = await _getSubsonic(savedProfile, 'getAlbum.view', {
      'id': albumId,
    });
    final album = response['album'];

    if (album is! Map<String, dynamic>) {
      throw const MusicServerException('The server did not return an album.');
    }

    final detail = AlbumDetail.fromSubsonic(album);
    return AlbumDetail(
      album: _attachCoverArtUri(savedProfile, detail.album),
      tracks: detail.tracks,
    );
  }

  Future<LibrarySearchResult> search(
    SavedServerProfile savedProfile,
    String query,
  ) async {
    final response = await _getSubsonic(savedProfile, 'search3.view', {
      'query': query,
      'artistCount': '0',
      'albumCount': '20',
      'songCount': '50',
    });
    final result = LibrarySearchResult.fromSubsonic(
      response['searchResult3'] is Map<String, dynamic>
          ? response['searchResult3'] as Map<String, dynamic>
          : const {},
    );

    return LibrarySearchResult(
      albums: [
        for (final album in result.albums)
          _attachCoverArtUri(savedProfile, album),
      ],
      tracks: [
        for (final track in result.tracks)
          _attachTrackCoverArtUri(savedProfile, track),
      ],
    );
  }

  Future<ServerScanResult> startScan(SavedServerProfile savedProfile) async {
    final response = await _getSubsonic(savedProfile, 'startScan.view', const {
      'fullScan': 'false',
    });
    return ServerScanResult.fromSubsonic(response['scanStatus']);
  }

  Uri streamUri(SavedServerProfile savedProfile, String trackId) {
    final profile = savedProfile.toServerProfile();
    final auth = SubsonicAuth.fromPassword(profile.password);
    return profile.normalizedBaseUri.replace(
      path: _joinPath(profile.normalizedBaseUri.path, 'rest/stream.view'),
      queryParameters: {
        'u': profile.username,
        't': auth.token,
        's': auth.salt,
        'v': '1.16.1',
        'c': 'NekoFM',
        'id': trackId,
      },
    );
  }

  Uri? coverArtUri(
    SavedServerProfile savedProfile,
    String? coverArtId, {
    int size = 512,
  }) {
    if (coverArtId == null || coverArtId.isEmpty) {
      return null;
    }

    final profile = savedProfile.toServerProfile();
    final auth = SubsonicAuth.fromPassword(profile.password);
    return profile.normalizedBaseUri.replace(
      path: _joinPath(profile.normalizedBaseUri.path, 'rest/getCoverArt.view'),
      queryParameters: {
        'u': profile.username,
        't': auth.token,
        's': auth.salt,
        'v': '1.16.1',
        'c': 'NekoFM',
        'id': coverArtId,
        'size': size.toString(),
      },
    );
  }

  Album _attachCoverArtUri(SavedServerProfile savedProfile, Album album) {
    return album.copyWith(
      coverArtUri: coverArtUri(savedProfile, album.coverArtId),
    );
  }

  Track _attachTrackCoverArtUri(SavedServerProfile savedProfile, Track track) {
    return track.copyWith(
      coverArtUri: coverArtUri(savedProfile, track.coverArtId),
    );
  }

  Future<Map<String, dynamic>> _getSubsonic(
    SavedServerProfile savedProfile,
    String endpoint,
    Map<String, String> queryParameters,
  ) async {
    final profile = savedProfile.toServerProfile();
    final auth = SubsonicAuth.fromPassword(profile.password);
    final uri = profile.normalizedBaseUri.replace(
      path: _joinPath(profile.normalizedBaseUri.path, 'rest/$endpoint'),
      queryParameters: {
        'u': profile.username,
        't': auth.token,
        's': auth.salt,
        'v': '1.16.1',
        'c': 'NekoFM',
        'f': 'json',
        ...queryParameters,
      },
    );

    try {
      final response = await _dio
          .getUri<Map<String, dynamic>>(
            uri,
            options: Options(
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          )
          .timeout(const Duration(seconds: 15));
      final body = response.data;
      final subsonicResponse = body?['subsonic-response'];

      if (subsonicResponse is! Map<String, dynamic>) {
        throw const MusicServerException(
          'The server did not return a Subsonic response.',
        );
      }

      if (subsonicResponse['status'] == 'ok') {
        return subsonicResponse;
      }

      throw MusicServerException(_extractSubsonicError(subsonicResponse));
    } on DioException catch (error) {
      throw MusicServerException(_formatDioError(error));
    } on MusicServerException {
      rethrow;
    } on FormatException catch (error) {
      throw MusicServerException(error.message);
    } on Object catch (error) {
      throw MusicServerException('Server request failed: $error');
    }
  }

  static String _joinPath(String basePath, String childPath) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase/$childPath';
  }

  static String _extractSubsonicError(Map<String, dynamic> response) {
    final error = response['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }

    return 'The server rejected the request.';
  }

  static String _formatDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return 'Server responded with HTTP $statusCode.';
    }

    return switch (error.type) {
      DioExceptionType.connectionTimeout => 'Connection timed out.',
      DioExceptionType.sendTimeout => 'Request timed out while sending.',
      DioExceptionType.receiveTimeout => 'Server response timed out.',
      DioExceptionType.badCertificate => 'The server certificate is invalid.',
      DioExceptionType.connectionError =>
        'Could not reach the server. Check the URL and network.',
      _ => error.message ?? 'Connection failed.',
    };
  }
}

class MusicServerException implements Exception {
  const MusicServerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ServerConnectionResult {
  const ServerConnectionResult._({
    required this.isSuccess,
    required this.message,
  });

  const ServerConnectionResult.success([String message = 'Connection works.'])
    : this._(isSuccess: true, message: message);

  const ServerConnectionResult.failure(String message)
    : this._(isSuccess: false, message: message);

  final bool isSuccess;
  final String message;
}

class ServerScanResult {
  const ServerScanResult({
    required this.isScanning,
    required this.scannedCount,
  });

  final bool isScanning;
  final int scannedCount;

  factory ServerScanResult.fromSubsonic(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const ServerScanResult(isScanning: false, scannedCount: 0);
    }

    return ServerScanResult(
      isScanning: value['scanning'] == true,
      scannedCount: _parseCount(value['count']),
    );
  }

  String get message {
    if (isScanning) {
      if (scannedCount > 0) {
        return 'Server scan started. $scannedCount items scanned so far.';
      }

      return 'Server scan started.';
    }

    if (scannedCount > 0) {
      return 'Server scan finished. $scannedCount items checked.';
    }

    return 'Server scan request was accepted.';
  }

  static int _parseCount(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }
}
