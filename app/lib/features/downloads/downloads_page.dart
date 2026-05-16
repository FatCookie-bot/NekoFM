import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_controller.dart';
import '../../core/downloads/download_repository.dart';
import '../../core/downloads/downloaded_track.dart';
import '../../core/player/player_controller.dart';
import '../player/playback_formatting.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  @override
  void initState() {
    super.initState();
    ref.read(downloadControllerProvider).load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(downloadControllerProvider);
    final player = ref.read(playerControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, player]),
      builder: (context, _) {
        if (!controller.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.tracks.isEmpty) {
          return _DownloadsMessage(
            icon: Icons.download_outlined,
            title: 'No downloads yet',
            message:
                _repairMessage(controller.lastRepairResult) ??
                'Download tracks from Library to play them offline.',
            actionLabel: 'Recheck',
            onAction: controller.repair,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DownloadsToolbar(
              repairMessage: _repairMessage(controller.lastRepairResult),
              onRepair: controller.repair,
              failedCount: controller.failedCount,
              onRetryFailed: controller.retryFailedDownloads,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: controller.tracks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  return _DownloadTile(
                    download: controller.tracks[index],
                    isPlaying: player.isCurrentTrack(
                      controller.tracks[index].trackId,
                    ),
                    onPlay: () => _playDownload(controller.tracks, index),
                    onRetry: () =>
                        controller.retryDownload(controller.tracks[index]),
                    onCancel: () => controller.cancelDownload(
                      controller.tracks[index].trackId,
                    ),
                    onDelete: () => _confirmDeleteDownload(
                      context,
                      controller.tracks[index],
                      () => controller.deleteTrack(
                        controller.tracks[index].trackId,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _playDownload(List<DownloadedTrack> downloads, int index) {
    final completeDownloads = [
      for (final download in downloads)
        if (download.state == DownloadState.complete) download,
    ];
    final selected = downloads[index];
    final startIndex = completeDownloads.indexWhere(
      (download) => download.trackId == selected.trackId,
    );
    if (startIndex < 0) {
      return Future.value();
    }

    return ref
        .read(playerControllerProvider)
        .playDownloadedTracks(
          downloads: completeDownloads,
          startIndex: startIndex,
        );
  }
}

class _DownloadsToolbar extends StatelessWidget {
  const _DownloadsToolbar({
    required this.onRepair,
    required this.failedCount,
    required this.onRetryFailed,
    this.repairMessage,
  });

  final VoidCallback onRepair;
  final int failedCount;
  final VoidCallback onRetryFailed;
  final String? repairMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (repairMessage != null) ...[
          Icon(Icons.build_outlined, size: 18, color: colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              repairMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ] else
          const Spacer(),
        if (failedCount > 0) ...[
          OutlinedButton.icon(
            onPressed: onRetryFailed,
            icon: const Icon(Icons.restart_alt_outlined),
            label: Text('Retry failed ($failedCount)'),
          ),
          const SizedBox(width: 8),
        ],
        OutlinedButton.icon(
          onPressed: onRepair,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Recheck'),
        ),
      ],
    );
  }
}

String? _repairMessage(DownloadRepairResult? repairResult) {
  if (repairResult == null || !repairResult.changed) {
    return null;
  }

  final parts = <String>[
    if (repairResult.removedAudioCount > 0)
      '${repairResult.removedAudioCount} missing audio removed',
    if (repairResult.clearedCoverCount > 0)
      '${repairResult.clearedCoverCount} missing covers cleared',
    if (repairResult.recoveredCoverCount > 0)
      '${repairResult.recoveredCoverCount} local covers recovered',
  ];
  return 'Repaired ${parts.join(' • ')}.';
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.download,
    required this.isPlaying,
    required this.onPlay,
    required this.onRetry,
    required this.onCancel,
    required this.onDelete,
  });

  final DownloadedTrack download;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stateIcon = switch (download.state) {
      DownloadState.queued => Icons.schedule,
      DownloadState.downloading => Icons.downloading,
      DownloadState.complete => Icons.download_done,
      DownloadState.failed => Icons.error_outline,
    };
    final stateColor = switch (download.state) {
      DownloadState.queued => colorScheme.primary,
      DownloadState.downloading => colorScheme.primary,
      DownloadState.complete => colorScheme.tertiary,
      DownloadState.failed => colorScheme.error,
    };
    final subtitle = [
      download.artist,
      if (download.albumName != null) download.albumName!,
      formatPlaybackDuration(Duration(seconds: download.durationSeconds)),
      if (download.state == DownloadState.queued) 'Queued',
      if (download.bytes != null) _formatBytes(download.bytes!),
    ].join(' • ');

    return _PlayingTileFrame(
      isPlaying: isPlaying,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        leading: Icon(stateIcon, color: stateColor),
        title: Text(
          download.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (download.state == DownloadState.queued)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Waiting for the download queue.',
                  style: TextStyle(color: colorScheme.primary),
                ),
              ),
            if (download.state == DownloadState.downloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: download.progress),
              ),
            if (download.state == DownloadState.failed &&
                download.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  download.errorMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (download.state == DownloadState.failed)
              IconButton(
                tooltip: 'Retry download',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_outlined),
              ),
            IconButton(
              tooltip: download.state == DownloadState.complete
                  ? 'Play downloaded track'
                  : 'Download location',
              onPressed: download.state == DownloadState.complete
                  ? onPlay
                  : null,
              icon: Icon(
                isPlaying
                    ? Icons.graphic_eq_outlined
                    : download.state == DownloadState.complete
                    ? Icons.play_arrow_outlined
                    : Icons.folder_outlined,
              ),
            ),
            if (download.state == DownloadState.queued ||
                download.state == DownloadState.downloading)
              IconButton(
                tooltip: 'Cancel download',
                onPressed: onCancel,
                icon: const Icon(Icons.close),
              )
            else
              IconButton(
                tooltip: 'Delete local download',
                onPressed: onDelete,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        onTap: download.state == DownloadState.complete ? onPlay : null,
      ),
    );
  }

  static String _formatBytes(int bytes) {
    return switch (bytes) {
      < 1024 => '$bytes B',
      < 1048576 => '${(bytes / 1024).toStringAsFixed(1)} KB',
      _ => '${(bytes / 1048576).toStringAsFixed(1)} MB',
    };
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
          'Remove "${download.title}" from this device. This will not delete anything from Navidrome.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    onConfirm();
  }
}

class _DownloadsMessage extends StatelessWidget {
  const _DownloadsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_outlined),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
