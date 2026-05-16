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
- Settings lets the user choose a custom download folder.
- Settings can reset new downloads back to the default app support folder.
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
- The Downloads tab shows downloading, complete, and failed states.
- Playback checks for a verified local file before falling back to the server stream.
- Player and mini-player show whether playback is local or streaming.
- Offline search can use downloaded metadata when Navidrome is unavailable.

Changing the download folder affects new downloads only. Existing downloads keep their saved local paths.

Still needed:

- moving existing downloads to a new folder
- stronger download job model
- richer offline search ranking

## App Downloads Versus Exports

App-managed downloads are for reliable offline playback inside NekoFM. Exports are user-visible folders for SD cards, USB drives, and other players.
