# NekoFM Architecture

NekoFM is a Flutter client with a local database, a playback layer, a transfer layer, and a provider abstraction for music servers.

## Main Boundary

Navidrome or another Subsonic-compatible server is the source of truth for the library. NekoFM is the client, cache, downloader, player, and export tool.

The UI must not call the server API or playback backend directly.

```text
UI
  -> controllers / use cases
  -> repositories
  -> provider, database, storage, playback backend
```

## Provider Abstraction

The app should define a server provider interface and implement Navidrome through that interface first.

```text
MusicServerProvider
  testConnection()
  getArtists()
  getAlbums()
  getTracks()
  getAlbum(id)
  search(query)
  getStreamUrl(trackId)
  getDownloadUrl(trackId)
  getCoverArt(id)

NavidromeProvider implements MusicServerProvider
```

## Server Identity

Local records should include a `serverProfileId` so the app can support one active server now and multiple servers later.

Server IDs are not globally unique. A local app ID should be separate from the server's track, album, artist, and playlist IDs.

## Playback

Playback should go through a controller and backend abstraction.

```text
UI
  -> PlaybackController
  -> AudioBackend
  -> JustAudioBackend
```

The source resolver chooses a local verified file first, then a server stream when the server is reachable.

## Local Database

Use SQLite through Drift for metadata, server profiles, playable sources, transfer jobs, and export state.

The library UI should read from repositories that can serve local cached data and refresh from the server.

## UI Experiments

Playback, downloads, sync, and export logic should stay outside widgets. This allows the visual design, navigation, and experimental controls to change without breaking core behavior.
