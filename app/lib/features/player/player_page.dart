import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/library/track.dart';
import '../../core/likes/liked_controller.dart';
import '../../core/player/player_controller.dart';
import 'album_art.dart';
import 'playback_formatting.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  @override
  void initState() {
    super.initState();
    ref.read(likedControllerProvider).load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(playerControllerProvider);
    final liked = ref.watch(likedControllerProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([controller, liked]),
      builder: (context, _) {
        if (!controller.hasQueue) {
          return const _EmptyPlayer();
        }

        return StreamBuilder<int?>(
          stream: controller.audioPlayer.currentIndexStream,
          initialData: controller.audioPlayer.currentIndex,
          builder: (context, indexSnapshot) {
            final track = controller.trackAt(indexSnapshot.data);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NowPlayingHeader(
                  track: track,
                  albumName: controller.album?.name ?? 'Unknown album',
                  artistName: controller.album?.artist,
                  coverArtUri: controller.album?.coverArtUri,
                  source: controller.sourceAt(indexSnapshot.data),
                  isLiked: track == null ? false : liked.isLiked(track.id),
                  onToggleLiked: track == null
                      ? null
                      : () => liked.toggleTrack(track),
                  isLoading: controller.isLoading,
                  errorMessage: controller.errorMessage,
                ),
                const SizedBox(height: 24),
                _PlaybackTimeline(controller: controller),
                const SizedBox(height: 18),
                _PlaybackControls(controller: controller),
                const SizedBox(height: 24),
                Expanded(child: _QueueList(controller: controller)),
              ],
            );
          },
        );
      },
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 56,
            color: colorScheme.primary,
            semanticLabel: 'Player',
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing playing',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a track from Library to start streaming.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingHeader extends StatelessWidget {
  const _NowPlayingHeader({
    required this.track,
    required this.albumName,
    required this.artistName,
    required this.coverArtUri,
    required this.source,
    required this.isLiked,
    required this.onToggleLiked,
    required this.isLoading,
    required this.errorMessage,
  });

  final Track? track;
  final String albumName;
  final String? artistName;
  final Uri? coverArtUri;
  final PlaybackSource? source;
  final bool isLiked;
  final VoidCallback? onToggleLiked;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          AlbumArt(
            imageUri: coverArtUri,
            size: 72,
            semanticLabel: '$albumName cover art',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? 'Loading track...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  {
                    if (track?.artist.isNotEmpty ?? false) track!.artist,
                    albumName,
                    if (artistName != null && artistName!.isNotEmpty)
                      artistName!,
                  }.join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (source != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _PlaybackSourceChip(source: source!),
                      IconButton(
                        tooltip: isLiked ? 'Remove from liked' : 'Add to liked',
                        onPressed: onToggleLiked,
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isLoading || errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage ?? 'Loading stream...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: errorMessage == null
                          ? colorScheme.primary
                          : colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackSourceChip extends StatelessWidget {
  const _PlaybackSourceChip({required this.source});

  final PlaybackSource source;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            source == PlaybackSource.local
                ? Icons.offline_pin_outlined
                : Icons.cloud_queue,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            source.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackTimeline extends StatefulWidget {
  const _PlaybackTimeline({required this.controller});

  final PlayerController controller;

  @override
  State<_PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<_PlaybackTimeline> {
  Duration? _previewPosition;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: widget.controller.audioPlayer.durationStream,
      initialData: widget.controller.audioPlayer.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: widget.controller.audioPlayer.positionStream,
          initialData: widget.controller.audioPlayer.position,
          builder: (context, positionSnapshot) {
            final position = clampPlaybackPosition(
              _previewPosition ?? positionSnapshot.data ?? Duration.zero,
              duration,
            );
            return Column(
              children: [
                Slider(
                  value: position.inMilliseconds.toDouble(),
                  min: 0,
                  max: duration.inMilliseconds <= 0
                      ? 1
                      : duration.inMilliseconds.toDouble(),
                  onChanged: duration.inMilliseconds <= 0
                      ? null
                      : (value) {
                          setState(() {
                            _previewPosition = Duration(
                              milliseconds: value.round(),
                            );
                          });
                        },
                  onChangeEnd: duration.inMilliseconds <= 0
                      ? null
                      : (value) async {
                          final position = Duration(
                            milliseconds: value.round(),
                          );
                          setState(() {
                            _previewPosition = position;
                          });
                          await widget.controller.seek(position);
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _previewPosition = null;
                          });
                        },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatPlaybackDuration(position)),
                    Text(formatPlaybackDuration(duration)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: controller.audioPlayer.playerStateStream,
      initialData: controller.audioPlayer.playerState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? controller.audioPlayer.playerState;
        final isBusy =
            state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        final isPlaying = state.playing;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Restart or previous track',
              onPressed: controller.seekBack,
              icon: const Icon(Icons.skip_previous),
            ),
            const SizedBox(width: 12),
            SizedBox.square(
              dimension: 56,
              child: IconButton.filled(
                tooltip: isPlaying ? 'Pause' : 'Play',
                onPressed: isBusy ? null : controller.togglePlayPause,
                icon: isBusy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: 'Next track',
              onPressed: controller.seekToNext,
              icon: const Icon(Icons.skip_next),
            ),
          ],
        );
      },
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
      stream: controller.audioPlayer.currentIndexStream,
      initialData: controller.audioPlayer.currentIndex,
      builder: (context, snapshot) {
        final currentIndex = snapshot.data ?? 0;
        return ListView.separated(
          itemCount: controller.queue.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final track = controller.queue[index];
            final isCurrent = index == currentIndex;
            return _PlayingTileFrame(
              isPlaying: isCurrent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                  isCurrent
                      ? Icons.graphic_eq_outlined
                      : Icons.music_note_outlined,
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artist} • ${formatPlaybackDuration(Duration(seconds: track.durationSeconds))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    controller.audioPlayer.seek(Duration.zero, index: index),
              ),
            );
          },
        );
      },
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
