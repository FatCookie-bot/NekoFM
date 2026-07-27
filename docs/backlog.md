# NekoFM backlog (deferred features)

Personal-use notes. These are intentional skips or “later” items, not forgotten bugs.

## Later

- **Play next** from Library, playlists, album rows, and Player (Liked circular double-tap already queues next).
- **Add to end of queue** — append without jumping the play-next stack. Add near full queue UI when ready.
- **Repeat One** — loop only the current track. Queue currently always loops (Repeat All behavior). No Repeat Off.
- **Typo-friendly search** — optional open-source search engine later.
- **Radio / similar songs** — optional discovery later (not needed for a self-curated library).

## Explicitly out of scope (for now)

- Genres, browse modes (recent/random/frequent), discovery-oriented library views.
- Server playlist sync (single Navidrome account is enough; local playlists stay local).
- Song ratings.
- Crossfade, sleep timer, playback speed, ReplayGain.
- Stream compression / max bitrate (always highest quality / original).
- Lyrics.
- Multi-device peer recovery when the server is down (each device only has its own cache; Navidrome is the shared source of truth for stars).

## Device cache note (Liked / stars)

Local SQLite caches server stars for offline use. Online, stars are server-sided.  
If Navidrome is down, devices cannot pull each other’s cache — only the server (or a backup) reconnects them.
