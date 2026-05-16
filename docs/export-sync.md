# Export Sync

Export is a separate feature from app downloads. Downloads make music playable offline in NekoFM. Exports create user-visible copies for SD cards, USB drives, folders, and other players.

## Export Principles

- Never delete original music from the server.
- Never delete exported files unless the user explicitly chooses that behavior.
- Default to preserving original audio files and metadata.
- Use metadata for the default folder layout.
- Allow naming templates later.

## Default Layout

```text
Music/
  {AlbumArtist}/
    {Album}/
      {TrackNumber} - {Title}.{ext}
```

## Manifest

Exports should write a visible manifest file:

```text
.neko-fm-export.json
```

The manifest records which files NekoFM exported, where they were written, and which source server/library items they came from.

This lets NekoFM safely skip unchanged files, update changed files, and delete only files it previously exported if the user enables that option.

## Delete Behavior

Export profiles should let the user choose:

```text
Never delete exported files
Delete only files NekoFM previously exported
Ask before deleting
```

The app must not silently delete unknown files from the target.
