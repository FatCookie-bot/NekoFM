# Server Compatibility

NekoFM's MVP is tested against Navidrome, while the app architecture follows a Subsonic-compatible provider model.

## MVP Target

- Primary server: Navidrome
- Local development URL: `http://localhost:4533`
- Docker image: `deluan/navidrome:0.61.2`
- Protocol family: Subsonic-compatible API

## Compatibility Promise

For MVP, only Navidrome compatibility is promised. Other Subsonic-compatible servers may work later if they fit the provider interface.

## Authentication

NekoFM stores server credentials locally using secure OS storage when the user enables remembering credentials.

The app should avoid sending raw passwords on every request when token/salt authentication is available.

## URL Security Policy

- Localhost HTTP is acceptable for development.
- Private LAN HTTP is acceptable with a warning.
- Public remote servers should use HTTPS.
- Tailscale/private network URLs are supported.
