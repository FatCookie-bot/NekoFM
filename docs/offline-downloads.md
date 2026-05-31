# Offline Downloads

NekoFM downloads user-owned music for offline playback. Downloads are not DRM, are not encrypted, and are not disabled when the server is unavailable.

## Download Rules

- Downloads should be persistent transfer jobs, not one-off HTTP calls from buttons.
- Track and album downloads should survive app restarts.
- Partial files should be written safely and renamed only after completion.
- Local playback should prefer a verified downloaded file over a server stream.

## Suggested Transfer Model

```text
TransferJob
  id
  serverProfileId
  entityType: track | album
  entityId
  priority
  state
  progress
  retryCount
  createdAt
  updatedAt

TransferItem
  jobId
  trackId
  state
  localPath
  partialPath
  totalBytes
  downloadedBytes
  error
  completedAt
  verifiedAt
```

## File State

Downloaded files should be tracked as:

```text
missing
partial
complete
corrupted
removed
```

At minimum, verification should check that the file exists, is non-empty, and matches the known downloaded byte count when available.

## Current Implementation

The first download slice is implemented for individual tracks.

Current behavior:

- Library track rows and search track rows have download buttons.
- Album detail has a download-album button.
- Album downloads skip tracks that are already downloaded.
- Track and album downloads enter a queued state and are processed one at a time.
- Interrupted in-progress downloads are repaired back into the queue on app load.
- Queued and active downloads can be cancelled from Downloads.
- Failed downloads can be retried individually or all together from Downloads.
- Settings lets the user choose a custom download folder.
- Settings can reset new downloads back to the default app support folder.
- Saving a different download folder can move existing downloads and update SQLite paths.
- Folder moves copy and verify files before deleting old audio or cover files.
- Downloaded tracks save minimal offline metadata: artist, album, song title, track number, local audio path, and local cover path when available.
- New downloads are stored as `Artist/Album/` folders inside the chosen download folder.
- Artist folders contain their album folders.
- Album folders use one shared `cover.jpg`, not one cover per track.
- Download folders receive a `nekofm_downloads_manifest.json` manifest.
- Cover art is downloaded beside tracks when available.
- Library falls back to downloaded albums when the server is unavailable.
- Offline Library groups downloaded tracks by album.
- Downloaded track buttons change to a local-delete action.
- Fully downloaded album button changes to delete album.
- Local deletes remove NekoFM audio files, cover files, partial files, and metadata only.
- Local deletes never delete Navidrome/server/source music.
- Downloads automatically repairs stale metadata when loading.
- Downloads has a manual Recheck button.
- Missing local audio removes the download entry.
- Missing local cover clears the cover path so the app can offer Download covers again.
- Failed downloads show retry buttons in Downloads.
- Failed track actions in Library change to retry.
- Downloads are written to a `.partial` file first.
- The partial file is renamed only after the HTTP download succeeds.
- The completed file is verified to exist and be non-empty.
- Download metadata persists in SQLite under the app support directory.
- Existing SharedPreferences download metadata is imported into SQLite once.
- Downloaded audio files live in the chosen download folder.
- The Downloads tab shows queued, downloading, complete, and failed states.
- Playback checks for a verified local file before falling back to the server stream.
- Player and mini-player show whether playback is local or streaming.
- Offline search can use downloaded metadata when Navidrome is unavailable.

Changing the download folder can either affect new downloads only or move existing complete downloads into the selected folder. Folder moves are blocked while downloads are queued or active.

Still needed:

- stronger multi-item download job model
- richer offline search ranking

## App Downloads Versus Exports

App-managed downloads are for reliable offline playback inside NekoFM. Exports are user-visible folders for SD cards, USB drives, and other players.

Current export behavior:

- Downloads has an export builder instead of a blind export-all flow.
- The export builder shows albums, custom playlists, and Liked.
- Checking a row selects the whole album/playlist/Liked list.
- Clicking a row opens it so individual songs can be selected, with a back button to return to the export menu.
- Offline unavailable songs are dimmed and cannot be selected.
- Online unavailable songs can be selected and are downloaded directly into the export folder without being added to the app-managed download library.
- Exports copy files into `Music/Artist/Album/` folders inside the selected export folder.
- Playlist files are written into `Playlists/`.
- Exports copy one `cover.jpg` per album when a local cover is available.
- Exports write `.m3u` files for selected custom playlists and Liked.
- Direct album selections copy audio and covers; they do not create album `.m3u` files by default.
- M3U entries use relative paths so the exported folder can be moved to an SD card or USB drive.
- M3U entries are written only for songs that were actually copied or downloaded into the export folder.
- If a playlist intentionally contains the same song multiple times, the exported `.m3u` preserves those repeated playlist entries while exporting the audio file once.
- If two exported songs would use the same filename, the later file gets its track id appended instead of overwriting the first.
- Exports write a hidden `.nekofm_export_manifest.json` so future clean exports know which old files NekoFM created.
- When exporting into a folder with an existing NekoFM export, the app asks whether to update in place or clean previous NekoFM export files first.
- Exports never move, delete, or rewrite app-managed downloads.

## Liked Playlist

Liked songs are stored inside SQLite as app metadata. M3U is intentionally not used for the in-app liked playlist.

M3U should be added later as an export format for SD card and car playback. Exported M3U files should use paths relative to the exported music folder, not absolute macOS paths.

Liked songs have an explicit SQLite `position` value. The Liked page has a reorder mode:

- `Reorder` unlocks order editing without stopping playback.
- Tapping one song highlights it; tapping another song swaps the two songs.
- Long-press/drag moves songs.
- `Confirm order` persists the new order and updates the active Liked playback queue when Liked is currently playing.
- `Cancel` leaves the saved order unchanged.

## Custom Playlists

Custom playlists are stored in SQLite as app metadata:

- `playlists` stores id, name, created time, and updated time.
- `playlist_tracks` stores copied track metadata and playlist position.
- Library track rows can add a track to a playlist.
- Adding a track opens a multi-select playlist picker with a confirm button.
- Playlists that already contain the chosen track show an `Already added` note in the picker.
- If a selected playlist already contains that track, NekoFM asks before adding another copy.
- The duplicate prompt can cancel, skip existing playlists, or add another copy anyway.
- Playlists can intentionally contain duplicate copies of the same song.
- The Playlists tab can create playlists, open them, play them, remove tracks, and delete playlists.
- The Playlists tab can like/unlike tracks inside a playlist.
- Playlist detail has the same reorder mode as Liked.
- Playlist reorder persists `playlist_tracks.position` by `entry_id`, so duplicate copies of the same song can be moved independently.
- Confirming playlist reorder updates the active playback queue when that playlist is currently playing, without restarting the current song.
- Playlist playback uses the same player path as albums, so downloaded tracks are still preferred when available.
