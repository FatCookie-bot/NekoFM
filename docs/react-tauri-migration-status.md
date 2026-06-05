# React/Tauri Status And QA Checklist

This document is the handoff note for the current NekoFM app in `desktop/`.

Flutter was intentionally removed on 2026-06-05 after the user decided the React/Tauri app does not need to be a perfect visual clone. The old Flutter app is no longer the reference implementation. Continue development from the React/Tauri app.

## Current Shape

- React/Tauri app lives in `desktop/`.
- React/Tauri uses React, TypeScript, Vite, Tauri, Rust commands, SQLite, and the OS/browser audio element.
- The desktop app is macOS-first for now.
- The packaged desktop app is configured as a single-instance app; a second launch focuses the existing window instead of starting another copy.
- The React web shell uses NekoFM title/favicon branding instead of the default Vite/Tauri template.
- The non-Tauri browser preview has a small read-only sample library/liked/playlist/download dataset so visual checks can be done without a live Tauri backend.
- The non-Tauri browser preview accepts screenshot URLs such as `?previewScreen=liked` and `?previewAlbum=preview-album-1`.
- The React root is wrapped in an error boundary so render failures show a NekoFM recovery panel instead of leaving a blank window.
- Sensitive/generated files are kept out of git through `.gitignore` entries for `node_modules/`, `dist/`, Tauri `target/`, and generated Tauri folders.

## Implemented In React/Tauri

- Shell/navigation with Library, Player, Liked, Playlists, Downloads, and Settings.
- Clicking an already-active Library, Liked, Playlists, Downloads, or Settings nav item resets that page.
- Settings server profile form, connection test, password visibility, remember-credentials option, HTTP warning, and server scan button.
- When remember-credentials is off, Tauri refuses to reuse any stale Keychain password for saved-profile server calls.
- After a successful connection test, React/Tauri keeps the active server profile in memory for the current app run, so users can browse/stream without saving the password.
- Successful connection tests and server scans notify Library, Liked, and Playlists to recheck server-backed availability.
- A successful Settings server scan also refreshes the in-memory active server profile for the current app run.
- Download folder settings, custom folder picker, reset-to-default, open-folder action, and in-app move-existing-downloads dialog.
- Library album list, album detail, search, offline fallback to downloaded albums, and random play from available library tracks.
- Album and track highlight for the currently playing song/album.
- Player page, mini-player, queue view, local/streaming source chip, like button, add-to-playlist menu, timeline, repeat, shuffle, previous threshold, and queue rows.
- Mini-player is fixed to the bottom of the app viewport/shell when visible, instead of being pushed to the bottom of long page content.
- Player queue current row uses a distinct playing/equalizer-style icon.
- Playback prefers verified local downloads before streaming from the server.
- Playback fixes already ported/tightened:
  - Previous button restarts the real audio element on the first track.
  - Queue navigation while paused stays paused.
  - Old audio pauses immediately while the next source is resolving.
  - Manual Next on the last song with repeat off is a no-op instead of fake-stopping the UI.
  - Repeat wrapping reloads playback even for a one-song queue.
  - Clicking the same song again reloads/restarts it from `0:00`.
  - Timeline scrub/reset state is keyed by queue entry plus playback request, so duplicate playlist entries and forced restarts do not reuse stale preview state.
  - Deleting local downloads removes only local-sourced queue entries.
  - Skip-unavailable queues can drop a failed source and continue to the next playable track.
- Downloads page with album groups, expansion, recheck, retry failed downloads, open folder, local delete, and delete-album dialogs.
- Downloaded files are stored in `Artist/Album/` folders with one `cover.jpg` per album folder.
- Downloads save minimal local metadata in SQLite: song title, artist, album, track number, duration, local audio path, local cover path, format suffix, and state.
- Deleting local tracks removes NekoFM-managed audio, partial files, metadata, and shared cover files only when no remaining local track uses that cover.
- Deleting the last local track in an album folder also removes the NekoFM folder manifest and then removes empty album/artist folders.
- Recheck treats manually missing audio like a local delete: it removes stale metadata, removes the shared cover when no remaining track uses it, and cleans empty NekoFM folders.
- Recheck can recover or redownload missing covers for completed local downloads when possible and reports `downloadedCoverCount`.
- Liked songs in SQLite, with offline unavailable rows dimmed and skipped.
- Liked page has play, shuffle, repeat, download/delete local, unlike, and reorder mode.
- Liked offline playback starts from the first available local song when the first liked row is not downloaded.
- Custom playlists in SQLite, including duplicate playlist entries by `entryId`.
- Playlist creation, rename, delete, play, shuffle, repeat, like/unlike inside playlist, remove entry, and reorder mode.
- Playlist reorder validation rejects missing, unknown, or duplicated submitted entry ids before saving an order.
- Add-to-playlist flow uses multi-select plus confirm; existing playlist membership is shown and duplicate prompts support cancel, skip existing, or add anyway.
- Export builder exists even though export is lower priority: albums, playlists, Liked, individual selection, relative M3U files, and manifest-based clean/update behavior.
- Export clean/update choice uses an in-app dialog instead of a native browser confirm.

