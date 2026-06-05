# NekoFM Product Decisions

NekoFM is an accountless, user-owned music client. It has no hosted NekoFM account, no central service, and no cloud telemetry.

## Project Shape

- Primary supported server for MVP: Navidrome.
- Protocol target: Subsonic-compatible API.
- MVP compatibility promise: tested with Navidrome only.
- Architecture goal: allow other Subsonic-compatible servers later without hardwiring UI to Navidrome.
- Target platforms: macOS first, Android second, Linux third. Windows and iOS are later.
- The repository can be public, but the app is built for personal use first.

## Server Profiles

NekoFM stores local server profiles. A profile contains the server URL, display name, server type, username, and optionally remembered credentials.

The app does not create NekoFM accounts. The user's server account is the only account involved.

## Remote Access

- `http://localhost:4533` is allowed for local development.
- HTTP on a private LAN is allowed with a visible warning.
- HTTPS is preferred for public remote access.
- Tailscale or another private network is supported as a practical secure path.
- Public HTTP should be discouraged because credentials and streams are not protected in transit.

## Offline Behavior

Downloaded music remains playable without server access. NekoFM does not disable downloaded files because the server is unavailable or credentials fail later.

When the server is unavailable, the app should enter offline mode and clearly show that state. Cached metadata remains browsable. Streaming, syncing, and downloading should be disabled or shown as unavailable until the server returns.

## Privacy And Diagnostics

NekoFM should not include analytics or automatic telemetry. Local diagnostic logs are acceptable if users can view and delete them.

## macOS Sandbox

During early local development, the macOS app is not sandboxed. This keeps local server networking and Keychain-backed credential storage simple without requiring an Apple development signing setup.

If NekoFM is packaged for broader distribution later, revisit sandboxing, hardened runtime, signing, and the required Keychain/network entitlements.

## Destructive Actions

NekoFM must ask for confirmation before destructive actions, including deleting downloads, clearing cache, removing a server profile, resetting local data, or deleting exported files from an SD card or folder.

NekoFM must not delete original music files from the server.

## GitHub Sync Workflow

When the user is satisfied with the current point and says to move on to the next point, push the current repo state to GitHub before starting the next major task.

Before pushing:

1. Check `.gitignore` so sensitive/local files are still excluded.
2. Run relevant verification, usually `npm run build`, `cargo test`, and `cargo check` for app changes.
3. Commit the current stable point with a clear message.
4. Push the branch to GitHub.

If no GitHub remote is configured, ask the user for the repository URL and do not invent one.
