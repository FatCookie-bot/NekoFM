import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_controller.dart';
import '../../core/downloads/downloaded_track.dart';
import '../../core/likes/liked_controller.dart';
import '../../core/likes/liked_track.dart';
import '../../core/library/album.dart';
import '../../core/library/music_library_repository.dart';
import '../../core/player/player_controller.dart';
import '../player/album_art.dart';
import '../player/playback_formatting.dart';

class LikedPage extends ConsumerStatefulWidget {
  const LikedPage({super.key});

  @override
  ConsumerState<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends ConsumerState<LikedPage> {
  final _libraryRepository = MusicLibraryRepository();
  bool _isOffline = false;
  bool _hasCheckedConnection = false;

  @override
  void initState() {
    super.initState();
    ref.read(likedControllerProvider).load();
    ref.read(downloadControllerProvider).load();
    _checkConnection();
  }

  @override
  Widget build(BuildContext context) {
    final liked = ref.read(likedControllerProvider);
    final downloads = ref.read(downloadControllerProvider);
    final player = ref.read(playerControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([liked, downloads, player]),
      builder: (context, _) {
        if (!liked.isLoaded || !downloads.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        if (liked.tracks.isEmpty) {
          return const _LikedMessage();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isOffline && _hasCheckedConnection) ...[
              const _OfflineLikedNotice(),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: ListView.separated(
                itemCount: liked.tracks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final track = liked.tracks[index];
                  final download = downloads.trackState(track.trackId);
                  final isPlayable =
                      !_isOffline || download?.state == DownloadState.complete;
                  return _LikedTrackTile(
                    track: track,
                    download: download,
                    isOffline: _isOffline,
                    isPlaying: player.isCurrentTrack(track.trackId),
                    onPlay: isPlayable
                        ? () =>
                              _playLiked(liked.tracks, downloads.tracks, index)
                        : null,
                    onDownload: () => downloads.downloadTrack(track.toTrack()),
                    onDeleteDownload: download == null
                        ? null
                        : () => _confirmDeleteDownload(context, download, () {
                            downloads.deleteTrack(download.trackId);
                          }),
                    onUnlike: () => liked.unlikeTrack(track.trackId),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkConnection() async {
    try {
      await _libraryRepository.getAlbums();
      if (!mounted) {
        return;
      }
      setState(() {
        _isOffline = false;
        _hasCheckedConnection = true;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _isOffline = true;
        _hasCheckedConnection = true;
      });
    }
  }

  Future<void> _playLiked(
    List<LikedTrack> likedTracks,
    List<DownloadedTrack> downloads,
    int index,
  ) {
    if (_isOffline) {
      final downloadedById = {
        for (final download in downloads)
          if (download.state == DownloadState.complete)
            download.trackId: download,
      };
      final playableDownloads = [
        for (final track in likedTracks)
          if (downloadedById[track.trackId] != null)
            downloadedById[track.trackId]!,
      ];
      final selectedTrackId = likedTracks[index].trackId;
      final startIndex = playableDownloads.indexWhere(
        (download) => download.trackId == selectedTrackId,
      );
      if (startIndex < 0) {
        return Future.value();
      }

      return ref
          .read(playerControllerProvider)
          .playDownloadedTracks(
            downloads: playableDownloads,
            startIndex: startIndex,
          );
    }

    final tracks = [for (final track in likedTracks) track.toTrack()];
    final selected = tracks[index];
    final album = Album(
      id: 'liked',
      name: 'Liked',
      artist: selected.artist,
      songCount: tracks.length,
      durationSeconds: tracks.fold(
        0,
        (total, track) => total + track.durationSeconds,
      ),
      coverArtUri: selected.coverArtUri,
    );

    return ref
        .read(playerControllerProvider)
        .playAlbum(album: album, tracks: tracks, startIndex: index);
  }
}

class _LikedTrackTile extends StatelessWidget {
  const _LikedTrackTile({
    required this.track,
    required this.download,
    required this.isOffline,
    required this.isPlaying,
    required this.onPlay,
    required this.onDownload,
    required this.onDeleteDownload,
    required this.onUnlike,
  });

  final LikedTrack track;
  final DownloadedTrack? download;
  final bool isOffline;
  final bool isPlaying;
  final VoidCallback? onPlay;
  final VoidCallback onDownload;
  final VoidCallback? onDeleteDownload;
  final VoidCallback onUnlike;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final downloadState = download?.state;
    final isDownloaded = downloadState == DownloadState.complete;
    final isQueued = downloadState == DownloadState.queued;
    final isDownloading = downloadState == DownloadState.downloading;
    final isUnavailableOffline = isOffline && !isDownloaded;
    final subtitle = [
      track.artist,
      if (track.albumName != null) track.albumName!,
      formatPlaybackDuration(Duration(seconds: track.durationSeconds)),
      if (track.suffix != null) track.suffix!.toUpperCase(),
      if (isUnavailableOffline) 'Not downloaded',
    ].join(' • ');
    final localCoverPath = download?.localCoverPath;
    final coverUri = localCoverPath == null || localCoverPath.isEmpty
        ? track.coverArtUri == null
              ? null
              : Uri.tryParse(track.coverArtUri!)
        : Uri.file(localCoverPath);

    return _PlayingTileFrame(
      isPlaying: isPlaying,
      child: Opacity(
        opacity: isUnavailableOffline ? 0.48 : 1,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 6,
          ),
          leading: AlbumArt(
            imageUri: coverUri,
            size: 44,
            semanticLabel: '${track.title} cover art',
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isQueued || isDownloading)
                SizedBox.square(
                  dimension: 40,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: isQueued
                        ? const Icon(Icons.schedule)
                        : CircularProgressIndicator(
                            strokeWidth: 2,
                            value: download?.progress,
                          ),
                  ),
                )
              else
                IconButton(
                  tooltip: isDownloaded
                      ? 'Delete local download'
                      : downloadState == DownloadState.failed
                      ? 'Retry download'
                      : 'Download track',
                  onPressed: isDownloaded ? onDeleteDownload : onDownload,
                  icon: Icon(
                    isDownloaded
                        ? Icons.delete_outline
                        : downloadState == DownloadState.failed
                        ? Icons.refresh_outlined
                        : Icons.download_outlined,
                    color: isDownloaded ? colorScheme.error : null,
                  ),
                ),
              IconButton(
                tooltip: 'Remove from liked',
                onPressed: onUnlike,
                icon: const Icon(Icons.favorite),
              ),
              IconButton(
                tooltip: isUnavailableOffline
                    ? 'Download before offline playback'
                    : 'Play',
                onPressed: onPlay,
                icon: Icon(
                  isPlaying
                      ? Icons.graphic_eq_outlined
                      : Icons.play_arrow_outlined,
                ),
              ),
            ],
          ),
          onTap: onPlay,
        ),
      ),
    );
  }
}

class _PlayingTileFrame extends StatelessWidget {
  const _PlayingTileFrame({required this.isPlaying, required this.child});

  final bool isPlaying;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isPlaying) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
        color: colorScheme.primary.withValues(alpha: 0.08),
      ),
      child: child,
    );
  }
}

Future<void> _confirmDeleteDownload(
  BuildContext context,
  DownloadedTrack download,
  VoidCallback onConfirm,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Delete local download?'),
        content: Text(
          'Remove "${download.title}" from this device. It will stay in Liked and will not delete anything from Navidrome.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete local file'),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    onConfirm();
  }
}

class _OfflineLikedNotice extends StatelessWidget {
  const _OfflineLikedNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(Icons.offline_pin_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline mode. Liked songs that are not downloaded are dimmed and skipped.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _LikedMessage extends StatelessWidget {
  const _LikedMessage();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 44, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No liked songs yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Use the heart button on songs or in the player to build this playlist.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
