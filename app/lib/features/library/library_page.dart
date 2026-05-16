import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_controller.dart';
import '../../core/downloads/download_repository.dart';
import '../../core/downloads/downloaded_track.dart';
import '../../core/library/album.dart';
import '../../core/library/album_detail.dart';
import '../../core/library/library_search_result.dart';
import '../../core/library/music_library_repository.dart';
import '../../core/library/track.dart';
import '../../core/player/player_controller.dart';
import '../player/album_art.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _repository = MusicLibraryRepository();
  final _downloadRepository = DownloadRepository();
  final _searchController = TextEditingController();

  Future<List<Album>>? _albumsFuture;
  Future<AlbumDetail>? _albumDetailFuture;
  Future<LibrarySearchResult>? _searchFuture;
  Map<String, AlbumDetail> _downloadedAlbumDetails = const {};
  Album? _selectedAlbum;
  Timer? _searchDebounce;
  String _searchQuery = '';
  bool _isShowingDownloadedLibrary = false;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    ref.read(downloadControllerProvider).load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.read(downloadControllerProvider);
    if (_selectedAlbum != null) {
      return ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          return _AlbumDetailView(
            album: _selectedAlbum!,
            albumDetailFuture: _albumDetailFuture!,
            downloads: downloads,
            onBack: _clearSelectedAlbum,
            onRetry: () => _openAlbum(_selectedAlbum!),
            onPlayTrack: _playTrack,
            onDownloadTrack: downloads.downloadTrack,
            onDownloadAlbum: downloads.downloadTracks,
            onDeleteTrack: _deleteTrackDownload,
            onDeleteAlbum: _deleteAlbumDownloads,
          );
        },
      );
    }

    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        return Column(
          children: [
            _LibrarySearchField(
              controller: _searchController,
              onChanged: _queueSearch,
              onClear: _clearSearch,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _searchQuery.isEmpty
                  ? _AlbumBrowser(
                      albumsFuture: _albumsFuture,
                      isDownloadedLibrary: _isShowingDownloadedLibrary,
                      onRefresh: _loadAlbums,
                      onOpenAlbum: _openAlbum,
                    )
                  : _SearchResultsView(
                      query: _searchQuery,
                      searchFuture: _searchFuture,
                      downloads: downloads,
                      onOpenAlbum: _openAlbum,
                      onPlayTrack: _playSearchTrack,
                      onDownloadTrack: downloads.downloadTrack,
                      onDeleteTrack: _deleteTrackDownload,
                    ),
            ),
          ],
        );
      },
    );
  }

  void _loadAlbums() {
    setState(() {
      _albumsFuture = _loadAlbumsWithOfflineFallback();
    });
  }

  void _openAlbum(Album album) {
    final downloadedDetail = _downloadedAlbumDetails[album.id];
    setState(() {
      _selectedAlbum = album;
      _albumDetailFuture = downloadedDetail == null
          ? _repository.getAlbum(album.id)
          : Future.value(downloadedDetail);
    });
  }

  Future<List<Album>> _loadAlbumsWithOfflineFallback() async {
    try {
      final albums = await _repository.getAlbums();
      _downloadedAlbumDetails = const {};
      _isShowingDownloadedLibrary = false;
      return albums;
    } on Object {
      final downloadedDetails = await _downloadRepository
          .loadDownloadedAlbumDetails();
      _downloadedAlbumDetails = {
        for (final detail in downloadedDetails) detail.album.id: detail,
      };
      _isShowingDownloadedLibrary = true;
      return [for (final detail in downloadedDetails) detail.album];
    }
  }

  void _clearSelectedAlbum() {
    setState(() {
      _selectedAlbum = null;
      _albumDetailFuture = null;
    });
  }

  void _queueSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }

      _runSearch(value);
    });
  }

  void _runSearch(String value) {
    final query = value.trim();
    setState(() {
      _searchQuery = query;
      _searchFuture = query.length < 2 ? null : _searchWithFallback(query);
    });
  }

  Future<LibrarySearchResult> _searchWithFallback(String query) async {
    if (_isShowingDownloadedLibrary) {
      return _downloadRepository.searchDownloaded(query);
    }

    try {
      return await _repository.search(query);
    } on Object {
      return _downloadRepository.searchDownloaded(query);
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchFuture = null;
    });
  }

  Future<void> _playTrack({
    required Album album,
    required List<Track> tracks,
    required int index,
  }) {
    return ref
        .read(playerControllerProvider)
        .playAlbum(album: album, tracks: tracks, startIndex: index);
  }

  Future<void> _playSearchTrack(Track track) async {
    final albumId = track.albumId;
    if (albumId != null && albumId.isNotEmpty) {
      final downloadedDetail = _downloadedAlbumDetails[albumId];
      if (downloadedDetail != null) {
        final index = downloadedDetail.tracks.indexWhere(
          (item) => item.id == track.id,
        );
        if (index >= 0) {
          await ref
              .read(playerControllerProvider)
              .playAlbum(
                album: downloadedDetail.album,
                tracks: downloadedDetail.tracks,
                startIndex: index,
              );
          return;
        }
      }

      try {
        final detail = await _repository.getAlbum(albumId);
        final index = detail.tracks.indexWhere((item) => item.id == track.id);
        if (index >= 0) {
          await ref
              .read(playerControllerProvider)
              .playAlbum(
                album: detail.album,
                tracks: detail.tracks,
                startIndex: index,
              );
          return;
        }
      } on Object {
        // Fall back to a single-track queue when album lookup is unavailable.
      }
    }

    await ref
        .read(playerControllerProvider)
        .playAlbum(
          album: _albumFromTrack(track),
          tracks: [track],
          startIndex: 0,
        );
  }

  Future<void> _deleteTrackDownload(Track track) async {
    await ref.read(downloadControllerProvider).deleteTrack(track.id);
    if (!_isShowingDownloadedLibrary || _selectedAlbum == null) {
      return;
    }

    final downloadedDetails = await _downloadRepository
        .loadDownloadedAlbumDetails();
    _downloadedAlbumDetails = {
      for (final detail in downloadedDetails) detail.album.id: detail,
    };
    final detail = _downloadedAlbumDetails[_selectedAlbum!.id];
    if (!mounted) {
      return;
    }

    setState(() {
      if (detail == null) {
        _selectedAlbum = null;
        _albumDetailFuture = null;
        _albumsFuture = Future.value([
          for (final item in downloadedDetails) item.album,
        ]);
      } else {
        _albumDetailFuture = Future.value(detail);
        _albumsFuture = Future.value([
          for (final item in downloadedDetails) item.album,
        ]);
      }
    });
  }

  Future<void> _deleteAlbumDownloads(List<Track> tracks) async {
    await ref.read(downloadControllerProvider).deleteTracks(tracks);
    if (!_isShowingDownloadedLibrary || !mounted) {
      return;
    }

    setState(() {
      _selectedAlbum = null;
      _albumDetailFuture = null;
      _albumsFuture = _loadAlbumsWithOfflineFallback();
    });
  }

  Album _albumFromTrack(Track track) {
    return Album(
      id: track.albumId ?? track.id,
      name: track.albumName ?? 'Search result',
      artist: track.artist,
      songCount: 1,
      durationSeconds: track.durationSeconds,
      coverArtId: track.coverArtId,
      coverArtUri: track.coverArtUri,
    );
  }
}

