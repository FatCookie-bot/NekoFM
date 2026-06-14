import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type {
  ComponentType,
  CSSProperties,
  PointerEvent as ReactPointerEvent,
  WheelEvent as ReactWheelEvent,
} from "react";
import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import useEmblaCarousel from "embla-carousel-react";
import type { EmblaCarouselType, EmblaOptionsType } from "embla-carousel";
import {
  Album,
  ArrowLeft,
  AudioLines,
  ChevronRight,
  CircleCheck,
  CircleMinus,
  CirclePlay,
  Disc3,
  Download,
  GripVertical,
  Heart,
  ListMusic,
  ListPlus,
  Music2,
  Pause,
  Pencil,
  Play,
  RefreshCw,
  Repeat,
  FolderOpen,
  Save,
  RotateCcw,
  Eye,
  EyeOff,
  LoaderCircle,
  Network,
  Search,
  ShieldAlert,
  Shuffle,
  SkipBack,
  SkipForward,
  Trash2,
  X,
} from "lucide-react";
import "./App.css";

type DestinationId =
  | "library"
  | "player"
  | "liked"
  | "playlists"
  | "downloads"
  | "settings";

type Destination = {
  id: DestinationId;
  label: string;
};

type ServerConnectionResult = {
  isSuccess: boolean;
  message: string;
};

type ServerScanResult = {
  isScanning: boolean;
  scannedCount: number;
  message: string;
};

type SavedServerProfile = {
  serverUrl: string;
  username: string;
  password: string;
  rememberPassword: boolean;
};

type PlaybackPreferences = {
  previousTrackThresholdSeconds: number;
};

type DownloadFolder = {
  path: string;
  isCustom: boolean;
};

type DownloadFolderMoveResult = {
  movedAudioCount: number;
  movedCoverCount: number;
  skippedCount: number;
  totalCount: number;
};

type MusicExportResult = {
  exportedTrackCount: number;
  copiedTrackCount: number;
  downloadedTrackCount: number;
  copiedCoverCount: number;
  downloadedCoverCount: number;
  skippedTrackCount: number;
  playlistCount: number;
  playlistEntryCount: number;
  skippedPlaylistEntryCount: number;
  collisionCount: number;
  message: string;
};

type ExportTrackRequest = {
  track: TrackModel;
  localDownload?: DownloadedTrack | null;
};

type ExportPlaylistRequest = {
  name: string;
  tracks: ExportTrackRequest[];
};

type PendingExportModeChoice = {
  targetFolder: string;
  directTracks: ExportTrackRequest[];
  playlists: ExportPlaylistRequest[];
};

type DownloadedTrack = {
  trackId: string;
  title: string;
  artist: string;
  trackNumber: number;
  durationSeconds: number;
  localPath: string;
  state: "downloading" | "complete" | "failed" | string;
  updatedAt: string;
  albumId?: string | null;
  albumName?: string | null;
  coverArtUri?: string | null;
  localCoverPath?: string | null;
  suffix?: string | null;
  bytes?: number | null;
  receivedBytes?: number | null;
  totalBytes?: number | null;
  errorMessage?: string | null;
};

type DownloadRepairResult = {
  tracks: DownloadedTrack[];
  removedAudioCount: number;
  clearedCoverCount: number;
  recoveredCoverCount: number;
  downloadedCoverCount: number;
};

type LikedTrack = {
  trackId: string;
  title: string;
  artist: string;
  trackNumber: number;
  durationSeconds: number;
  likedAt: string;
  position: number;
  albumId?: string | null;
  albumName?: string | null;
  coverArtId?: string | null;
  coverArtUri?: string | null;
  suffix?: string | null;
};

type PlaylistModel = {
  id: string;
  name: string;
  createdAt: string;
  updatedAt: string;
  trackCount: number;
};

type PlaylistNameDialogState =
  | { mode: "create"; initialName: string }
  | { mode: "rename"; playlistId: string; initialName: string };

type PlaylistDeleteDialogState = {
  playlistId: string;
  playlistName: string;
};

type LocalDownloadDeleteDialogState = {
  trackId: string;
  title: string;
};

type LocalAlbumDeleteDialogState = {
  albumName: string;
  trackIds: string[];
};

type MoveDownloadsDialogState = {
  completeCount: number;
  resolve: (choice: "move" | "new-only" | "cancel") => void;
};

type PlaylistTrack = {
  entryId: string;
  playlistId: string;
  trackId: string;
  title: string;
  artist: string;
  trackNumber: number;
  durationSeconds: number;
  position: number;
  addedAt: string;
  albumId?: string | null;
  albumName?: string | null;
  coverArtId?: string | null;
  coverArtUri?: string | null;
  suffix?: string | null;
};

type PlaybackSource = {
  uri: string;
  source: "local" | "stream" | string;
};

type AlbumModel = {
  id: string;
  name: string;
  artist: string;
  songCount: number;
  durationSeconds: number;
  coverArtId?: string | null;
  coverArtUri?: string | null;
  year?: number | null;
};

type TrackModel = {
  id: string;
  title: string;
  artist: string;
  trackNumber: number;
  durationSeconds: number;
  queueKey?: string | null;
  albumId?: string | null;
  albumName?: string | null;
  coverArtId?: string | null;
  coverArtUri?: string | null;
  suffix?: string | null;
};

type AlbumDetailModel = {
  album: AlbumModel;
  tracks: TrackModel[];
};

type LibrarySearchResult = {
  albums: AlbumModel[];
  tracks: TrackModel[];
};

type PlayerState = {
  album: AlbumModel | null;
  queue: TrackModel[];
  currentIndex: number;
  isPlaying: boolean;
  isLoading: boolean;
  isRepeatEnabled: boolean;
  isShuffleEnabled: boolean;
  skipUnavailable: boolean;
  positionSeconds: number;
  durationSeconds: number;
  errorMessage: string | null;
  source: "local" | "stream" | null;
  sourceByQueueKey: Record<string, "local" | "stream">;
  baseQueueKeys: string[];
  playbackRequestId: number;
};

type PlayerActions = {
  playAlbum: (
    album: AlbumModel,
    tracks: TrackModel[],
    startIndex: number,
    options?: { skipUnavailable?: boolean },
  ) => void;
  replaceQueueForAlbum: (albumId: string, tracks: TrackModel[]) => void;
  removeDeletedLocalTracks: (trackIds: string[]) => void;
  togglePlayPause: () => void;
  seekBack: () => void;
  seekNext: () => void;
  seekTo: (seconds: number) => void;
  seekToQueueIndex: (index: number) => void;
  toggleRepeat: () => void;
  toggleShuffle: () => void;
};

type AppPreferences = {
  previousTrackThresholdSeconds: number;
};

type PreferenceActions = {
  setPreviousTrackThreshold: (seconds: number) => Promise<void>;
};

type DownloadActions = {
  downloadTrack: (track: TrackModel) => Promise<void>;
  downloadTracks: (tracks: TrackModel[]) => Promise<void>;
  deleteDownload: (trackId: string) => Promise<void>;
  deleteDownloads: (trackIds: string[]) => Promise<void>;
  openDownloadFolder: () => Promise<void>;
  retryFailedDownloads: () => Promise<void>;
  reloadDownloads: () => Promise<DownloadRepairResult | null>;
};

type LikedActions = {
  toggleLiked: (track: TrackModel) => Promise<void>;
  unlikeTrack: (trackId: string) => Promise<void>;
  reorderLikedTracks: (trackIds: string[]) => Promise<LikedTrack[]>;
  reloadLikedTracks: () => Promise<void>;
};

type PlaylistActions = {
  createPlaylist: (name: string) => Promise<void>;
  renamePlaylist: (playlistId: string, name: string) => Promise<void>;
  deletePlaylist: (playlistId: string) => Promise<void>;
  loadPlaylistTracks: (playlistId: string) => Promise<PlaylistTrack[]>;
  addTrackToPlaylist: (playlistId: string, track: TrackModel) => Promise<PlaylistTrack[]>;
  removePlaylistEntry: (playlistId: string, entryId: string) => Promise<PlaylistTrack[]>;
  reorderPlaylistTracks: (playlistId: string, entryIds: string[]) => Promise<PlaylistTrack[]>;
  reloadPlaylists: () => Promise<void>;
};

const emptyPlayerState: PlayerState = {
  album: null,
  queue: [],
  currentIndex: 0,
  isPlaying: false,
  isLoading: false,
  isRepeatEnabled: false,
  isShuffleEnabled: false,
  skipUnavailable: false,
  positionSeconds: 0,
  durationSeconds: 0,
  errorMessage: null,
  source: null,
  sourceByQueueKey: {},
  baseQueueKeys: [],
  playbackRequestId: 0,
};

const defaultPreferences: AppPreferences = {
  previousTrackThresholdSeconds: 3,
};

