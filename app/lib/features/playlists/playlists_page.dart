import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/album.dart';
import '../../core/likes/liked_controller.dart';
import '../../core/player/player_controller.dart';
import '../../core/playlists/playlist.dart';
import '../../core/playlists/playlist_controller.dart';
import '../../core/playlists/playlist_track.dart';
import '../player/album_art.dart';
import '../player/playback_formatting.dart';

class PlaylistsPage extends ConsumerStatefulWidget {
  const PlaylistsPage({super.key});

  @override
  ConsumerState<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends ConsumerState<PlaylistsPage> {
  Playlist? _selectedPlaylist;
  bool _isReordering = false;
  int? _selectedReorderIndex;
  List<PlaylistTrack> _reorderDraft = const [];

  @override
  void initState() {
    super.initState();
    ref.read(playlistControllerProvider).load();
    ref.read(likedControllerProvider).load();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.read(playlistControllerProvider);
    final liked = ref.read(likedControllerProvider);
    final player = ref.read(playerControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([playlists, liked, player]),
      builder: (context, _) {
        if (!playlists.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final selected = _selectedPlaylist;
        if (selected != null) {
          final tracks = _isReordering
              ? _reorderDraft
              : playlists.tracksFor(selected.id);
          return _PlaylistDetailView(
            playlist: selected,
            tracks: tracks,
            liked: liked,
            player: player,
            isReordering: _isReordering,
            selectedReorderIndex: _selectedReorderIndex,
            onBack: () => setState(() {
              _selectedPlaylist = null;
              _isReordering = false;
              _selectedReorderIndex = null;
              _reorderDraft = const [];
            }),
            onPlay: (index) => _playPlaylist(selected, index),
            onDelete: () => _confirmDeletePlaylist(selected),
            onToggleLiked: (track) => liked.toggleTrack(track.toTrack()),
            onRemoveTrack: (track) =>
                playlists.removeEntry(selected.id, track.entryId),
            onStartReorder: () =>
                _startPlaylistReorder(playlists.tracksFor(selected.id)),
            onCancelReorder: _cancelPlaylistReorder,
            onConfirmReorder: () => _confirmPlaylistReorder(selected),
            onMoveReorder: _movePlaylistDraft,
            onSelectOrSwapReorder: _selectOrSwapPlaylist,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _createPlaylist,
                icon: const Icon(Icons.add),
                label: const Text('New playlist'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: playlists.playlists.isEmpty
                  ? const _PlaylistsMessage()
                  : ListView.separated(
                      itemCount: playlists.playlists.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final playlist = playlists.playlists[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          leading: const Icon(Icons.queue_music_outlined),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${playlist.trackCount} tracks'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await playlists.loadTracks(playlist.id);
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _selectedPlaylist = playlist;
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createPlaylist() async {
    final name = await _promptForPlaylistName(context);
    if (name == null || name.trim().isEmpty) {
      return;
    }

    await ref.read(playlistControllerProvider).createPlaylist(name);
  }

  Future<void> _confirmDeletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete playlist?'),
          content: Text('Delete "${playlist.name}" from NekoFM.'),
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

    if (confirmed != true) {
      return;
    }

    await ref.read(playlistControllerProvider).deletePlaylist(playlist.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPlaylist = null;
    });
  }

  Future<void> _playPlaylist(Playlist playlist, int index) {
    final tracks = _isReordering
        ? _reorderDraft
        : ref.read(playlistControllerProvider).tracksFor(playlist.id);
    if (tracks.isEmpty) {
      return Future.value();
    }

    return ref
        .read(playerControllerProvider)
        .playAlbum(
          album: Album(
            id: playlist.id,
            name: playlist.name,
            artist: 'Playlist',
            songCount: tracks.length,
            durationSeconds: tracks.fold(
              0,
              (total, track) => total + track.durationSeconds,
            ),
            coverArtUri: tracks.first.toTrack().coverArtUri,
          ),
          tracks: [for (final track in tracks) track.toTrack()],
          startIndex: index,
        );
  }

  void _startPlaylistReorder(List<PlaylistTrack> tracks) {
    setState(() {
      _isReordering = true;
      _selectedReorderIndex = null;
      _reorderDraft = List<PlaylistTrack>.of(tracks);
    });
  }

  void _cancelPlaylistReorder() {
    setState(() {
      _isReordering = false;
      _selectedReorderIndex = null;
      _reorderDraft = const [];
    });
  }

  Future<void> _confirmPlaylistReorder(Playlist playlist) async {
    final orderedTracks = List<PlaylistTrack>.of(_reorderDraft);
    await ref
        .read(playlistControllerProvider)
        .reorderTracks(playlist.id, orderedTracks);
    await ref
        .read(playerControllerProvider)
        .reorderCurrentQueue(
          albumId: playlist.id,
          tracks: [for (final track in orderedTracks) track.toTrack()],
        );
    if (!mounted) {
      return;
    }
    _cancelPlaylistReorder();
  }

  void _movePlaylistDraft(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = _reorderDraft.removeAt(oldIndex);
      _reorderDraft.insert(newIndex, moved);
      _selectedReorderIndex = null;
    });
  }

  void _selectOrSwapPlaylist(int index) {
    final selected = _selectedReorderIndex;
    if (selected == null || selected == index) {
      setState(() {
        _selectedReorderIndex = selected == index ? null : index;
      });
      return;
    }

    setState(() {
      final next = List<PlaylistTrack>.of(_reorderDraft);
      final first = next[selected];
      next[selected] = next[index];
      next[index] = first;
      _reorderDraft = next;
      _selectedReorderIndex = null;
    });
  }
}

class _PlaylistDetailView extends StatelessWidget {
  const _PlaylistDetailView({
    required this.playlist,
    required this.tracks,
    required this.liked,
    required this.player,
    required this.isReordering,
    required this.selectedReorderIndex,
    required this.onBack,
    required this.onPlay,
    required this.onDelete,
    required this.onToggleLiked,
    required this.onRemoveTrack,
    required this.onStartReorder,
    required this.onCancelReorder,
    required this.onConfirmReorder,
    required this.onMoveReorder,
    required this.onSelectOrSwapReorder,
  });

  final Playlist playlist;
  final List<PlaylistTrack> tracks;
  final LikedController liked;
  final PlayerController player;
  final bool isReordering;
  final int? selectedReorderIndex;
  final VoidCallback onBack;
  final ValueChanged<int> onPlay;
  final VoidCallback onDelete;
  final ValueChanged<PlaylistTrack> onToggleLiked;
  final ValueChanged<PlaylistTrack> onRemoveTrack;
  final VoidCallback onStartReorder;
  final VoidCallback onCancelReorder;
  final VoidCallback onConfirmReorder;
  final void Function(int oldIndex, int newIndex) onMoveReorder;
  final ValueChanged<int> onSelectOrSwapReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to playlists',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Delete playlist',
              onPressed: isReordering ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
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
              ] else
                OutlinedButton.icon(
                  onPressed: tracks.length < 2 ? null : onStartReorder,
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Reorder'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: tracks.isEmpty
              ? const _PlaylistDetailMessage()
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: tracks.length,
                  onReorder: isReordering ? onMoveReorder : (_, _) {},
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final tile = _PlayingTileFrame(
                      key: ValueKey(track.entryId),
                      isPlaying:
                          !isReordering && player.isCurrentTrack(track.trackId),
                      isSelected: selectedReorderIndex == index,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        leading: AlbumArt(
                          imageUri: track.toTrack().coverArtUri,
                          size: 44,
                          semanticLabel: '${track.title} cover art',
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            track.artist,
                            if (track.albumName != null) track.albumName!,
                            formatPlaybackDuration(
                              Duration(seconds: track.durationSeconds),
                            ),
                          ].join(' • '),
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
                            else ...[
                              IconButton(
                                tooltip: liked.isLiked(track.trackId)
                                    ? 'Remove from liked'
                                    : 'Add to liked',
                                onPressed: () => onToggleLiked(track),
                                icon: Icon(
                                  liked.isLiked(track.trackId)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove from playlist',
                                onPressed: () => onRemoveTrack(track),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Icon(
                                player.isCurrentTrack(track.trackId)
                                    ? Icons.graphic_eq_outlined
                                    : Icons.play_arrow_outlined,
                              ),
                            ],
                          ],
                        ),
                        onTap: isReordering
                            ? () => onSelectOrSwapReorder(index)
                            : () => onPlay(index),
                      ),
                    );
                    if (!isReordering) {
                      return tile;
                    }
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey('reorder-${track.entryId}'),
                      index: index,
                      child: tile,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PlaylistsMessage extends StatelessWidget {
  const _PlaylistsMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Create a playlist, then add tracks from Library.'),
    );
  }
}

class _PlaylistDetailMessage extends StatelessWidget {
  const _PlaylistDetailMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('This playlist is empty.'));
  }
}

class _PlayingTileFrame extends StatelessWidget {
  const _PlayingTileFrame({
    required this.isPlaying,
    required this.child,
    this.isSelected = false,
    super.key,
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

Future<String?> _promptForPlaylistName(BuildContext context) async {
  final controller = TextEditingController();
  try {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Playlist name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
