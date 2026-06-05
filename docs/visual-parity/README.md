# Visual Check Screenshots

This folder stores screenshot artifacts for checking the React/Tauri app.

The old Flutter app was removed on 2026-06-05. Screenshots should now be used to catch React/Tauri regressions and compare against prior React/Tauri states, not to chase perfect Flutter parity.

The React preview screenshots are generated from the non-Tauri browser preview dataset. They are not real user music and do not touch Navidrome, SQLite, credentials, or local downloads.

## React Preview URLs

Use these URLs while the React dev server is running on `http://127.0.0.1:1420`.

```text
Library:
http://127.0.0.1:1420/?previewScreen=library&previewPlayer=1

Album detail:
http://127.0.0.1:1420/?previewScreen=library&previewAlbum=preview-album-1&previewPlayer=1

Player:
http://127.0.0.1:1420/?previewScreen=player&previewPlayer=1

Liked:
http://127.0.0.1:1420/?previewScreen=liked&previewPlayer=1

Playlists:
http://127.0.0.1:1420/?previewScreen=playlists&previewPlayer=1

Downloads:
http://127.0.0.1:1420/?previewScreen=downloads&previewPlayer=1

Settings:
http://127.0.0.1:1420/?previewScreen=settings&previewPlayer=1
```

## Current React Baseline

Current React preview screenshots live in `react-preview/`:

- `library.png`
- `album-detail.png`
- `player.png`
- `liked.png`
- `playlists.png`
- `downloads.png`
- `settings.png`

## Capture Note

On 2026-06-05, macOS blocked direct native window capture: Swift/CoreGraphics could list the app window id, but `screencapture -l <window id>` failed with `could not create image from window`, and full-screen capture returned a black image. Grant Screen Recording/assistive permissions before relying on native capture again.

## Recent Visual Fixes

- React preview Library was adjusted on 2026-06-05:
  wider rail, larger rail icons/labels, selected icon pill with the label outside the pill, taller album rows, larger album metadata, larger search/toolbar controls, empty search prompt, and album-row chevrons.
- React preview Settings was adjusted on 2026-06-05:
  server, password, and download-folder inputs now use outlined floating-label styling.
- React preview Player was adjusted on 2026-06-05:
  the current queue row now uses a distinct playing/equalizer-style icon instead of the same music-note icon as upcoming rows.
- React preview shell was adjusted on 2026-06-05:
  the mini-player is fixed to the bottom of the app viewport/shell when visible, instead of being laid out after long page content.
