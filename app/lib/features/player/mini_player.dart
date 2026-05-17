import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/library/track.dart';
import '../../core/player/player_controller.dart';
import 'album_art.dart';
import 'playback_formatting.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({required this.onOpenPlayer, super.key});

  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playerControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.hasQueue) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<int?>(
          stream: controller.audioPlayer.currentIndexStream,
          initialData: controller.audioPlayer.currentIndex,
          builder: (context, indexSnapshot) {
            return _MiniPlayerSurface(
              controller: controller,
              track: controller.trackAt(indexSnapshot.data),
              source: controller.sourceAt(indexSnapshot.data),
              onOpenPlayer: onOpenPlayer,
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerSurface extends StatelessWidget {
  const _MiniPlayerSurface({
    required this.controller,
    required this.track,
    required this.source,
    required this.onOpenPlayer,
  });

  final PlayerController controller;
  final Track? track;
  final PlaybackSource? source;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Mini player',
      button: true,
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenPlayer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniProgressBar(controller: controller),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    AlbumArt(
                      imageUri:
                          track?.coverArtUri ?? controller.album?.coverArtUri,
                      size: 44,
                      semanticLabel:
                          '${controller.album?.name ?? 'Album'} cover art',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track?.title ?? 'Loading track...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  track?.artist ??
                                      controller.album?.artist ??
                                      '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                              if (source != null) ...[
                                const SizedBox(width: 8),
                                _MiniSourceLabel(source: source!),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MiniPlayerControls(controller: controller),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSourceLabel extends StatelessWidget {
  const _MiniSourceLabel({required this.source});

  final PlaybackSource source;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: source == PlaybackSource.local
          ? 'Playing from local download'
          : 'Streaming from server',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            source == PlaybackSource.local
                ? Icons.offline_pin_outlined
                : Icons.cloud_queue,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            source.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: controller.audioPlayer.durationStream,
      initialData: controller.audioPlayer.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: controller.audioPlayer.positionStream,
          initialData: controller.audioPlayer.position,
          builder: (context, positionSnapshot) {
            final position = clampPlaybackPosition(
              positionSnapshot.data ?? Duration.zero,
              duration,
            );
            final progress = duration.inMilliseconds <= 0
                ? 0.0
                : position.inMilliseconds / duration.inMilliseconds;
            return LinearProgressIndicator(
              minHeight: 3,
              value: progress.clamp(0.0, 1.0),
              semanticsLabel: 'Playback progress',
              semanticsValue:
                  '${formatPlaybackDuration(position)} of ${formatPlaybackDuration(duration)}',
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerControls extends StatelessWidget {
  const _MiniPlayerControls({required this.controller});

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
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Restart or previous track',
              onPressed: controller.seekBack,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton.filled(
              tooltip: isPlaying ? 'Pause' : 'Play',
              onPressed: isBusy ? null : controller.togglePlayPause,
              icon: isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
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
