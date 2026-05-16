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

## App Downloads Versus Exports

App-managed downloads are for reliable offline playback inside NekoFM. Exports are user-visible folders for SD cards, USB drives, and other players.