function hasTauriRuntime() {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

function previewCover(seed: string, label: string) {
  const hue = Array.from(seed).reduce((total, char) => total + char.charCodeAt(0), 0) % 360;
  const svg = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
      <defs>
        <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="hsl(${hue}, 68%, 62%)"/>
          <stop offset="1" stop-color="hsl(${(hue + 115) % 360}, 58%, 30%)"/>
        </linearGradient>
      </defs>
      <rect width="256" height="256" fill="url(#g)"/>
      <circle cx="188" cy="64" r="54" fill="rgba(255,255,255,.2)"/>
      <circle cx="68" cy="188" r="72" fill="rgba(0,0,0,.22)"/>
      <text x="28" y="222" fill="white" font-family="system-ui, sans-serif" font-size="28" font-weight="700">${label}</text>
    </svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}

const previewAlbums: AlbumModel[] = [
  {
    id: "preview-album-1",
    name: "Midnight Cache",
    artist: "NekoFM Preview",
    songCount: 4,
    durationSeconds: 914,
    coverArtId: "preview-cover-1",
    coverArtUri: previewCover("midnight-cache", "MC"),
    year: 2026,
  },
  {
    id: "preview-album-2",
    name: "Offline Signals",
    artist: "Local Tests",
    songCount: 3,
    durationSeconds: 641,
    coverArtId: "preview-cover-2",
    coverArtUri: previewCover("offline-signals", "OS"),
    year: 2025,
  },
];

const previewAlbumDetails: AlbumDetailModel[] = previewAlbums.map((album, albumIndex) => ({
  album,
  tracks: Array.from({ length: album.songCount }, (_, index) => ({
    id: `${album.id}-track-${index + 1}`,
    title:
      albumIndex === 0
        ? ["Wake the Index", "Soft Delete", "Cover Repair", "Queue Bloom"][index]
        : ["Local First", "Signal Gap", "Folder Memory"][index],
    artist: album.artist,
    trackNumber: index + 1,
    durationSeconds: albumIndex === 0 ? [212, 188, 261, 253][index] : [203, 216, 222][index],
    albumId: album.id,
    albumName: album.name,
    coverArtId: album.coverArtId,
    coverArtUri: album.coverArtUri,
    suffix: "flac",
  })),
}));

const previewTracks = previewAlbumDetails.flatMap((detail) => detail.tracks);
const previewDownloads: DownloadedTrack[] = previewTracks.slice(0, 5).map((track, index) => ({
  trackId: track.id,
  title: track.title,
  artist: track.artist,
  trackNumber: track.trackNumber,
  durationSeconds: track.durationSeconds,
  localPath: `/Preview/${track.artist}/${track.albumName}/${track.trackNumber} - ${track.title}.flac`,
  state: "complete",
  updatedAt: "2026-06-05T00:00:00Z",
  albumId: track.albumId,
  albumName: track.albumName,
  coverArtUri: track.coverArtUri,
  localCoverPath: null,
  suffix: track.suffix,
  bytes: 24_000_000 + index * 1_000_000,
  receivedBytes: 24_000_000 + index * 1_000_000,
  totalBytes: 24_000_000 + index * 1_000_000,
  errorMessage: null,
}));

const previewLikedTracks: LikedTrack[] = previewTracks.slice(1, 5).map((track, index) => ({
  trackId: track.id,
  title: track.title,
  artist: track.artist,
  trackNumber: track.trackNumber,
  durationSeconds: track.durationSeconds,
  likedAt: "2026-06-05T00:00:00Z",
  position: index,
  albumId: track.albumId,
  albumName: track.albumName,
  coverArtId: track.coverArtId,
  coverArtUri: track.coverArtUri,
  suffix: track.suffix,
}));

const previewPlaylists: PlaylistModel[] = [
  {
    id: "preview-playlist",
    name: "Liked Road Test",
    createdAt: "2026-06-05T00:00:00Z",
    updatedAt: "2026-06-05T00:00:00Z",
    trackCount: 4,
  },
];

const previewPlaylistTracks: PlaylistTrack[] = [
  ...previewTracks.slice(0, 3),
  previewTracks[1],
].map((track, index) => ({
  entryId: `preview-playlist-entry-${index + 1}`,
  playlistId: "preview-playlist",
  trackId: track.id,
  title: track.title,
  artist: track.artist,
  trackNumber: track.trackNumber,
  durationSeconds: track.durationSeconds,
  position: index,
  addedAt: "2026-06-05T00:00:00Z",
  albumId: track.albumId,
  albumName: track.albumName,
  coverArtId: track.coverArtId,
  coverArtUri: track.coverArtUri,
  suffix: track.suffix,
}));

const primaryDestinations: Destination[] = [
  { id: "liked", label: "Liked" },
  { id: "playlists", label: "Playlist" },
  { id: "library", label: "Library" },
];

const primaryDestinationIds = new Set<DestinationId>(
  primaryDestinations.map((destination) => destination.id),
);

function primaryDestinationIndex(id: DestinationId) {
  return primaryDestinations.findIndex((destination) => destination.id === id);
}

function isPrimaryDestination(id: DestinationId) {
  return primaryDestinationIds.has(id);
}

const controlDestinations: Destination[] = [
  { id: "settings", label: "Settings" },
  { id: "downloads", label: "Downloads" },
];

const controlDestinationIds = new Set<DestinationId>(
  controlDestinations.map((destination) => destination.id),
);

function controlDestinationIndex(id: DestinationId) {
  return controlDestinations.findIndex((destination) => destination.id === id);
}

function isControlDestination(id: DestinationId) {
  return controlDestinationIds.has(id);
}

const wheelNavigationLockMs = 85;
const wheelNavigationStreamIdleMs = 65;
const wheelNavigationThresholdPx = 28;

const destinations: Destination[] = [
  ...primaryDestinations,
  { id: "player", label: "Player" },
  ...controlDestinations,
];

function previewSearchParams() {
  if (typeof window === "undefined" || hasTauriRuntime()) {
    return new URLSearchParams();
  }
  return new URLSearchParams(window.location.search);
}

function storedHomeDestination(): DestinationId | null {
  if (typeof window === "undefined") {
    return null;
  }
  const stored = window.localStorage.getItem("nekofm.homePage");
  return primaryDestinations.some((destination) => destination.id === stored)
    ? (stored as DestinationId)
    : null;
}

function initialHomeDestination(): DestinationId {
  return storedHomeDestination() ?? "liked";
}

function initialPreviewDestination(): DestinationId {
  const requested = previewSearchParams().get("previewScreen");
  return destinations.some((destination) => destination.id === requested)
    ? (requested as DestinationId)
    : initialHomeDestination();
}

function initialPreviewPlayerState(): PlayerState {
  if (previewSearchParams().get("previewPlayer") !== "1") {
    return emptyPlayerState;
  }
  const album = previewAlbumDetails[0].album;
  const queue = previewAlbumDetails[0].tracks;
  return {
    ...emptyPlayerState,
    album,
    queue,
    currentIndex: 1,
    isPlaying: false,
    positionSeconds: 42,
    durationSeconds: queue[1]?.durationSeconds ?? 0,
    source: "local",
    sourceByQueueKey: sourceMapForTracks(queue, previewDownloads),
    baseQueueKeys: queue.map(queueTrackKey),
  };
}

function initialPreviewAlbumDetail() {
  const albumId = previewSearchParams().get("previewAlbum");
  return previewAlbumDetails.find((detail) => detail.album.id === albumId) ?? null;
}

async function invokeCommand<T>(
  command: string,
  args?: Record<string, unknown>,
): Promise<T> {
  if (!hasTauriRuntime()) {
    if (command === "get_albums") {
      return previewAlbums as T;
    }
    if (command === "get_album") {
      const albumId = String(args?.albumId ?? "");
      const detail = previewAlbumDetails.find((item) => item.album.id === albumId);
      if (detail) {
        return detail as T;
      }
      throw new Error("Preview album was not found.");
    }
    if (command === "search_library" || command === "search_downloaded_library") {
      const query = String(args?.query ?? "").trim().toLowerCase();
      const matches = (value?: string | null) =>
        value?.toLowerCase().includes(query) ?? false;
      return {
        albums: previewAlbums.filter(
          (album) => matches(album.name) || matches(album.artist),
        ),
        tracks: previewTracks.filter(
          (track) =>
            matches(track.title) ||
            matches(track.artist) ||
            matches(track.albumName),
        ),
      } as T;
    }
    if (command === "load_server_profile") {
      return null as T;
    }
    if (command === "load_playback_preferences") {
      return defaultPreferences as T;
    }
    if (command === "load_downloads") {
      return previewDownloads as T;
    }
    if (command === "recheck_downloads") {
      return {
        tracks: previewDownloads,
        removedAudioCount: 0,
        clearedCoverCount: 0,
        recoveredCoverCount: 0,
        downloadedCoverCount: 0,
      } as T;
    }
    if (command === "load_liked_tracks") {
      return previewLikedTracks as T;
    }
    if (command === "load_playlists") {
      return previewPlaylists as T;
    }
    if (command === "load_playlist_tracks") {
      const playlistId = String(args?.playlistId ?? "");
      return previewPlaylistTracks.filter((track) => track.playlistId === playlistId) as T;
    }
    if (command === "get_playback_source") {
      return {
        uri: "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAESsAACJWAAACABAAZGF0YQAAAAA=",
        source: "stream",
      } as T;
    }
    if (command === "load_download_folder") {
      return { path: "Default NekoFM downloads folder", isCustom: false } as T;
    }
    if (command === "choose_download_folder") {
      return null as T;
    }
    if (command === "choose_export_folder") {
      return null as T;
    }
    if (command === "save_download_folder" || command === "reset_download_folder") {
      return { path: String(args?.path ?? "Default NekoFM downloads folder"), isCustom: true } as T;
    }
    if (command === "open_download_folder") {
      return undefined as T;
    }
    if (command === "export_local_music") {
      return {
        exportedTrackCount: 0,
        copiedTrackCount: 0,
        downloadedTrackCount: 0,
        copiedCoverCount: 0,
        downloadedCoverCount: 0,
        skippedTrackCount: 0,
        playlistCount: 0,
        playlistEntryCount: 0,
        skippedPlaylistEntryCount: 0,
        collisionCount: 0,
        message: "Open the Tauri app to export music.",
      } as T;
    }
    if (command === "export_music_selection") {
      return {
        exportedTrackCount: 0,
        copiedTrackCount: 0,
        downloadedTrackCount: 0,
        copiedCoverCount: 0,
        downloadedCoverCount: 0,
        skippedTrackCount: 0,
        playlistCount: 0,
        playlistEntryCount: 0,
        skippedPlaylistEntryCount: 0,
        collisionCount: 0,
        message: "Open the Tauri app to export music.",
      } as T;
    }
    if (command === "has_existing_export") {
      return false as T;
    }
    if (command === "start_server_scan") {
      return {
        isScanning: true,
        scannedCount: 0,
        message: "Server scan started.",
      } as T;
    }
    if (command === "load_downloaded_album_details") {
      return previewAlbumDetails.map((detail) => ({
        album: detail.album,
        tracks: detail.tracks.filter((track) =>
          previewDownloads.some((download) => download.trackId === track.id),
        ),
      })).filter((detail) => detail.tracks.length > 0) as T;
    }
    if (
      command === "download_track" ||
      command === "delete_download" ||
      command === "toggle_liked_track" ||
      command === "unlike_track" ||
      command === "reorder_liked_tracks" ||
      command === "create_playlist" ||
      command === "rename_playlist" ||
      command === "delete_playlist" ||
      command === "add_track_to_playlist" ||
      command === "remove_playlist_entry" ||
      command === "reorder_playlist_tracks"
    ) {
      return [] as T;
    }
    if (command === "save_previous_track_threshold") {
      return {
        previousTrackThresholdSeconds: Number(args?.seconds ?? 3),
      } as T;
    }
    throw new Error("Open the Tauri app to use this command.");
  }

  return invoke<T>(command, args);
}

function App() {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const shouldPlayAfterSourceLoadRef = useRef(false);
  const [selectedId, setSelectedId] = useState<DestinationId>(initialPreviewDestination);
  const [homeDestinationId, setHomeDestinationId] =
    useState<DestinationId>(initialHomeDestination);
  const selectedIdRef = useRef(selectedId);
  const lastPrimaryDestinationIdRef = useRef<DestinationId>(
    isPrimaryDestination(selectedId) ? selectedId : homeDestinationId,
  );
  const controlScrollFramesRef = useRef<Partial<Record<DestinationId, HTMLDivElement | null>>>({});
  const pendingControlScrollResetRef = useRef(false);
  const isWheelNavigationLockedRef = useRef(false);
  const isWheelNavigationStreamActiveRef = useRef(false);
  const wheelNavigationLockTimerRef = useRef<number | null>(null);
  const wheelNavigationStreamIdleTimerRef = useRef<number | null>(null);
  const isControlWheelNavigationLockedRef = useRef(false);
  const isControlWheelNavigationStreamActiveRef = useRef(false);
  const controlWheelNavigationLockTimerRef = useRef<number | null>(null);
  const controlWheelNavigationStreamIdleTimerRef = useRef<number | null>(null);
  const initialPrimaryIndexRef = useRef(
    Math.max(
      0,
      primaryDestinationIndex(
        isPrimaryDestination(selectedId) ? selectedId : homeDestinationId,
      ),
    ),
  );
  const initialControlIndexRef = useRef(
    Math.max(
      0,
      controlDestinationIndex(
        isControlDestination(selectedId) ? selectedId : "settings",
      ),
    ),
  );
  const primaryEmblaOptions = useMemo<EmblaOptionsType>(
    () => ({
      loop: true,
      align: "center",
      dragFree: false,
      skipSnaps: false,
      slidesToScroll: 1,
      startIndex: initialPrimaryIndexRef.current,
      watchDrag: (_emblaApi, event) => {
        const target = event.target;
        if (!(target instanceof Element)) {
          return true;
        }
        return !target.closest("[data-no-page-swipe], [data-no-page-drag], input[type='range'], [role='slider']");
      },
    }),
    [],
  );
  const [primaryEmblaRef, primaryEmblaApi] = useEmblaCarousel(primaryEmblaOptions);
  const controlEmblaOptions = useMemo<EmblaOptionsType>(
    () => ({
      loop: true,
      align: "center",
      dragFree: false,
      skipSnaps: false,
      slidesToScroll: 1,
      startIndex: initialControlIndexRef.current,
      watchDrag: (_emblaApi, event) => {
        const target = event.target;
        if (!(target instanceof Element)) {
          return true;
        }
        return !target.closest("[data-no-page-swipe], [data-no-page-drag], input[type='range'], [role='slider']");
      },
    }),
    [],
  );
  const [controlEmblaRef, controlEmblaApi] = useEmblaCarousel(controlEmblaOptions);
  const [player, setPlayer] = useState<PlayerState>(initialPreviewPlayerState);
  const [downloads, setDownloads] = useState<DownloadedTrack[]>([]);
  const [likedTracks, setLikedTracks] = useState<LikedTrack[]>([]);
  const [playlists, setPlaylists] = useState<PlaylistModel[]>([]);
  const [playlistTracksById, setPlaylistTracksById] = useState<
    Record<string, PlaylistTrack[]>
  >({});
  const [activeDownloadTrackIds, setActiveDownloadTrackIds] = useState<Set<string>>(
    () => new Set(),
  );
  const [preferences, setPreferences] = useState<AppPreferences>(defaultPreferences);
  const [serverConnectionVersion, setServerConnectionVersion] = useState(0);
  const [resetKeys, setResetKeys] = useState<Record<DestinationId, number>>({
    library: 0,
    player: 0,
    liked: 0,
    playlists: 0,
    downloads: 0,
    settings: 0,
  });
  const [focusedPrimaryId, setFocusedPrimaryId] = useState<DestinationId | null>(null);
  const selectedPrimaryId = isPrimaryDestination(selectedId) ? selectedId : null;
  const selectedControlId = isControlDestination(selectedId) ? selectedId : null;
  const selected = destinations.find((item) => item.id === selectedId)!;
  const showMiniPlayer = selectedId !== "player";
  const currentTrack = player.queue[player.currentIndex] ?? null;
  const currentQueueKey = currentTrack ? queueTrackKey(currentTrack) : null;
  const sourceLoadKey = currentQueueKey
    ? `${currentQueueKey}:${player.playbackRequestId}`
    : null;

  useEffect(() => {
    let isCurrent = true;

    async function loadPreferences() {
      try {
        const loaded = await invokeCommand<PlaybackPreferences>(
          "load_playback_preferences",
        );
        if (!isCurrent) {
          return;
        }
        setPreferences({
          previousTrackThresholdSeconds: clampPreviousTrackThreshold(
            loaded.previousTrackThresholdSeconds,
          ),
        });
      } catch {
        if (isCurrent) {
          setPreferences(defaultPreferences);
        }
      }
    }

    loadPreferences();

    return () => {
      isCurrent = false;
    };
  }, []);

  useEffect(() => {
    selectedIdRef.current = selectedId;
  }, [selectedId]);

  useEffect(() => {
    if (selectedPrimaryId) {
      lastPrimaryDestinationIdRef.current = selectedPrimaryId;
    }
  }, [selectedPrimaryId]);

  function resetControlScrollPositions() {
    controlDestinations.forEach((destination) => {
      const frame = controlScrollFramesRef.current[destination.id];
      if (!frame) {
        return;
      }
      frame.scrollTop = 0;
      frame.scrollLeft = 0;
      frame.querySelectorAll<HTMLElement>("*").forEach((node) => {
        node.scrollTop = 0;
        node.scrollLeft = 0;
      });
    });
  }

  const syncPrimarySelection = useCallback((emblaApi: EmblaCarouselType) => {
    const destination = primaryDestinations[emblaApi.selectedScrollSnap()];
    if (!destination) {
      return;
    }
    if (!isPrimaryDestination(selectedIdRef.current)) {
      return;
    }
    selectedIdRef.current = destination.id;
    setSelectedId(destination.id);
  }, []);

  useEffect(() => {
    if (!primaryEmblaApi) {
      return;
    }
    const handleSelect = (emblaApi: EmblaCarouselType) => syncPrimarySelection(emblaApi);
    primaryEmblaApi.on("select", handleSelect);
    primaryEmblaApi.on("reInit", handleSelect);
    syncPrimarySelection(primaryEmblaApi);
    return () => {
      primaryEmblaApi.off("select", handleSelect);
      primaryEmblaApi.off("reInit", handleSelect);
    };
  }, [primaryEmblaApi, syncPrimarySelection]);

  useEffect(() => {
    if (!primaryEmblaApi || !isPrimaryDestination(selectedId)) {
      return;
    }
    const selectedIndex = primaryDestinationIndex(selectedId);
    if (selectedIndex < 0) {
      return;
    }
    window.requestAnimationFrame(() => {
      if (primaryEmblaApi.selectedScrollSnap() !== selectedIndex) {
        primaryEmblaApi.scrollTo(selectedIndex, true);
      }
    });
  }, [primaryEmblaApi, selectedId]);

  const syncControlSelection = useCallback((emblaApi: EmblaCarouselType) => {
    const destination = controlDestinations[emblaApi.selectedScrollSnap()];
    if (!destination) {
      return;
    }
    if (!isControlDestination(selectedIdRef.current)) {
      return;
    }
    selectedIdRef.current = destination.id;
    setSelectedId(destination.id);
  }, []);

  useEffect(() => {
    if (!controlEmblaApi) {
      return;
    }
    const handleSelect = (emblaApi: EmblaCarouselType) => syncControlSelection(emblaApi);
    controlEmblaApi.on("select", handleSelect);
    controlEmblaApi.on("reInit", handleSelect);
    syncControlSelection(controlEmblaApi);
    return () => {
      controlEmblaApi.off("select", handleSelect);
      controlEmblaApi.off("reInit", handleSelect);
    };
  }, [controlEmblaApi, syncControlSelection]);

  useEffect(() => {
    if (!controlEmblaApi || !isControlDestination(selectedId)) {
      return;
    }
    const selectedIndex = controlDestinationIndex(selectedId);
    if (selectedIndex < 0) {
      return;
    }
    window.requestAnimationFrame(() => {
      if (controlEmblaApi.selectedScrollSnap() !== selectedIndex) {
        controlEmblaApi.scrollTo(selectedIndex, true);
      }
    });
  }, [controlEmblaApi, selectedId]);

  useEffect(() => {
    if (!selectedControlId || !pendingControlScrollResetRef.current) {
      return;
    }
    window.requestAnimationFrame(() => {
      resetControlScrollPositions();
      pendingControlScrollResetRef.current = false;
    });
  }, [selectedControlId]);

  useEffect(() => {
    if (!primaryEmblaApi) {
      return;
    }
    const handleResize = () => primaryEmblaApi.reInit();
    window.addEventListener("resize", handleResize);
    window.addEventListener("orientationchange", handleResize);
    return () => {
      window.removeEventListener("resize", handleResize);
      window.removeEventListener("orientationchange", handleResize);
    };
  }, [primaryEmblaApi]);

  useEffect(() => {
    if (!controlEmblaApi) {
      return;
    }
    const handleResize = () => controlEmblaApi.reInit();
    window.addEventListener("resize", handleResize);
    window.addEventListener("orientationchange", handleResize);
    return () => {
      window.removeEventListener("resize", handleResize);
      window.removeEventListener("orientationchange", handleResize);
    };
  }, [controlEmblaApi]);

  useEffect(() => {
    if (!primaryEmblaApi) {
      return;
    }
    const rootNode = primaryEmblaApi.rootNode();
    const scheduleWheelNavigationLock = () => {
      if (wheelNavigationLockTimerRef.current !== null) {
        window.clearTimeout(wheelNavigationLockTimerRef.current);
      }
      isWheelNavigationLockedRef.current = true;
      wheelNavigationLockTimerRef.current = window.setTimeout(() => {
        isWheelNavigationLockedRef.current = false;
        wheelNavigationLockTimerRef.current = null;
      }, wheelNavigationLockMs);
    };

    const markWheelNavigationStreamActive = () => {
      if (wheelNavigationStreamIdleTimerRef.current !== null) {
        window.clearTimeout(wheelNavigationStreamIdleTimerRef.current);
      }
      isWheelNavigationStreamActiveRef.current = true;
      wheelNavigationStreamIdleTimerRef.current = window.setTimeout(() => {
        isWheelNavigationStreamActiveRef.current = false;
        wheelNavigationStreamIdleTimerRef.current = null;
      }, wheelNavigationStreamIdleMs);
    };

    const handleWheel = (event: WheelEvent) => {
      const target = event.target;
      if (
        target instanceof Element &&
        target.closest("[data-no-page-swipe], input[type='range'], [role='slider']")
      ) {
        return;
      }

      const horizontalDelta = event.shiftKey ? event.deltaY : event.deltaX;
      const verticalDelta = event.shiftKey ? event.deltaX : event.deltaY;
      if (
        Math.abs(horizontalDelta) < wheelNavigationThresholdPx ||
        Math.abs(horizontalDelta) <= Math.abs(verticalDelta) * 1.15
      ) {
        return;
      }

      const wasWheelNavigationStreamActive = isWheelNavigationStreamActiveRef.current;
      markWheelNavigationStreamActive();
      if (isWheelNavigationLockedRef.current) {
        event.preventDefault();
        return;
      }

      if (wasWheelNavigationStreamActive) {
        event.preventDefault();
        return;
      }

      scheduleWheelNavigationLock();
      event.preventDefault();
      if (horizontalDelta > 0) {
        primaryEmblaApi.scrollNext();
      } else {
        primaryEmblaApi.scrollPrev();
      }
    };

    rootNode.addEventListener("wheel", handleWheel, { passive: false, capture: true });
    return () => {
      rootNode.removeEventListener("wheel", handleWheel, { capture: true });
      if (wheelNavigationLockTimerRef.current !== null) {
        window.clearTimeout(wheelNavigationLockTimerRef.current);
        wheelNavigationLockTimerRef.current = null;
      }
      if (wheelNavigationStreamIdleTimerRef.current !== null) {
        window.clearTimeout(wheelNavigationStreamIdleTimerRef.current);
        wheelNavigationStreamIdleTimerRef.current = null;
      }
      isWheelNavigationLockedRef.current = false;
      isWheelNavigationStreamActiveRef.current = false;
    };
  }, [primaryEmblaApi]);

  useEffect(() => {
    if (!controlEmblaApi) {
      return;
    }
    const rootNode = controlEmblaApi.rootNode();
    const scheduleWheelNavigationLock = () => {
      if (controlWheelNavigationLockTimerRef.current !== null) {
        window.clearTimeout(controlWheelNavigationLockTimerRef.current);
      }
      isControlWheelNavigationLockedRef.current = true;
      controlWheelNavigationLockTimerRef.current = window.setTimeout(() => {
        isControlWheelNavigationLockedRef.current = false;
        controlWheelNavigationLockTimerRef.current = null;
      }, wheelNavigationLockMs);
    };

    const markWheelNavigationStreamActive = () => {
      if (controlWheelNavigationStreamIdleTimerRef.current !== null) {
        window.clearTimeout(controlWheelNavigationStreamIdleTimerRef.current);
      }
      isControlWheelNavigationStreamActiveRef.current = true;
      controlWheelNavigationStreamIdleTimerRef.current = window.setTimeout(() => {
        isControlWheelNavigationStreamActiveRef.current = false;
        controlWheelNavigationStreamIdleTimerRef.current = null;
      }, wheelNavigationStreamIdleMs);
    };

    const handleWheel = (event: WheelEvent) => {
      const target = event.target;
      if (
        target instanceof Element &&
        target.closest("[data-no-page-swipe], input[type='range'], [role='slider']")
      ) {
        return;
      }

      const horizontalDelta = event.shiftKey ? event.deltaY : event.deltaX;
      const verticalDelta = event.shiftKey ? event.deltaX : event.deltaY;
      if (
        Math.abs(horizontalDelta) < wheelNavigationThresholdPx ||
        Math.abs(horizontalDelta) <= Math.abs(verticalDelta) * 1.15
      ) {
        return;
      }

      const wasWheelNavigationStreamActive = isControlWheelNavigationStreamActiveRef.current;
      markWheelNavigationStreamActive();
      if (isControlWheelNavigationLockedRef.current) {
        event.preventDefault();
        return;
      }

      if (wasWheelNavigationStreamActive) {
        event.preventDefault();
        return;
      }

      scheduleWheelNavigationLock();
      event.preventDefault();
      if (horizontalDelta > 0) {
        controlEmblaApi.scrollNext();
      } else {
        controlEmblaApi.scrollPrev();
      }
    };

    rootNode.addEventListener("wheel", handleWheel, { passive: false, capture: true });
    return () => {
      rootNode.removeEventListener("wheel", handleWheel, { capture: true });
      if (controlWheelNavigationLockTimerRef.current !== null) {
        window.clearTimeout(controlWheelNavigationLockTimerRef.current);
        controlWheelNavigationLockTimerRef.current = null;
      }
      if (controlWheelNavigationStreamIdleTimerRef.current !== null) {
        window.clearTimeout(controlWheelNavigationStreamIdleTimerRef.current);
        controlWheelNavigationStreamIdleTimerRef.current = null;
      }
      isControlWheelNavigationLockedRef.current = false;
      isControlWheelNavigationStreamActiveRef.current = false;
    };
  }, [controlEmblaApi]);

  useEffect(() => {
    reloadDownloads();
  }, []);

  useEffect(() => {
    reloadLikedTracks();
  }, []);

  useEffect(() => {
    reloadPlaylists();
  }, []);

  useEffect(() => {
    shouldPlayAfterSourceLoadRef.current = player.isPlaying;
  }, [player.isPlaying]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !currentTrack) {
      return;
    }

    let isCurrent = true;
    const shouldAutoPlay = shouldPlayAfterSourceLoadRef.current;
    audio.pause();
    setPlayer((current) => ({
      ...current,
      isLoading: true,
      errorMessage: null,
      positionSeconds: 0,
      durationSeconds: currentTrack.durationSeconds,
      source: null,
    }));

    async function loadStream() {
      try {
        const playbackSource = await invokeCommand<PlaybackSource>("get_playback_source", {
          trackId: currentTrack.id,
        });
        if (!isCurrent || !audio) {
          return;
        }

        audio.src = playbackSource.source === "local"
          ? convertFileSrc(stripFileProtocol(playbackSource.uri))
          : playbackSource.uri;
        audio.currentTime = 0;
        if (shouldAutoPlay) {
          await audio.play();
        } else {
          audio.load();
        }
        setPlayer((current) => ({
          ...current,
          isPlaying: shouldAutoPlay,
          isLoading: false,
          errorMessage: null,
          source: playbackSource.source === "local" ? "local" : "stream",
          sourceByQueueKey: {
            ...current.sourceByQueueKey,
            [currentQueueKey ?? queueTrackKey(currentTrack)]: playbackSource.source === "local" ? "local" : "stream",
          },
        }));
      } catch (error) {
        if (!isCurrent) {
          return;
        }

        setPlayer((current) => {
          if (!current.skipUnavailable) {
            return {
              ...current,
              isPlaying: false,
              isLoading: false,
              errorMessage: String(error),
              source: null,
            };
          }

          const failedKey = currentQueueKey ?? queueTrackKey(currentTrack);
          const failedIndex = current.queue.findIndex(
            (track) => queueTrackKey(track) === failedKey,
          );
          const nextQueue = current.queue.filter(
            (track) => queueTrackKey(track) !== failedKey,
          );

          if (nextQueue.length === 0) {
            return {
              ...emptyPlayerState,
              errorMessage: String(error),
            };
          }

          const nextIndex = Math.min(
            failedIndex >= 0 ? failedIndex : current.currentIndex,
            nextQueue.length - 1,
          );
          const nextTrack = nextQueue[nextIndex] ?? nextQueue[0];
          const nextSourceByQueueKey = { ...current.sourceByQueueKey };
          delete nextSourceByQueueKey[failedKey];

          return {
            ...current,
            album: current.album
              ? {
                  ...current.album,
                  songCount: nextQueue.length,
                  durationSeconds: nextQueue.reduce(
                    (total, track) => total + track.durationSeconds,
                    0,
                  ),
                  coverArtUri: current.album.coverArtUri ?? nextTrack.coverArtUri,
                }
              : current.album,
            queue: nextQueue,
            currentIndex: nextIndex,
            isPlaying: shouldAutoPlay,
            isLoading: true,
            positionSeconds: 0,
            durationSeconds: nextTrack.durationSeconds,
            errorMessage: null,
            source: null,
            sourceByQueueKey: nextSourceByQueueKey,
            baseQueueKeys: current.baseQueueKeys.filter((key) => key !== failedKey),
            playbackRequestId: current.playbackRequestId + 1,
          };
        });
      }
    }

    loadStream();

    return () => {
      isCurrent = false;
    };
  }, [sourceLoadKey]);

  const playerActions: PlayerActions = {
    playAlbum(album, tracks, startIndex, options) {
      if (tracks.length === 0) {
        return;
      }

      const safeIndex = Math.min(Math.max(startIndex, 0), tracks.length - 1);
      setPlayer((current) => ({
        ...current,
        album,
        queue: tracks,
        currentIndex: safeIndex,
        isPlaying: true,
        isLoading: true,
        isShuffleEnabled: false,
        skipUnavailable: options?.skipUnavailable ?? false,
        positionSeconds: 0,
        durationSeconds: tracks[safeIndex]?.durationSeconds ?? 0,
        errorMessage: null,
        source: null,
        sourceByQueueKey: sourceMapForTracks(tracks, downloads),
        baseQueueKeys: tracks.map(queueTrackKey),
        playbackRequestId: current.playbackRequestId + 1,
      }));
    },
    replaceQueueForAlbum(albumId, tracks) {
      setPlayer((current) => {
        if (!current.album || current.album.id !== albumId || tracks.length === 0) {
          return current;
        }
        const currentTrack = current.queue[current.currentIndex];
        const currentKey = currentTrack?.queueKey ?? currentTrack?.id;
        const nextIndex = Math.max(
          0,
          tracks.findIndex((track) => (track.queueKey ?? track.id) === currentKey),
        );
        const nextTrack = tracks[nextIndex] ?? tracks[0];
        return {
          ...current,
          album: {
            ...current.album,
            songCount: tracks.length,
            durationSeconds: tracks.reduce(
              (total, track) => total + track.durationSeconds,
              0,
            ),
            coverArtUri: current.album.coverArtUri ?? nextTrack.coverArtUri,
          },
          queue: tracks,
          currentIndex: nextIndex,
          durationSeconds: nextTrack.durationSeconds,
          baseQueueKeys: tracks.map(queueTrackKey),
          sourceByQueueKey: {
            ...sourceMapForTracks(tracks, downloads),
            ...Object.fromEntries(
              tracks
                .map((track) => [queueTrackKey(track), current.sourceByQueueKey[queueTrackKey(track)]])
                .filter((entry): entry is [string, "local" | "stream"] => Boolean(entry[1])),
            ),
          },
        };
      });
    },
    removeDeletedLocalTracks(trackIds) {
      const deletedTrackIds = new Set(trackIds);
      if (deletedTrackIds.size === 0) {
        return;
      }
      setPlayer((current) => {
        if (current.queue.length === 0) {
          return current;
        }
        const keptQueue = current.queue.filter(
          (track) =>
            !(
              deletedTrackIds.has(track.id) &&
              current.sourceByQueueKey[queueTrackKey(track)] === "local"
            ),
        );
        if (keptQueue.length === current.queue.length) {
          return current;
        }
        if (keptQueue.length === 0) {
          audioRef.current?.pause();
          if (audioRef.current) {
            audioRef.current.removeAttribute("src");
            audioRef.current.load();
          }
          return emptyPlayerState;
        }

        const currentTrack = current.queue[current.currentIndex];
        const nextIndex = Math.max(
          0,
          keptQueue.findIndex(
            (track) => (track.queueKey ?? track.id) === (currentTrack?.queueKey ?? currentTrack?.id),
          ),
        );
        const nextTrack = keptQueue[nextIndex] ?? keptQueue[0];
        const nextSourceByQueueKey = Object.fromEntries(
          keptQueue
            .map((track) => [queueTrackKey(track), current.sourceByQueueKey[queueTrackKey(track)]])
            .filter((entry): entry is [string, "local" | "stream"] => Boolean(entry[1])),
        );
        return {
          ...current,
          album: current.album
            ? {
                ...current.album,
                songCount: keptQueue.length,
                durationSeconds: keptQueue.reduce(
                  (total, track) => total + track.durationSeconds,
                  0,
                ),
                coverArtUri: current.album.coverArtUri ?? nextTrack.coverArtUri,
              }
            : current.album,
          queue: keptQueue,
          currentIndex: nextIndex,
          positionSeconds: nextTrack.id === currentTrack?.id ? current.positionSeconds : 0,
          durationSeconds: nextTrack.durationSeconds,
          source: nextTrack.id === currentTrack?.id ? current.source : null,
          baseQueueKeys: current.baseQueueKeys.filter((key) =>
            keptQueue.some((track) => queueTrackKey(track) === key),
          ),
          sourceByQueueKey: nextSourceByQueueKey,
        };
      });
    },
    togglePlayPause() {
      const audio = audioRef.current;
      if (!audio || !currentTrack) {
        return;
      }

      if (player.isPlaying) {
        audio.pause();
        setPlayer((current) => ({ ...current, isPlaying: false }));
        return;
      }

      audio.play().catch((error) => {
        setPlayer((current) => ({
          ...current,
          isPlaying: false,
          errorMessage: String(error),
        }));
      });
      setPlayer((current) => ({ ...current, isPlaying: true }));
    },
    seekBack() {
      const audio = audioRef.current;
      if (!audio || !currentTrack) {
        return;
      }

      if (audio.currentTime >= preferences.previousTrackThresholdSeconds) {
        audio.currentTime = 0;
        setPlayer((current) => ({ ...current, positionSeconds: 0 }));
        return;
      }

      setPlayer((current) => {
        if (current.currentIndex <= 0) {
          audio.currentTime = 0;
          return { ...current, positionSeconds: 0 };
        }
        return {
          ...current,
          currentIndex: current.currentIndex - 1,
          positionSeconds: 0,
        };
      });
    },
    seekNext() {
      advanceQueue("manual");
    },
    seekTo(seconds) {
      const audio = audioRef.current;
      if (!audio) {
        return;
      }

      const safeSeconds = Math.max(0, Math.min(seconds, player.durationSeconds || seconds));
      audio.currentTime = safeSeconds;
      setPlayer((current) => ({ ...current, positionSeconds: safeSeconds }));
    },
    seekToQueueIndex(index) {
      if (index < 0 || index >= player.queue.length) {
        return;
      }
      const audio = audioRef.current;
      if (audio) {
        audio.currentTime = 0;
      }
      setPlayer((current) => {
        return {
          ...current,
          currentIndex: index,
          positionSeconds: 0,
          playbackRequestId: current.playbackRequestId + 1,
        };
      });
    },
    toggleRepeat() {
      setPlayer((current) => ({
        ...current,
        isRepeatEnabled: !current.isRepeatEnabled,
      }));
    },
    toggleShuffle() {
      setPlayer((current) => {
        if (current.queue.length < 2) {
          return current;
        }

        const currentTrack = current.queue[current.currentIndex];
        const currentKey = queueTrackKey(currentTrack);
        const queueByKey = new Map(
          current.queue.map((track) => [queueTrackKey(track), track]),
        );
        const orderedUpcoming = current.baseQueueKeys
          .filter((key) => key !== currentKey)
          .map((key) => queueByKey.get(key))
          .filter((track): track is TrackModel => Boolean(track));
        const fallbackUpcoming = current.queue.filter(
          (_, index) => index !== current.currentIndex,
        );
        const upcoming = orderedUpcoming.length === fallbackUpcoming.length
          ? orderedUpcoming
          : fallbackUpcoming;
        const nextQueue = current.isShuffleEnabled
          ? [currentTrack, ...upcoming]
          : [currentTrack, ...shuffleItems(upcoming)];

        return {
          ...current,
          queue: nextQueue,
          currentIndex: 0,
          isShuffleEnabled: !current.isShuffleEnabled,
        };
      });
    },
  };

  const preferenceActions: PreferenceActions = {
    async setPreviousTrackThreshold(seconds) {
      const safeSeconds = clampPreviousTrackThreshold(seconds);
      setPreferences({ previousTrackThresholdSeconds: safeSeconds });
      const saved = await invokeCommand<PlaybackPreferences>(
        "save_previous_track_threshold",
        { seconds: safeSeconds },
      );
      setPreferences({
        previousTrackThresholdSeconds: clampPreviousTrackThreshold(
          saved.previousTrackThresholdSeconds,
        ),
      });
    },
  };

  const downloadActions: DownloadActions = {
    async downloadTrack(track) {
      setActiveDownloadTrackIds((current) => new Set(current).add(track.id));
      try {
        const updated = await invokeCommand<DownloadedTrack[]>("download_track", {
          track,
        });
        setDownloads(updated);
      } finally {
        setActiveDownloadTrackIds((current) => {
          const next = new Set(current);
          next.delete(track.id);
          return next;
        });
      }
    },
    async downloadTracks(tracks) {
      for (const track of tracks) {
        await downloadActions.downloadTrack(track);
      }
    },
    async deleteDownload(trackId) {
      setActiveDownloadTrackIds((current) => new Set(current).add(trackId));
      try {
        const updated = await invokeCommand<DownloadedTrack[]>("delete_download", {
          trackId,
        });
        setDownloads(updated);
        playerActions.removeDeletedLocalTracks([trackId]);
      } finally {
        setActiveDownloadTrackIds((current) => {
          const next = new Set(current);
          next.delete(trackId);
          return next;
        });
      }
    },
    async deleteDownloads(trackIds) {
      for (const trackId of trackIds) {
        await downloadActions.deleteDownload(trackId);
      }
    },
    async openDownloadFolder() {
      await invokeCommand<void>("open_download_folder");
    },
    async retryFailedDownloads() {
      const failedTracks = downloads
        .filter((download) => download.state === "failed")
        .map(downloadToTrack);
      await downloadActions.downloadTracks(failedTracks);
    },
    reloadDownloads,
  };

  const likedActions: LikedActions = {
    async toggleLiked(track) {
      const updated = await invokeCommand<LikedTrack[]>("toggle_liked_track", {
        track,
      });
      setLikedTracks(updated);
    },
    async unlikeTrack(trackId) {
      const updated = await invokeCommand<LikedTrack[]>("unlike_track", {
        trackId,
      });
      setLikedTracks(updated);
    },
    async reorderLikedTracks(trackIds) {
      const updated = await invokeCommand<LikedTrack[]>("reorder_liked_tracks", {
        trackIds,
      });
      setLikedTracks(updated);
      return updated;
    },
    reloadLikedTracks,
  };

  const playlistActions: PlaylistActions = {
    async createPlaylist(name) {
      const updated = await invokeCommand<PlaylistModel[]>("create_playlist", {
        name,
      });
      setPlaylists(updated);
    },
    async renamePlaylist(playlistId, name) {
      const updated = await invokeCommand<PlaylistModel[]>("rename_playlist", {
        playlistId,
        name,
      });
      setPlaylists(updated);
    },
    async deletePlaylist(playlistId) {
      const updated = await invokeCommand<PlaylistModel[]>("delete_playlist", {
        playlistId,
      });
      setPlaylists(updated);
      setPlaylistTracksById((current) => {
        const next = { ...current };
        delete next[playlistId];
        return next;
      });
    },
    async loadPlaylistTracks(playlistId) {
      const loaded = await invokeCommand<PlaylistTrack[]>("load_playlist_tracks", {
        playlistId,
      });
      setPlaylistTracksById((current) => ({ ...current, [playlistId]: loaded }));
      return loaded;
    },
    async addTrackToPlaylist(playlistId, track) {
      const updated = await invokeCommand<PlaylistTrack[]>("add_track_to_playlist", {
        playlistId,
        track,
      });
      setPlaylistTracksById((current) => ({ ...current, [playlistId]: updated }));
      await reloadPlaylists();
      return updated;
    },
    async removePlaylistEntry(playlistId, entryId) {
      const updated = await invokeCommand<PlaylistTrack[]>("remove_playlist_entry", {
        playlistId,
        entryId,
      });
      setPlaylistTracksById((current) => ({ ...current, [playlistId]: updated }));
      await reloadPlaylists();
      return updated;
    },
    async reorderPlaylistTracks(playlistId, entryIds) {
      const updated = await invokeCommand<PlaylistTrack[]>("reorder_playlist_tracks", {
        playlistId,
        entryIds,
      });
      setPlaylistTracksById((current) => ({ ...current, [playlistId]: updated }));
      await reloadPlaylists();
      return updated;
    },
    reloadPlaylists,
  };

  async function reloadDownloads() {
    const result = await invokeCommand<DownloadRepairResult>("recheck_downloads");
    setDownloads(result.tracks);
    return result;
  }

  async function reloadLikedTracks() {
    const loaded = await invokeCommand<LikedTrack[]>("load_liked_tracks");
    setLikedTracks(loaded);
  }

  async function reloadPlaylists() {
    const loaded = await invokeCommand<PlaylistModel[]>("load_playlists");
    setPlaylists(loaded);
  }

  function advanceQueue(reason: "ended" | "manual") {
    setPlayer((current) => {
      if (current.queue.length === 0) {
        return current;
      }
      if (current.currentIndex + 1 < current.queue.length) {
        return {
          ...current,
          currentIndex: current.currentIndex + 1,
          positionSeconds: 0,
        };
      }
      if (current.isRepeatEnabled) {
        return {
          ...current,
          currentIndex: 0,
          positionSeconds: 0,
          playbackRequestId: current.playbackRequestId + 1,
        };
      }
      if (reason === "manual") {
        return current;
      }
      return { ...current, isPlaying: false, positionSeconds: current.durationSeconds };
    });
  }

  function selectDestination(id: DestinationId) {
    if (id === selectedId && id !== "player") {
      setResetKeys((current) => ({ ...current, [id]: current[id] + 1 }));
    }
    if (isPrimaryDestination(id)) {
      const selectedIndex = primaryDestinationIndex(id);
      if (primaryEmblaApi && selectedIndex >= 0) {
        if (!isPrimaryDestination(selectedId)) {
          selectedIdRef.current = id;
          setSelectedId(id);
          window.requestAnimationFrame(() => primaryEmblaApi.scrollTo(selectedIndex, true));
          return;
        }
        primaryEmblaApi.scrollTo(selectedIndex);
        return;
      }
    }
    if (isControlDestination(id)) {
      const selectedIndex = controlDestinationIndex(id);
      if (controlEmblaApi && selectedIndex >= 0) {
        if (!isControlDestination(selectedId)) {
          selectedIdRef.current = id;
          setSelectedId(id);
          window.requestAnimationFrame(() => controlEmblaApi.scrollTo(selectedIndex, true));
          return;
        }
        controlEmblaApi.scrollTo(selectedIndex);
        return;
      }
    }
    selectedIdRef.current = id;
    setSelectedId(id);
  }

  function selectHomeDestination(id: DestinationId) {
    if (!primaryDestinations.some((destination) => destination.id === id)) {
      return;
    }
    setHomeDestinationId(id);
    if (typeof window !== "undefined") {
      window.localStorage.setItem("nekofm.homePage", id);
    }
  }

  function openControlDestination() {
    if (isControlDestination(selectedId)) {
      resetControlScrollPositions();
      selectDestination(lastPrimaryDestinationIdRef.current);
      return;
    }
    if (isPrimaryDestination(selectedId)) {
      lastPrimaryDestinationIdRef.current = selectedId;
    }
    pendingControlScrollResetRef.current = true;
    selectDestination("settings");
  }

  function renderShellPage(
    id: DestinationId,
    className: string,
  ) {
    return (
      <div key={id} className={className}>
        <PageForDestination
          id={id}
          resetKey={resetKeys[id]}
          player={player}
          playerActions={playerActions}
          preferences={preferences}
          preferenceActions={preferenceActions}
          downloads={downloads}
          activeDownloadTrackIds={activeDownloadTrackIds}
          downloadActions={downloadActions}
          likedTracks={likedTracks}
          likedActions={likedActions}
          playlists={playlists}
          playlistTracksById={playlistTracksById}
          playlistActions={playlistActions}
          serverConnectionVersion={serverConnectionVersion}
          homeDestinationId={homeDestinationId}
          onHomeDestinationChange={selectHomeDestination}
          onServerProfileChanged={() => setServerConnectionVersion((version) => version + 1)}
        />
      </div>
    );
  }

  return (
    <div className="app-shell">
      <main className="shell-main">
        <audio
          ref={audioRef}
          preload="metadata"
          onTimeUpdate={(event) => {
            const audio = event.currentTarget;
            setPlayer((current) => ({
              ...current,
              positionSeconds: audio.currentTime,
              durationSeconds: Number.isFinite(audio.duration)
                ? audio.duration
                : current.durationSeconds,
            }));
          }}
          onLoadedMetadata={(event) => {
            const audio = event.currentTarget;
            setPlayer((current) => ({
              ...current,
              durationSeconds: Number.isFinite(audio.duration)
                ? audio.duration
                : current.durationSeconds,
            }));
          }}
          onEnded={() => advanceQueue("ended")}
          onPlay={() => setPlayer((current) => ({ ...current, isPlaying: true }))}
          onPause={() => setPlayer((current) => ({ ...current, isPlaying: false }))}
        />
        <section
          className={`shell-page ${showMiniPlayer ? "has-mini-player" : ""}`}
          aria-label={selected.label}
        >
          <header className="shell-header">
            <AppMark onPress={openControlDestination} />
          </header>

          <div
            className={`primary-pager ${selectedPrimaryId ? "" : "is-shell-hidden"}`}
            ref={primaryEmblaRef}
            aria-label="Primary pages"
          >
            <div className="primary-pager-track">
              {primaryDestinations.map((destination) => {
                const isActivePrimaryPage = selectedPrimaryId === destination.id;
                const shouldHideFromAccessibility =
                  !isActivePrimaryPage && focusedPrimaryId !== destination.id;
                return (
                  <div
                    className="primary-pager-slide"
                    key={destination.id}
                    aria-hidden={shouldHideFromAccessibility}
                    inert={shouldHideFromAccessibility ? true : undefined}
                    onFocusCapture={() => setFocusedPrimaryId(destination.id)}
                    onBlurCapture={(event) => {
                      if (!event.currentTarget.contains(event.relatedTarget)) {
                        setFocusedPrimaryId((current) =>
                          current === destination.id ? null : current,
                        );
                      }
                    }}
                  >
                    <div className="content-frame primary-pager-frame">
                      {renderShellPage(destination.id, "page-static-panel")}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          <div
            className={`content-frame shell-secondary-frame ${selectedPrimaryId ? "is-shell-hidden" : ""} ${selectedControlId ? "has-control-pager" : ""}`}
          >
            {selectedPrimaryId ? null : (
              <div className="secondary-page-stack">
                {selectedControlId ? (
                  <div
                    className="control-pager"
                    ref={controlEmblaRef}
                    aria-label="Settings and downloads pages"
                  >
                    <div className="control-pager-track">
                      {controlDestinations.map((destination) => {
                        const isActiveControlPage = selectedControlId === destination.id;
                        return (
                          <div
                            className="control-pager-slide"
                            key={destination.id}
                            aria-hidden={!isActiveControlPage}
                            inert={!isActiveControlPage ? true : undefined}
                          >
                            <div
                              className="page-static-panel control-pager-frame"
                              ref={(node) => {
                                controlScrollFramesRef.current[destination.id] = node;
                              }}
                            >
                              <PageForDestination
                                id={destination.id}
                                resetKey={resetKeys[destination.id]}
                                player={player}
                                playerActions={playerActions}
                                preferences={preferences}
                                preferenceActions={preferenceActions}
                                downloads={downloads}
                                activeDownloadTrackIds={activeDownloadTrackIds}
                                downloadActions={downloadActions}
                                likedTracks={likedTracks}
                                likedActions={likedActions}
                                playlists={playlists}
                                playlistTracksById={playlistTracksById}
                                playlistActions={playlistActions}
                                serverConnectionVersion={serverConnectionVersion}
                                homeDestinationId={homeDestinationId}
                                onHomeDestinationChange={selectHomeDestination}
                                onServerProfileChanged={() => setServerConnectionVersion((version) => version + 1)}
                              />
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                ) : (
                  renderShellPage(selectedId, "page-static-panel")
                )}
              </div>
            )}
          </div>

          {showMiniPlayer ? (
            <MiniPlayer
              player={player}
              actions={playerActions}
              onOpenPlayer={() => selectDestination("player")}
            />
          ) : null}
        </section>
      </main>
    </div>
  );
}

function PageForDestination({
  id,
  resetKey,
  player,
  playerActions,
  preferences,
  preferenceActions,
  downloads,
  activeDownloadTrackIds,
  downloadActions,
  likedTracks,
  likedActions,
  playlists,
  playlistTracksById,
  playlistActions,
  serverConnectionVersion,
  homeDestinationId,
  onHomeDestinationChange,
  onServerProfileChanged,
}: {
  id: DestinationId;
  resetKey: number;
  player: PlayerState;
  playerActions: PlayerActions;
  preferences: AppPreferences;
  preferenceActions: PreferenceActions;
  downloads: DownloadedTrack[];
  activeDownloadTrackIds: Set<string>;
  downloadActions: DownloadActions;
  likedTracks: LikedTrack[];
  likedActions: LikedActions;
  playlists: PlaylistModel[];
  playlistTracksById: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
  serverConnectionVersion: number;
  homeDestinationId: DestinationId;
  onHomeDestinationChange: (id: DestinationId) => void;
  onServerProfileChanged: () => void;
}) {
  const key = `${id}-${resetKey}`;
  switch (id) {
    case "library":
      return (
        <LibraryPlaceholder
          key={key}
          player={player}
          actions={playerActions}
          downloads={downloads}
          activeDownloadTrackIds={activeDownloadTrackIds}
          downloadActions={downloadActions}
          likedTracks={likedTracks}
          likedActions={likedActions}
          playlists={playlists}
          playlistTracksById={playlistTracksById}
          playlistActions={playlistActions}
          serverConnectionVersion={serverConnectionVersion}
        />
      );
    case "player":
      return (
        <PlayerPage
          key={key}
          player={player}
          actions={playerActions}
          downloads={downloads}
          likedTracks={likedTracks}
          likedActions={likedActions}
          playlists={playlists}
          playlistTracksById={playlistTracksById}
          playlistActions={playlistActions}
        />
      );
    case "liked":
      return (
        <LikedPage
          key={key}
          likedTracks={likedTracks}
          player={player}
          actions={playerActions}
          downloads={downloads}
          activeDownloadTrackIds={activeDownloadTrackIds}
          downloadActions={downloadActions}
          likedActions={likedActions}
          serverConnectionVersion={serverConnectionVersion}
        />
      );
    case "playlists":
      return (
        <PlaylistsPage
          key={key}
          playlists={playlists}
          tracksByPlaylistId={playlistTracksById}
          playlistActions={playlistActions}
          player={player}
          playerActions={playerActions}
          downloads={downloads}
          likedTracks={likedTracks}
          likedActions={likedActions}
          serverConnectionVersion={serverConnectionVersion}
        />
      );
    case "downloads":
      return (
        <DownloadsPage
          key={key}
          player={player}
          playerActions={playerActions}
          downloads={downloads}
          activeDownloadTrackIds={activeDownloadTrackIds}
          actions={downloadActions}
          likedTracks={likedTracks}
          playlists={playlists}
          tracksByPlaylistId={playlistTracksById}
          playlistActions={playlistActions}
        />
      );
    case "settings":
      return (
        <SettingsPlaceholder
          key={key}
          preferences={preferences}
          preferenceActions={preferenceActions}
          homeDestinationId={homeDestinationId}
          onHomeDestinationChange={onHomeDestinationChange}
          onDownloadsChanged={async () => {
            await downloadActions.reloadDownloads();
          }}
          onServerProfileChanged={onServerProfileChanged}
        />
      );
  }
}

function AppMark({ onPress }: { onPress?: () => void }) {
  return (
    <button className="app-mark" type="button" aria-label="Open NekoFM controls" onClick={onPress}>
      <span aria-hidden="true">N</span>
    </button>
  );
}

function LibraryPlaceholder({
  player,
  actions,
  downloads,
  activeDownloadTrackIds,
  downloadActions,
  likedTracks,
  likedActions,
  playlists,
  playlistTracksById,
  playlistActions,
  serverConnectionVersion,
}: {
  player: PlayerState;
  actions: PlayerActions;
  downloads: DownloadedTrack[];
  activeDownloadTrackIds: Set<string>;
  downloadActions: DownloadActions;
  likedTracks: LikedTrack[];
  likedActions: LikedActions;
  playlists: PlaylistModel[];
  playlistTracksById: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
  serverConnectionVersion: number;
}) {
  const initialAlbumDetail = initialPreviewAlbumDetail();
  const [albums, setAlbums] = useState<AlbumModel[]>([]);
  const [selectedAlbum, setSelectedAlbum] = useState<AlbumModel | null>(
    initialAlbumDetail?.album ?? null,
  );
  const [albumDetail, setAlbumDetail] = useState<AlbumDetailModel | null>(initialAlbumDetail);
  const [query, setQuery] = useState("");
  const [searchResult, setSearchResult] = useState<LibrarySearchResult | null>(null);
  const [isSearching, setIsSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [isLoadingAlbums, setIsLoadingAlbums] = useState(true);
  const [isLoadingDetail, setIsLoadingDetail] = useState(false);
  const [isShuffling, setIsShuffling] = useState(false);
  const [isDownloadedLibrary, setIsDownloadedLibrary] = useState(false);
  const [shuffleNotice, setShuffleNotice] = useState<{
    tone: "success" | "warning";
    message: string;
  } | null>(null);
  const [downloadedAlbumDetails, setDownloadedAlbumDetails] = useState<
    Record<string, AlbumDetailModel>
  >({});
  const [libraryError, setLibraryError] = useState<string | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);

  useEffect(() => {
    loadAlbums();
  }, [serverConnectionVersion]);

  useEffect(() => {
    let isCurrent = true;
    const trimmedQuery = query.trim();
    setSearchError(null);

    if (trimmedQuery.length === 0) {
      setSearchResult(null);
      setIsSearching(false);
      return () => {
        isCurrent = false;
      };
    }

    if (trimmedQuery.length < 2) {
      setSearchResult(null);
      setIsSearching(false);
      return () => {
        isCurrent = false;
      };
    }

    setIsSearching(true);
    const timeout = window.setTimeout(async () => {
      try {
        const result = isDownloadedLibrary
          ? await invokeCommand<LibrarySearchResult>("search_downloaded_library", {
              query: trimmedQuery,
            })
          : await searchLibraryWithDownloadedFallback(trimmedQuery);
        if (isCurrent) {
          setSearchResult(result);
        }
      } catch (error) {
        if (isCurrent) {
          setSearchError(String(error));
          setSearchResult({ albums: [], tracks: [] });
        }
      } finally {
        if (isCurrent) {
          setIsSearching(false);
        }
      }
    }, 300);

    return () => {
      isCurrent = false;
      window.clearTimeout(timeout);
    };
  }, [query, isDownloadedLibrary]);

  async function searchLibraryWithDownloadedFallback(trimmedQuery: string) {
    try {
      return await invokeCommand<LibrarySearchResult>("search_library", {
        query: trimmedQuery,
      });
    } catch {
      return invokeCommand<LibrarySearchResult>("search_downloaded_library", {
        query: trimmedQuery,
      });
    }
  }

  async function loadAlbums() {
    setIsLoadingAlbums(true);
    setLibraryError(null);
    setShuffleNotice(null);

    try {
      const result = await invokeCommand<AlbumModel[]>("get_albums");
      setAlbums(result);
      setDownloadedAlbumDetails({});
      setIsDownloadedLibrary(false);
    } catch (error) {
      try {
        const downloadedDetails = await invokeCommand<AlbumDetailModel[]>(
          "load_downloaded_album_details",
        );
        setDownloadedAlbumDetails(
          Object.fromEntries(
            downloadedDetails.map((detail) => [detail.album.id, detail]),
          ),
        );
        setAlbums(downloadedDetails.map((detail) => detail.album));
        setIsDownloadedLibrary(true);
        setLibraryError(null);
      } catch {
        setLibraryError(String(error));
        setAlbums([]);
        setDownloadedAlbumDetails({});
        setIsDownloadedLibrary(false);
      }
    } finally {
      setIsLoadingAlbums(false);
    }
  }

  async function openAlbum(album: AlbumModel) {
    const downloadedDetail = downloadedAlbumDetails[album.id];
    setSelectedAlbum(album);
    setAlbumDetail(downloadedDetail ?? null);
    setDetailError(null);
    setIsLoadingDetail(!downloadedDetail);

    if (downloadedDetail) {
      return;
    }

    try {
      const result = await invokeCommand<AlbumDetailModel>("get_album", {
        albumId: album.id,
      });
      setAlbumDetail(result);
    } catch (error) {
      setDetailError(String(error));
    } finally {
      setIsLoadingDetail(false);
    }
  }

  function backToAlbums() {
    setSelectedAlbum(null);
    setAlbumDetail(null);
    setDetailError(null);
  }

  async function shuffleAll() {
    if (isShuffling) {
      return;
    }

    setIsShuffling(true);
    setShuffleNotice(null);
    const tracks: TrackModel[] = [];
    let skippedAlbumCount = 0;

    try {
      if (isDownloadedLibrary) {
        for (const detail of Object.values(downloadedAlbumDetails)) {
          tracks.push(...detail.tracks);
        }
      } else {
        for (const album of albums) {
          try {
            const detail = await invokeCommand<AlbumDetailModel>("get_album", {
              albumId: album.id,
            });
            tracks.push(...detail.tracks);
          } catch {
            const downloadedDetail = downloadedAlbumDetails[album.id];
            if (downloadedDetail) {
              tracks.push(...downloadedDetail.tracks);
            } else {
              skippedAlbumCount += 1;
            }
          }
        }
      }

      if (tracks.length === 0) {
        setShuffleNotice({
          tone: "warning",
          message: "No playable songs were found for shuffle.",
        });
        return;
      }

      const shuffled = shuffleItems(tracks);
      const firstTrack = shuffled[0];
      actions.playAlbum(
        {
          id: isDownloadedLibrary ? "downloaded-library-shuffle" : "library-shuffle",
          name: isDownloadedLibrary ? "Downloaded library shuffle" : "Library shuffle",
          artist: "Library",
          songCount: shuffled.length,
          durationSeconds: shuffled.reduce(
            (total, track) => total + track.durationSeconds,
            0,
          ),
          coverArtId: firstTrack.coverArtId,
          coverArtUri: firstTrack.coverArtUri,
        },
        shuffled,
        0,
        { skipUnavailable: true },
      );
      setShuffleNotice({
        tone: "success",
        message:
          skippedAlbumCount > 0
            ? `Shuffled ${shuffled.length} songs. ${skippedAlbumCount} albums could not be loaded.`
            : `Shuffled ${shuffled.length} songs.`,
      });
    } finally {
      setIsShuffling(false);
    }
  }

  async function playSearchTrack(track: TrackModel) {
    const albumId = track.albumId;
    if (albumId) {
      const downloadedDetail = downloadedAlbumDetails[albumId];
      if (downloadedDetail) {
        const index = downloadedDetail.tracks.findIndex((item) => item.id === track.id);
        if (index >= 0) {
          actions.playAlbum(downloadedDetail.album, downloadedDetail.tracks, index);
          return;
        }
      }

      try {
        const detail = await invokeCommand<AlbumDetailModel>("get_album", {
          albumId,
        });
        const index = detail.tracks.findIndex((item) => item.id === track.id);
        if (index >= 0) {
          actions.playAlbum(detail.album, detail.tracks, index);
          return;
        }
      } catch {
        // Fall back to a single-track queue when album lookup is unavailable.
      }
    }

    actions.playAlbum(
      albumFromTrack(track),
      [track],
      0,
    );
  }

  const trimmedQuery = query.trim();
  const isSearchActive = trimmedQuery.length > 0;
  const currentTrackId = player.queue[player.currentIndex]?.id ?? null;
  const likedTrackIds = new Set(likedTracks.map((track) => track.trackId));
  const downloadsByTrackId = useMemo(
    () => new Map(downloads.map((download) => [download.trackId, download])),
    [downloads],
  );

  if (selectedAlbum) {
    const detailAlbum = albumDetail?.album ?? selectedAlbum;
    return (
      <AlbumDetailView
        album={detailAlbum}
        tracks={albumDetail?.tracks ?? []}
        isLoading={isLoadingDetail}
        error={detailError}
        currentTrackId={player.queue[player.currentIndex]?.id ?? null}
        downloads={downloads}
        activeDownloadTrackIds={activeDownloadTrackIds}
        onBack={backToAlbums}
        onRetry={() => openAlbum(selectedAlbum)}
        onPlayTrack={(index) => actions.playAlbum(detailAlbum, albumDetail?.tracks ?? [], index)}
        onDownloadTrack={downloadActions.downloadTrack}
        onDeleteDownload={downloadActions.deleteDownload}
        onDownloadAlbum={downloadActions.downloadTracks}
        onDeleteAlbum={downloadActions.deleteDownloads}
        likedTrackIds={likedTrackIds}
        onToggleLiked={likedActions.toggleLiked}
        playlists={playlists}
        playlistTracksById={playlistTracksById}
        playlistActions={playlistActions}
      />
    );
  }

  return (
    <div className="page-stack">
      <label className="search-field deferred-circular-control">
        <Search size={20} />
        <span>Search library</span>
        <input
          value={query}
          placeholder="Search library"
          onChange={(event) => setQuery(event.target.value)}
        />
        {query ? (
          <button
            type="button"
            aria-label="Clear search"
            title="Clear search"
            onClick={() => setQuery("")}
          >
            <X size={18} />
          </button>
        ) : null}
      </label>
      <div className="library-toolbar deferred-circular-control">
        <button type="button" disabled={albums.length === 0 || isShuffling} onClick={shuffleAll}>
          {isShuffling ? <LoaderCircle className="spin-icon" size={18} /> : <Shuffle size={18} />}
          {isShuffling ? "Shuffling..." : "Shuffle all"}
        </button>
        <button type="button" onClick={loadAlbums}>
          <RefreshCw size={18} />
          Refresh
        </button>
      </div>
      {shuffleNotice ? (
        <InlineNotice tone={shuffleNotice.tone} icon={Shuffle} message={shuffleNotice.message} />
      ) : null}
      {isDownloadedLibrary ? (
        <div className="offline-notice">
          <CircleCheck size={18} />
          Navidrome is offline. Showing albums downloaded on this device.
        </div>
      ) : null}
      <div className="library-list">
        {isLoadingAlbums ? (
          <LibraryMessage icon={LoaderCircle} title="Loading library" message="Asking the server for albums." spin />
        ) : libraryError ? (
          <LibraryMessage
            icon={ShieldAlert}
            title="Could not load library"
            message={libraryError}
            actionLabel="Retry"
            onAction={loadAlbums}
          />
        ) : isSearchActive ? (
          <LibrarySearchResults
            query={trimmedQuery}
            result={searchResult}
            isSearching={isSearching}
            error={searchError}
            currentAlbumId={player.album?.id ?? null}
            currentTrackId={currentTrackId}
            downloadsByTrackId={downloadsByTrackId}
            activeDownloadTrackIds={activeDownloadTrackIds}
            likedTrackIds={likedTrackIds}
            playlists={playlists}
            playlistTracksById={playlistTracksById}
            playlistActions={playlistActions}
            onOpenAlbum={openAlbum}
            onPlayTrack={playSearchTrack}
            onDownloadTrack={downloadActions.downloadTrack}
            onDeleteDownload={downloadActions.deleteDownload}
            onToggleLiked={likedActions.toggleLiked}
          />
        ) : albums.length === 0 ? (
          <LibraryMessage
            icon={isDownloadedLibrary ? Download : Disc3}
            title={
              isDownloadedLibrary
                ? "No downloaded albums"
                : "No albums found"
            }
            message={
              isDownloadedLibrary
                ? "Navidrome is offline and there are no completed album downloads on this device."
                : "Navidrome is connected, but it did not return any albums yet."
            }
            actionLabel="Refresh"
            onAction={loadAlbums}
          />
        ) : (
          albums.map((album) => (
            <AlbumRow
              key={album.id}
              album={album}
              isPlaying={
                player.album?.id === album.id ||
                player.queue[player.currentIndex]?.albumId === album.id
              }
              onClick={() => openAlbum(album)}
            />
          ))
        )}
      </div>
    </div>
  );
}

function LibrarySearchResults({
  query,
  result,
  isSearching,
  error,
  currentAlbumId,
  currentTrackId,
  downloadsByTrackId,
  activeDownloadTrackIds,
  likedTrackIds,
  playlists,
  playlistTracksById,
  playlistActions,
  onOpenAlbum,
  onPlayTrack,
  onDownloadTrack,
  onDeleteDownload,
  onToggleLiked,
}: {
  query: string;
  result: LibrarySearchResult | null;
  isSearching: boolean;
  error: string | null;
  currentAlbumId: string | null;
  currentTrackId: string | null;
  downloadsByTrackId: Map<string, DownloadedTrack>;
  activeDownloadTrackIds: Set<string>;
  likedTrackIds: Set<string>;
  playlists: PlaylistModel[];
  playlistTracksById: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
  onOpenAlbum: (album: AlbumModel) => void;
  onPlayTrack: (track: TrackModel) => void;
  onDownloadTrack: (track: TrackModel) => Promise<void>;
  onDeleteDownload: (trackId: string) => Promise<void>;
  onToggleLiked: (track: TrackModel) => Promise<void>;
}) {
  if (query.length < 2) {
    return (
      <LibraryMessage
        icon={Search}
        title="Keep typing"
        message="Search starts after 2 characters."
      />
    );
  }

  if (isSearching && !result) {
    return (
      <LibraryMessage
        icon={LoaderCircle}
        title="Searching library"
        message="Looking for matching albums and songs."
        spin
      />
    );
  }

  if (error) {
    return (
      <LibraryMessage
        icon={ShieldAlert}
        title="Search failed"
        message={error}
      />
    );
  }

  const albums = result?.albums ?? [];
  const tracks = result?.tracks ?? [];
  if (albums.length === 0 && tracks.length === 0) {
    return (
      <LibraryMessage
        icon={Search}
        title="No results"
        message={`Nothing matched "${query}".`}
      />
    );
  }

  return (
    <div className="search-results">
      {albums.length > 0 ? (
        <section>
          <h3 className="result-section-header">Albums</h3>
          {albums.map((album) => (
            <AlbumRow
              key={album.id}
              album={album}
              isPlaying={currentAlbumId === album.id}
              onClick={() => onOpenAlbum(album)}
            />
          ))}
        </section>
      ) : null}
      {albums.length > 0 && tracks.length > 0 ? <div className="result-section-divider" /> : null}
      {tracks.length > 0 ? (
        <section>
          <h3 className="result-section-header">Tracks</h3>
          {tracks.map((track, index) => (
            <TrackRow
              key={`${track.id}-${index}`}
              track={track}
              fallbackNumber={index + 1}
              isPlaying={currentTrackId === track.id}
              download={downloadsByTrackId.get(track.id) ?? null}
              isDownloadActive={activeDownloadTrackIds.has(track.id)}
              isLiked={likedTrackIds.has(track.id)}
              playlists={playlists}
              playlistTracksById={playlistTracksById}
              playlistActions={playlistActions}
              onClick={() => onPlayTrack(track)}
              onDownload={() => onDownloadTrack(track)}
              onDeleteDownload={() => onDeleteDownload(track.id)}
              onToggleLiked={() => onToggleLiked(track)}
            />
          ))}
        </section>
      ) : null}
    </div>
  );
}

function AlbumDetailView({
  album,
  tracks,
  isLoading,
  error,
  currentTrackId,
  downloads,
  activeDownloadTrackIds,
  onBack,
  onRetry,
  onPlayTrack,
  onDownloadTrack,
  onDeleteDownload,
  onDownloadAlbum,
  onDeleteAlbum,
  likedTrackIds,
  onToggleLiked,
  playlists,
  playlistActions,
  playlistTracksById,
}: {
  album: AlbumModel;
  tracks: TrackModel[];
  isLoading: boolean;
  error: string | null;
  currentTrackId: string | null;
  downloads: DownloadedTrack[];
  activeDownloadTrackIds: Set<string>;
  onBack: () => void;
  onRetry: () => void;
  onPlayTrack: (index: number) => void;
  onDownloadTrack: (track: TrackModel) => Promise<void>;
  onDeleteDownload: (trackId: string) => Promise<void>;
  onDownloadAlbum: (tracks: TrackModel[]) => Promise<void>;
  onDeleteAlbum: (trackIds: string[]) => Promise<void>;
  likedTrackIds: Set<string>;
  onToggleLiked: (track: TrackModel) => Promise<void>;
  playlists: PlaylistModel[];
  playlistActions: PlaylistActions;
  playlistTracksById: Record<string, PlaylistTrack[]>;
}) {
  const [deleteAlbumDialog, setDeleteAlbumDialog] =
    useState<LocalAlbumDeleteDialogState | null>(null);
  const downloadsByTrackId = new Map(
    downloads.map((download) => [download.trackId, download]),
  );
  const completeTrackIds = tracks
    .filter((track) => downloadsByTrackId.get(track.id)?.state === "complete")
    .map((track) => track.id);
  const missingTracks = tracks.filter(
    (track) => downloadsByTrackId.get(track.id)?.state !== "complete",
  );
  const albumDownloadState = albumDownloadStateFromTracks(
    tracks,
    downloadsByTrackId,
    activeDownloadTrackIds,
  );

  async function confirmDeleteAlbum() {
    const dialog = deleteAlbumDialog;
    if (!dialog) {
      return;
    }
    await onDeleteAlbum(dialog.trackIds);
    setDeleteAlbumDialog(null);
  }

  return (
    <div className="album-detail">
      <button className="back-button" type="button" onClick={onBack}>
        <ArrowLeft size={20} />
        Back
      </button>
      <div className="album-hero">
        <AlbumArt imageUri={album.coverArtUri} label={album.name} size="large" />
        <div>
          <h2>{album.name}</h2>
          <p>
            {album.artist}
            {album.year ? ` • ${album.year}` : ""} • {album.songCount} songs •{" "}
            {formatDuration(album.durationSeconds)}
          </p>
        </div>
      </div>

      <div className="track-list">
        {isLoading ? (
          <LibraryMessage icon={LoaderCircle} title="Loading album" message="Asking the server for tracks." spin />
        ) : error ? (
          <LibraryMessage
            icon={ShieldAlert}
            title="Could not load album"
            message={error}
            actionLabel="Retry"
            onAction={onRetry}
          />
        ) : tracks.length === 0 ? (
          <LibraryMessage
            icon={Music2}
            title="No tracks found"
            message="The server returned this album without songs."
          />
        ) : (
          <>
            <AlbumDownloadRow
              state={albumDownloadState}
              onDownload={() => onDownloadAlbum(albumDownloadState.hasMissingCovers ? tracks : missingTracks)}
              onDelete={() =>
                setDeleteAlbumDialog({
                  albumName: album.name,
                  trackIds: completeTrackIds,
                })
              }
            />
            {tracks.map((track, index) => (
              <TrackRow
                key={`${track.id}-${index}`}
                track={track}
                fallbackNumber={index + 1}
                isPlaying={currentTrackId === track.id}
                download={downloadsByTrackId.get(track.id) ?? null}
                isDownloadActive={activeDownloadTrackIds.has(track.id)}
                onClick={() => onPlayTrack(index)}
                onDownload={() => onDownloadTrack(track)}
                onDeleteDownload={() => onDeleteDownload(track.id)}
                isLiked={likedTrackIds.has(track.id)}
                onToggleLiked={() => onToggleLiked(track)}
                playlists={playlists}
                playlistTracksById={playlistTracksById}
                playlistActions={playlistActions}
              />
            ))}
          </>
        )}
      </div>
      {deleteAlbumDialog ? (
        <LocalAlbumDeleteDialog
          dialog={deleteAlbumDialog}
          isWorking={deleteAlbumDialog.trackIds.some((trackId) =>
            activeDownloadTrackIds.has(trackId),
          )}
          onCancel={() => setDeleteAlbumDialog(null)}
          onConfirm={confirmDeleteAlbum}
        />
      ) : null}
    </div>
  );
}

type AlbumDownloadState = {
  totalCount: number;
  completeCount: number;
  queuedCount: number;
  downloadingCount: number;
  missingCoverCount: number;
  remainingCount: number;
  progress: number;
  isComplete: boolean;
  hasActiveDownloads: boolean;
  hasMissingCovers: boolean;
  activeDownloadSummary: string;
  buttonLabel: string;
  subtitle: string;
};

function AlbumDownloadRow({
  state,
  onDownload,
  onDelete,
}: {
  state: AlbumDownloadState;
  onDownload: () => void;
  onDelete: () => void;
}) {
  const isDisabled = state.hasActiveDownloads;
  return (
    <div className="album-download-row">
      <span className="album-download-icon">
        {state.isComplete ? <CircleCheck size={22} /> : <Download size={22} />}
      </span>
      <span className="album-download-copy">
        <strong>{state.buttonLabel}</strong>
        <span>{state.subtitle}</span>
        {!state.isComplete && state.completeCount > 0 ? (
          <span className="album-download-progress" aria-label="Album download progress">
            <span style={{ width: `${Math.round(state.progress * 100)}%` }} />
          </span>
        ) : null}
      </span>
      <button
        type="button"
        disabled={isDisabled}
        onClick={state.isComplete ? onDelete : onDownload}
      >
        {state.isComplete ? <Trash2 size={18} /> : <Download size={18} />}
        {state.buttonLabel}
      </button>
    </div>
  );
}

function albumDownloadStateFromTracks(
  tracks: TrackModel[],
  downloadsByTrackId: Map<string, DownloadedTrack>,
  activeDownloadTrackIds: Set<string>,
): AlbumDownloadState {
  let completeCount = 0;
  let queuedCount = 0;
  let downloadingCount = 0;
  let missingCoverCount = 0;

  for (const track of tracks) {
    const download = downloadsByTrackId.get(track.id);
    if (download?.state === "complete") {
      completeCount += 1;
      if (track.coverArtUri && !download.localCoverPath) {
        missingCoverCount += 1;
      }
    } else if (download?.state === "queued") {
      queuedCount += 1;
    } else if (download?.state === "downloading" || activeDownloadTrackIds.has(track.id)) {
      downloadingCount += 1;
    }
  }

  const totalCount = tracks.length;
  const remainingCount = totalCount - completeCount - queuedCount - downloadingCount;
  const isComplete = totalCount > 0 && completeCount === totalCount && missingCoverCount === 0;
  const hasActiveDownloads = queuedCount > 0 || downloadingCount > 0;
  const hasMissingCovers = totalCount > 0 && completeCount === totalCount && missingCoverCount > 0;
  const activeDownloadSummary = [
    queuedCount > 0 ? `${queuedCount} queued` : null,
    downloadingCount > 0 ? `${downloadingCount} downloading` : null,
  ].filter(Boolean).join(" • ");
  const buttonLabel = isComplete
    ? "Delete album"
    : hasMissingCovers
      ? "Download covers"
      : hasActiveDownloads
        ? queuedCount > 0
          ? "Album queued"
          : "Downloading album"
        : completeCount > 0
          ? "Download missing"
          : "Download album";
  const subtitle = isComplete
    ? "All tracks are saved for offline playback."
    : hasMissingCovers
      ? `${missingCoverCount} local covers missing`
      : hasActiveDownloads
        ? `${activeDownloadSummary} • ${completeCount}/${totalCount} saved`
        : `${remainingCount} tracks not saved yet`;

  return {
    totalCount,
    completeCount,
    queuedCount,
    downloadingCount,
    missingCoverCount,
    remainingCount,
    progress: totalCount <= 0 ? 0 : completeCount / totalCount,
    isComplete,
    hasActiveDownloads,
    hasMissingCovers,
    activeDownloadSummary,
    buttonLabel,
    subtitle,
  };
}

function AlbumRow({
  album,
  isPlaying,
  onClick,
}: {
  album: AlbumModel;
  isPlaying: boolean;
  onClick: () => void;
}) {
  return (
    <button className={`album-row ${isPlaying ? "is-playing" : ""}`} type="button" onClick={onClick}>
      <AlbumArt imageUri={album.coverArtUri} label={album.name} />
      <div className="album-row-copy">
        <strong>{album.name}</strong>
        <span>
          {album.artist}
          {album.year ? ` • ${album.year}` : ""} • {album.songCount} songs •{" "}
          {formatDuration(album.durationSeconds)}
        </span>
      </div>
      <ChevronRight className="album-row-chevron" aria-hidden="true" size={28} />
    </button>
  );
}

function TrackRow({
  track,
  fallbackNumber,
  isPlaying,
  download,
  isDownloadActive,
  isLiked,
  playlists,
  playlistTracksById,
  playlistActions,
  onClick,
  onDownload,
  onDeleteDownload,
  onToggleLiked,
}: {
  track: TrackModel;
  fallbackNumber: number;
  isPlaying: boolean;
  download: DownloadedTrack | null;
  isDownloadActive: boolean;
  isLiked: boolean;
  playlists: PlaylistModel[];
  playlistTracksById: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
  onClick: () => void;
  onDownload: () => void;
  onDeleteDownload: () => void;
  onToggleLiked: () => void;
}) {
  const [deleteDownloadDialog, setDeleteDownloadDialog] =
    useState<LocalDownloadDeleteDialogState | null>(null);
  const trackNumber = track.trackNumber || fallbackNumber;
  const isComplete = download?.state === "complete";
  const isBusy = isDownloadActive || download?.state === "downloading";

  async function confirmDeleteDownload() {
    if (!deleteDownloadDialog) {
      return;
    }
    await onDeleteDownload();
    setDeleteDownloadDialog(null);
  }

  return (
    <div className={`track-row ${isPlaying ? "is-playing" : ""}`}>
      <button className="track-main" type="button" onClick={onClick}>
        <span className="track-number">{trackNumber}</span>
        <span className="track-copy">
          <strong>{track.title}</strong>
          <span>
            {track.artist} • {formatDuration(track.durationSeconds)}
            {track.suffix ? ` • ${track.suffix.toUpperCase()}` : ""}
          </span>
        </span>
      </button>
      <span className="track-actions">
        <button
          type="button"
          className={isLiked ? "is-liked" : ""}
          aria-label={isLiked ? "Remove from liked" : "Add to liked"}
          title={isLiked ? "Remove from liked" : "Add to liked"}
          onClick={onToggleLiked}
        >
          <Heart size={20} fill={isLiked ? "currentColor" : "none"} />
        </button>
        <PlaylistAddMenu
          track={track}
          playlists={playlists}
          tracksByPlaylistId={playlistTracksById}
          playlistActions={playlistActions}
        />
        <button
          type="button"
          aria-label={isComplete ? "Delete local download" : "Download track"}
          title={isComplete ? "Delete local download" : "Download track"}
          disabled={isBusy}
          onClick={
            isComplete
              ? () =>
                  setDeleteDownloadDialog({
                    trackId: track.id,
                    title: track.title,
                  })
              : onDownload
          }
        >
          {isBusy ? (
            <LoaderCircle className="spin-icon" size={20} />
          ) : isComplete ? (
            <Trash2 size={20} />
          ) : download?.state === "failed" ? (
            <ShieldAlert size={20} />
          ) : (
            <Download size={20} />
          )}
        </button>
        <Play aria-hidden="true" size={20} />
      </span>
      {deleteDownloadDialog ? (
        <LocalDownloadDeleteDialog
          dialog={deleteDownloadDialog}
          isWorking={isDownloadActive}
          onCancel={() => setDeleteDownloadDialog(null)}
          onConfirm={confirmDeleteDownload}
        />
      ) : null}
    </div>
  );
}

function LocalAlbumDeleteDialog({
  dialog,
  isWorking,
  onCancel,
  onConfirm,
}: {
  dialog: LocalAlbumDeleteDialogState;
  isWorking: boolean;
  onCancel: () => void;
  onConfirm: () => Promise<void>;
}) {
  return (
    <div className="playlist-dialog-backdrop" role="presentation">
      <section
        className="playlist-dialog playlist-delete-dialog"
        aria-modal="true"
        role="dialog"
        aria-label="Delete local album"
      >
        <h2>Delete local album?</h2>
        <p>
          Remove all downloaded tracks from &quot;{dialog.albumName}&quot; on this device. This will not delete anything from Navidrome.
        </p>
        <span className="playlist-dialog-actions">
          <button type="button" disabled={isWorking} onClick={onCancel}>
            Cancel
          </button>
          <button type="button" disabled={isWorking} onClick={onConfirm}>
            {isWorking ? <LoaderCircle className="spin-icon" size={16} /> : <Trash2 size={16} />}
            Delete album
          </button>
        </span>
      </section>
    </div>
  );
}

function LibraryMessage({
  icon: Icon,
  title,
  message,
  actionLabel,
  onAction,
  spin = false,
}: {
  icon: ComponentType<{ size?: number; strokeWidth?: number; className?: string }>;
  title: string;
  message: string;
  actionLabel?: string;
  onAction?: () => void;
  spin?: boolean;
}) {
  return (
    <div className="library-message">
      <Icon className={spin ? "spin-icon" : undefined} size={48} />
      <h2>{title}</h2>
      <p>{message}</p>
      {actionLabel && onAction ? (
        <button type="button" onClick={onAction}>
          {actionLabel}
        </button>
      ) : null}
    </div>
  );
}

function AlbumArt({
  imageUri,
  label,
  size = "normal",
}: {
  imageUri?: string | null;
  label: string;
  size?: "normal" | "large" | "header";
}) {
  return (
    <span className={`album-art is-${size}`}>
      {imageUri ? <img src={imageUri} alt={label} /> : <Disc3 size={size === "large" ? 44 : 24} />}
    </span>
  );
}

function formatDuration(seconds: number) {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return "0:00";
  }

  const total = Math.round(seconds);
  const minutes = Math.floor(total / 60);
  const remainder = total % 60;
  if (minutes < 60) {
    return `${minutes}:${remainder.toString().padStart(2, "0")}`;
  }

  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return `${hours}:${remainingMinutes.toString().padStart(2, "0")}:${remainder
    .toString()
    .padStart(2, "0")}`;
}

function PlayerPage({
  player,
  actions,
  downloads,
  likedTracks,
  likedActions,
  playlists,
  playlistTracksById,
  playlistActions,
}: {
  player: PlayerState;
  actions: PlayerActions;
  downloads: DownloadedTrack[];
  likedTracks: LikedTrack[];
  likedActions: LikedActions;
  playlists: PlaylistModel[];
  playlistTracksById: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
}) {
  const currentTrack = player.queue[player.currentIndex] ?? null;

  if (!currentTrack || !player.album) {
    return (
      <div className="empty-state">
        <CirclePlay size={56} />
        <h2>Nothing playing</h2>
        <p>Choose a track from Library to start streaming.</p>
      </div>
    );
  }

  const coverArtUri = currentTrack.coverArtUri ?? player.album.coverArtUri;
  const isLiked = likedTracks.some((track) => track.trackId === currentTrack.id);

  return (
    <div className="player-page">
      <section className="now-playing-header" aria-live="polite">
        <AlbumArt imageUri={coverArtUri} label={`${player.album.name} cover art`} size="header" />
        <div className="now-playing-copy">
          <h2>{currentTrack.title}</h2>
          <p>
            {[currentTrack.artist, player.album.name, player.album.artist]
              .filter(Boolean)
              .join(" • ")}
          </p>
          {player.source ? (
            <div className="source-chip">
              {player.source === "local" ? <CircleCheck size={16} /> : <Network size={16} />}
              {player.source === "local" ? "Local" : "Streaming"}
            </div>
          ) : null}
          {player.isLoading || player.errorMessage ? (
            <span className={`playback-status ${player.errorMessage ? "is-error" : ""}`}>
              {player.errorMessage ?? "Loading stream..."}
            </span>
          ) : null}
        </div>
        <button
          className={`now-playing-like ${isLiked ? "is-liked" : ""}`}
          type="button"
          aria-label={isLiked ? "Remove from liked" : "Add to liked"}
          onClick={() => likedActions.toggleLiked(currentTrack)}
        >
          <Heart size={22} fill={isLiked ? "currentColor" : "none"} />
        </button>
        <span className="now-playing-add">
          <PlaylistAddMenu
            track={currentTrack}
            playlists={playlists}
            tracksByPlaylistId={playlistTracksById}
            playlistActions={playlistActions}
          />
        </span>
      </section>

      <PlaybackTimeline player={player} actions={actions} />
      <PlaybackControls player={player} actions={actions} />
      <QueueList player={player} actions={actions} downloads={downloads} />
    </div>
  );
}

function PlaybackTimeline({
  player,
  actions,
}: {
  player: PlayerState;
  actions: PlayerActions;
}) {
  const [previewSeconds, setPreviewSeconds] = useState<number | null>(null);
  const [isScrubbing, setIsScrubbing] = useState(false);
  const duration = Math.max(player.durationSeconds, 0);
  const position = Math.max(0, Math.min(player.positionSeconds, duration || player.positionSeconds));
  const displayPosition = previewSeconds ?? position;
  const currentTrack = player.queue[player.currentIndex] ?? null;
  const timelineResetKey = currentTrack
    ? `${queueTrackKey(currentTrack)}:${player.playbackRequestId}`
    : "empty";

  useEffect(() => {
    setPreviewSeconds(null);
    setIsScrubbing(false);
  }, [timelineResetKey]);

  function safeTimelineValue(value: number) {
    return Math.max(0, Math.min(value, duration || value));
  }

  function commitSeek(value: number) {
    const safeValue = safeTimelineValue(value);
    setPreviewSeconds(null);
    setIsScrubbing(false);
    actions.seekTo(safeValue);
  }

  return (
    <div className="playback-timeline">
      <input
        data-no-page-swipe
        type="range"
        min={0}
        max={duration > 0 ? duration : 1}
        step={0.25}
        value={displayPosition}
        disabled={duration <= 0}
        aria-label="Playback progress"
        onPointerDown={(event) => {
          setIsScrubbing(true);
          setPreviewSeconds(safeTimelineValue(Number(event.currentTarget.value)));
        }}
        onPointerUp={(event) => commitSeek(Number(event.currentTarget.value))}
        onPointerCancel={() => {
          setPreviewSeconds(null);
          setIsScrubbing(false);
        }}
        onBlur={(event) => {
          if (isScrubbing) {
            commitSeek(Number(event.currentTarget.value));
          }
        }}
        onChange={(event) => {
          const nextValue = safeTimelineValue(Number(event.target.value));
          if (isScrubbing) {
            setPreviewSeconds(nextValue);
            return;
          }
          actions.seekTo(nextValue);
        }}
      />
      <div>
        <span>{formatDuration(displayPosition)}</span>
        <span>{formatDuration(duration)}</span>
      </div>
    </div>
  );
}

function PlaybackControls({
  player,
  actions,
}: {
  player: PlayerState;
  actions: PlayerActions;
}) {
  return (
    <div className="playback-controls">
      <button
        type="button"
        className={player.isRepeatEnabled ? "is-active" : ""}
        aria-label={player.isRepeatEnabled ? "Turn repeat off" : "Repeat queue"}
        title={player.isRepeatEnabled ? "Turn repeat off" : "Repeat queue"}
        onClick={actions.toggleRepeat}
      >
        <Repeat size={22} />
      </button>
      <button
        type="button"
        className={player.isShuffleEnabled ? "is-active" : ""}
        disabled={player.queue.length < 2}
        aria-label={player.isShuffleEnabled ? "Turn shuffle off" : "Shuffle upcoming queue"}
        title={player.isShuffleEnabled ? "Turn shuffle off" : "Shuffle upcoming queue"}
        onClick={actions.toggleShuffle}
      >
        <Shuffle size={22} />
      </button>
      <button
        type="button"
        aria-label="Restart or previous track"
        title="Restart or previous track"
        onClick={actions.seekBack}
      >
        <SkipBack size={24} />
      </button>
      <button
        type="button"
        className="playback-primary"
        disabled={player.isLoading || player.queue.length === 0}
        aria-label={player.isPlaying ? "Pause" : "Play"}
        title={player.isPlaying ? "Pause" : "Play"}
        onClick={actions.togglePlayPause}
      >
        {player.isLoading ? (
          <LoaderCircle className="spin-icon" size={24} />
        ) : player.isPlaying ? (
          <Pause size={26} />
        ) : (
          <Play size={26} />
        )}
      </button>
      <button
        type="button"
        aria-label="Next track"
        title="Next track"
        onClick={actions.seekNext}
      >
        <SkipForward size={24} />
      </button>
    </div>
  );
}

function QueueList({
  player,
  actions,
  downloads,
}: {
  player: PlayerState;
  actions: PlayerActions;
  downloads: DownloadedTrack[];
}) {
  const indexes = visibleQueueIndexes(
    player.currentIndex,
    player.queue.length,
    player.isRepeatEnabled,
  );
  const localTrackIds = new Set(
    downloads
      .filter((download) => download.state === "complete")
      .map((download) => download.trackId),
  );

  return (
    <section className="queue-list">
      <header>
        <h2>Queue</h2>
        <p>{player.album?.name ?? "Queue"}</p>
      </header>
      <div className="queue-rows">
        {indexes.map((queueIndex, visibleIndex) => {
          const track = player.queue[queueIndex];
          const isCurrent = visibleIndex === 0;
          const isKnownLocal = localTrackIds.has(track.id);
          const knownSource = player.sourceByQueueKey[queueTrackKey(track)] ?? (isKnownLocal ? "local" : null);
          const subtitleParts = [
            isCurrent ? "Now playing" : "Next",
            track.artist,
            formatDuration(track.durationSeconds),
            isCurrent && player.source === "local" ? "Local" : null,
            isCurrent && player.source === "stream" ? "Streaming" : null,
            !isCurrent && knownSource === "local" ? "Local" : null,
            !isCurrent && knownSource === "stream" ? "Streaming" : null,
          ].filter(Boolean);
          return (
            <button
              key={`${track.id}-${queueIndex}-${visibleIndex}`}
              type="button"
              className={`queue-row ${isCurrent ? "is-playing" : ""}`}
              onClick={() => actions.seekToQueueIndex(queueIndex)}
            >
              {isCurrent ? <AudioLines size={20} /> : <Music2 size={20} />}
              <div>
                <strong>{track.title}</strong>
                <span>{subtitleParts.join(" • ")}</span>
              </div>
            </button>
          );
        })}
      </div>
    </section>
  );
}

function visibleQueueIndexes(currentIndex: number, queueLength: number, shouldWrap: boolean) {
  if (queueLength <= 0) {
    return [];
  }

  const visibleCount = shouldWrap ? 10 : Math.min(10, queueLength - currentIndex);
  return Array.from({ length: visibleCount }, (_, offset) =>
    shouldWrap ? (currentIndex + offset) % queueLength : currentIndex + offset,
  );
}

function queueTrackKey(track: TrackModel) {
  return track.queueKey ?? track.id;
}

function sourceMapForTracks(
  tracks: TrackModel[],
  downloads: DownloadedTrack[],
): Record<string, "local" | "stream"> {
  const localTrackIds = new Set(
    downloads
      .filter((download) => download.state === "complete")
      .map((download) => download.trackId),
  );
  const sourceByQueueKey: Record<string, "local" | "stream"> = {};
  for (const track of tracks) {
    if (localTrackIds.has(track.id)) {
      sourceByQueueKey[queueTrackKey(track)] = "local";
    }
  }
  return sourceByQueueKey;
}

function shuffleItems<T>(items: T[]) {
  const shuffled = [...items];
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1));
    [shuffled[index], shuffled[swapIndex]] = [shuffled[swapIndex], shuffled[index]];
  }
  return shuffled;
}

function moveItem<T>(items: T[], fromIndex: number, toIndex: number) {
  if (
    fromIndex === toIndex ||
    fromIndex < 0 ||
    toIndex < 0 ||
    fromIndex >= items.length ||
    toIndex >= items.length
  ) {
    return items;
  }
  const next = [...items];
  const [moved] = next.splice(fromIndex, 1);
  next.splice(toIndex, 0, moved);
  return next;
}

function groupDownloadsByAlbum(downloads: DownloadedTrack[]) {
  const groups = new Map<
    string,
    {
      id: string;
      name: string;
      artist: string;
      coverArtUri?: string | null;
      tracks: DownloadedTrack[];
    }
  >();

  for (const download of downloads) {
    const albumKey = download.albumId ?? download.albumName ?? "Downloads";
    const key = `${download.artist}\u0000${albumKey}`;
    const existing = groups.get(key);
    if (existing) {
      existing.tracks.push(download);
      if (!existing.coverArtUri) {
        existing.coverArtUri = localOrRemoteCover(download);
      }
      continue;
    }

    groups.set(key, {
      id: albumKey,
      name: download.albumName ?? "Downloads",
      artist: download.artist,
      coverArtUri: localOrRemoteCover(download),
      tracks: [download],
    });
  }

  return [...groups.values()]
    .map((group) => ({
      ...group,
      tracks: [...group.tracks].sort((left, right) => {
        const numberCompare = left.trackNumber - right.trackNumber;
        return numberCompare || left.title.localeCompare(right.title);
      }),
    }))
    .sort((left, right) => {
      const artistCompare = left.artist.localeCompare(right.artist);
      return artistCompare || left.name.localeCompare(right.name);
    });
}

function downloadGroupToAlbum(group: {
  id: string;
  name: string;
  artist: string;
  tracks: DownloadedTrack[];
  coverArtUri?: string | null;
}): AlbumModel {
  return {
    id: group.id,
    name: group.name,
    artist: group.artist,
    songCount: group.tracks.length,
    durationSeconds: group.tracks.reduce(
      (total, track) => total + track.durationSeconds,
      0,
    ),
    coverArtUri: group.coverArtUri,
  };
}

function downloadGroupStorageKey(group: { id: string; name: string; artist: string }) {
  return `${group.artist}\u0000${group.id}\u0000${group.name}`;
}

function downloadedAlbumStatus(downloads: DownloadedTrack[]) {
  const completeCount = downloads.filter((download) => download.state === "complete").length;
  const activeCount = downloads.filter(
    (download) => download.state === "downloading" || download.state === "queued",
  ).length;
  const failedCount = downloads.filter((download) => download.state === "failed").length;
  const totalBytes = downloads.reduce((total, download) => total + (download.bytes ?? 0), 0);
  return [
    `${completeCount}/${downloads.length} local`,
    activeCount > 0 ? `${activeCount} active` : null,
    failedCount > 0 ? `${failedCount} failed` : null,
    totalBytes > 0 ? formatBytes(totalBytes) : null,
  ]
    .filter(Boolean)
    .join(" • ");
}

function downloadToTrack(download: DownloadedTrack): TrackModel {
  return {
    id: download.trackId,
    title: download.title,
    artist: download.artist,
    trackNumber: download.trackNumber,
    durationSeconds: download.durationSeconds,
    albumId: download.albumId,
    albumName: download.albumName,
    coverArtUri: localOrRemoteCover(download),
    suffix: download.suffix,
  };
}

function likedToTrack(liked: LikedTrack): TrackModel {
  return {
    id: liked.trackId,
    title: liked.title,
    artist: liked.artist,
    trackNumber: liked.trackNumber,
    durationSeconds: liked.durationSeconds,
    albumId: liked.albumId,
    albumName: liked.albumName,
    coverArtId: liked.coverArtId,
    coverArtUri: liked.coverArtUri,
    suffix: liked.suffix,
  };
}

function playlistTrackToTrack(track: PlaylistTrack): TrackModel {
  return {
    id: track.trackId,
    title: track.title,
    artist: track.artist,
    trackNumber: track.trackNumber,
    durationSeconds: track.durationSeconds,
    queueKey: track.entryId,
    albumId: track.albumId,
    albumName: track.albumName,
    coverArtId: track.coverArtId,
    coverArtUri: track.coverArtUri,
    suffix: track.suffix,
  };
}

function albumFromTrack(track: TrackModel): AlbumModel {
  return {
    id: track.albumId ?? track.id,
    name: track.albumName ?? "Search result",
    artist: track.artist,
    songCount: 1,
    durationSeconds: track.durationSeconds,
    coverArtId: track.coverArtId,
    coverArtUri: track.coverArtUri,
    year: null,
  };
}

function localOrRemoteCover(download: DownloadedTrack) {
  return download.localCoverPath ? convertFileSrc(download.localCoverPath) : download.coverArtUri;
}

function stripFileProtocol(pathOrUri: string) {
  if (pathOrUri.startsWith("file://")) {
    try {
      return decodeURIComponent(new URL(pathOrUri).pathname);
    } catch {
      return pathOrUri.slice("file://".length);
    }
  }
  return pathOrUri;
}

function downloadSubtitle(download: DownloadedTrack) {
  return [
    download.artist,
    download.albumName,
    formatDuration(download.durationSeconds),
    download.state !== "complete" ? download.state : null,
    download.bytes ? formatBytes(download.bytes) : null,
  ]
    .filter(Boolean)
    .join(" • ");
}

function downloadProgress(download: DownloadedTrack) {
  const received = download.receivedBytes ?? 0;
  const total = download.totalBytes ?? 0;
  if (download.state !== "downloading" || total <= 0 || received < 0) {
    return null;
  }
  return Math.min(1, Math.max(0, received / total));
}

function downloadRepairMessage(result: DownloadRepairResult | null) {
  if (!result) {
    return null;
  }
  const parts = [
    result.removedAudioCount > 0
      ? `${result.removedAudioCount} missing audio removed`
      : null,
    result.clearedCoverCount > 0
      ? `${result.clearedCoverCount} missing covers cleared`
      : null,
    result.recoveredCoverCount > 0
      ? `${result.recoveredCoverCount} local covers recovered`
      : null,
    result.downloadedCoverCount > 0
      ? `${result.downloadedCoverCount} covers downloaded`
      : null,
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(" • ") : null;
}

function formatBytes(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return "0 B";
  }
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value >= 10 || unitIndex === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unitIndex]}`;
}

function clampPreviousTrackThreshold(seconds: number) {
  if (!Number.isFinite(seconds)) {
    return defaultPreferences.previousTrackThresholdSeconds;
  }
  return Math.min(15, Math.max(0, Math.round(seconds)));
}

function LikedPage({
  likedTracks,
  player,
  actions,
  downloads,
  activeDownloadTrackIds,
  downloadActions,
  likedActions,
  serverConnectionVersion,
}: {
  likedTracks: LikedTrack[];
  player: PlayerState;
  actions: PlayerActions;
  downloads: DownloadedTrack[];
  activeDownloadTrackIds: Set<string>;
  downloadActions: DownloadActions;
  likedActions: LikedActions;
  serverConnectionVersion: number;
}) {
  const [isOffline, setIsOffline] = useState(false);
  const [hasCheckedConnection, setHasCheckedConnection] = useState(false);
  const [isReordering, setIsReordering] = useState(false);
  const [selectedReorderIndex, setSelectedReorderIndex] = useState<number | null>(null);
  const [draggedReorderIndex, setDraggedReorderIndex] = useState<number | null>(null);
  const [deleteDownloadDialog, setDeleteDownloadDialog] =
    useState<LocalDownloadDeleteDialogState | null>(null);
  const [reorderDraft, setReorderDraft] = useState<LikedTrack[]>([]);
  const [circularActiveIndex, setCircularActiveIndex] = useState(0);
  const downloadsByTrackId = useMemo(
    () => new Map(downloads.map((download) => [download.trackId, download])),
    [downloads],
  );
  const visibleLikedTracks = isReordering ? reorderDraft : likedTracks;
  const tracks = visibleLikedTracks.map(likedToPlayableTrack);
  const currentTrack = player.queue[player.currentIndex] ?? null;
  const playableTracks = isOffline
    ? tracks.filter((track) => downloadsByTrackId.get(track.id)?.state === "complete")
    : tracks;

  const circularItems = visibleLikedTracks.map((liked, index) => {
    const download = downloadsByTrackId.get(liked.trackId) ?? null;
    const isComplete = download?.state === "complete";
    const track = likedToPlayableTrack(liked);
    return {
      coverUri: isComplete && download ? localOrRemoteCover(download) : liked.coverArtUri,
      index,
      isPlaying:
        !isReordering &&
        player.album?.id === "liked" &&
        currentTrack?.id === liked.trackId,
      isUnavailableOffline: isOffline && !isComplete,
      liked,
      track,
    };
  });

  useEffect(() => {
    setCircularActiveIndex((current) => {
      if (visibleLikedTracks.length === 0) {
        return 0;
      }
      return ((current % visibleLikedTracks.length) + visibleLikedTracks.length) % visibleLikedTracks.length;
    });
  }, [visibleLikedTracks.length]);

  useEffect(() => {
    let isCurrent = true;

    async function checkConnection() {
      try {
        await invokeCommand<AlbumModel[]>("get_albums");
        if (isCurrent) {
          setIsOffline(false);
          setHasCheckedConnection(true);
        }
      } catch {
        if (isCurrent) {
          setIsOffline(true);
          setHasCheckedConnection(true);
        }
      }
    }

    checkConnection();

    return () => {
      isCurrent = false;
    };
  }, [serverConnectionVersion]);

  function likedToPlayableTrack(liked: LikedTrack) {
    const download = downloadsByTrackId.get(liked.trackId);
    return download?.state === "complete" ? downloadToTrack(download) : likedToTrack(liked);
  }

  function playLikedFrom(index: number) {
    const selectedTrackId = tracks[index]?.id;
    const selectedIndex = playableTracks.findIndex((track) => track.id === selectedTrackId);
    const safeIndex = selectedIndex >= 0 ? selectedIndex : 0;

    if (playableTracks.length === 0) {
      return;
    }

    const selectedTrack = playableTracks[safeIndex];
    actions.playAlbum(
      {
        id: "liked",
        name: "Liked",
        artist: selectedTrack.artist,
        songCount: playableTracks.length,
        durationSeconds: playableTracks.reduce(
          (total, track) => total + track.durationSeconds,
          0,
        ),
        coverArtUri: selectedTrack.coverArtUri,
      },
      playableTracks,
      safeIndex,
      { skipUnavailable: isOffline },
    );
  }

  function shuffleLiked() {
    if (playableTracks.length < 2) {
      return;
    }
    const shuffled = shuffleItems(playableTracks);
    const first = shuffled[0];
    actions.playAlbum(
      {
        id: "liked",
        name: "Liked",
        artist: first.artist,
        songCount: shuffled.length,
        durationSeconds: shuffled.reduce(
          (total, track) => total + track.durationSeconds,
          0,
        ),
        coverArtUri: first.coverArtUri,
      },
      shuffled,
      0,
      { skipUnavailable: isOffline },
    );
  }

  function startReorder() {
    setReorderDraft([...likedTracks]);
    setSelectedReorderIndex(null);
    setDraggedReorderIndex(null);
    setIsReordering(true);
  }

  function cancelReorder() {
    setIsReordering(false);
    setSelectedReorderIndex(null);
    setDraggedReorderIndex(null);
    setReorderDraft([]);
  }

  function selectOrSwap(index: number) {
    if (!isReordering) {
      playLikedFrom(index);
      return;
    }
    if (selectedReorderIndex === null || selectedReorderIndex === index) {
      setSelectedReorderIndex(selectedReorderIndex === index ? null : index);
      return;
    }
    setReorderDraft((current) => {
      const next = [...current];
      [next[selectedReorderIndex], next[index]] = [next[index], next[selectedReorderIndex]];
      return next;
    });
    setSelectedReorderIndex(null);
  }

  function dropLikedDraft(index: number) {
    const draggedIndex = draggedReorderIndex;
    if (draggedIndex === null) {
      return;
    }
    setReorderDraft((current) => moveItem(current, draggedIndex, index));
    setSelectedReorderIndex(null);
    setDraggedReorderIndex(null);
  }

  async function confirmReorder() {
    const ordered = await likedActions.reorderLikedTracks(
      reorderDraft.map((track) => track.trackId),
    );
    if (player.album?.id === "liked") {
      const nextQueue = (isOffline
        ? ordered.filter((track) => downloadsByTrackId.get(track.trackId)?.state === "complete")
        : ordered
      ).map(likedToPlayableTrack);
      actions.replaceQueueForAlbum("liked", nextQueue);
    }
    cancelReorder();
  }

  async function confirmDeleteDownload() {
    const dialog = deleteDownloadDialog;
    if (!dialog) {
      return;
    }
    await downloadActions.deleteDownload(dialog.trackId);
    setDeleteDownloadDialog(null);
  }

  if (likedTracks.length === 0) {
    return (
      <LibraryMessage
        icon={Heart}
        title="No liked songs yet"
        message="Use the heart button on a track or in Player to add it here."
      />
    );
  }

  return (
    <div className="liked-page">
      <div className="liked-header">
        <div className="liked-title">
          <span className="liked-mark">
            <Heart size={24} fill="currentColor" />
          </span>
          <div>
            <h2>Liked</h2>
            <p>
              {visibleLikedTracks.length} {visibleLikedTracks.length === 1 ? "song" : "songs"} •{" "}
              {formatDuration(
                visibleLikedTracks.reduce(
                  (total, track) => total + track.durationSeconds,
                  0,
                ),
              )}
            </p>
          </div>
        </div>
        <div className="liked-actions deferred-circular-control">
          {isReordering ? (
            <>
              <button type="button" onClick={cancelReorder}>
                <RotateCcw size={18} />
                Cancel
              </button>
              <button type="button" onClick={confirmReorder}>
                <CircleCheck size={18} />
                Confirm order
              </button>
            </>
          ) : (
            <>
              <button type="button" disabled={playableTracks.length === 0} onClick={() => playLikedFrom(0)}>
                <Play size={18} />
                Play
              </button>
              <button
                type="button"
                disabled={playableTracks.length < 2}
                onClick={shuffleLiked}
              >
                <Shuffle size={18} />
                Shuffle
              </button>
              <button type="button" onClick={actions.toggleRepeat}>
                <Repeat size={18} />
                {player.isRepeatEnabled ? "Repeat on" : "Repeat"}
              </button>
              <button type="button" disabled={likedTracks.length < 2} onClick={startReorder}>
                <ListMusic size={18} />
                Reorder
              </button>
            </>
          )}
        </div>
      </div>
      {isOffline && hasCheckedConnection ? (
        <div className="offline-notice">
          <CircleCheck size={18} />
          Navidrome is offline. Liked songs that are not downloaded will be skipped.
        </div>
      ) : null}
      <CircularLikedScroller
        activeIndex={circularActiveIndex}
        items={circularItems}
        onActiveIndexChange={setCircularActiveIndex}
        onPlayIndex={playLikedFrom}
      />
      <div className="track-list liked-list deferred-circular-control">
        {visibleLikedTracks.map((liked, index) => {
          const download = downloadsByTrackId.get(liked.trackId) ?? null;
          const isComplete = download?.state === "complete";
          const isUnavailableOffline = isOffline && !isComplete;
          const isBusy =
            activeDownloadTrackIds.has(liked.trackId) ||
            download?.state === "downloading";
          const coverUri = isComplete && download ? localOrRemoteCover(download) : liked.coverArtUri;
          const isPlaying =
            !isReordering &&
            player.album?.id === "liked" &&
            currentTrack?.id === liked.trackId;
          const isSelected = isReordering && selectedReorderIndex === index;
          const isDragging = isReordering && draggedReorderIndex === index;

          return (
            <div
              className={`track-row liked-row ${isPlaying ? "is-playing" : ""} ${isUnavailableOffline ? "is-unavailable" : ""} ${isSelected ? "is-reorder-selected" : ""} ${isDragging ? "is-reorder-dragging" : ""}`}
              draggable={isReordering}
              key={`${liked.trackId}-${liked.position}`}
              onDragStart={(event) => {
                if (!isReordering) {
                  return;
                }
                event.dataTransfer.effectAllowed = "move";
                setDraggedReorderIndex(index);
              }}
              onDragOver={(event) => {
                if (isReordering) {
                  event.preventDefault();
                  event.dataTransfer.dropEffect = "move";
                }
              }}
              onDrop={(event) => {
                event.preventDefault();
                dropLikedDraft(index);
              }}
              onDragEnd={() => setDraggedReorderIndex(null)}
            >
              <button
                className="track-main"
                type="button"
                disabled={isUnavailableOffline && !isReordering}
                onClick={() => selectOrSwap(index)}
              >
                <AlbumArt imageUri={coverUri} label={`${liked.title} cover art`} />
                <span className="track-copy">
                  <strong>{liked.title}</strong>
                  <span>
                    {liked.artist}
                    {liked.albumName ? ` • ${liked.albumName}` : ""} •{" "}
                    {formatDuration(liked.durationSeconds)}
                    {liked.suffix ? ` • ${liked.suffix.toUpperCase()}` : ""}
                    {isComplete ? " • Local" : ""}
                    {isUnavailableOffline ? " • Not downloaded" : ""}
                  </span>
                </span>
              </button>
              <span className="track-actions">
                {isReordering ? (
                  <span
                    className="reorder-handle"
                    aria-label="Drag to reorder"
                    title="Drag to reorder"
                    data-no-page-swipe
                  >
                    <GripVertical size={22} />
                  </span>
                ) : (
                  <>
                    <button
                      type="button"
                      aria-label={isComplete ? "Delete local download" : "Download track"}
                      title={isComplete ? "Delete local download" : "Download track"}
                      disabled={isBusy}
                      onClick={
                        isComplete
                          ? () =>
                              setDeleteDownloadDialog({
                                trackId: liked.trackId,
                                title: liked.title,
                              })
                          : () => downloadActions.downloadTrack(likedToTrack(liked))
                      }
                    >
                      {isBusy ? (
                        <LoaderCircle className="spin-icon" size={20} />
                      ) : isComplete ? (
                        <Trash2 size={20} />
                      ) : download?.state === "failed" ? (
                        <ShieldAlert size={20} />
                      ) : (
                        <Download size={20} />
                      )}
                    </button>
                    <button
                      type="button"
                      className="is-liked"
                      aria-label="Remove from liked"
                      title="Remove from liked"
                      onClick={() => likedActions.unlikeTrack(liked.trackId)}
                    >
                      <Heart size={20} fill="currentColor" />
                    </button>
                    <Play aria-hidden="true" size={20} />
                  </>
                )}
              </span>
            </div>
          );
        })}
      </div>
      {deleteDownloadDialog ? (
        <LocalDownloadDeleteDialog
          dialog={deleteDownloadDialog}
          isWorking={activeDownloadTrackIds.has(deleteDownloadDialog.trackId)}
          onCancel={() => setDeleteDownloadDialog(null)}
          onConfirm={confirmDeleteDownload}
        />
      ) : null}
    </div>
  );
}

type CircularLikedItem = {
  coverUri?: string | null;
  index: number;
  isPlaying: boolean;
  isUnavailableOffline: boolean;
  liked: LikedTrack;
  track: TrackModel;
};

const circularScrollerSlotCount = 8;
const circularScrollerOpacity = [1, 0.82, 0.7, 0.6, 0.54, 0.5, 0.46, 0.42];
const circularScrollerScale = [1.08, 0.98, 0.92, 0.88, 0.84, 0.8, 0.76, 0.72];
const circularScrollerWheelPixelsPerSlot = 140;
const circularScrollerDragPixelsPerSlot = 112;
const circularScrollerSnapDelayMs = 130;
const circularScrollerMaxWheelStep = 0.72;
const circularScrollerDragThreshold = 5;
const circularScrollerClickTransitionMs = 430;

function circularScrollerPosition(slot: number) {
  if (slot <= -1) {
    return {
      opacity: 0,
      scale: 1.48,
    };
  }
  if (slot >= circularScrollerSlotCount) {
    return {
      opacity: 0,
      scale: 0.64,
    };
  }
  const lowerSlot = Math.floor(slot);
  const upperSlot = lowerSlot + 1;
  const progress = slot - lowerSlot;
  const opacityAt = (position: number) => {
    if (position === -1 || position === circularScrollerSlotCount) {
      return 0;
    }
    return circularScrollerOpacity[position] ?? 0;
  };
  const scaleAt = (position: number) => {
    if (position === -1) {
      return 1.48;
    }
    if (position === circularScrollerSlotCount) {
      return 0.64;
    }
    return circularScrollerScale[position] ?? 0.64;
  };
  const lowerOpacity = opacityAt(lowerSlot);
  const upperOpacity = opacityAt(upperSlot);
  const lowerScale = scaleAt(lowerSlot);
  const upperScale = scaleAt(upperSlot);
  return {
    opacity: lowerOpacity + (upperOpacity - lowerOpacity) * progress,
    scale: lowerScale + (upperScale - lowerScale) * progress,
  };
}

function circularScrollerDistance(slot: number) {
  // The outgoing song stays at spot one while it grows and fades toward the listener.
  if (slot < 0) {
    return 75;
  }
  // Slot nine is one full turn past spot one, so it enters from that same point
  // and follows the coil continuously into spot eight.
  return 75 + slot * 12.5;
}

function CircularLikedScroller({
  activeIndex,
  items,
  onActiveIndexChange,
  onPlayIndex,
}: {
  activeIndex: number;
  items: CircularLikedItem[];
  onActiveIndexChange: (index: number) => void;
  onPlayIndex: (index: number) => void;
}) {
  const [wheelPosition, setWheelPosition] = useState(activeIndex);
  const [isInteracting, setIsInteracting] = useState(false);
  const wheelPositionRef = useRef(activeIndex);
  const dragRef = useRef<{
    clickTarget: {
      itemIndex: number;
      playIndex: number;
      slot: number;
    } | null;
    hasPointerCapture: boolean;
    pointerId: number;
    sideFactor: number;
    startPosition: number;
    startY: number;
    totalMovement: number;
  } | null>(null);
  const suppressClickRef = useRef(false);
  const snapTimerRef = useRef<number | null>(null);
  const clickTimerRef = useRef<number | null>(null);
  const normalizedPosition =
    items.length > 0 ? ((wheelPosition % items.length) + items.length) % items.length : 0;
  const nearestIndex =
    items.length > 0 ? Math.round(normalizedPosition) % items.length : 0;
  const activeItem = items[nearestIndex] ?? items[0];
  const wheelItems = items.flatMap((item, itemIndex) => {
    let slot = itemIndex - normalizedPosition;
    while (slot < -1) {
      slot += items.length;
    }
    while (slot > items.length - 1) {
      slot -= items.length;
    }
    return slot > circularScrollerSlotCount || slot < -1
      ? []
      : [{ item, itemIndex, slot }];
  });

  useEffect(() => {
    if (!dragRef.current) {
      wheelPositionRef.current = activeIndex;
      setWheelPosition(activeIndex);
    }
  }, [activeIndex]);

  useEffect(() => {
    return () => {
      if (snapTimerRef.current !== null) {
        window.clearTimeout(snapTimerRef.current);
      }
      if (clickTimerRef.current !== null) {
        window.clearTimeout(clickTimerRef.current);
      }
    };
  }, []);

  function sideFactorFor(clientX: number, element: HTMLDivElement) {
    const bounds = element.getBoundingClientRect();
    return clientX < bounds.left + bounds.width / 2 ? -1 : 1;
  }

  function snapToNearest(position: number) {
    if (items.length === 0) {
      return;
    }
    const snappedPosition = Math.round(position);
    const snappedIndex = ((snappedPosition % items.length) + items.length) % items.length;
    wheelPositionRef.current = snappedPosition;
    setWheelPosition(snappedPosition);
    setIsInteracting(false);
    onActiveIndexChange(snappedIndex);
  }

  function scheduleSnap(position: number) {
    if (snapTimerRef.current !== null) {
      window.clearTimeout(snapTimerRef.current);
    }
    snapTimerRef.current = window.setTimeout(() => {
      snapTimerRef.current = null;
      snapToNearest(position);
    }, circularScrollerSnapDelayMs);
  }

  function moveToAndPlay(itemIndex: number, playIndex: number, slot: number) {
    if (items.length === 0) {
      return;
    }
    if (snapTimerRef.current !== null) {
      window.clearTimeout(snapTimerRef.current);
      snapTimerRef.current = null;
    }
    if (clickTimerRef.current !== null) {
      window.clearTimeout(clickTimerRef.current);
    }
    const targetPosition = wheelPositionRef.current + slot;
    wheelPositionRef.current = targetPosition;
    setIsInteracting(false);
    setWheelPosition(targetPosition);
    onPlayIndex(playIndex);
    clickTimerRef.current = window.setTimeout(() => {
      clickTimerRef.current = null;
      onActiveIndexChange(itemIndex);
    }, circularScrollerClickTransitionMs);
  }

  function handleWheel(event: ReactWheelEvent<HTMLDivElement>) {
    if (items.length < 2) {
      return;
    }
    if (Math.abs(event.deltaX) >= Math.abs(event.deltaY) || Math.abs(event.deltaY) < 0.25) {
      return;
    }
    event.preventDefault();
    if (clickTimerRef.current !== null) {
      window.clearTimeout(clickTimerRef.current);
      clickTimerRef.current = null;
    }
    const sideFactor = sideFactorFor(event.clientX, event.currentTarget);
    const step = Math.max(
      -circularScrollerMaxWheelStep,
      Math.min(
        circularScrollerMaxWheelStep,
        event.deltaY / circularScrollerWheelPixelsPerSlot,
      ),
    );
    const next = wheelPositionRef.current + step * sideFactor;
    wheelPositionRef.current = next;
    setWheelPosition(next);
    setIsInteracting(true);
    scheduleSnap(next);
  }

  function handlePointerDown(event: ReactPointerEvent<HTMLDivElement>) {
    if (items.length < 2 || event.button !== 0) {
      return;
    }
    if (snapTimerRef.current !== null) {
      window.clearTimeout(snapTimerRef.current);
      snapTimerRef.current = null;
    }
    if (clickTimerRef.current !== null) {
      window.clearTimeout(clickTimerRef.current);
      clickTimerRef.current = null;
    }
    suppressClickRef.current = false;
    const clickedCard =
      event.target instanceof Element
        ? event.target.closest<HTMLElement>(".liked-circular-card")
        : null;
    const itemIndex = Number(clickedCard?.dataset.itemIndex);
    const playIndex = Number(clickedCard?.dataset.playIndex);
    const slot = Number(clickedCard?.dataset.slot);
    dragRef.current = {
      clickTarget:
        Number.isFinite(itemIndex) && Number.isFinite(playIndex) && Number.isFinite(slot)
          ? { itemIndex, playIndex, slot }
          : null,
      hasPointerCapture: false,
      pointerId: event.pointerId,
      sideFactor: sideFactorFor(event.clientX, event.currentTarget),
      startPosition: wheelPositionRef.current,
      startY: event.clientY,
      totalMovement: 0,
    };
    setIsInteracting(true);
  }

  function handlePointerMove(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }
    const movement = event.clientY - drag.startY;
    drag.totalMovement = Math.abs(movement);
    suppressClickRef.current =
      drag.totalMovement >= circularScrollerDragThreshold;
    if (suppressClickRef.current && !drag.hasPointerCapture) {
      event.currentTarget.setPointerCapture(event.pointerId);
      drag.hasPointerCapture = true;
    }
    const next =
      drag.startPosition +
      (movement * drag.sideFactor) / circularScrollerDragPixelsPerSlot;
    wheelPositionRef.current = next;
    setWheelPosition(next);
  }

  function handlePointerUp(event: ReactPointerEvent<HTMLDivElement>) {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }
    dragRef.current = null;
    if (drag.hasPointerCapture) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    if (!suppressClickRef.current && drag.clickTarget) {
      suppressClickRef.current = true;
      if (drag.clickTarget.itemIndex === nearestIndex) {
        onPlayIndex(drag.clickTarget.playIndex);
      } else {
        moveToAndPlay(
          drag.clickTarget.itemIndex,
          drag.clickTarget.playIndex,
          drag.clickTarget.slot,
        );
      }
      return;
    }
    snapToNearest(wheelPositionRef.current);
  }

  if (!activeItem) {
    return null;
  }

  return (
    <div
      className={`liked-circular-scroller ${isInteracting ? "is-interacting" : ""}`}
      aria-label="Liked songs circular scroller"
      onWheel={handleWheel}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
      data-no-page-drag
    >
      <div className="liked-circular-center" aria-live="polite">
        <strong>{activeItem.track.title}</strong>
        <span>{activeItem.track.albumName || "Unknown album"}</span>
        <span>{activeItem.track.artist || "Unknown artist"}</span>
      </div>

      {wheelItems.map(({ item, itemIndex, slot }) => {
        const { opacity, scale } = circularScrollerPosition(slot);
        const isActive = itemIndex === nearestIndex;
        const style = {
          "--circle-distance": `${circularScrollerDistance(slot)}%`,
          "--circle-opacity": opacity,
          "--circle-scale": scale,
        } as CSSProperties;

        return (
          <button
            key={item.liked.trackId}
            className={`liked-circular-card ${isActive ? "is-active" : ""} ${slot <= -1 ? "is-exiting" : ""} ${slot >= circularScrollerSlotCount ? "is-entering" : ""} ${item.isPlaying ? "is-playing" : ""} ${item.isUnavailableOffline ? "is-unavailable" : ""}`}
            style={style}
            type="button"
            aria-label={`${item.track.title} by ${item.track.artist}`}
            data-item-index={itemIndex}
            data-play-index={item.index}
            data-slot={slot}
            onClick={() => {
              if (suppressClickRef.current) {
                suppressClickRef.current = false;
                return;
              }
              if (isActive) {
                onPlayIndex(item.index);
              } else {
                moveToAndPlay(itemIndex, item.index, slot);
              }
            }}
          >
            <AlbumArt imageUri={item.coverUri} label={`${item.track.title} cover art`} />
            <span className="liked-circular-number">{item.index + 1}</span>
          </button>
        );
      })}
    </div>
  );
}

function LocalDownloadDeleteDialog({
  dialog,
  isWorking,
  onCancel,
  onConfirm,
}: {
  dialog: LocalDownloadDeleteDialogState;
  isWorking: boolean;
  onCancel: () => void;
  onConfirm: () => Promise<void>;
}) {
  return (
    <div className="playlist-dialog-backdrop" role="presentation">
      <section
        className="playlist-dialog playlist-delete-dialog"
        aria-modal="true"
        role="dialog"
        aria-label="Delete local download"
      >
        <h2>Delete local download?</h2>
        <p>
          Remove &quot;{dialog.title}&quot; from this device. It will stay in Liked and will not delete anything from Navidrome.
        </p>
        <span className="playlist-dialog-actions">
          <button type="button" disabled={isWorking} onClick={onCancel}>
            Cancel
          </button>
          <button type="button" disabled={isWorking} onClick={onConfirm}>
            {isWorking ? <LoaderCircle className="spin-icon" size={16} /> : <Trash2 size={16} />}
            Delete local file
          </button>
        </span>
      </section>
    </div>
  );
}

function PlaylistAddMenu({
  track,
  playlists,
  tracksByPlaylistId,
  playlistActions,
}: {
  track: TrackModel;
  playlists: PlaylistModel[];
  tracksByPlaylistId: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set());
  const [newPlaylistName, setNewPlaylistName] = useState("");
  const [isWorking, setIsWorking] = useState(false);
  const [duplicateChoiceIds, setDuplicateChoiceIds] = useState<string[] | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const duplicatePlaylistIds = new Set(
    playlists
      .filter((playlist) =>
        (tracksByPlaylistId[playlist.id] ?? []).some(
          (item) => item.trackId === track.id,
        ),
      )
      .map((playlist) => playlist.id),
  );

  async function openMenu() {
    const nextOpen = !isOpen;
    setIsOpen(nextOpen);
    setMessage(null);
    setDuplicateChoiceIds(null);
    if (!nextOpen) {
      return;
    }
    await Promise.all(
      playlists.map((playlist) => playlistActions.loadPlaylistTracks(playlist.id)),
    ).catch((error) => setMessage(`Playlists could not be checked: ${String(error)}`));
  }

  function togglePlaylist(playlistId: string) {
    setSelectedIds((current) => {
      const next = new Set(current);
      if (next.has(playlistId)) {
        next.delete(playlistId);
      } else {
        next.add(playlistId);
      }
      return next;
    });
    setDuplicateChoiceIds(null);
    setMessage(null);
  }

  async function createPlaylistInsideMenu() {
    const trimmed = newPlaylistName.trim();
    if (!trimmed) {
      setMessage("Enter a playlist name.");
      return;
    }
    setIsWorking(true);
    setMessage(null);
    try {
      await playlistActions.createPlaylist(trimmed);
      setNewPlaylistName("");
      setMessage("Playlist created. Select it, then confirm.");
    } catch (error) {
      setMessage(`Playlist could not be created: ${String(error)}`);
    } finally {
      setIsWorking(false);
    }
  }

  async function addSelected(mode: "all" | "skip-existing" = "all") {
    const ids = [...selectedIds];
    if (ids.length === 0) {
      setMessage("Choose at least one playlist.");
      return;
    }
    const duplicates = ids.filter((playlistId) => duplicatePlaylistIds.has(playlistId));
    if (duplicates.length > 0 && mode === "all" && duplicateChoiceIds === null) {
      setDuplicateChoiceIds(duplicates);
      return;
    }
    const idsToAdd = mode === "skip-existing"
      ? ids.filter((playlistId) => !duplicatePlaylistIds.has(playlistId))
      : ids;
    if (idsToAdd.length === 0) {
      setIsOpen(false);
      setSelectedIds(new Set());
      setDuplicateChoiceIds(null);
      return;
    }
    setIsWorking(true);
    setMessage(null);
    try {
      await Promise.all(
        idsToAdd.map((playlistId) =>
          playlistActions.addTrackToPlaylist(playlistId, track),
        ),
      );
      setIsOpen(false);
      setSelectedIds(new Set());
      setDuplicateChoiceIds(null);
    } catch (error) {
      setMessage(`Song could not be added: ${String(error)}`);
    } finally {
      setIsWorking(false);
    }
  }

  const duplicateNames = duplicateChoiceIds
    ?.map((playlistId) => playlists.find((playlist) => playlist.id === playlistId)?.name)
    .filter(Boolean)
    .join(", ");

  return (
    <span className="playlist-add-menu">
      <button
        type="button"
        aria-label="Add to playlist"
        title="Add to playlist"
        onClick={openMenu}
      >
        <ListPlus size={20} />
      </button>
      {isOpen ? (
        <span className="playlist-add-popover">
          <strong>Add to playlists</strong>
          {playlists.length === 0 ? (
            <span className="playlist-add-empty">Create a playlist, then choose it here.</span>
          ) : (
            <span className="playlist-choice-list">
              {playlists.map((playlist) => {
                const isDuplicate = duplicatePlaylistIds.has(playlist.id);
                return (
                  <label key={playlist.id} className="playlist-choice-row">
                    <input
                      type="checkbox"
                      checked={selectedIds.has(playlist.id)}
                      onChange={() => togglePlaylist(playlist.id)}
                    />
                    <ListMusic size={16} />
                    <span>
                      <strong>{playlist.name}</strong>
                      <small>
                        {playlist.trackCount} {playlist.trackCount === 1 ? "song" : "songs"}
                        {isDuplicate ? " • Already added" : ""}
                      </small>
                    </span>
                  </label>
                );
              })}
            </span>
          )}
          <span className="playlist-new-row">
            <input
              value={newPlaylistName}
              placeholder="New playlist"
              onChange={(event) => {
                setNewPlaylistName(event.target.value);
                setMessage(null);
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  createPlaylistInsideMenu();
                }
              }}
            />
            <button type="button" disabled={isWorking} onClick={createPlaylistInsideMenu}>
              <ListPlus size={16} />
              New
            </button>
          </span>
          {duplicateChoiceIds ? (
            <span className="playlist-duplicate-box">
              <span>"{track.title}" is already in {duplicateNames}. Add another copy anyway?</span>
              <span>
                <button type="button" onClick={() => setDuplicateChoiceIds(null)}>
                  Cancel
                </button>
                <button type="button" onClick={() => addSelected("skip-existing")}>
                  Skip existing
                </button>
                <button type="button" onClick={() => addSelected("all")}>
                  Add anyway
                </button>
              </span>
            </span>
          ) : null}
          {message ? <span className="playlist-add-message">{message}</span> : null}
          <span className="playlist-add-actions">
            <button
              type="button"
              onClick={() => {
                setIsOpen(false);
                setDuplicateChoiceIds(null);
              }}
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={selectedIds.size === 0 || isWorking}
              onClick={() => addSelected("all")}
            >
              {isWorking ? <LoaderCircle className="spin-icon" size={16} /> : <ListPlus size={16} />}
              Add
            </button>
          </span>
        </span>
      ) : null}
    </span>
  );
}

function PlaylistsPage({
  playlists,
  tracksByPlaylistId,
  playlistActions,
  player,
  playerActions,
  downloads,
  likedTracks,
  likedActions,
  serverConnectionVersion,
}: {
  playlists: PlaylistModel[];
  tracksByPlaylistId: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
  player: PlayerState;
  playerActions: PlayerActions;
  downloads: DownloadedTrack[];
  likedTracks: LikedTrack[];
  likedActions: LikedActions;
  serverConnectionVersion: number;
}) {
  const [selectedPlaylist, setSelectedPlaylist] = useState<PlaylistModel | null>(null);
  const [nameDialog, setNameDialog] = useState<PlaylistNameDialogState | null>(null);
  const [deleteDialog, setDeleteDialog] = useState<PlaylistDeleteDialogState | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [isWorking, setIsWorking] = useState(false);
  const [isReordering, setIsReordering] = useState(false);
  const [selectedReorderIndex, setSelectedReorderIndex] = useState<number | null>(null);
  const [draggedReorderIndex, setDraggedReorderIndex] = useState<number | null>(null);
  const [reorderDraft, setReorderDraft] = useState<PlaylistTrack[]>([]);
  const [isOffline, setIsOffline] = useState(false);
  const [hasCheckedConnection, setHasCheckedConnection] = useState(false);

  useEffect(() => {
    if (!selectedPlaylist || tracksByPlaylistId[selectedPlaylist.id]) {
      return;
    }
    playlistActions.loadPlaylistTracks(selectedPlaylist.id).catch((error) => {
      setMessage(`Playlist tracks could not be loaded: ${String(error)}`);
    });
  }, [selectedPlaylist?.id]);

  useEffect(() => {
    let isCurrent = true;

    async function checkConnection() {
      try {
        await invokeCommand<AlbumModel[]>("get_albums");
        if (isCurrent) {
          setIsOffline(false);
          setHasCheckedConnection(true);
        }
      } catch {
        if (isCurrent) {
          setIsOffline(true);
          setHasCheckedConnection(true);
        }
      }
    }

    checkConnection();

    return () => {
      isCurrent = false;
    };
  }, [serverConnectionVersion]);

  async function confirmPlaylistName(name: string) {
    const dialog = nameDialog;
    const trimmed = name.trim();
    if (!trimmed) {
      setMessage("Enter a playlist name.");
      return;
    }
    setIsWorking(true);
    setMessage(null);
    try {
      if (dialog?.mode === "rename") {
        await playlistActions.renamePlaylist(dialog.playlistId, trimmed);
        setSelectedPlaylist((current) =>
          current?.id === dialog.playlistId ? { ...current, name: trimmed } : current,
        );
      } else {
        await playlistActions.createPlaylist(trimmed);
      }
      setNameDialog(null);
    } catch (error) {
      setMessage(
        dialog?.mode === "rename"
          ? `Playlist could not be renamed: ${String(error)}`
          : `Playlist could not be created: ${String(error)}`,
      );
    } finally {
      setIsWorking(false);
    }
  }

  async function confirmDeletePlaylist() {
    const dialog = deleteDialog;
    if (!dialog) {
      return;
    }
    setIsWorking(true);
    setMessage(null);
    try {
      await playlistActions.deletePlaylist(dialog.playlistId);
      setDeleteDialog(null);
      resetPlaylistDetail();
    } catch (error) {
      setMessage(`Playlist could not be deleted: ${String(error)}`);
    } finally {
      setIsWorking(false);
    }
  }

  function resetPlaylistDetail() {
    setSelectedPlaylist(null);
    setIsReordering(false);
    setSelectedReorderIndex(null);
    setDraggedReorderIndex(null);
    setReorderDraft([]);
  }

  async function openPlaylist(playlist: PlaylistModel) {
    setSelectedPlaylist(playlist);
    setIsReordering(false);
    setSelectedReorderIndex(null);
    setDraggedReorderIndex(null);
    setReorderDraft([]);
    await playlistActions.loadPlaylistTracks(playlist.id);
  }

  if (selectedPlaylist) {
    const playlist = selectedPlaylist;
    const tracks = tracksByPlaylistId[playlist.id] ?? [];
    const visibleTracks = isReordering ? reorderDraft : tracks;
    const currentTrack = player.queue[player.currentIndex] ?? null;
    const likedTrackIds = new Set(likedTracks.map((track) => track.trackId));
    const downloadsByTrackId = new Map(
      downloads.map((download) => [download.trackId, download]),
    );
    const playableTracks = isOffline
      ? tracks.filter((track) => downloadsByTrackId.get(track.trackId)?.state === "complete")
      : tracks;
    const visiblePlayableTracks = isOffline
      ? visibleTracks.filter((track) => downloadsByTrackId.get(track.trackId)?.state === "complete")
      : visibleTracks;

    function playlistToPlayableTrack(track: PlaylistTrack) {
      const download = downloadsByTrackId.get(track.trackId);
      return download?.state === "complete"
        ? { ...downloadToTrack(download), queueKey: track.entryId }
        : playlistTrackToTrack(track);
    }

    function playFrom(index: number) {
      const selectedEntryId = tracks[index]?.entryId;
      const queueSource = isOffline ? playableTracks : tracks;
      const queue = queueSource.map(playlistToPlayableTrack);
      if (queue.length === 0) {
        return;
      }
      const safeIndex = Math.max(
        0,
        queue.findIndex((track) => track.queueKey === selectedEntryId),
      );
      const selectedTrack = queue[safeIndex];
      playerActions.playAlbum(
        {
          id: playlist.id,
          name: playlist.name,
          artist: "Playlist",
          songCount: queue.length,
          durationSeconds: queue.reduce((total, track) => total + track.durationSeconds, 0),
          coverArtUri: selectedTrack.coverArtUri,
        },
        queue,
        safeIndex,
        { skipUnavailable: isOffline },
      );
    }

    function shufflePlaylist() {
      const queue = shuffleItems(visiblePlayableTracks.map(playlistToPlayableTrack));
      if (queue.length === 0) {
        return;
      }
      playerActions.playAlbum(
        {
          id: playlist.id,
          name: playlist.name,
          artist: "Playlist",
          songCount: queue.length,
          durationSeconds: queue.reduce((total, track) => total + track.durationSeconds, 0),
          coverArtUri: queue[0].coverArtUri,
        },
        queue,
        0,
        { skipUnavailable: isOffline },
      );
    }

    function startReorder() {
      setReorderDraft([...tracks]);
      setSelectedReorderIndex(null);
      setDraggedReorderIndex(null);
      setIsReordering(true);
    }

    function cancelReorder() {
      setIsReordering(false);
      setSelectedReorderIndex(null);
      setDraggedReorderIndex(null);
      setReorderDraft([]);
    }

    function selectOrSwap(index: number) {
      if (!isReordering) {
        playFrom(index);
        return;
      }
      if (selectedReorderIndex === null || selectedReorderIndex === index) {
        setSelectedReorderIndex(selectedReorderIndex === index ? null : index);
        return;
      }
      setReorderDraft((current) => {
        const next = [...current];
        [next[selectedReorderIndex], next[index]] = [next[index], next[selectedReorderIndex]];
        return next;
      });
      setSelectedReorderIndex(null);
    }

    function dropDraft(index: number) {
      const draggedIndex = draggedReorderIndex;
      if (draggedIndex === null) {
        return;
      }
      setReorderDraft((current) => moveItem(current, draggedIndex, index));
      setSelectedReorderIndex(null);
      setDraggedReorderIndex(null);
    }

    async function confirmReorder() {
      const ordered = await playlistActions.reorderPlaylistTracks(
        playlist.id,
        reorderDraft.map((track) => track.entryId),
      );
      if (player.album?.id === playlist.id) {
        const nextQueue = (isOffline
          ? ordered.filter((track) => downloadsByTrackId.get(track.trackId)?.state === "complete")
          : ordered
        ).map(playlistToPlayableTrack);
        playerActions.replaceQueueForAlbum(playlist.id, nextQueue);
      }
      cancelReorder();
    }

    const playlistSummary = [
      `${visibleTracks.length} ${visibleTracks.length === 1 ? "song" : "songs"}`,
      visibleTracks.length > 0
        ? formatDuration(visibleTracks.reduce((total, track) => total + track.durationSeconds, 0))
        : null,
    ].filter(Boolean).join(" • ");

    return (
      <div className="playlist-detail">
        <div className="playlist-detail-header">
          <button type="button" aria-label="Back to playlists" title="Back to playlists" onClick={resetPlaylistDetail}>
            <ArrowLeft size={20} />
          </button>
          <span className="playlist-detail-title">
            <h2>{playlist.name}</h2>
            <p>{playlistSummary}</p>
          </span>
          <button
            className="deferred-circular-control"
            type="button"
            aria-label="Rename playlist"
            title="Rename playlist"
            disabled={isReordering}
            onClick={() =>
              setNameDialog({
                mode: "rename",
                playlistId: playlist.id,
                initialName: playlist.name,
              })
            }
          >
            <Pencil size={20} />
          </button>
          <button
            className="deferred-circular-control"
            type="button"
            aria-label="Delete playlist"
            title="Delete playlist"
            disabled={isReordering}
            onClick={() =>
              setDeleteDialog({
                playlistId: playlist.id,
                playlistName: playlist.name,
              })
            }
          >
            <Trash2 size={20} />
          </button>
        </div>
        <div className="liked-actions deferred-circular-control">
          {isReordering ? (
            <>
              <button type="button" onClick={cancelReorder}>
                <RotateCcw size={18} />
                Cancel
              </button>
              <button type="button" onClick={confirmReorder}>
                <CircleCheck size={18} />
                Confirm order
              </button>
            </>
          ) : (
            <>
              <button type="button" disabled={playableTracks.length === 0} onClick={() => playFrom(0)}>
                <Play size={18} />
                Play
              </button>
              <button type="button" disabled={visiblePlayableTracks.length < 2} onClick={shufflePlaylist}>
                <Shuffle size={18} />
                Shuffle
              </button>
              <button type="button" onClick={playerActions.toggleRepeat}>
                <Repeat size={18} />
                {player.isRepeatEnabled ? "Repeat on" : "Repeat"}
              </button>
              <button type="button" disabled={tracks.length < 2} onClick={startReorder}>
                <ListMusic size={18} />
                Reorder
              </button>
            </>
          )}
        </div>
        {isOffline && hasCheckedConnection ? (
          <div className="offline-notice">
            <CircleCheck size={18} />
            Navidrome is offline. Playlist songs that are not downloaded will be skipped.
          </div>
        ) : null}
        <div className="track-list">
          {visibleTracks.length === 0 ? (
            <LibraryMessage
              icon={ListMusic}
              title="No songs in this playlist"
              message="Use the playlist button on songs to add them here."
            />
          ) : (
            visibleTracks.map((track, index) => {
              const download = downloadsByTrackId.get(track.trackId) ?? null;
              const coverUri =
                download?.state === "complete" && download
                  ? localOrRemoteCover(download)
                  : track.coverArtUri;
              const isPlaying =
                player.album?.id === playlist.id &&
                currentTrack?.queueKey === track.entryId;
              const isSelected = isReordering && selectedReorderIndex === index;
              const isDragging = isReordering && draggedReorderIndex === index;
              const isUnavailableOffline =
                isOffline && download?.state !== "complete";
              return (
                <div
                  className={`track-row liked-row ${isPlaying ? "is-playing" : ""} ${isSelected ? "is-reorder-selected" : ""} ${isUnavailableOffline ? "is-unavailable" : ""} ${isDragging ? "is-reorder-dragging" : ""}`}
                  draggable={isReordering}
                  key={track.entryId}
                  onDragStart={(event) => {
                    if (!isReordering) {
                      return;
                    }
                    event.dataTransfer.effectAllowed = "move";
                    setDraggedReorderIndex(index);
                  }}
                  onDragOver={(event) => {
                    if (isReordering) {
                      event.preventDefault();
                      event.dataTransfer.dropEffect = "move";
                    }
                  }}
                  onDrop={(event) => {
                    event.preventDefault();
                    dropDraft(index);
                  }}
                  onDragEnd={() => setDraggedReorderIndex(null)}
                >
                  <button
                    className="track-main"
                    type="button"
                    disabled={isUnavailableOffline && !isReordering}
                    onClick={() => selectOrSwap(index)}
                  >
                    <AlbumArt imageUri={coverUri} label={`${track.title} cover art`} />
                    <span className="track-copy">
                      <strong>{track.title}</strong>
                      <span>
                        {track.artist}
                        {track.albumName ? ` • ${track.albumName}` : ""} •{" "}
                        {formatDuration(track.durationSeconds)}
                        {track.suffix ? ` • ${track.suffix.toUpperCase()}` : ""}
                        {download?.state === "complete" ? " • Local" : ""}
                        {isUnavailableOffline ? " • Not downloaded" : ""}
                      </span>
                    </span>
                  </button>
                  <span className="track-actions">
                    {isReordering ? (
                      <span
                        className="reorder-handle"
                        aria-label="Drag to reorder"
                        title="Drag to reorder"
                        data-no-page-swipe
                      >
                        <GripVertical size={22} />
                      </span>
                    ) : (
                      <>
                        <button
                          type="button"
                          className={likedTrackIds.has(track.trackId) ? "is-liked" : ""}
                          aria-label={likedTrackIds.has(track.trackId) ? "Remove from liked" : "Add to liked"}
                          title={likedTrackIds.has(track.trackId) ? "Remove from liked" : "Add to liked"}
                          onClick={() => likedActions.toggleLiked(playlistTrackToTrack(track))}
                        >
                          <Heart size={20} fill={likedTrackIds.has(track.trackId) ? "currentColor" : "none"} />
                        </button>
                        <button
                          type="button"
                          aria-label="Remove from playlist"
                          title="Remove from playlist"
                          onClick={() =>
                            playlistActions.removePlaylistEntry(
                              playlist.id,
                              track.entryId,
                            )
                          }
                        >
                          <CircleMinus size={20} />
                        </button>
                        <Play aria-hidden="true" size={20} />
                      </>
                    )}
                  </span>
                </div>
              );
            })
          )}
        </div>
        {nameDialog ? (
          <PlaylistNameDialog
            dialog={nameDialog}
            isWorking={isWorking}
            onCancel={() => setNameDialog(null)}
            onConfirm={confirmPlaylistName}
          />
        ) : null}
        {deleteDialog ? (
          <PlaylistDeleteDialog
            dialog={deleteDialog}
            isWorking={isWorking}
            onCancel={() => setDeleteDialog(null)}
            onConfirm={confirmDeletePlaylist}
          />
        ) : null}
      </div>
    );
  }

  return (
    <div className="playlists-page">
      <div className="playlist-create-row deferred-circular-control">
        <button
          type="button"
          disabled={isWorking}
          onClick={() => setNameDialog({ mode: "create", initialName: "" })}
        >
          {isWorking ? <LoaderCircle className="spin-icon" size={18} /> : <ListPlus size={18} />}
          New playlist
        </button>
      </div>
      {message ? <InlineNotice tone="warning" icon={ShieldAlert} message={message} /> : null}
      <div className="library-list">
        {playlists.length === 0 ? (
          <LibraryMessage
            icon={ListMusic}
            title="No playlists yet"
            message="Create a playlist, then add songs from Library or Player."
          />
        ) : (
          playlists.map((playlist) => (
            <button
              key={playlist.id}
              className={`album-row playlist-row ${player.album?.id === playlist.id ? "is-playing" : ""}`}
              type="button"
              onClick={() => openPlaylist(playlist)}
            >
              <span className="liked-mark">
                <ListMusic size={22} />
              </span>
              <span className="album-row-copy">
                <strong>{playlist.name}</strong>
                <span>
                  {playlist.trackCount} {playlist.trackCount === 1 ? "song" : "songs"}
                </span>
              </span>
              {player.album?.id === playlist.id ? <Music2 size={20} /> : <ChevronRight size={20} />}
            </button>
          ))
        )}
      </div>
      {nameDialog ? (
        <PlaylistNameDialog
          dialog={nameDialog}
          isWorking={isWorking}
          onCancel={() => setNameDialog(null)}
          onConfirm={confirmPlaylistName}
        />
      ) : null}
      {deleteDialog ? (
        <PlaylistDeleteDialog
          dialog={deleteDialog}
          isWorking={isWorking}
          onCancel={() => setDeleteDialog(null)}
          onConfirm={confirmDeletePlaylist}
        />
      ) : null}
    </div>
  );
}

function PlaylistNameDialog({
  dialog,
  isWorking,
  onCancel,
  onConfirm,
}: {
  dialog: PlaylistNameDialogState;
  isWorking: boolean;
  onCancel: () => void;
  onConfirm: (name: string) => Promise<void>;
}) {
  const [name, setName] = useState(dialog.initialName);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const title = dialog.mode === "rename" ? "Rename playlist" : "New playlist";
  const confirmLabel = dialog.mode === "rename" ? "Rename" : "Create";

  useEffect(() => {
    inputRef.current?.focus();
    inputRef.current?.select();
  }, []);

  return (
    <div className="playlist-dialog-backdrop" role="presentation">
      <form
        className="playlist-dialog"
        aria-modal="true"
        role="dialog"
        aria-label={title}
        onSubmit={(event) => {
          event.preventDefault();
          onConfirm(name);
        }}
      >
        <h2>{title}</h2>
        <label>
          <span>Playlist name</span>
          <input
            ref={inputRef}
            value={name}
            disabled={isWorking}
            onChange={(event) => setName(event.target.value)}
          />
        </label>
        <span className="playlist-dialog-actions">
          <button type="button" disabled={isWorking} onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" disabled={isWorking || name.trim().length === 0}>
            {isWorking ? <LoaderCircle className="spin-icon" size={16} /> : null}
            {confirmLabel}
          </button>
        </span>
      </form>
    </div>
  );
}

function PlaylistDeleteDialog({
  dialog,
  isWorking,
  onCancel,
  onConfirm,
}: {
  dialog: PlaylistDeleteDialogState;
  isWorking: boolean;
  onCancel: () => void;
  onConfirm: () => Promise<void>;
}) {
  return (
    <div className="playlist-dialog-backdrop" role="presentation">
      <section
        className="playlist-dialog playlist-delete-dialog"
        aria-modal="true"
        role="dialog"
        aria-label="Delete playlist"
      >
        <h2>Delete playlist?</h2>
        <p>Delete &quot;{dialog.playlistName}&quot; from NekoFM.</p>
        <span className="playlist-dialog-actions">
          <button type="button" disabled={isWorking} onClick={onCancel}>
            Cancel
          </button>
          <button type="button" disabled={isWorking} onClick={onConfirm}>
            {isWorking ? <LoaderCircle className="spin-icon" size={16} /> : <Trash2 size={16} />}
            Delete
          </button>
        </span>
      </section>
    </div>
  );
}

function DownloadsPage({
  player,
  playerActions,
  downloads,
  activeDownloadTrackIds,
  actions,
  likedTracks,
  playlists,
  tracksByPlaylistId,
  playlistActions,
}: {
  player: PlayerState;
  playerActions: PlayerActions;
  downloads: DownloadedTrack[];
  activeDownloadTrackIds: Set<string>;
  actions: DownloadActions;
  likedTracks: LikedTrack[];
  playlists: PlaylistModel[];
  tracksByPlaylistId: Record<string, PlaylistTrack[]>;
  playlistActions: PlaylistActions;
}) {
  const [isExporting, setIsExporting] = useState(false);
  const [isExportChooserOpen, setIsExportChooserOpen] = useState(false);
  const [exportMessage, setExportMessage] = useState<string | null>(null);
  const [exportWarning, setExportWarning] = useState<string | null>(null);
  const [repairMessage, setRepairMessage] = useState<string | null>(null);
  const [deleteAlbumDialog, setDeleteAlbumDialog] =
    useState<LocalAlbumDeleteDialogState | null>(null);
  const [deleteDownloadDialog, setDeleteDownloadDialog] =
    useState<LocalDownloadDeleteDialogState | null>(null);
  const [expandedDownloadGroupKeys, setExpandedDownloadGroupKeys] = useState<Set<string> | null>(null);
  const [exportAlbums, setExportAlbums] = useState<AlbumModel[]>([]);
  const [isExportOnline, setIsExportOnline] = useState(true);
  const [activeExportGroupId, setActiveExportGroupId] = useState<string | null>(null);
  const [exportTracksByGroupId, setExportTracksByGroupId] = useState<Record<string, TrackModel[]>>({});
  const [exportPlaylistTracksById, setExportPlaylistTracksById] = useState<Record<string, PlaylistTrack[]>>({});
  const [loadingExportGroupIds, setLoadingExportGroupIds] = useState<Set<string>>(
    () => new Set(),
  );
  const [selectedExportKeysByGroupId, setSelectedExportKeysByGroupId] = useState<Record<string, Set<string>>>(
    () => ({}),
  );
  const [pendingExportModeChoice, setPendingExportModeChoice] =
    useState<PendingExportModeChoice | null>(null);
  const groups = groupDownloadsByAlbum(downloads);
  const expandedGroupKeys =
    expandedDownloadGroupKeys ?? new Set(groups.map(downloadGroupStorageKey));
  const totalBytes = downloads.reduce((total, download) => total + (download.bytes ?? 0), 0);
  const completeDownloadsByTrackId = new Map(
    downloads
      .filter((download) => download.state === "complete")
      .map((download) => [download.trackId, download]),
  );
  const exportGroups = [
    ...exportAlbums.map((album) => ({
      id: `album:${album.id}`,
      type: "album" as const,
      title: album.name,
      subtitle: `${album.artist} • ${album.songCount} songs`,
      album,
    })),
    ...(likedTracks.length > 0
      ? [
          {
            id: "liked",
            type: "liked" as const,
            title: "Liked",
            subtitle: `${likedTracks.length} songs`,
          },
        ]
      : []),
    ...playlists.map((playlist) => ({
      id: `playlist:${playlist.id}`,
      type: "playlist" as const,
      title: playlist.name,
      subtitle: `${playlist.trackCount} songs`,
      playlist,
    })),
  ];
  const activeExportGroup = exportGroups.find((group) => group.id === activeExportGroupId) ?? null;
  const failedDownloadCount = downloads.filter((download) => download.state === "failed").length;
  const selectedExportCount = Object.values(selectedExportKeysByGroupId).reduce(
    (total, selected) => total + selected.size,
    0,
  );

  async function openExportChooser() {
    setExportWarning(null);
    setExportMessage(null);
    setActiveExportGroupId(null);
    setExportTracksByGroupId({});
    setExportPlaylistTracksById({});
    setSelectedExportKeysByGroupId({});
    setLoadingExportGroupIds(new Set());
    try {
      const loadedPlaylists = await Promise.all(
        playlists.map(async (playlist) => [
          playlist.id,
          await playlistActions.loadPlaylistTracks(playlist.id),
        ] as const),
      );
      setExportPlaylistTracksById(Object.fromEntries(loadedPlaylists));
    } catch (error) {
      setExportWarning(`Playlists could not be loaded: ${String(error)}`);
    }
    try {
      const albums = await invokeCommand<AlbumModel[]>("get_albums");
      setExportAlbums(albums);
      setIsExportOnline(true);
    } catch {
      setExportAlbums(groups.map(downloadGroupToAlbum));
      setIsExportOnline(false);
    }
    setIsExportChooserOpen(true);
  }

  async function recheckDownloads() {
    setRepairMessage(null);
    setExportWarning(null);
    try {
      const result = await actions.reloadDownloads();
      setRepairMessage(downloadRepairMessage(result) ?? "Downloads checked. Nothing needed repair.");
    } catch (error) {
      setExportWarning(`Recheck failed: ${String(error)}`);
    }
  }

  async function confirmDeleteAlbum() {
    const dialog = deleteAlbumDialog;
    if (!dialog) {
      return;
    }
    await actions.deleteDownloads(dialog.trackIds);
    setDeleteAlbumDialog(null);
  }

  async function confirmDeleteDownload() {
    const dialog = deleteDownloadDialog;
    if (!dialog) {
      return;
    }
    await actions.deleteDownload(dialog.trackId);
    setDeleteDownloadDialog(null);
  }

  async function ensureExportGroupTracks(group: (typeof exportGroups)[number]) {
    const existing = exportTracksByGroupId[group.id];
    if (existing) {
      return existing;
    }
    if (loadingExportGroupIds.has(group.id)) {
      return existing ?? [];
    }
    setLoadingExportGroupIds((current) => new Set(current).add(group.id));
    let tracks: TrackModel[] = [];
    try {
      if (group.type === "album") {
        if (isExportOnline) {
          const detail = await invokeCommand<AlbumDetailModel>("get_album", {
            albumId: group.album.id,
          });
          tracks = detail.tracks;
        } else {
          tracks = downloadedTracksForExportAlbum(group.album.id);
        }
      } else if (group.type === "liked") {
        tracks = likedTracks.map(likedToTrack);
      } else {
        tracks = (exportPlaylistTracksById[group.playlist.id] ?? tracksByPlaylistId[group.playlist.id] ?? []).map(playlistTrackToTrack);
      }
    } catch {
      if (group.type === "album") {
        tracks = downloadedTracksForExportAlbum(group.album.id);
      }
    } finally {
      setLoadingExportGroupIds((current) => {
        const next = new Set(current);
        next.delete(group.id);
        return next;
      });
    }
    setExportTracksByGroupId((current) => ({ ...current, [group.id]: tracks }));
    return tracks;
  }

  function downloadedTracksForExportAlbum(albumId: string) {
    return downloads
      .filter((download) => {
        const key = download.albumId ?? download.albumName ?? "downloads";
        return download.state === "complete" && key === albumId;
      })
      .sort((left, right) => left.trackNumber - right.trackNumber || left.title.localeCompare(right.title))
      .map(downloadToTrack);
  }

  async function toggleWholeExportGroup(group: (typeof exportGroups)[number]) {
    const tracks = await ensureExportGroupTracks(group);
    const availableKeys = new Set<string>();
    tracks.forEach((track, index) => {
      if (isExportTrackAvailable(track)) {
        availableKeys.add(exportEntryKey(group, track, index));
      }
    });
    setSelectedExportKeysByGroupId((current) => {
      const selected = current[group.id] ?? new Set<string>();
      const next = { ...current };
      if (availableKeys.size > 0 && selected.size >= availableKeys.size) {
        delete next[group.id];
      } else {
        next[group.id] = availableKeys;
      }
      return next;
    });
  }

  function toggleSingleExportTrack(groupId: string, key: string) {
    setSelectedExportKeysByGroupId((current) => {
      const selected = new Set(current[groupId] ?? []);
      if (!selected.add(key)) {
        selected.delete(key);
      }
      const next = { ...current };
      if (selected.size === 0) {
        delete next[groupId];
      } else {
        next[groupId] = selected;
      }
      return next;
    });
  }

  function isExportTrackAvailable(track: TrackModel) {
    return isExportOnline || completeDownloadsByTrackId.has(track.id);
  }

  function exportRequestForTrack(track: TrackModel): ExportTrackRequest {
    return {
      track,
      localDownload: completeDownloadsByTrackId.get(track.id) ?? null,
    };
  }

  function buildExportSelection() {
    const directTracksById = new Map<string, ExportTrackRequest>();
    const exportPlaylists: ExportPlaylistRequest[] = [];
    for (const group of exportGroups) {
      const selectedKeys = selectedExportKeysByGroupId[group.id];
      if (!selectedKeys || selectedKeys.size === 0) {
        continue;
      }
      const tracks = exportTracksByGroupId[group.id] ?? [];
      const selectedRequests: ExportTrackRequest[] = [];
      tracks.forEach((track, index) => {
        if (!selectedKeys.has(exportEntryKey(group, track, index))) {
          return;
        }
        const request = exportRequestForTrack(track);
        if (group.type === "album") {
          if (!directTracksById.has(track.id)) {
            directTracksById.set(track.id, request);
          }
        } else {
          selectedRequests.push(request);
        }
      });
      if (group.type !== "album" && selectedRequests.length > 0) {
        exportPlaylists.push({
          name: group.title,
          tracks: selectedRequests,
        });
      }
    }
    return {
      directTracks: [...directTracksById.values()],
      playlists: exportPlaylists,
    };
  }

  async function openExportGroup(group: (typeof exportGroups)[number]) {
    setActiveExportGroupId(group.id);
    await ensureExportGroupTracks(group);
  }

  function exportEntryKey(group: (typeof exportGroups)[number], track: TrackModel, index: number) {
    return group.type === "playlist" ? `${track.id}:${index}` : track.id;
  }

  function toggleDownloadGroup(groupKey: string) {
    setExpandedDownloadGroupKeys((current) => {
      const next = new Set(current ?? groups.map(downloadGroupStorageKey));
      if (!next.delete(groupKey)) {
        next.add(groupKey);
      }
      return next;
    });
  }

  const exportModal = isExportChooserOpen ? (
    <div className="export-modal-backdrop" role="presentation">
      <section className="export-modal" aria-modal="true" role="dialog" aria-label="Export music">
        <header>
          {activeExportGroup ? (
            <button
              type="button"
              aria-label="Back to export groups"
              title="Back to export groups"
              onClick={() => setActiveExportGroupId(null)}
            >
              <ArrowLeft size={18} />
            </button>
          ) : null}
          <h2>{activeExportGroup?.title ?? "Export"}</h2>
          <button
            type="button"
            aria-label="Close export"
            title="Close export"
            onClick={() => setIsExportChooserOpen(false)}
          >
            <X size={18} />
          </button>
        </header>
        <div className="export-modal-body">
          {activeExportGroup ? (
            <section>
              {loadingExportGroupIds.has(activeExportGroup.id) &&
              !(exportTracksByGroupId[activeExportGroup.id]?.length > 0) ? (
                <div className="export-empty">
                  <LoaderCircle className="spin-icon" size={22} />
                </div>
              ) : (exportTracksByGroupId[activeExportGroup.id] ?? []).length === 0 ? (
                <div className="export-empty">No songs found.</div>
              ) : (
                (exportTracksByGroupId[activeExportGroup.id] ?? []).map((track, index) => {
                  const key = exportEntryKey(activeExportGroup, track, index);
                  const selected = selectedExportKeysByGroupId[activeExportGroup.id]?.has(key) ?? false;
                  const isAvailable = isExportTrackAvailable(track);
                  const isLocal = completeDownloadsByTrackId.has(track.id);
                  return (
                    <label
                      className={`export-choice-row ${isAvailable ? "" : "is-unavailable"}`}
                      key={key}
                    >
                      <input
                        type="checkbox"
                        checked={selected}
                        disabled={!isAvailable}
                        onChange={() => toggleSingleExportTrack(activeExportGroup.id, key)}
                      />
                      <span>
                        <strong>{track.title}</strong>
                        <small>
                          {track.artist} •{" "}
                          {isLocal
                            ? "Local"
                            : isExportOnline
                              ? "Will download to export"
                              : "Not downloaded"}
                        </small>
                      </span>
                    </label>
                  );
                })
              )}
            </section>
          ) : (
            <section>
              <h3>{isExportOnline ? "Albums, liked, and playlists" : "Downloaded albums, liked, and playlists"}</h3>
              {exportGroups.length === 0 ? (
                <div className="export-empty">No albums, playlists, or liked songs to export yet.</div>
              ) : (
                exportGroups.map((group) => {
                  const knownTracks = exportTracksByGroupId[group.id] ?? [];
                  const selectedCount = selectedExportKeysByGroupId[group.id]?.size ?? 0;
                  const availableCount = knownTracks.filter(isExportTrackAvailable).length;
                  const isLoading = loadingExportGroupIds.has(group.id);
                  const isChecked = availableCount > 0 && selectedCount >= availableCount;
                  return (
                    <div className="export-choice-row export-group-row" key={group.id}>
                      <input
                        type="checkbox"
                        checked={isChecked}
                        disabled={isLoading}
                        onChange={() => toggleWholeExportGroup(group)}
                      />
                      <button type="button" onClick={() => openExportGroup(group)}>
                        <span className="liked-mark">
                          {group.type === "liked" ? (
                            <Heart size={18} fill="currentColor" />
                          ) : group.type === "playlist" ? (
                            <ListMusic size={18} />
                          ) : (
                            <Album size={18} />
                          )}
                        </span>
                        <span>
                          <strong>{group.title}</strong>
                          <small>
                            {selectedCount > 0 ? `${selectedCount} selected • ` : ""}
                            {group.subtitle}
                          </small>
                        </span>
                        {isLoading ? <LoaderCircle className="spin-icon" size={18} /> : <ChevronRight size={16} />}
                      </button>
                    </div>
                  );
                })
              )}
            </section>
          )}
        </div>
        <footer>
          <button type="button" onClick={() => setIsExportChooserOpen(false)}>
            Cancel
          </button>
          <button type="button" disabled={isExporting || selectedExportCount === 0} onClick={exportSelectedMusic}>
            {isExporting ? <LoaderCircle className="spin-icon" size={18} /> : <FolderOpen size={18} />}
            {selectedExportCount > 0 ? `Export ${selectedExportCount}` : "Export selected"}
          </button>
        </footer>
      </section>
    </div>
  ) : null;

  const exportModeDialog = pendingExportModeChoice ? (
    <div className="playlist-dialog-backdrop" role="presentation">
      <section
        className="playlist-dialog export-mode-dialog"
        aria-modal="true"
        role="dialog"
        aria-label="Existing export found"
      >
        <h2>Existing NekoFM export found</h2>
        <p>
          Update keeps extra old files. Clean removes files from the previous
          NekoFM export manifest before copying the current export.
        </p>
        <span className="playlist-dialog-actions">
          <button
            type="button"
            disabled={isExporting}
            onClick={() => setPendingExportModeChoice(null)}
          >
            Cancel
          </button>
          <button
            className="export-mode-update"
            type="button"
            disabled={isExporting}
            onClick={() => runExportSelection(pendingExportModeChoice, false)}
          >
            {isExporting ? <LoaderCircle className="spin-icon" size={16} /> : <RefreshCw size={16} />}
            Update export
          </button>
          <button
            className="export-mode-clean"
            type="button"
            disabled={isExporting}
            onClick={() => runExportSelection(pendingExportModeChoice, true)}
          >
            {isExporting ? <LoaderCircle className="spin-icon" size={16} /> : <Trash2 size={16} />}
            Clean export
          </button>
        </span>
      </section>
    </div>
  ) : null;

  async function runExportSelection(
    pendingExport: PendingExportModeChoice,
    cleanFirst: boolean,
  ) {
    setIsExporting(true);
    setExportMessage(null);
    setExportWarning(null);
    try {
      const result = await invokeCommand<MusicExportResult>("export_music_selection", {
        targetFolder: pendingExport.targetFolder,
        cleanFirst,
        directTracks: pendingExport.directTracks,
        playlists: pendingExport.playlists,
      });
      setExportMessage(result.message);
      setPendingExportModeChoice(null);
      setIsExportChooserOpen(false);
    } catch (error) {
      setExportWarning(`Export failed: ${String(error)}`);
    } finally {
      setIsExporting(false);
    }
  }

  async function exportSelectedMusic() {
    setExportMessage(null);
    setExportWarning(null);
    try {
      const selection = buildExportSelection();
      if (selection.directTracks.length === 0 && selection.playlists.length === 0) {
        setExportWarning("Choose at least one album, playlist, liked song, or individual song.");
        return;
      }
      const targetFolder = await invokeCommand<string | null>("choose_export_folder");
      if (!targetFolder) {
        return;
      }
      setIsExporting(true);
      let cleanFirst = false;
      const hasExisting = await invokeCommand<boolean>("has_existing_export", {
        targetFolder,
      });
      if (hasExisting) {
        setPendingExportModeChoice({
          targetFolder,
          directTracks: selection.directTracks,
          playlists: selection.playlists,
        });
        return;
      }
      await runExportSelection({
        targetFolder,
        directTracks: selection.directTracks,
        playlists: selection.playlists,
      }, cleanFirst);
    } catch (error) {
      setExportWarning(`Export failed: ${String(error)}`);
    } finally {
      setIsExporting(false);
    }
  }

  if (downloads.length === 0) {
    return (
      <div className="downloads-page">
        <div className="downloads-empty">
          <Download size={48} />
          <h2>No downloads yet</h2>
          <p>Download tracks from Library to play them offline, or export from your server directly.</p>
          <div className="downloads-empty-actions">
            <button type="button" disabled={isExporting} onClick={openExportChooser}>
              {isExporting ? <LoaderCircle className="spin-icon" size={18} /> : <FolderOpen size={18} />}
              {isExporting ? "Exporting..." : "Export"}
            </button>
            <button type="button" onClick={actions.openDownloadFolder}>
              <FolderOpen size={18} />
              Open folder
            </button>
            <button type="button" onClick={recheckDownloads}>
              <RefreshCw size={18} />
              Recheck
            </button>
          </div>
          {exportMessage ? (
            <InlineNotice tone="success" icon={CircleCheck} message={exportMessage} />
          ) : null}
          {exportWarning ? (
            <InlineNotice tone="warning" icon={ShieldAlert} message={exportWarning} />
          ) : null}
          {repairMessage ? (
            <InlineNotice tone="success" icon={CircleCheck} message={repairMessage} />
          ) : null}
        </div>
        {exportModal}
        {exportModeDialog}
      </div>
    );
  }

  return (
    <div className="downloads-page">
      <div className="downloads-toolbar">
        <div>
          <strong>{groups.length} albums</strong>
          <span>{formatBytes(totalBytes)} local</span>
        </div>
        <span className="downloads-toolbar-actions">
          {failedDownloadCount > 0 ? (
            <button type="button" onClick={actions.retryFailedDownloads}>
              <RotateCcw size={18} />
              Retry failed ({failedDownloadCount})
            </button>
          ) : null}
          <button type="button" disabled={isExporting} onClick={openExportChooser}>
            {isExporting ? <LoaderCircle className="spin-icon" size={18} /> : <FolderOpen size={18} />}
            {isExporting ? "Exporting..." : "Export local"}
          </button>
          <button type="button" onClick={actions.openDownloadFolder}>
            <FolderOpen size={18} />
            Open folder
          </button>
          <button type="button" onClick={recheckDownloads}>
            <RefreshCw size={18} />
            Recheck
          </button>
        </span>
      </div>
      {exportMessage ? (
        <InlineNotice tone="success" icon={CircleCheck} message={exportMessage} />
      ) : null}
      {exportWarning ? (
        <InlineNotice tone="warning" icon={ShieldAlert} message={exportWarning} />
      ) : null}
      {repairMessage ? (
        <InlineNotice tone="success" icon={CircleCheck} message={repairMessage} />
      ) : null}
      {exportModal}
      {exportModeDialog}
      <div className="download-groups">
        {groups.map((group) => {
          const groupKey = downloadGroupStorageKey(group);
          const isExpanded = expandedGroupKeys.has(groupKey);
          const completeDownloads = group.tracks.filter((download) => download.state === "complete");
          const groupTracks = completeDownloads.map(downloadToTrack);
          const isGroupPlaying = player.album?.id === group.id;
          return (
            <section className={`download-group ${isGroupPlaying ? "is-playing" : ""}`} key={groupKey}>
              <header
                role="button"
                tabIndex={0}
                aria-expanded={isExpanded}
                onClick={() => toggleDownloadGroup(groupKey)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    toggleDownloadGroup(groupKey);
                  }
                }}
              >
                <AlbumArt imageUri={group.coverArtUri} label={group.name} />
                <div>
                  <h2>{group.name}</h2>
                  <p>
                    {group.artist} • {downloadedAlbumStatus(group.tracks)}
                  </p>
                </div>
                <span className="download-group-actions">
                  <button
                    type="button"
                    disabled={groupTracks.length === 0}
                    aria-label="Play downloaded album"
                    title="Play downloaded album"
                    onClick={(event) => {
                      event.stopPropagation();
                      playerActions.playAlbum(downloadGroupToAlbum(group), groupTracks, 0);
                    }}
                  >
                    {isGroupPlaying ? <Music2 size={20} /> : <Play size={20} />}
                  </button>
                  <button
                    type="button"
                    aria-label="Delete local album"
                    title="Delete local album"
                    onClick={(event) => {
                      event.stopPropagation();
                      setDeleteAlbumDialog({
                        albumName: group.name,
                        trackIds: group.tracks.map((download) => download.trackId),
                      });
                    }}
                  >
                    <Trash2 size={20} />
                  </button>
                  <ChevronRight
                    aria-hidden="true"
                    className={isExpanded ? "is-expanded" : undefined}
                    size={18}
                  />
                </span>
              </header>
              {isExpanded ? (
              <div>
                {group.tracks.map((download) => {
                  const isBusy =
                    activeDownloadTrackIds.has(download.trackId) ||
                    download.state === "downloading";
                  const trackIndex = groupTracks.findIndex((track) => track.id === download.trackId);
                  const isTrackPlaying =
                    isGroupPlaying &&
                    player.queue[player.currentIndex]?.id === download.trackId;
                  const progress = downloadProgress(download);
                  const playDownload = () => {
                    if (trackIndex >= 0) {
                      playerActions.playAlbum(downloadGroupToAlbum(group), groupTracks, trackIndex);
                    }
                  };
                  return (
                    <div
                      className={`download-row ${isTrackPlaying ? "is-playing" : ""}`}
                      key={download.trackId}
                      role={download.state === "complete" ? "button" : undefined}
                      tabIndex={download.state === "complete" ? 0 : undefined}
                      onClick={download.state === "complete" ? playDownload : undefined}
                      onKeyDown={(event) => {
                        if (
                          download.state === "complete" &&
                          (event.key === "Enter" || event.key === " ")
                        ) {
                          event.preventDefault();
                          playDownload();
                        }
                      }}
                    >
                      <span className="track-number">
                        {download.trackNumber || ""}
                      </span>
                      <div>
                        <strong>{download.title}</strong>
                        <span>{downloadSubtitle(download)}</span>
                        {download.errorMessage ? (
                          <small className="download-row-error">{download.errorMessage}</small>
                        ) : null}
                        {progress != null ? (
                          <span className="download-row-progress">
                            <span style={{ width: `${Math.round(progress * 100)}%` }} />
                          </span>
                        ) : null}
                      </div>
                      <span className="download-row-actions">
                        {download.state === "failed" ? (
                          <button
                            type="button"
                            disabled={isBusy}
                            aria-label="Retry download"
                            title="Retry download"
                            onClick={(event) => {
                              event.stopPropagation();
                              actions.downloadTrack(downloadToTrack(download));
                            }}
                          >
                            <RefreshCw size={20} />
                          </button>
                        ) : null}
                        {download.state === "complete" ? (
                          <button
                            type="button"
                            aria-label="Play downloaded track"
                            title="Play downloaded track"
                            onClick={(event) => {
                              event.stopPropagation();
                              playDownload();
                            }}
                          >
                            {isTrackPlaying ? <Music2 size={20} /> : <Play size={20} />}
                          </button>
                        ) : null}
                        <button
                          type="button"
                          disabled={isBusy}
                          aria-label="Delete local download"
                          title="Delete local download"
                          onClick={(event) => {
                            event.stopPropagation();
                            setDeleteDownloadDialog({
                              trackId: download.trackId,
                              title: download.title,
                            });
                          }}
                        >
                          {isBusy ? (
                            <LoaderCircle className="spin-icon" size={20} />
                          ) : (
                            <Trash2 size={20} />
                          )}
                        </button>
                      </span>
                    </div>
                  );
                })}
              </div>
              ) : null}
            </section>
          );
        })}
      </div>
      {deleteAlbumDialog ? (
        <LocalAlbumDeleteDialog
          dialog={deleteAlbumDialog}
          isWorking={deleteAlbumDialog.trackIds.some((trackId) =>
            activeDownloadTrackIds.has(trackId),
          )}
          onCancel={() => setDeleteAlbumDialog(null)}
          onConfirm={confirmDeleteAlbum}
        />
      ) : null}
      {deleteDownloadDialog ? (
        <LocalDownloadDeleteDialog
          dialog={deleteDownloadDialog}
          isWorking={activeDownloadTrackIds.has(deleteDownloadDialog.trackId)}
          onCancel={() => setDeleteDownloadDialog(null)}
          onConfirm={confirmDeleteDownload}
        />
      ) : null}
    </div>
  );
}

function SettingsPlaceholder({
  preferences,
  preferenceActions,
  homeDestinationId,
  onHomeDestinationChange,
  onDownloadsChanged,
  onServerProfileChanged,
}: {
  preferences: AppPreferences;
  preferenceActions: PreferenceActions;
  homeDestinationId: DestinationId;
  onHomeDestinationChange: (id: DestinationId) => void;
  onDownloadsChanged: () => Promise<void>;
  onServerProfileChanged: () => void;
}) {
  const [serverUrl, setServerUrl] = useState("http://127.0.0.1:4533");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [rememberPassword, setRememberPassword] = useState(true);
  const [isPasswordVisible, setIsPasswordVisible] = useState(false);
  const [isLoadingProfile, setIsLoadingProfile] = useState(true);
  const [isTestingConnection, setIsTestingConnection] = useState(false);
  const [isScanningServer, setIsScanningServer] = useState(false);
  const [isSavingThreshold, setIsSavingThreshold] = useState(false);
  const [isSavingDownloadFolder, setIsSavingDownloadFolder] = useState(false);
  const [downloadFolder, setDownloadFolder] = useState<DownloadFolder>({
    path: "",
    isCustom: false,
  });
  const [connectionStep, setConnectionStep] = useState<string | null>(null);
  const [connectionResult, setConnectionResult] =
    useState<ServerConnectionResult | null>(null);
  const [scanMessage, setScanMessage] = useState<string | null>(null);
  const [scanWarning, setScanWarning] = useState<string | null>(null);
  const [playbackWarning, setPlaybackWarning] = useState<string | null>(null);
  const [downloadFolderMessage, setDownloadFolderMessage] = useState<string | null>(null);
  const [downloadFolderWarning, setDownloadFolderWarning] = useState<string | null>(null);
  const [moveDownloadsDialog, setMoveDownloadsDialog] =
    useState<MoveDownloadsDialogState | null>(null);
  const moveDownloadsDialogRef = useRef<MoveDownloadsDialogState | null>(null);

  const showHttpWarning = usesPublicHttp(serverUrl);

  useEffect(() => {
    moveDownloadsDialogRef.current = moveDownloadsDialog;
  }, [moveDownloadsDialog]);

  useEffect(() => {
    return () => {
      const dialog = moveDownloadsDialogRef.current;
      if (dialog) {
        dialog.resolve("cancel");
        moveDownloadsDialogRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    let isCurrent = true;

    async function loadProfile() {
      try {
        const savedProfile = await invokeCommand<SavedServerProfile | null>(
          "load_server_profile",
        );
        if (!isCurrent || !savedProfile) {
          return;
        }

        setServerUrl(savedProfile.serverUrl);
        setUsername(savedProfile.username);
        setPassword(savedProfile.password);
        setRememberPassword(savedProfile.rememberPassword);
      } catch (error) {
        if (isCurrent) {
          setConnectionResult({
            isSuccess: false,
            message: `Saved profile could not be loaded: ${String(error)}`,
          });
        }
      } finally {
        if (isCurrent) {
          setIsLoadingProfile(false);
        }
      }
    }

    loadProfile();

    return () => {
      isCurrent = false;
    };
  }, []);

  useEffect(() => {
    let isCurrent = true;

    async function loadDownloadFolder() {
      try {
        const folder = await invokeCommand<DownloadFolder>("load_download_folder");
        if (isCurrent) {
          setDownloadFolder(folder);
        }
      } catch (error) {
        if (isCurrent) {
          setDownloadFolderWarning(`Download folder could not be loaded: ${String(error)}`);
        }
      }
    }

    loadDownloadFolder();

    return () => {
      isCurrent = false;
    };
  }, []);

  async function testConnection() {
    const validationMessage = validateServerProfile(serverUrl, username, password);
    if (validationMessage) {
      setConnectionResult({
        isSuccess: false,
        message: validationMessage,
      });
      return;
    }

    setIsTestingConnection(true);
    setConnectionStep("Preparing secure Subsonic auth...");
    setConnectionResult(null);
    setScanMessage(null);

    try {
      setConnectionStep("Contacting server...");
      const result = await invokeCommand<ServerConnectionResult>(
        "test_server_connection",
        {
          profile: { serverUrl, username, password, rememberPassword },
        },
      );
      setConnectionResult(result);
      if (result.isSuccess) {
        onServerProfileChanged();
      }
    } catch (error) {
      setConnectionResult({
        isSuccess: false,
        message: `Connection failed: ${String(error)}`,
      });
    } finally {
      setConnectionStep(null);
      setIsTestingConnection(false);
    }
  }

  async function scanServerLibrary() {
    const validationMessage = validateServerProfile(serverUrl, username, password);
    if (validationMessage) {
      setScanWarning(validationMessage);
      return;
    }

    setIsScanningServer(true);
    setScanMessage("Asking server to scan the music folder...");
    setScanWarning(null);
    try {
      const result = await invokeCommand<ServerScanResult>("start_server_scan_with_profile", {
        profile: { serverUrl, username, password, rememberPassword },
      });
      setScanMessage(result.message);
      onServerProfileChanged();
    } catch (error) {
      setScanMessage(null);
      setScanWarning(`Server scan failed: ${String(error)}`);
    } finally {
      setIsScanningServer(false);
    }
  }

  async function updatePreviousTrackThreshold(value: number) {
    const safeValue = clampPreviousTrackThreshold(value);
    setIsSavingThreshold(true);
    setPlaybackWarning(null);
    try {
      await preferenceActions.setPreviousTrackThreshold(safeValue);
    } catch (error) {
      setPlaybackWarning(`Playback preference could not be saved: ${String(error)}`);
    } finally {
      setIsSavingThreshold(false);
    }
  }

  async function chooseDownloadFolder() {
    const selected = await invokeCommand<string | null>("choose_download_folder");
    if (!selected) {
      return;
    }
    setDownloadFolder({ path: selected, isCustom: true });
    setDownloadFolderMessage(null);
    setDownloadFolderWarning(null);
  }

  async function saveDownloadFolder() {
    if (!downloadFolder.path.trim()) {
      setDownloadFolderWarning("Choose a folder before saving.");
      return;
    }
    setIsSavingDownloadFolder(true);
    setDownloadFolderMessage(null);
    setDownloadFolderWarning(null);
    try {
      const moveResult = await maybeMoveExistingDownloads(downloadFolder.path);
      if (moveResult === "cancelled") {
        return;
      }
      const saved = await invokeCommand<DownloadFolder>("save_download_folder", {
        path: downloadFolder.path,
      });
      setDownloadFolder(saved);
      await onDownloadsChanged();
      setDownloadFolderMessage(downloadFolderSavedMessage(moveResult, "New downloads will use this folder."));
    } catch (error) {
      setDownloadFolderWarning(`Download folder could not be saved: ${String(error)}`);
    } finally {
      setIsSavingDownloadFolder(false);
    }
  }

  async function resetDownloadFolder() {
    setIsSavingDownloadFolder(true);
    setDownloadFolderMessage(null);
    setDownloadFolderWarning(null);
    try {
      const moveResult = await maybeMoveExistingDownloads(null);
      if (moveResult === "cancelled") {
        return;
      }
      const saved = await invokeCommand<DownloadFolder>("reset_download_folder");
      setDownloadFolder(saved);
      await onDownloadsChanged();
      setDownloadFolderMessage(downloadFolderSavedMessage(moveResult, "New downloads will use the default folder."));
    } catch (error) {
      setDownloadFolderWarning(`Default folder could not be restored: ${String(error)}`);
    } finally {
      setIsSavingDownloadFolder(false);
    }
  }

  async function maybeMoveExistingDownloads(
    targetPath: string | null,
  ): Promise<DownloadFolderMoveResult | null | "cancelled"> {
    const currentFolder = await invokeCommand<DownloadFolder>("load_download_folder");
    if (targetPath && sameDownloadPath(currentFolder.path, targetPath)) {
      return null;
    }
    if (!targetPath && !currentFolder.isCustom) {
      return null;
    }

    const currentDownloads = await invokeCommand<DownloadedTrack[]>("load_downloads");
    const hasActiveDownloads = currentDownloads.some((download) =>
      download.state === "downloading" || download.state === "queued"
    );
    if (hasActiveDownloads) {
      setDownloadFolderWarning("Wait for current downloads to finish before moving the folder.");
      return "cancelled";
    }

    const completeCount = currentDownloads.filter((download) => download.state === "complete").length;
    if (completeCount === 0) {
      return null;
    }

    const moveChoice = await askMoveExistingDownloads(completeCount);
    if (moveChoice === "cancel") {
      return "cancelled";
    }
    if (moveChoice === "new-only") {
      return null;
    }

    if (targetPath) {
      return invokeCommand<DownloadFolderMoveResult>("move_downloads_to_folder", {
        path: targetPath,
      });
    }
    return invokeCommand<DownloadFolderMoveResult>("move_downloads_to_default_folder");
  }

  function askMoveExistingDownloads(
    completeCount: number,
  ): Promise<"move" | "new-only" | "cancel"> {
    return new Promise((resolve) => {
      const pendingDialog = moveDownloadsDialogRef.current;
      if (pendingDialog) {
        pendingDialog.resolve("cancel");
      }

      const nextDialog = { completeCount, resolve };
      moveDownloadsDialogRef.current = nextDialog;
      setMoveDownloadsDialog(nextDialog);
    });
  }

  function chooseMoveDownloads(choice: "move" | "new-only" | "cancel") {
    const dialog = moveDownloadsDialogRef.current;
    if (!dialog) {
      return;
    }
    moveDownloadsDialogRef.current = null;
    dialog.resolve(choice);
    setMoveDownloadsDialog(null);
  }

  function downloadFolderSavedMessage(
    moveResult: DownloadFolderMoveResult | null,
    fallback: string,
  ) {
    if (!moveResult) {
      return fallback;
    }
    const parts = [
      `${moveResult.movedAudioCount} tracks moved`,
      `${moveResult.movedCoverCount} covers moved`,
    ];
    if (moveResult.skippedCount > 0) {
      parts.push(`${moveResult.skippedCount} skipped`);
    }
    return `Download folder saved. ${parts.join(" • ")}.`;
  }

  async function openDownloadFolder() {
    setDownloadFolderMessage(null);
    setDownloadFolderWarning(null);
    try {
      await invokeCommand<void>("open_download_folder");
    } catch (error) {
      setDownloadFolderWarning(`Could not open download folder: ${String(error)}`);
    }
  }

  return (
    <div className="settings-placeholder">
      <section className="settings-home-panel">
        <h2>Home page</h2>
        <p>Choose where NekoFM opens first.</p>
        <div className="home-page-selector" role="radiogroup" aria-label="Home page">
          {primaryDestinations.map((destination) => (
            <button
              key={destination.id}
              type="button"
              className={homeDestinationId === destination.id ? "is-selected" : ""}
              role="radio"
              aria-checked={homeDestinationId === destination.id}
              onClick={() => onHomeDestinationChange(destination.id)}
            >
              {destination.label}
            </button>
          ))}
        </div>
      </section>
      <h2>Server connection</h2>
      <p>Connect directly to your own Navidrome or Subsonic-compatible server.</p>
      {isLoadingProfile ? (
        <InlineNotice
          tone="success"
          icon={LoaderCircle}
          message="Loading saved profile..."
        />
      ) : null}
      <label>
        <span>Server URL</span>
        <input
          value={serverUrl}
          inputMode="url"
          onChange={(event) => {
            setServerUrl(event.target.value);
            setConnectionResult(null);
          }}
        />
      </label>
      {showHttpWarning ? (
        <InlineNotice
          tone="warning"
          icon={ShieldAlert}
          message="Public HTTP is not encrypted. Use HTTPS for remote servers."
        />
      ) : null}
      <label>
        <span>Username</span>
        <input
          value={username}
          autoComplete="username"
          onChange={(event) => {
            setUsername(event.target.value);
            setConnectionResult(null);
          }}
        />
      </label>
      <label>
        <span>Password</span>
        <span className="password-field">
          <input
            value={password}
            type={isPasswordVisible ? "text" : "password"}
            autoComplete="current-password"
            onChange={(event) => {
              setPassword(event.target.value);
              setConnectionResult(null);
            }}
          />
          <button
            type="button"
            aria-label={isPasswordVisible ? "Hide password" : "Show password"}
            title={isPasswordVisible ? "Hide password" : "Show password"}
            onClick={() => setIsPasswordVisible((current) => !current)}
          >
            {isPasswordVisible ? <EyeOff size={20} /> : <Eye size={20} />}
          </button>
        </span>
      </label>
      <label className="check-row">
        <input
          type="checkbox"
          checked={rememberPassword}
          onChange={(event) => setRememberPassword(event.target.checked)}
        />
        <span>
          Remember credentials on this device
          <small>Saved locally in secure OS storage. NekoFM has no cloud account.</small>
        </span>
      </label>
      <button
        type="button"
        className="wide-action"
        disabled={isTestingConnection}
        onClick={testConnection}
      >
        {isTestingConnection ? (
          <LoaderCircle className="spin-icon" size={20} />
        ) : (
          <Network size={20} />
        )}
        {isTestingConnection ? "Testing..." : "Test connection"}
      </button>
      {connectionStep ? (
        <InlineNotice tone="success" icon={RefreshCw} message={connectionStep} />
      ) : null}
      <button
        type="button"
        className="secondary-action"
        disabled={isScanningServer}
        onClick={scanServerLibrary}
      >
        {isScanningServer ? (
          <LoaderCircle className="spin-icon" size={20} />
        ) : (
          <Search size={20} />
        )}
        {isScanningServer ? "Scanning..." : "Scan server library"}
      </button>
      {scanMessage ? (
        <InlineNotice tone="success" icon={Search} message={scanMessage} />
      ) : null}
      {scanWarning ? (
        <InlineNotice tone="warning" icon={ShieldAlert} message={scanWarning} />
      ) : null}
      {connectionResult ? (
        <InlineNotice
          tone={connectionResult.isSuccess ? "success" : "error"}
          icon={connectionResult.isSuccess ? Network : ShieldAlert}
          message={connectionResult.message}
        />
      ) : null}
      <section className="settings-section">
        <h2>Playback</h2>
        <p>Choose how the previous-track button behaves after a song has already started.</p>
        <div className="threshold-control">
          <label>
            <span>Previous button threshold</span>
            <strong>
              {preferences.previousTrackThresholdSeconds} second
              {preferences.previousTrackThresholdSeconds === 1 ? "" : "s"}
            </strong>
          </label>
          <input
            data-no-page-swipe
            type="range"
            min={0}
            max={15}
            step={1}
            value={preferences.previousTrackThresholdSeconds}
            disabled={isSavingThreshold}
            onChange={(event) => updatePreviousTrackThreshold(Number(event.target.value))}
          />
          <input
            type="number"
            min={0}
            max={15}
            step={1}
            value={preferences.previousTrackThresholdSeconds}
            disabled={isSavingThreshold}
            aria-label="Previous button threshold seconds"
            onChange={(event) => updatePreviousTrackThreshold(Number(event.target.value))}
          />
        </div>
        {playbackWarning ? (
          <InlineNotice tone="warning" icon={ShieldAlert} message={playbackWarning} />
        ) : null}
      </section>
      <section className="settings-section">
        <h2>Downloads</h2>
        <p>Choose where downloaded tracks are saved. Existing downloads can be moved into the new folder.</p>
        <label>
          <span>Download folder</span>
          <input
            value={downloadFolder.path}
            onChange={(event) => {
              setDownloadFolder({ path: event.target.value, isCustom: true });
              setDownloadFolderMessage(null);
              setDownloadFolderWarning(null);
            }}
          />
        </label>
        <div className="settings-button-row">
          <button type="button" onClick={chooseDownloadFolder}>
            <FolderOpen size={18} />
            Choose folder
          </button>
          <button
            type="button"
            disabled={isSavingDownloadFolder}
            onClick={saveDownloadFolder}
          >
            {isSavingDownloadFolder ? <LoaderCircle className="spin-icon" size={18} /> : <Save size={18} />}
            Save folder
          </button>
          <button
            type="button"
            disabled={isSavingDownloadFolder}
            onClick={resetDownloadFolder}
          >
            <RotateCcw size={18} />
            Use default
          </button>
          <button type="button" onClick={openDownloadFolder}>
            <FolderOpen size={18} />
            Open folder
          </button>
        </div>
        {downloadFolderMessage ? (
          <InlineNotice tone="success" icon={CircleCheck} message={downloadFolderMessage} />
        ) : null}
        {downloadFolderWarning ? (
          <InlineNotice tone="warning" icon={ShieldAlert} message={downloadFolderWarning} />
        ) : null}
      </section>
      {moveDownloadsDialog ? (
        <MoveDownloadsDialog
          dialog={moveDownloadsDialog}
          isWorking={false}
          onChoose={chooseMoveDownloads}
        />
      ) : null}
    </div>
  );
}

function MoveDownloadsDialog({
  dialog,
  isWorking,
  onChoose,
}: {
  dialog: MoveDownloadsDialogState;
  isWorking: boolean;
  onChoose: (choice: "move" | "new-only" | "cancel") => void;
}) {
  return (
    <div className="playlist-dialog-backdrop" role="presentation">
      <section
        className="playlist-dialog"
        aria-modal="true"
        role="dialog"
        aria-label="Move existing downloads"
      >
        <h2>Move existing downloads?</h2>
        <p>
          Move {dialog.completeCount} downloaded {dialog.completeCount === 1 ? "track" : "tracks"} into the selected folder, or only use it for future downloads.
        </p>
        <span className="playlist-dialog-actions">
          <button type="button" disabled={isWorking} onClick={() => onChoose("cancel")}>
            Cancel
          </button>
          <button type="button" disabled={isWorking} onClick={() => onChoose("new-only")}>
            Only new downloads
          </button>
          <button type="button" disabled={isWorking} onClick={() => onChoose("move")}>
            {isWorking ? <LoaderCircle className="spin-icon" size={16} /> : <FolderOpen size={16} />}
            Move downloads
          </button>
        </span>
      </section>
    </div>
  );
}

function InlineNotice({
  tone,
  icon: Icon,
  message,
}: {
  tone: "success" | "warning" | "error";
  icon: ComponentType<{ size?: number; strokeWidth?: number }>;
  message: string;
}) {
  return (
    <div className={`inline-notice is-${tone}`}>
      <Icon size={20} strokeWidth={2.2} />
      <span>{message}</span>
    </div>
  );
}

function usesPublicHttp(value: string) {
  const trimmed = value.trim();
  const withScheme = trimmed.includes("://") ? trimmed : `http://${trimmed}`;

  try {
    const url = new URL(withScheme);
    if (url.protocol !== "http:") {
      return false;
    }

    const host = url.hostname;
    return (
      host !== "localhost" &&
      host !== "127.0.0.1" &&
      host !== "::1" &&
      !host.startsWith("192.168.") &&
      !host.startsWith("10.") &&
      !/^172\.(1[6-9]|2\d|3[0-1])\./.test(host)
    );
  } catch {
    return false;
  }
}

function validateServerProfile(serverUrl: string, username: string, password: string) {
  const trimmedUrl = serverUrl.trim();
  if (!trimmedUrl) {
    return "Enter your server URL.";
  }

  const withScheme = trimmedUrl.includes("://") ? trimmedUrl : `http://${trimmedUrl}`;
  try {
    const url = new URL(withScheme);
    if (!url.hostname) {
      return "Enter a valid server URL.";
    }
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return "Server URL must use HTTP or HTTPS.";
    }
  } catch {
    return "Enter a valid server URL.";
  }

  if (!username.trim()) {
    return "Enter your server username.";
  }
  if (!password) {
    return "Enter your server password.";
  }
  return null;
}

