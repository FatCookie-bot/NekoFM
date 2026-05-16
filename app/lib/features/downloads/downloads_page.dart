import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_controller.dart';
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
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.tracks.isEmpty) {
          return const _DownloadsMessage(
            icon: Icons.download_outlined,
            title: 'No downloads yet',
            message: 'Download tracks from Library to play them offline.',
          );
        }

        return ListView.separated(
          itemCount: controller.tracks.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return _DownloadTile(
              download: controller.tracks[index],
              onPlay: () => _playDownload(controller.tracks, index),
              onDelete: () => _confirmDeleteDownload(
                context,
                controller.tracks[index],
                () => controller.deleteTrack(controller.tracks[index].trackId),
              ),
            );
          },
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

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.download,
    required this.onPlay,
    required this.onDelete,
  });

  final DownloadedTrack download;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stateIcon = switch (download.state) {
      DownloadState.downloading => Icons.downloading,
      DownloadState.complete => Icons.download_done,
      DownloadState.failed => Icons.error_outline,
    };
    final stateColor = switch (download.state) {
      DownloadState.downloading => colorScheme.primary,
      DownloadState.complete => colorScheme.tertiary,
      DownloadState.failed => colorScheme.error,
    };
    final subtitle = [
      download.artist,
      if (download.albumName != null) download.albumName!,
      formatPlaybackDuration(Duration(seconds: download.durationSeconds)),
      if (download.bytes != null) _formatBytes(download.bytes!),
    ].join(' • ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: Icon(stateIcon, color: stateColor),
      title: Text(download.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
          IconButton(
            tooltip: download.state == DownloadState.complete
                ? 'Play downloaded track'
                : 'Download location',
            onPressed: download.state == DownloadState.complete ? onPlay : null,
            icon: Icon(
              download.state == DownloadState.complete
                  ? Icons.play_arrow_outlined
                  : Icons.folder_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Delete local download',
            onPressed: download.state == DownloadState.downloading
                ? null
                : onDelete,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      onTap: download.state == DownloadState.complete ? onPlay : null,
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
  });

  final IconData icon;
  final String title;
  final String message;

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
          ],
        ),
      ),
    );
  }
}