## Crucial Manual Checks Still Needed

Run these with the packaged app, not only the browser preview.

- Server connection:
  - Log in to local Navidrome at `http://127.0.0.1:4533`.
  - Test both remembered credentials and current-session-only credentials.
  - Restart the app and confirm remembered credentials still load.
  - Turn remember-credentials off and confirm stale Keychain passwords are not reused.
- Online library:
  - Confirm albums load from Navidrome.
  - Open album detail pages.
  - Search by song, album, and artist.
  - Use Library random play and confirm online-only tracks stream.
- Offline mode:
  - Turn Navidrome off.
  - Confirm Library shows downloaded albums only.
  - Confirm downloaded album covers still appear.
  - Confirm online-only Liked/Playlist rows are dimmed and skipped.
  - Confirm offline playback uses local files.
- Downloads and local metadata:
  - Download a whole album.
  - Download one song from an album and confirm `Artist/Album/cover.jpg` exists.
  - Delete one song while other songs from that album remain; shared cover should remain.
  - Delete the last local song in an album; shared cover, manifest, and empty NekoFM folders should be removed.
  - Manually delete an audio file, then Recheck should remove stale metadata and clean leftovers.
  - Manually delete `cover.jpg`, then Recheck should recover or redownload it when possible.
  - Move/reset the download folder and confirm paths update without stale metadata.
- Playback:
  - Pause, then Next/Previous/queue-row click should stay paused.
  - Repeat off/on at queue end.
  - Shuffle toggle should reorder only upcoming songs and not skip immediately.
  - Reorder Liked/Playlist while currently playing should preserve the current song.
  - Duplicate playlist entries should highlight only the active entry.
  - Downloaded tracks should play locally instead of streaming.
- Liked and playlists:
  - Liked songs survive app restart.
  - Playlist names, order, duplicate entries, likes, and removed entries survive app restart.
  - Add-to-playlist multi-select handles existing tracks with cancel, skip existing, and add anyway.
- Export:
  - Current export builder exists, but it still needs a full SD-card style test.
  - Test albums, selected songs, playlists, Liked, M3U paths, clean/update behavior, and missing online tracks.
- Packaging/runtime:
  - Packaged macOS app launches without Vite/dev server.
  - Tauri permissions are only as broad as needed.
  - No secrets are written into tracked files.
  - Linux readiness can wait, but avoid macOS-only assumptions in React where easy.

## Automated Verification

Run these after meaningful changes:

```sh
cd desktop
npm run build
npm run tauri build -- --bundles app
```

```sh
cd desktop/src-tauri
cargo test
cargo check
```

Rust tests currently cover:

- NekoFM download folder cleanup:
  - Empty album/artist folders are removed after the last local track is deleted.
  - Folders with user files are preserved.
  - Folders still used by another remaining download are preserved.
- Playlist duplicate-entry durability:
  - Duplicate playlist entries for the same song stay independent by `entryId`.
  - Reorder validation rejects duplicate, missing, or unknown ids.

## Preview Screenshots

React preview screenshots live in `docs/visual-parity/react-preview/`.

On 2026-06-05, macOS allowed window ids to be listed through Swift/CoreGraphics but blocked both `screencapture -l <window id>` window capture and useful full-screen capture, producing either `could not create image from window` or a black screenshot. Native screenshots may require Screen Recording/assistive permissions before the next native capture.

## Useful Paths

Packaged app path, relative to repo root:

```text
desktop/src-tauri/target/release/bundle/macos/NekoFM React.app
```

## Working Rule

When the user is satisfied with a stable point and says to move to the next major point, run verification, commit, and push to GitHub before starting the next major task.