function sameDownloadPath(left: string, right: string) {
  function normalize(path: string) {
    const trimmed = path.trim();
    if (trimmed.length > 1 && /[\\/]$/.test(trimmed)) {
      return trimmed.slice(0, -1);
    }
    return trimmed;
  }

  return normalize(left) === normalize(right);
}

function MiniPlayer({
  player,
  actions,
  onOpenPlayer,
}: {
  player: PlayerState;
  actions: PlayerActions;
  onOpenPlayer: () => void;
}) {
  const currentTrack = player.queue[player.currentIndex] ?? null;
  if (!currentTrack || !player.album) {
    return null;
  }

  const progress =
    player.durationSeconds <= 0
      ? 0
      : Math.min(1, Math.max(0, player.positionSeconds / player.durationSeconds));

  return (
    <div className="mini-player">
      <div className="mini-progress" style={{ transform: `scaleX(${progress})` }} />
      <div className="mini-body">
        <button className="mini-open" type="button" onClick={onOpenPlayer}>
          <AlbumArt
            imageUri={currentTrack.coverArtUri ?? player.album.coverArtUri}
            label={`${player.album.name} cover art`}
          />
          <span className="mini-copy">
            <strong>{currentTrack.title}</strong>
            <span>
              {currentTrack.artist}
              {player.source ? (
                <span
                  className="mini-source"
                  title={player.source === "local" ? "Playing from local download" : "Streaming from server"}
                  aria-label={player.source === "local" ? "Playing from local download" : "Streaming from server"}
                >
                  {player.source === "local" ? <CircleCheck size={14} /> : <Network size={14} />}
                  {player.source === "local" ? "Local" : "Streaming"}
                </span>
              ) : null}
            </span>
          </span>
        </button>
        <div className="mini-controls">
          <button
            type="button"
            aria-label="Restart or previous track"
            title="Restart or previous track"
            onClick={actions.seekBack}
          >
            <SkipBack size={22} />
          </button>
          <button
            type="button"
            className="mini-play"
            disabled={player.isLoading}
            aria-label={player.isPlaying ? "Pause" : "Play"}
            title={player.isPlaying ? "Pause" : "Play"}
            onClick={actions.togglePlayPause}
          >
            {player.isLoading ? (
              <LoaderCircle className="spin-icon" size={20} />
            ) : player.isPlaying ? (
              <Pause size={24} />
            ) : (
              <Play size={24} />
            )}
          </button>
          <button
            type="button"
            aria-label="Next track"
            title="Next track"
            onClick={actions.seekNext}
          >
            <SkipForward size={22} />
          </button>
        </div>
      </div>
    </div>
  );
}

export default App;
