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
  bool _isReordering = false;
  int? _selectedReorderIndex;
  List<LikedTrack> _reorderDraft = const [];

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

        final visibleTracks = _isReordering ? _reorderDraft : liked.tracks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LikedHeader(
              tracks: visibleTracks,
              isReordering: _isReordering,
              isRepeatEnabled: player.isRepeatEnabled,
              onPlay: () => _playFirstLiked(visibleTracks, downloads.tracks),
              onShuffle: visibleTracks.length < 2
                  ? null
                  : () => _shuffleLiked(visibleTracks, downloads.tracks),
              onToggleRepeat: player.toggleRepeat,
              onStartReorder: liked.tracks.length < 2
                  ? null
                  : () => _startLikedReorder(liked.tracks),
              onCancelReorder: _cancelLikedReorder,
              onConfirmReorder: () => _confirmLikedReorder(liked),
            ),
            const SizedBox(height: 8),
            if (_isOffline && _hasCheckedConnection) ...[
              const _OfflineLikedNotice(),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: visibleTracks.length,
                onReorder: _isReordering
                    ? (oldIndex, newIndex) =>
                          _moveLikedDraft(oldIndex, newIndex)
                    : (_, _) {},
                itemBuilder: (context, index) {
                  final track = visibleTracks[index];
                  final download = downloads.trackState(track.trackId);
                  final isPlayable =
                      !_isOffline || download?.state == DownloadState.complete;
                  final tile = _LikedTrackTile(
                    key: ValueKey(track.trackId),
                    track: track,
                    download: download,
                    isOffline: _isOffline,
                    isPlaying:
                        !_isReordering && player.isCurrentTrack(track.trackId),
                    isReordering: _isReordering,
                    isSelectedForReorder: _selectedReorderIndex == index,
                    onPlay: _isReordering
                        ? () => _selectOrSwapLiked(index)
                        : isPlayable
                        ? () =>
                              _playLiked(visibleTracks, downloads.tracks, index)
                        : null,
                    onDownload: () => downloads.downloadTrack(track.toTrack()),
                    onDeleteDownload: download == null
                        ? null
                        : () => _confirmDeleteDownload(
                            context,
                            download,
                            () async {
                              await downloads.deleteTrack(download.trackId);
                              await player.removeDeletedLocalTracks([
                                download.trackId,
                              ]);
                            },
                          ),
                    onUnlike: () => liked.unlikeTrack(track.trackId),
                  );
                  if (!_isReordering) {
                    return tile;
                  }
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey('reorder-${track.trackId}'),
                    index: index,
                    child: tile,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _startLikedReorder(List<LikedTrack> tracks) {
    setState(() {
      _isReordering = true;
      _selectedReorderIndex = null;
      _reorderDraft = List<LikedTrack>.of(tracks);
    });
  }

  void _cancelLikedReorder() {
    setState(() {
      _isReordering = false;
      _selectedReorderIndex = null;
      _reorderDraft = const [];
    });
  }

  Future<void> _confirmLikedReorder(LikedController liked) async {
    final orderedTracks = List<LikedTrack>.of(_reorderDraft);
    await liked.reorderTracks(orderedTracks);
    await ref
        .read(playerControllerProvider)
        .reorderCurrentQueue(
          albumId: 'liked',
          tracks: [for (final track in orderedTracks) track.toTrack()],
        );
    if (!mounted) {
      return;
    }
    _cancelLikedReorder();
  }

  void _moveLikedDraft(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = _reorderDraft.removeAt(oldIndex);
      _reorderDraft.insert(newIndex, moved);
      _selectedReorderIndex = null;
    });
  }

  void _selectOrSwapLiked(int index) {
    final selected = _selectedReorderIndex;
    if (selected == null || selected == index) {
      setState(() {
        _selectedReorderIndex = selected == index ? null : index;
      });
      return;
    }

    setState(() {
      final next = List<LikedTrack>.of(_reorderDraft);
      final first = next[selected];
      next[selected] = next[index];
      next[index] = first;
      _reorderDraft = next;
      _selectedReorderIndex = null;
    });
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

      final tracks = [
        for (final download in playableDownloads) download.toTrack(),
      ];
      final selected = tracks[startIndex];
      return ref
          .read(playerControllerProvider)
          .playAlbum(
            album: Album(
              id: 'liked',
              name: 'Liked',
              artist: selected.artist,
              songCount: tracks.length,
              durationSeconds: tracks.fold(
                0,
                (total, track) => total + track.durationSeconds,
              ),
              coverArtUri: selected.coverArtUri,
            ),
            tracks: tracks,
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

  Future<void> _playFirstLiked(
    List<LikedTrack> likedTracks,
    List<DownloadedTrack> downloads,
  ) {
    if (!_isOffline) {
      return _playLiked(likedTracks, downloads, 0);
    }

    final downloadedIds = {
      for (final download in downloads)
        if (download.state == DownloadState.complete) download.trackId,
    };
    final firstPlayableIndex = likedTracks.indexWhere(
      (track) => downloadedIds.contains(track.trackId),
    );
    if (firstPlayableIndex < 0) {
      return Future.value();
    }

    return _playLiked(likedTracks, downloads, firstPlayableIndex);
  }

  Future<void> _shuffleLiked(
    List<LikedTrack> likedTracks,
    List<DownloadedTrack> downloads,
  ) {
    final shuffled = List<LikedTrack>.of(likedTracks)..shuffle();
    if (!_isOffline) {
      return _playLiked(shuffled, downloads, 0);
    }

    final downloadedIds = {
      for (final download in downloads)
        if (download.state == DownloadState.complete) download.trackId,
    };
    final playable = [
      for (final track in shuffled)
        if (downloadedIds.contains(track.trackId)) track,
    ];
    if (playable.isEmpty) {
      return Future.value();
    }

    return _playLiked(playable, downloads, 0);
  }
}

class _LikedHeader extends StatelessWidget {
  const _LikedHeader({
    required this.tracks,
    required this.isReordering,
    required this.isRepeatEnabled,
    required this.onPlay,
    required this.onToggleRepeat,
    required this.onCancelReorder,
    required this.onConfirmReorder,
    this.onShuffle,
    this.onStartReorder,
  });

  final List<LikedTrack> tracks;
  final bool isReordering;
  final bool isRepeatEnabled;
  final VoidCallback onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onToggleRepeat;
  final VoidCallback? onStartReorder;
  final VoidCallback onCancelReorder;
  final VoidCallback onConfirmReorder;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(
      seconds: tracks.fold(0, (total, track) => total + track.durationSeconds),
    );
    final summary = [
      '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
      if (tracks.isNotEmpty) formatPlaybackDuration(duration),
    ].join(' • ');
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.favorite,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Liked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (isReordering) ...[
              TextButton.icon(
                onPressed: onCancelReorder,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: onConfirmReorder,
                icon: const Icon(Icons.check),
                label: const Text('Confirm order'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: tracks.isEmpty ? null : onPlay,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              OutlinedButton.icon(
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle),
                label: const Text('Shuffle'),
              ),
              OutlinedButton.icon(
                onPressed: onToggleRepeat,
                icon: Icon(isRepeatEnabled ? Icons.repeat_on : Icons.repeat),
                label: Text(isRepeatEnabled ? 'Repeat on' : 'Repeat'),
              ),
              OutlinedButton.icon(
                onPressed: onStartReorder,
                icon: const Icon(Icons.swap_vert),
                label: const Text('Reorder'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _LikedTrackTile extends StatelessWidget {
  const _LikedTrackTile({
    required this.track,
    required this.download,
    required this.isOffline,
    required this.isPlaying,
    required this.isReordering,
    required this.isSelectedForReorder,
    required this.onPlay,
    required this.onDownload,
    required this.onDeleteDownload,
    required this.onUnlike,
    super.key,
  });

  final LikedTrack track;
  final DownloadedTrack? download;
  final bool isOffline;
  final bool isPlaying;
  final bool isReordering;
  final bool isSelectedForReorder;
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
      isSelected: isSelectedForReorder,
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
              if (isReordering)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.drag_handle),
                )
              else if (isQueued || isDownloading)
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
  const _PlayingTileFrame({
    required this.isPlaying,
    required this.child,
    this.isSelected = false,
  });

  final bool isPlaying;
  final Widget child;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    if (!isPlaying && !isSelected) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
        color: colorScheme.primary.withValues(alpha: isSelected ? 0.16 : 0.08),
      ),
      child: child,
    );
  }
}

Future<void> _confirmDeleteDownload(
  BuildContext context,
  DownloadedTrack download,
  Future<void> Function() onConfirm,
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
    await onConfirm();
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
