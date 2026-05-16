import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final _searchController = TextEditingController();

  Future<List<Album>>? _albumsFuture;
  Future<AlbumDetail>? _albumDetailFuture;
  Future<LibrarySearchResult>? _searchFuture;
  Album? _selectedAlbum;
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedAlbum != null) {
      return _AlbumDetailView(
        album: _selectedAlbum!,
        albumDetailFuture: _albumDetailFuture!,
        onBack: _clearSelectedAlbum,
        onRetry: () => _openAlbum(_selectedAlbum!),
        onPlayTrack: _playTrack,
      );
    }

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
                  onRefresh: _loadAlbums,
                  onOpenAlbum: _openAlbum,
                )
              : _SearchResultsView(
                  query: _searchQuery,
                  searchFuture: _searchFuture,
                  onOpenAlbum: _openAlbum,
                  onPlayTrack: _playSearchTrack,
                ),
        ),
      ],
    );
  }

  void _loadAlbums() {
    setState(() {
      _albumsFuture = _repository.getAlbums();
    });
  }

  void _openAlbum(Album album) {
    setState(() {
      _selectedAlbum = album;
      _albumDetailFuture = _repository.getAlbum(album.id);
    });
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
      _searchFuture = query.length < 2 ? null : _repository.search(query);
    });
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
    required this.onRefresh,
    required this.onOpenAlbum,
  });

  final Future<List<Album>>? albumsFuture;
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
            icon: Icons.album_outlined,
            title: 'No albums found',
            message:
                'Navidrome is connected, but it did not return any albums yet.',
            actionLabel: 'Refresh',
            onAction: onRefresh,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView.separated(
            itemCount: albums.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final album = albums[index];
              return _AlbumTile(album: album, onTap: () => onOpenAlbum(album));
            },
          ),
        );
      },
    );
  }
}

class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({
    required this.query,
    required this.searchFuture,
    required this.onOpenAlbum,
    required this.onPlayTrack,
  });

  final String query;
  final Future<LibrarySearchResult>? searchFuture;
  final ValueChanged<Album> onOpenAlbum;
  final ValueChanged<Track> onPlayTrack;

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
                _SearchTrackTile(track: track, onTap: () => onPlayTrack(track)),
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
    required this.onBack,
    required this.onRetry,
    required this.onPlayTrack,
  });

  final Album album;
  final Future<AlbumDetail> albumDetailFuture;
  final VoidCallback onBack;
  final VoidCallback onRetry;
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

              return ListView.separated(
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  return _TrackTile(
                    track: tracks[index],
                    onTap: () =>
                        onPlayTrack(album: album, tracks: tracks, index: index),
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
  const _TrackTile({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

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
      trailing: const Icon(Icons.play_arrow_outlined),
      onTap: onTap,
    );
  }
}

class _SearchTrackTile extends StatelessWidget {
  const _SearchTrackTile({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

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
      trailing: const Icon(Icons.play_arrow_outlined),
      onTap: onTap,
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
