import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/album.dart';
import '../../core/library/music_library_repository.dart';
import '../../core/library/track.dart';
import '../../core/downloads/download_controller.dart';
import '../../core/downloads/download_repository.dart';
import '../../core/downloads/downloaded_track.dart';
import '../../core/exports/music_exporter.dart';
import '../../core/likes/liked_controller.dart';
import '../../core/player/player_controller.dart';
import '../../core/playlists/playlist_controller.dart';
import '../../core/server/music_server_client.dart';
import '../../core/server/secure_server_profile_store.dart';
import '../player/playback_formatting.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  final _exporter = const MusicExporter();
  final _downloadRepository = DownloadRepository();
  final _libraryRepository = MusicLibraryRepository();
  final _profileStore = const SecureServerProfileStore();
  final _serverClient = MusicServerClient();
  final _dio = Dio();
  bool _isExporting = false;
  String? _exportMessage;

  @override
  void initState() {
    super.initState();
    ref.read(downloadControllerProvider).load();
    ref.read(likedControllerProvider).load();
    ref.read(playlistControllerProvider).load();
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(downloadControllerProvider);
    final liked = ref.read(likedControllerProvider);
    final playlists = ref.read(playlistControllerProvider);
    final player = ref.read(playerControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, liked, playlists, player]),
      builder: (context, _) {
        if (!controller.isLoaded || !liked.isLoaded || !playlists.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.tracks.isEmpty) {
          return _DownloadsMessage(
            icon: Icons.download_outlined,
            title: 'No downloads yet',
            message:
                _repairMessage(controller.lastRepairResult) ??
                'Download tracks from Library to play them offline, or export from your server directly.',
            actionLabel: _isExporting ? 'Exporting...' : 'Export',
            actionIcon: _isExporting
                ? Icons.hourglass_empty_outlined
                : Icons.ios_share_outlined,
            onAction: _isExporting
                ? null
                : () => _exportDownloads(controller.tracks),
            secondaryActionLabel: 'Recheck',
            secondaryActionIcon: Icons.refresh_outlined,
            onSecondaryAction: controller.repair,
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
              isExporting: _isExporting,
              onExport: () => _exportDownloads(controller.tracks),
            ),
            if (_exportMessage != null) ...[
              const SizedBox(height: 8),
              _InlineDownloadNotice(message: _exportMessage!),
            ],
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

  Future<void> _exportDownloads(List<DownloadedTrack> downloads) async {
    final builderData = await _loadExportBuilderData(downloads);
    if (!mounted) {
      return;
    }

    if (!builderData.hasAnyExportableMusic) {
      setState(() {
        _exportMessage = 'No albums, playlists, or liked songs to export yet.';
      });
      return;
    }

    final selection = await showDialog<_ExportSelection>(
      context: context,
      builder: (context) => _ExportBuilderDialog(data: builderData),
    );
    if (selection == null || selection.isEmpty || !mounted) {
      return;
    }

    final path = await getDirectoryPath(confirmButtonText: 'Export here');
    if (path == null || !mounted) {
      return;
    }

    final targetRoot = Directory(path);
    final exportMode = await _chooseExportMode(targetRoot);
    if (exportMode == null || !mounted) {
      return;
    }

    setState(() {
      _isExporting = true;
      _exportMessage = null;
    });

    try {
      final profile = selection.hasMissingRemoteTracks
          ? await _profileStore.load()
          : null;
      final canDownloadRemote = profile != null && profile.password.isNotEmpty;
      final result = await _exporter.exportSelection(
        tracks: selection.directTracks,
        targetRoot: targetRoot,
        playlists: selection.playlists,
        cleanFirst: exportMode == _ExportMode.clean,
        downloadRemoteTrack: canDownloadRemote
            ? (request, destination) async {
                try {
                  await _serverClient.downloadTrack(
                    profile,
                    request.track.id,
                    destination.path,
                  );
                  return true;
                } on Object {
                  return false;
                }
              }
            : null,
        downloadRemoteCover: canDownloadRemote
            ? (request, destination) async {
                final coverUri = request.track.coverArtUri;
                if (coverUri == null) {
                  return false;
                }
                try {
                  await _dio.downloadUri(
                    coverUri,
                    destination.path,
                    options: Options(
                      receiveTimeout: const Duration(seconds: 20),
                    ),
                  );
                  return true;
                } on Object {
                  return false;
                }
              }
            : null,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _isExporting = false;
        _exportMessage =
            'Exported ${result.exportedTrackCount} tracks (${result.copiedTrackCount} copied, ${result.downloadedTrackCount} downloaded), ${result.playlistCount} playlists, ${result.skippedTrackCount + result.skippedPlaylistEntryCount} skipped, and ${result.collisionCount} filename fixes.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isExporting = false;
        _exportMessage = 'Export failed: $error';
      });
    }
  }

  Future<_ExportBuilderData> _loadExportBuilderData(
    List<DownloadedTrack> downloads,
  ) async {
    final downloadMap = {
      for (final download in _completeDownloads(downloads))
        download.trackId: download,
    };
    var isOnline = true;
    List<Album> albums;
    try {
      albums = await _libraryRepository.getAlbums();
    } on Object {
      isOnline = false;
      final downloadedDetails = await _downloadRepository
          .loadDownloadedAlbumDetails();
      albums = [for (final detail in downloadedDetails) detail.album];
    }

    final playlists = ref.read(playlistControllerProvider);
    for (final playlist in playlists.playlists) {
      await playlists.loadTracks(playlist.id);
    }

    return _ExportBuilderData(
      albums: albums,
      isOnline: isOnline,
      downloadsByTrackId: downloadMap,
      loadAlbumTracks: (album) async {
        if (isOnline) {
          try {
            return (await _libraryRepository.getAlbum(album.id)).tracks;
          } on Object {
            return _downloadedTracksForAlbum(album.id, downloadMap);
          }
        }
        return _downloadedTracksForAlbum(album.id, downloadMap);
      },
      playlists: [
        for (final playlist in playlists.playlists)
          _ExportPlaylistGroup(
            id: playlist.id,
            name: playlist.name,
            tracks: [
              for (final track in playlists.tracksFor(playlist.id))
                track.toTrack(),
            ],
          ),
      ],
      likedTracks: [
        for (final liked in ref.read(likedControllerProvider).tracks)
          liked.toTrack(),
      ],
    );
  }

  List<Track> _downloadedTracksForAlbum(
    String albumId,
    Map<String, DownloadedTrack> downloadsByTrackId,
  ) {
    final tracks = [
      for (final download in downloadsByTrackId.values)
        if ((download.albumId ?? download.albumName ?? 'downloads') == albumId)
          download.toTrack(),
    ]..sort((left, right) => left.trackNumber.compareTo(right.trackNumber));
    return tracks;
  }

  Future<_ExportMode?> _chooseExportMode(Directory targetRoot) async {
    if (!await _exporter.hasExistingExport(targetRoot)) {
      return _ExportMode.update;
    }

    if (!mounted) {
      return null;
    }

    return showDialog<_ExportMode>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Existing NekoFM export found'),
          content: const Text(
            'Update keeps extra old files. Clean removes files from the previous NekoFM export manifest before copying the current export.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_ExportMode.update),
              child: const Text('Update export'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_ExportMode.clean),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clean export'),
            ),
          ],
        );
      },
    );
  }

  List<DownloadedTrack> _completeDownloads(List<DownloadedTrack> downloads) {
    return [
      for (final download in downloads)
        if (download.state == DownloadState.complete) download,
    ];
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

enum _ExportMode { update, clean }

class _ExportBuilderData {
  const _ExportBuilderData({
    required this.albums,
    required this.isOnline,
    required this.downloadsByTrackId,
    required this.loadAlbumTracks,
    required this.playlists,
    required this.likedTracks,
  });

  final List<Album> albums;
  final bool isOnline;
  final Map<String, DownloadedTrack> downloadsByTrackId;
  final Future<List<Track>> Function(Album album) loadAlbumTracks;
  final List<_ExportPlaylistGroup> playlists;
  final List<Track> likedTracks;

  bool get hasAnyExportableMusic =>
      albums.isNotEmpty || playlists.isNotEmpty || likedTracks.isNotEmpty;

  MusicExportTrackRequest requestFor(Track track) {
    return MusicExportTrackRequest(
      track: track,
      localDownload: downloadsByTrackId[track.id],
    );
  }

  bool isAvailable(Track track) {
    return isOnline || downloadsByTrackId.containsKey(track.id);
  }

  bool isDownloaded(Track track) {
    return downloadsByTrackId.containsKey(track.id);
  }
}

class _ExportPlaylistGroup {
  const _ExportPlaylistGroup({
    required this.id,
    required this.name,
    required this.tracks,
  });

  final String id;
  final String name;
  final List<Track> tracks;
}

class _ExportSelection {
  const _ExportSelection({
    required this.directTracks,
    required this.playlists,
    required this.hasMissingRemoteTracks,
  });

  final List<MusicExportTrackRequest> directTracks;
  final List<MusicExportPlaylistRequest> playlists;
  final bool hasMissingRemoteTracks;

  bool get isEmpty => directTracks.isEmpty && playlists.isEmpty;
}

enum _ExportGroupType { album, liked, playlist }

class _ExportGroupRef {
  const _ExportGroupRef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.album,
    this.playlist,
  });

  final String id;
  final String title;
  final String subtitle;
  final _ExportGroupType type;
  final Album? album;
  final _ExportPlaylistGroup? playlist;
}

