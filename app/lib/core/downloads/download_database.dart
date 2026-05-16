import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../likes/liked_track.dart';
import 'downloaded_track.dart';

class DownloadDatabase {
  DownloadDatabase({String? path, Database? database})
    : _path = path,
      _database = database;

  final String? _path;
  Database? _database;
  bool _isInitialized = false;

  Future<List<DownloadedTrack>> loadTracks() async {
    final db = await _open();
    final result = db.select('''
      SELECT *
      FROM downloaded_tracks
      ORDER BY updated_at DESC
      ''');
    return [for (final row in result) _trackFromRow(row)];
  }

  Future<DownloadedTrack?> trackById(String trackId) async {
    final db = await _open();
    final result = db.select(
      '''
      SELECT *
      FROM downloaded_tracks
      WHERE track_id = ?
      LIMIT 1
      ''',
      [trackId],
    );
    if (result.isEmpty) {
      return null;
    }

    return _trackFromRow(result.first);
  }

  Future<bool> isEmpty() async {
    final db = await _open();
    final result = db.select('SELECT COUNT(*) AS count FROM downloaded_tracks');
    return (result.first['count'] as int) == 0;
  }

  Future<void> replaceTracks(List<DownloadedTrack> tracks) async {
    final db = await _open();
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('DELETE FROM downloaded_tracks');
      final statement = db.prepare('''
        INSERT INTO downloaded_tracks (
          track_id,
          title,
          artist,
          track_number,
          duration_seconds,
          local_path,
          state,
          updated_at,
          album_id,
          album_name,
          cover_art_uri,
          local_cover_path,
          suffix,
          bytes,
          received_bytes,
          total_bytes,
          error_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''');
      try {
        for (final track in tracks) {
          statement.execute(_trackArguments(track));
        }
      } finally {
        statement.close();
      }
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<LikedTrack>> loadLikedTracks() async {
    final db = await _open();
    final result = db.select('''
      SELECT *
      FROM liked_tracks
      ORDER BY liked_at DESC
      ''');
    return [for (final row in result) _likedTrackFromRow(row)];
  }

  Future<bool> isTrackLiked(String trackId) async {
    final db = await _open();
    final result = db.select(
      '''
      SELECT 1
      FROM liked_tracks
      WHERE track_id = ?
      LIMIT 1
      ''',
      [trackId],
    );
    return result.isNotEmpty;
  }

  Future<void> upsertLikedTrack(LikedTrack track) async {
    final db = await _open();
    db.execute('''
      INSERT INTO liked_tracks (
        track_id,
        title,
        artist,
        track_number,
        duration_seconds,
        liked_at,
        album_id,
        album_name,
        cover_art_id,
        cover_art_uri,
        suffix
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(track_id) DO UPDATE SET
        title = excluded.title,
        artist = excluded.artist,
        track_number = excluded.track_number,
        duration_seconds = excluded.duration_seconds,
        liked_at = excluded.liked_at,
        album_id = excluded.album_id,
        album_name = excluded.album_name,
        cover_art_id = excluded.cover_art_id,
        cover_art_uri = excluded.cover_art_uri,
        suffix = excluded.suffix
      ''', _likedTrackArguments(track));
  }

  Future<void> deleteLikedTrack(String trackId) async {
    final db = await _open();
    db.execute('DELETE FROM liked_tracks WHERE track_id = ?', [trackId]);
  }

  Future<void> close() async {
    _database?.close();
    _database = null;
    _isInitialized = false;
  }

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) {
      _initialize(existing);
      return existing;
    }

    final path = _path ?? await _defaultPath();
    final db = sqlite3.open(path);
    _database = db;
    _initialize(db);
    return db;
  }

  void _initialize(Database db) {
    if (_isInitialized) {
      return;
    }

    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('''
      CREATE TABLE IF NOT EXISTS downloaded_tracks (
        track_id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        track_number INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        local_path TEXT NOT NULL,
        state TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        album_id TEXT,
        album_name TEXT,
        cover_art_uri TEXT,
        local_cover_path TEXT,
        suffix TEXT,
        bytes INTEGER,
        received_bytes INTEGER,
        total_bytes INTEGER,
        error_message TEXT
      )
      ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS downloaded_tracks_album_idx
      ON downloaded_tracks(album_id, album_name)
      ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS downloaded_tracks_updated_idx
      ON downloaded_tracks(updated_at DESC)
      ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS liked_tracks (
        track_id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        track_number INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        liked_at TEXT NOT NULL,
        album_id TEXT,
        album_name TEXT,
        cover_art_id TEXT,
        cover_art_uri TEXT,
        suffix TEXT
      )
      ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS liked_tracks_liked_at_idx
      ON liked_tracks(liked_at DESC)
      ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS liked_tracks_album_idx
      ON liked_tracks(album_id, album_name)
      ''');
    _isInitialized = true;
  }

  Future<String> _defaultPath() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory('${supportDirectory.path}/NekoFM');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return '${directory.path}/downloads.sqlite';
  }

  DownloadedTrack _trackFromRow(Row row) {
    return DownloadedTrack(
      trackId: row['track_id'] as String,
      title: row['title'] as String,
      artist: row['artist'] as String,
      trackNumber: row['track_number'] as int,
      durationSeconds: row['duration_seconds'] as int,
      localPath: row['local_path'] as String,
      state: DownloadState.fromName(row['state'] as String?),
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      albumId: row['album_id'] as String?,
      albumName: row['album_name'] as String?,
      coverArtUri: row['cover_art_uri'] as String?,
      localCoverPath: row['local_cover_path'] as String?,
      suffix: row['suffix'] as String?,
      bytes: row['bytes'] as int?,
      receivedBytes: row['received_bytes'] as int?,
      totalBytes: row['total_bytes'] as int?,
      errorMessage: row['error_message'] as String?,
    );
  }

  List<Object?> _trackArguments(DownloadedTrack track) {
    return [
      track.trackId,
      track.title,
      track.artist,
      track.trackNumber,
      track.durationSeconds,
      track.localPath,
      track.state.name,
      track.updatedAt.toIso8601String(),
      track.albumId,
      track.albumName,
      track.coverArtUri,
      track.localCoverPath,
      track.suffix,
      track.bytes,
      track.receivedBytes,
      track.totalBytes,
      track.errorMessage,
    ];
  }

  LikedTrack _likedTrackFromRow(Row row) {
    return LikedTrack(
      trackId: row['track_id'] as String,
      title: row['title'] as String,
      artist: row['artist'] as String,
      trackNumber: row['track_number'] as int,
      durationSeconds: row['duration_seconds'] as int,
      likedAt:
          DateTime.tryParse(row['liked_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      albumId: row['album_id'] as String?,
      albumName: row['album_name'] as String?,
      coverArtId: row['cover_art_id'] as String?,
      coverArtUri: row['cover_art_uri'] as String?,
      suffix: row['suffix'] as String?,
    );
  }

  List<Object?> _likedTrackArguments(LikedTrack track) {
    return [
      track.trackId,
      track.title,
      track.artist,
      track.trackNumber,
      track.durationSeconds,
      track.likedAt.toIso8601String(),
      track.albumId,
      track.albumName,
      track.coverArtId,
      track.coverArtUri,
      track.suffix,
    ];
  }
}
