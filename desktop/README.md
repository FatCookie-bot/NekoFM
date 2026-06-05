# NekoFM React/Tauri

This folder contains the current NekoFM desktop app.

The old Flutter app was removed on 2026-06-05 after React/Tauri became the main implementation.

Read the current migration handoff before continuing work:

- `../docs/react-tauri-migration-status.md`

## Common Commands

```sh
npm run build
npm run tauri build -- --bundles app
```

Rust checks:

```sh
cd src-tauri
cargo test
cargo check
```