class _ExportBuilderDialog extends StatefulWidget {
  const _ExportBuilderDialog({required this.data});

  final _ExportBuilderData data;

  @override
  State<_ExportBuilderDialog> createState() => _ExportBuilderDialogState();
}

class _ExportBuilderDialogState extends State<_ExportBuilderDialog> {
  final Map<String, List<Track>> _tracksByGroupId = {};
  final Map<String, Set<String>> _selectedKeysByGroupId = {};
  final Set<String> _loadingGroupIds = {};
  _ExportGroupRef? _activeGroup;

  List<_ExportGroupRef> get _groups {
    return [
      for (final album in widget.data.albums)
        _ExportGroupRef(
          id: 'album:${album.id}',
          title: album.name,
          subtitle: '${album.artist} • ${album.songCount} songs',
          type: _ExportGroupType.album,
          album: album,
        ),
      if (widget.data.likedTracks.isNotEmpty)
        _ExportGroupRef(
          id: 'liked',
          title: 'Liked',
          subtitle: '${widget.data.likedTracks.length} songs',
          type: _ExportGroupType.liked,
        ),
      for (final playlist in widget.data.playlists)
        _ExportGroupRef(
          id: 'playlist:${playlist.id}',
          title: playlist.name,
          subtitle: '${playlist.tracks.length} songs',
          type: _ExportGroupType.playlist,
          playlist: playlist,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final activeGroup = _activeGroup;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: activeGroup == null
          ? const Text('Export')
          : Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => setState(() => _activeGroup = null),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activeGroup.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
      content: SizedBox(
        width: 640,
        height: 520,
        child: activeGroup == null
            ? _buildGroupList(context)
            : _buildTrackList(context, activeGroup),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _selectedCount == 0
              ? null
              : () => Navigator.of(context).pop(_buildSelection()),
          icon: const Icon(Icons.ios_share_outlined),
          label: Text('Export $_selectedCount'),
        ),
      ],
    );
  }