class _LibrarySearchField extends StatelessWidget {
  const _LibrarySearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Search library',
            hintText: 'Song, album, or artist',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: onClear,
                  ),
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _AlbumBrowser extends StatelessWidget {
  const _AlbumBrowser({
    required this.albumsFuture,
    required this.isDownloadedLibrary,
    required this.onRefresh,
    required this.onOpenAlbum,
  });

  final Future<List<Album>>? albumsFuture;
  final bool isDownloadedLibrary;
  final VoidCallback onRefresh;
  final ValueChanged<Album> onOpenAlbum;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Album>>(
      future: albumsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LibraryLoading();
        }

        if (snapshot.hasError) {
          return _LibraryMessage(
            icon: Icons.error_outline,
            title: 'Could not load library',
            message: snapshot.error.toString(),
            actionLabel: 'Retry',
            onAction: onRefresh,
          );
        }

        final albums = snapshot.data ?? const <Album>[];
        if (albums.isEmpty) {
          return _LibraryMessage(
            icon: isDownloadedLibrary
                ? Icons.download_done_outlined
                : Icons.album_outlined,
            title: isDownloadedLibrary
                ? 'No downloaded albums'
                : 'No albums found',
            message: isDownloadedLibrary
                ? 'Navidrome is offline and there are no completed album downloads on this device.'
                : 'Navidrome is connected, but it did not return any albums yet.',
            actionLabel: 'Refresh',
            onAction: onRefresh,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isDownloadedLibrary) ...[
              const _OfflineLibraryNotice(),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => onRefresh(),
                child: ListView.separated(
                  itemCount: albums.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return _AlbumTile(
                      album: album,
                      onTap: () => onOpenAlbum(album),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OfflineLibraryNotice extends StatelessWidget {
  const _OfflineLibraryNotice();

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
              'Navidrome is offline. Showing albums downloaded on this device.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({
    required this.query,
    required this.searchFuture,
    required this.downloads,
    required this.onOpenAlbum,
    required this.onPlayTrack,
    required this.onDownloadTrack,
    required this.onDeleteTrack,
  });

  final String query;
  final Future<LibrarySearchResult>? searchFuture;
  final DownloadController downloads;
  final ValueChanged<Album> onOpenAlbum;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onDownloadTrack;
  final ValueChanged<Track> onDeleteTrack;

  @override
  Widget build(BuildContext context) {
    if (query.length < 2) {
      return const _LibraryMessage(
        icon: Icons.search,
        title: 'Keep typing',
        message: 'Search starts after 2 characters.',
      );
    }

    return FutureBuilder<LibrarySearchResult>(
      future: searchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LibraryLoading();
        }

        if (snapshot.hasError) {
          return _LibraryMessage(
            icon: Icons.error_outline,
            title: 'Search failed',
            message: snapshot.error.toString(),
          );
        }

        final result =
            snapshot.data ?? const LibrarySearchResult(albums: [], tracks: []);
        if (result.isEmpty) {
          return _LibraryMessage(
            icon: Icons.search_off,
            title: 'No results',
            message: 'Nothing matched "$query".',
          );
        }

        return ListView(
          children: [
            if (result.albums.isNotEmpty) ...[
              const _ResultSectionHeader(label: 'Albums'),
              for (final album in result.albums)
                _AlbumTile(album: album, onTap: () => onOpenAlbum(album)),
            ],
            if (result.albums.isNotEmpty && result.tracks.isNotEmpty)
              const Divider(height: 24),
            if (result.tracks.isNotEmpty) ...[
              const _ResultSectionHeader(label: 'Tracks'),
              for (final track in result.tracks)
                _SearchTrackTile(
                  track: track,
                  download: downloads.trackState(track.id),
                  onTap: () => onPlayTrack(track),
                  onDownload: () => onDownloadTrack(track),
                  onDelete: () => _confirmDeleteTrack(context, track, () {
                    onDeleteTrack(track);
                  }),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _AlbumDetailView extends StatelessWidget {
  const _AlbumDetailView({
    required this.album,
    required this.albumDetailFuture,
    required this.downloads,
    required this.onBack,
    required this.onRetry,
    required this.onPlayTrack,
    required this.onDownloadTrack,
    required this.onDownloadAlbum,
    required this.onDeleteTrack,
    required this.onDeleteAlbum,
  });

  final Album album;
  final Future<AlbumDetail> albumDetailFuture;
  final DownloadController downloads;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final ValueChanged<Track> onDownloadTrack;
  final ValueChanged<List<Track>> onDownloadAlbum;
  final ValueChanged<Track> onDeleteTrack;
  final ValueChanged<List<Track>> onDeleteAlbum;
  final Future<void> Function({
    required Album album,
    required List<Track> tracks,
    required int index,
  })
  onPlayTrack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to albums',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            AlbumArt(
              imageUri: album.coverArtUri,
              size: 64,
              semanticLabel: '${album.name} cover art',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<AlbumDetail>(
            future: albumDetailFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _LibraryLoading();
              }

              if (snapshot.hasError) {
                return _LibraryMessage(
                  icon: Icons.error_outline,
                  title: 'Could not load album',
                  message: snapshot.error.toString(),
                  actionLabel: 'Retry',
                  onAction: onRetry,
                );
              }

              final tracks = snapshot.data?.tracks ?? const <Track>[];
              if (tracks.isEmpty) {
                return _LibraryMessage(
                  icon: Icons.music_note_outlined,
                  title: 'No tracks found',
                  message: 'This album did not include any playable tracks.',
                  actionLabel: 'Retry',
                  onAction: onRetry,
                );
              }

              final albumDownload = _AlbumDownloadState.fromTracks(
                tracks,
                downloads,
              );

              return ListView.separated(
                itemCount: tracks.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _AlbumDownloadTile(
                      state: albumDownload,
                      onDownload: () => onDownloadAlbum(tracks),
                      onDelete: () => _confirmDeleteAlbum(
                        context,
                        album.name,
                        () => onDeleteAlbum(tracks),
                      ),
                    );
                  }

                  final track = tracks[index - 1];
                  return _TrackTile(
                    track: track,
                    download: downloads.trackState(track.id),
                    onTap: () => onPlayTrack(
                      album: album,
                      tracks: tracks,
                      index: index - 1,
                    ),
                    onDownload: () => onDownloadTrack(track),
                    onDelete: () => _confirmDeleteTrack(context, track, () {
                      onDeleteTrack(track);
                    }),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AlbumDownloadTile extends StatelessWidget {
  const _AlbumDownloadTile({
    required this.state,
    required this.onDownload,
    required this.onDelete,
  });

  final _AlbumDownloadState state;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = state.hasActiveDownloads;
    final subtitle = state.isComplete
        ? 'All tracks are saved for offline playback.'
        : state.hasMissingCovers
        ? '${state.missingCoverCount} local covers missing'
        : state.hasActiveDownloads
        ? '${state.downloadingCount} downloading • ${state.completeCount}/${state.totalCount} saved'
        : '${state.remainingCount} tracks not saved yet';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: Icon(
        state.isComplete ? Icons.download_done : Icons.download_for_offline,
        color: state.isComplete ? colorScheme.tertiary : colorScheme.primary,
      ),
      title: Text(state.buttonLabel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          if (!state.isComplete && state.completeCount > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: state.progress,
              minHeight: 4,
              semanticsLabel: 'Album download progress',
              semanticsValue:
                  '${state.completeCount} of ${state.totalCount} tracks saved',
            ),
          ],
        ],
      ),
      trailing: FilledButton.icon(
        onPressed: isDisabled
            ? null
            : state.isComplete
            ? onDelete
            : onDownload,
        icon: Icon(state.isComplete ? Icons.delete_outline : Icons.download),
        label: Text(state.buttonLabel),
      ),
    );
  }
}

class _AlbumDownloadState {
  const _AlbumDownloadState({
    required this.totalCount,
    required this.completeCount,
    required this.downloadingCount,
    required this.missingCoverCount,
  });

  final int totalCount;
  final int completeCount;
  final int downloadingCount;
  final int missingCoverCount;

  int get remainingCount => totalCount - completeCount - downloadingCount;
  double get progress => totalCount <= 0 ? 0 : completeCount / totalCount;
  bool get isComplete =>
      totalCount > 0 && completeCount == totalCount && missingCoverCount == 0;
  bool get hasActiveDownloads => downloadingCount > 0;
  bool get hasMissingCovers =>
      totalCount > 0 && completeCount == totalCount && missingCoverCount > 0;

  String get buttonLabel {
    if (isComplete) {
      return 'Delete album';
    }

    if (hasMissingCovers) {
      return 'Download covers';
    }

    if (hasActiveDownloads) {
      return 'Downloading album';
    }

    if (completeCount > 0) {
      return 'Download missing';
    }

    return 'Download album';
  }

  factory _AlbumDownloadState.fromTracks(
    List<Track> tracks,
    DownloadController downloads,
  ) {
    var completeCount = 0;
    var downloadingCount = 0;
    var missingCoverCount = 0;
    for (final track in tracks) {
      final download = downloads.trackState(track.id);
      final state = download?.state;
      if (state == DownloadState.complete) {
        completeCount += 1;
        if (track.coverArtUri != null && download?.localCoverPath == null) {
          missingCoverCount += 1;
        }
      } else if (state == DownloadState.downloading) {
        downloadingCount += 1;
      }
    }

    return _AlbumDownloadState(
      totalCount: tracks.length,
      completeCount: completeCount,
      downloadingCount: downloadingCount,
      missingCoverCount: missingCoverCount,
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      album.artist,
      if (album.year != null && album.year != 0) album.year.toString(),
      '${album.songCount} tracks',
      _formatDuration(album.durationSeconds),
    ].join(' • ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: AlbumArt(
        imageUri: album.coverArtUri,
        size: 44,
        semanticLabel: '${album.name} cover art',
      ),
      title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.download,
    required this.onTap,
    required this.onDownload,
    required this.onDelete,
  });

  final Track track;
  final DownloadedTrack? download;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final number = track.trackNumber == 0 ? '-' : track.trackNumber.toString();
    final subtitle = [
      track.artist,
      _formatDuration(track.durationSeconds),
      if (track.suffix != null) track.suffix!.toUpperCase(),
    ].join(' • ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Text(number, style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _TrackActions(
        download: download,
        onDownload: onDownload,
        onDelete: onDelete,
      ),
      onTap: onTap,
    );
  }
}

class _SearchTrackTile extends StatelessWidget {
  const _SearchTrackTile({
    required this.track,
    required this.download,
    required this.onTap,
    required this.onDownload,
    required this.onDelete,
  });

  final Track track;
  final DownloadedTrack? download;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      track.artist,
      if (track.albumName != null) track.albumName!,
      _formatDuration(track.durationSeconds),
      if (track.suffix != null) track.suffix!.toUpperCase(),
    ].join(' • ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: AlbumArt(
        imageUri: track.coverArtUri,
        size: 44,
        semanticLabel: '${track.title} cover art',
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _TrackActions(
        download: download,
        onDownload: onDownload,
        onDelete: onDelete,
      ),
      onTap: onTap,
    );
  }
}

class _TrackActions extends StatelessWidget {
  const _TrackActions({
    required this.download,
    required this.onDownload,
    required this.onDelete,
  });

  final DownloadedTrack? download;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final state = download?.state;
    final isDownloading = state == DownloadState.downloading;
    final isComplete = state == DownloadState.complete;
    final isFailed = state == DownloadState.failed;

    if (isDownloading) {
      return SizedBox.square(
        dimension: 40,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: download?.progress,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: isComplete
              ? 'Delete local download'
              : isFailed
              ? 'Retry download'
              : 'Download track',
          onPressed: isComplete ? onDelete : onDownload,
          icon: Icon(
            isComplete
                ? Icons.close
                : isFailed
                ? Icons.refresh_outlined
                : Icons.download_outlined,
          ),
        ),
        const Icon(Icons.play_arrow_outlined),
      ],
    );
  }
}

class _ResultSectionHeader extends StatelessWidget {
  const _ResultSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

Future<void> _confirmDeleteTrack(
  BuildContext context,
  Track track,
  VoidCallback onConfirm,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Delete local download?'),
        content: Text(
          'Remove "${track.title}" from this device. This will not delete anything from Navidrome.',
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

Future<void> _confirmDeleteAlbum(
  BuildContext context,
  String albumName,
  VoidCallback onConfirm,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Delete local album?'),
        content: Text(
          'Remove all downloaded tracks from "$albumName" on this device. This will not delete anything from Navidrome.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete album'),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    onConfirm();
  }
}

class _LibraryLoading extends StatelessWidget {
  const _LibraryLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
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
            Icon(icon, size: 44, color: colorScheme.primary),
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
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) {
    return '0:00';
  }

  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
}