  Widget _buildGroupList(BuildContext context) {
    return ListView.separated(
      itemCount: _groups.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final group = _groups[index];
        final selectedCount = _selectedKeysByGroupId[group.id]?.length ?? 0;
        final knownTracks = _knownTracksFor(group);
        final availableCount = knownTracks
            .where(widget.data.isAvailable)
            .length;
        final isLoading = _loadingGroupIds.contains(group.id);
        final isChecked = availableCount > 0 && selectedCount >= availableCount;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: isLoading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Checkbox(
                  value: isChecked,
                  onChanged: (_) => _toggleWholeGroup(group),
                ),
          title: Text(
            group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            selectedCount == 0
                ? group.subtitle
                : '$selectedCount selected • ${group.subtitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openGroup(group),
        );
      },
    );
  }

  Widget _buildTrackList(BuildContext context, _ExportGroupRef group) {
    final tracks = _knownTracksFor(group);
    final isLoading = _loadingGroupIds.contains(group.id);
    if (isLoading && tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tracks.isEmpty) {
      return const Center(child: Text('No songs found.'));
    }

    return ListView.separated(
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final key = _entryKey(group, track, index);
        final selected =
            _selectedKeysByGroupId[group.id]?.contains(key) ?? false;
        final available = widget.data.isAvailable(track);
        final downloaded = widget.data.isDownloaded(track);
        return Opacity(
          opacity: available ? 1 : 0.45,
          child: CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: selected,
            onChanged: available
                ? (_) => setState(() {
                    final selectedKeys = _selectedKeysByGroupId.putIfAbsent(
                      group.id,
                      () => <String>{},
                    );
                    if (!selectedKeys.add(key)) {
                      selectedKeys.remove(key);
                    }
                  })
                : null,
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              downloaded
                  ? '${track.artist} • Local'
                  : widget.data.isOnline
                  ? '${track.artist} • Will download to export'
                  : '${track.artist} • Not downloaded',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openGroup(_ExportGroupRef group) async {
    setState(() => _activeGroup = group);
    await _ensureGroupTracks(group);
  }

  Future<void> _toggleWholeGroup(_ExportGroupRef group) async {
    final tracks = await _ensureGroupTracks(group);
    if (!mounted) {
      return;
    }
    final availableEntries = <String>{};
    for (var i = 0; i < tracks.length; i += 1) {
      final track = tracks[i];
      if (widget.data.isAvailable(track)) {
        availableEntries.add(_entryKey(group, track, i));
      }
    }
    final selectedEntries = _selectedKeysByGroupId[group.id] ?? <String>{};
    setState(() {
      if (availableEntries.isNotEmpty &&
          selectedEntries.length >= availableEntries.length) {
        _selectedKeysByGroupId.remove(group.id);
      } else {
        _selectedKeysByGroupId[group.id] = availableEntries;
      }
    });
  }

  Future<List<Track>> _ensureGroupTracks(_ExportGroupRef group) async {
    final existing = _tracksByGroupId[group.id];
    if (existing != null) {
      return existing;
    }
    if (_loadingGroupIds.contains(group.id)) {
      return existing ?? const [];
    }

    setState(() => _loadingGroupIds.add(group.id));
    final tracks = switch (group.type) {
      _ExportGroupType.album => await widget.data.loadAlbumTracks(group.album!),
      _ExportGroupType.liked => widget.data.likedTracks,
      _ExportGroupType.playlist => group.playlist!.tracks,
    };
    if (!mounted) {
      return tracks;
    }
    setState(() {
      _tracksByGroupId[group.id] = tracks;
      _loadingGroupIds.remove(group.id);
    });
    return tracks;
  }

  List<Track> _knownTracksFor(_ExportGroupRef group) {
    if (_tracksByGroupId[group.id] != null) {
      return _tracksByGroupId[group.id]!;
    }
    return switch (group.type) {
      _ExportGroupType.album => const [],
      _ExportGroupType.liked => widget.data.likedTracks,
      _ExportGroupType.playlist => group.playlist!.tracks,
    };
  }

  int get _selectedCount {
    var count = 0;
    for (final selected in _selectedKeysByGroupId.values) {
      count += selected.length;
    }
    return count;
  }

  _ExportSelection _buildSelection() {
    final directTracksById = <String, MusicExportTrackRequest>{};
    final playlists = <MusicExportPlaylistRequest>[];
    var hasMissingRemoteTracks = false;

    for (final group in _groups) {
      final selectedKeys = _selectedKeysByGroupId[group.id];
      if (selectedKeys == null || selectedKeys.isEmpty) {
        continue;
      }
      final tracks = _knownTracksFor(group);
      final selectedRequests = <MusicExportTrackRequest>[];
      for (var i = 0; i < tracks.length; i += 1) {
        final track = tracks[i];
        if (!selectedKeys.contains(_entryKey(group, track, i))) {
          continue;
        }
        final request = widget.data.requestFor(track);
        if (request.localDownload == null) {
          hasMissingRemoteTracks = true;
        }
        if (group.type == _ExportGroupType.album) {
          directTracksById.putIfAbsent(track.id, () => request);
        } else {
          selectedRequests.add(request);
        }
      }
      if (selectedRequests.isNotEmpty) {
        playlists.add(
          MusicExportPlaylistRequest(
            name: group.title,
            tracks: selectedRequests,
          ),
        );
      }
    }

    return _ExportSelection(
      directTracks: directTracksById.values.toList(),
      playlists: playlists,
      hasMissingRemoteTracks: hasMissingRemoteTracks,
    );
  }

  String _entryKey(_ExportGroupRef group, Track track, int index) {
    return group.type == _ExportGroupType.playlist
        ? '${track.id}:$index'
        : track.id;
  }
}

class _DownloadsToolbar extends StatelessWidget {
  const _DownloadsToolbar({
    required this.onRepair,
    required this.failedCount,
    required this.onRetryFailed,
    required this.isExporting,
    required this.onExport,
    this.repairMessage,
  });

  final VoidCallback onRepair;
  final int failedCount;
  final VoidCallback onRetryFailed;
  final bool isExporting;
  final VoidCallback onExport;
  final String? repairMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (repairMessage != null)
          Row(
            children: [
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
            ],
          ),
        if (repairMessage != null) const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (failedCount > 0)
                OutlinedButton.icon(
                  onPressed: onRetryFailed,
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: Text('Retry failed ($failedCount)'),
                ),
              OutlinedButton.icon(
                onPressed: isExporting ? null : onExport,
                icon: isExporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_outlined),
                label: Text(isExporting ? 'Exporting...' : 'Export'),
              ),
              OutlinedButton.icon(
                onPressed: onRepair,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Recheck'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineDownloadNotice extends StatelessWidget {
  const _InlineDownloadNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
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
    this.actionIcon,
    this.onAction,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon ?? Icons.refresh_outlined),
                    label: Text(actionLabel!),
                  ),
                  if (secondaryActionLabel != null && onSecondaryAction != null)
                    OutlinedButton.icon(
                      onPressed: onSecondaryAction,
                      icon: Icon(secondaryActionIcon ?? Icons.refresh_outlined),
                      label: Text(secondaryActionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
