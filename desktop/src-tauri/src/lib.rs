use rand::RngCore;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;
use url::Url;

const KEYCHAIN_SERVICE: &str = "NekoFM";
const KEYCHAIN_PASSWORD_ACCOUNT: &str = "server_profile.password";
const PROFILE_FILE_NAME: &str = "server-profile.json";
const PASSWORD_FALLBACK_FILE_NAME: &str = "server-password.local";
const PLAYBACK_PREFERENCES_FILE_NAME: &str = "playback-preferences.json";
const DOWNLOADS_FILE_NAME: &str = "downloads.json";
const LIKED_TRACKS_FILE_NAME: &str = "liked-tracks.json";
const PLAYLISTS_FILE_NAME: &str = "playlists.json";
const DOWNLOADS_DATABASE_FILE_NAME: &str = "downloads.sqlite";
const DOWNLOAD_PREFERENCES_FILE_NAME: &str = "download-preferences.json";
const DOWNLOADS_MANIFEST_FILE_NAME: &str = "nekofm_downloads_manifest.json";
const EXPORT_MANIFEST_FILE_NAME: &str = ".nekofm_export_manifest.json";
const ALL_DOWNLOADS_PLAYLIST_NAME: &str = "NekoFM All Downloads";
const LIKED_PLAYLIST_NAME: &str = "Liked";
const DEFAULT_PREVIOUS_TRACK_THRESHOLD_SECONDS: u64 = 3;
const MIN_PREVIOUS_TRACK_THRESHOLD_SECONDS: u64 = 0;
const MAX_PREVIOUS_TRACK_THRESHOLD_SECONDS: u64 = 15;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerProfileInput {
    server_url: String,
    username: String,
    password: String,
    remember_password: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ServerConnectionResult {
    is_success: bool,
    message: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ServerScanResult {
    is_scanning: bool,
    scanned_count: i64,
    message: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SavedServerProfileOutput {
    server_url: String,
    username: String,
    password: String,
    remember_password: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerProfileMetadata {
    server_url: String,
    username: String,
    remember_password: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlaybackPreferences {
    previous_track_threshold_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DownloadPreferences {
    custom_download_folder: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DownloadFolderOutput {
    path: String,
    is_custom: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DownloadFolderMoveResultOutput {
    moved_audio_count: i64,
    moved_cover_count: i64,
    skipped_count: i64,
    total_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DownloadRepairResultOutput {
    tracks: Vec<DownloadedTrackOutput>,
    removed_audio_count: i64,
    cleared_cover_count: i64,
    recovered_cover_count: i64,
    downloaded_cover_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct MusicExportResultOutput {
    exported_track_count: i64,
    copied_track_count: i64,
    downloaded_track_count: i64,
    copied_cover_count: i64,
    downloaded_cover_count: i64,
    skipped_track_count: i64,
    playlist_count: i64,
    playlist_entry_count: i64,
    skipped_playlist_entry_count: i64,
    collision_count: i64,
    message: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExportTrackInput {
    track: TrackOutput,
    local_download: Option<DownloadedTrackOutput>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExportPlaylistInput {
    name: String,
    tracks: Vec<ExportTrackInput>,
}

#[derive(Debug, Clone)]
struct SavedServerProfile {
    server_url: String,
    username: String,
    password: String,
}

#[derive(Debug, Default)]
struct SessionProfileState {
    profile: Mutex<Option<SavedServerProfile>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AlbumOutput {
    id: String,
    name: String,
    artist: String,
    song_count: i64,
    duration_seconds: i64,
    cover_art_id: Option<String>,
    cover_art_uri: Option<String>,
    year: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TrackOutput {
    id: String,
    title: String,
    artist: String,
    track_number: i64,
    duration_seconds: i64,
    album_id: Option<String>,
    album_name: Option<String>,
    cover_art_id: Option<String>,
    cover_art_uri: Option<String>,
    suffix: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AlbumDetailOutput {
    album: AlbumOutput,
    tracks: Vec<TrackOutput>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LibrarySearchResultOutput {
    albums: Vec<AlbumOutput>,
    tracks: Vec<TrackOutput>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DownloadedTrackOutput {
    track_id: String,
    title: String,
    artist: String,
    track_number: i64,
    duration_seconds: i64,
    local_path: String,
    state: String,
    updated_at: String,
    album_id: Option<String>,
    album_name: Option<String>,
    cover_art_uri: Option<String>,
    local_cover_path: Option<String>,
    suffix: Option<String>,
    bytes: Option<u64>,
    received_bytes: Option<u64>,
    total_bytes: Option<u64>,
    error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LikedTrackOutput {
    track_id: String,
    title: String,
    artist: String,
    track_number: i64,
    duration_seconds: i64,
    liked_at: String,
    position: i64,
    album_id: Option<String>,
    album_name: Option<String>,
    cover_art_id: Option<String>,
    cover_art_uri: Option<String>,
    suffix: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlaylistOutput {
    id: String,
    name: String,
    created_at: String,
    updated_at: String,
    track_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlaylistTrackOutput {
    entry_id: String,
    playlist_id: String,
    track_id: String,
    title: String,
    artist: String,
    track_number: i64,
    duration_seconds: i64,
    position: i64,
    added_at: String,
    album_id: Option<String>,
    album_name: Option<String>,
    cover_art_id: Option<String>,
    cover_art_uri: Option<String>,
    suffix: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlaylistStore {
    playlists: Vec<PlaylistOutput>,
    tracks: Vec<PlaylistTrackOutput>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PlaybackSourceOutput {
    uri: String,
    source: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "kebab-case")]
struct SubsonicEnvelope {
    #[serde(rename = "subsonic-response")]
    subsonic_response: Option<SubsonicResponse>,
}

#[derive(Debug, Deserialize)]
struct SubsonicResponse {
    status: Option<String>,
    error: Option<SubsonicError>,
    #[serde(flatten)]
    data: serde_json::Map<String, Value>,
}

#[derive(Debug, Deserialize)]
struct SubsonicError {
    message: Option<String>,
}

#[tauri::command]
async fn test_server_connection(
    app: tauri::AppHandle,
    profile: ServerProfileInput,
) -> ServerConnectionResult {
    match test_connection(profile).await {
        Ok(profile) => save_profile_safely(&app, &profile),
        Err(message) => ServerConnectionResult {
            is_success: false,
            message,
        },
    }
}

#[tauri::command]
fn load_server_profile(app: tauri::AppHandle) -> Result<Option<SavedServerProfileOutput>, String> {
    let metadata = match load_profile_metadata(&app)? {
        Some(metadata) => metadata,
        None => return Ok(None),
    };

    let password = if metadata.remember_password {
        let loaded = load_password(&app).map_err(|error| {
            format!(
                "Saved profile exists, but the password could not be loaded from Keychain: {error}"
            )
        })?;
        if loaded.is_empty() {
            return Err(
                "Saved profile exists, but the saved password is empty. Reconnect in Settings."
                    .to_string(),
            );
        }
        loaded
    } else {
        String::new()
    };

    Ok(Some(SavedServerProfileOutput {
        server_url: metadata.server_url,
        username: metadata.username,
        password,
        remember_password: metadata.remember_password,
    }))
}

#[tauri::command]
async fn get_albums(app: tauri::AppHandle) -> Result<Vec<AlbumOutput>, String> {
    let profile = require_saved_profile(&app)?;
    let response = get_subsonic(
        &profile,
        "getAlbumList2.view",
        &[
            ("type", "alphabeticalByName"),
            ("size", "500"),
            ("offset", "0"),
        ],
    )
    .await?;

    let albums = response
        .data
        .get("albumList2")
        .and_then(|value| value.get("album"))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|value| value.as_object())
                .map(|json| album_from_subsonic(&profile, json))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Ok(albums)
}

#[tauri::command]
async fn get_album(app: tauri::AppHandle, album_id: String) -> Result<AlbumDetailOutput, String> {
    let profile = require_saved_profile(&app)?;
    let response = get_subsonic(&profile, "getAlbum.view", &[("id", album_id.as_str())]).await?;
    let album_json = response
        .data
        .get("album")
        .and_then(Value::as_object)
        .ok_or_else(|| "The server did not return an album.".to_string())?;

    let tracks = album_json
        .get("song")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|value| value.as_object())
                .map(|json| track_from_subsonic(&profile, json))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Ok(AlbumDetailOutput {
        album: album_from_subsonic(&profile, album_json),
        tracks,
    })
}

#[tauri::command]
async fn search_library(
    app: tauri::AppHandle,
    query: String,
) -> Result<LibrarySearchResultOutput, String> {
    if query.trim().len() < 2 {
        return Ok(LibrarySearchResultOutput {
            albums: Vec::new(),
            tracks: Vec::new(),
        });
    }

    let profile = require_saved_profile(&app)?;
    let response = get_subsonic(
        &profile,
        "search3.view",
        &[
            ("query", query.trim()),
            ("artistCount", "0"),
            ("albumCount", "20"),
            ("songCount", "50"),
        ],
    )
    .await?;
    Ok(search_result_from_subsonic(
        &profile,
        response.data.get("searchResult3"),
    ))
}

#[tauri::command]
fn search_downloaded_library(
    app: tauri::AppHandle,
    query: String,
) -> Result<LibrarySearchResultOutput, String> {
    search_downloaded_details(&app, &query)
}

#[tauri::command]
async fn start_server_scan(app: tauri::AppHandle) -> Result<ServerScanResult, String> {
    let profile = require_saved_profile(&app)?;
    start_scan_for_profile(&profile).await
}

#[tauri::command]
async fn start_server_scan_with_profile(
    app: tauri::AppHandle,
    profile: ServerProfileInput,
) -> Result<ServerScanResult, String> {
    let profile = saved_profile_from_input(&profile)?;
    let result = start_scan_for_profile(&profile).await?;
    set_session_profile(&app, Some(profile))?;
    Ok(result)
}

async fn start_scan_for_profile(profile: &SavedServerProfile) -> Result<ServerScanResult, String> {
    let response = get_subsonic(&profile, "startScan.view", &[("fullScan", "false")]).await?;
    let scan_status = response.data.get("scanStatus");
    let is_scanning = scan_status
        .and_then(|value| value.get("scanning"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let scanned_count = int_value(scan_status.and_then(|value| value.get("count")));
    Ok(ServerScanResult {
        is_scanning,
        scanned_count,
        message: server_scan_message(is_scanning, scanned_count),
    })
}

#[tauri::command]
fn get_stream_uri(app: tauri::AppHandle, track_id: String) -> Result<String, String> {
    let profile = require_saved_profile(&app)?;
    stream_uri(&profile, &track_id)
        .ok_or_else(|| "Track stream URL could not be created.".to_string())
}

#[tauri::command]
fn get_playback_source(
    app: tauri::AppHandle,
    track_id: String,
) -> Result<PlaybackSourceOutput, String> {
    if let Some(download) = complete_download_for_track(&app, &track_id)? {
        let path = PathBuf::from(&download.local_path);
        return Ok(PlaybackSourceOutput {
            uri: path.to_string_lossy().to_string(),
            source: "local".to_string(),
        });
    }

    let profile = require_saved_profile(&app)?;
    let uri = stream_uri(&profile, &track_id)
        .ok_or_else(|| "Track stream URL could not be created.".to_string())?;
    Ok(PlaybackSourceOutput {
        uri,
        source: "stream".to_string(),
    })
}

#[tauri::command]
fn load_downloaded_album_details(app: tauri::AppHandle) -> Result<Vec<AlbumDetailOutput>, String> {
    downloaded_album_details(&app)
}

#[tauri::command]
fn load_downloads(app: tauri::AppHandle) -> Result<Vec<DownloadedTrackOutput>, String> {
    repair_downloads(&app)
}

#[tauri::command]
async fn recheck_downloads(app: tauri::AppHandle) -> Result<DownloadRepairResultOutput, String> {
    let result = repair_downloads_with_result(&app)?;
    repair_missing_album_covers(&app, result).await
}

#[tauri::command]
fn load_liked_tracks(app: tauri::AppHandle) -> Result<Vec<LikedTrackOutput>, String> {
    load_liked_tracks_from_disk(&app)
}

#[tauri::command]
fn toggle_liked_track(
    app: tauri::AppHandle,
    track: TrackOutput,
) -> Result<Vec<LikedTrackOutput>, String> {
    let mut tracks = load_liked_tracks_from_disk(&app)?;
    if tracks.iter().any(|liked| liked.track_id == track.id) {
        tracks.retain(|liked| liked.track_id != track.id);
        normalize_liked_positions(&mut tracks);
        save_liked_tracks(&app, &tracks)?;
        return Ok(tracks);
    }

    let next_position = tracks
        .iter()
        .map(|liked| liked.position)
        .max()
        .unwrap_or(-1)
        + 1;
    tracks.push(liked_track_from_track(&track, next_position));
    normalize_liked_positions(&mut tracks);
    save_liked_tracks(&app, &tracks)?;
    Ok(tracks)
}

#[tauri::command]
fn unlike_track(app: tauri::AppHandle, track_id: String) -> Result<Vec<LikedTrackOutput>, String> {
    let mut tracks = load_liked_tracks_from_disk(&app)?;
    tracks.retain(|liked| liked.track_id != track_id);
    normalize_liked_positions(&mut tracks);
    save_liked_tracks(&app, &tracks)?;
    Ok(tracks)
}

#[tauri::command]
fn reorder_liked_tracks(
    app: tauri::AppHandle,
    track_ids: Vec<String>,
) -> Result<Vec<LikedTrackOutput>, String> {
    let mut tracks = load_liked_tracks_from_disk(&app)?;
    let existing_ids = tracks
        .iter()
        .map(|track| track.track_id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    if !is_exact_id_order(&track_ids, &existing_ids) {
        return Err("Liked order does not match the current liked songs.".to_string());
    }

    for (index, track_id) in track_ids.iter().enumerate() {
        if let Some(track) = tracks.iter_mut().find(|track| track.track_id == *track_id) {
            track.position = index as i64;
        }
    }
    save_liked_tracks(&app, &tracks)?;
    load_liked_tracks_from_disk(&app)
}

#[tauri::command]
fn load_playlists(app: tauri::AppHandle) -> Result<Vec<PlaylistOutput>, String> {
    let store = load_playlist_store(&app)?;
    Ok(playlists_with_counts(&store))
}

#[tauri::command]
fn load_playlist_tracks(
    app: tauri::AppHandle,
    playlist_id: String,
) -> Result<Vec<PlaylistTrackOutput>, String> {
    let mut tracks = load_playlist_store(&app)?
        .tracks
        .into_iter()
        .filter(|track| track.playlist_id == playlist_id)
        .collect::<Vec<_>>();
    normalize_playlist_track_positions(&mut tracks);
    Ok(tracks)
}

#[tauri::command]
fn create_playlist(app: tauri::AppHandle, name: String) -> Result<Vec<PlaylistOutput>, String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("Enter a playlist name.".to_string());
    }

    let mut store = load_playlist_store(&app)?;
    let timestamp = now_timestamp();
    store.playlists.push(PlaylistOutput {
        id: format!("playlist-{timestamp}-{}", store.playlists.len()),
        name: trimmed.to_string(),
        created_at: timestamp.clone(),
        updated_at: timestamp,
        track_count: 0,
    });
    save_playlist_store(&app, &store)?;
    Ok(playlists_with_counts(&store))
}

#[tauri::command]
fn rename_playlist(
    app: tauri::AppHandle,
    playlist_id: String,
    name: String,
) -> Result<Vec<PlaylistOutput>, String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("Enter a playlist name.".to_string());
    }

    let mut store = load_playlist_store(&app)?;
    let Some(playlist) = store
        .playlists
        .iter_mut()
        .find(|playlist| playlist.id == playlist_id)
    else {
        return Err("Playlist was not found.".to_string());
    };
    playlist.name = trimmed.to_string();
    playlist.updated_at = now_timestamp();
    save_playlist_store(&app, &store)?;
    Ok(playlists_with_counts(&store))
}

#[tauri::command]
fn delete_playlist(
    app: tauri::AppHandle,
    playlist_id: String,
) -> Result<Vec<PlaylistOutput>, String> {
    let mut store = load_playlist_store(&app)?;
    store
        .playlists
        .retain(|playlist| playlist.id != playlist_id);
    store
        .tracks
        .retain(|track| track.playlist_id != playlist_id);
    save_playlist_store(&app, &store)?;
    Ok(playlists_with_counts(&store))
}

#[tauri::command]
fn add_track_to_playlist(
    app: tauri::AppHandle,
    playlist_id: String,
    track: TrackOutput,
) -> Result<Vec<PlaylistTrackOutput>, String> {
    let mut store = load_playlist_store(&app)?;
    if !store
        .playlists
        .iter()
        .any(|playlist| playlist.id == playlist_id)
    {
        return Err("Playlist was not found.".to_string());
    }
    let next_position = store
        .tracks
        .iter()
        .filter(|item| item.playlist_id == playlist_id)
        .map(|item| item.position)
        .max()
        .unwrap_or(-1)
        + 1;
    store.tracks.push(playlist_track_from_track(
        &playlist_id,
        &track,
        next_position,
    ));
    touch_playlist(&mut store, &playlist_id);
    save_playlist_store(&app, &store)?;
    playlist_tracks_for_store(&store, &playlist_id)
}

#[tauri::command]
fn remove_playlist_entry(
    app: tauri::AppHandle,
    playlist_id: String,
    entry_id: String,
) -> Result<Vec<PlaylistTrackOutput>, String> {
    let mut store = load_playlist_store(&app)?;
    store
        .tracks
        .retain(|track| !(track.playlist_id == playlist_id && track.entry_id == entry_id));
    touch_playlist(&mut store, &playlist_id);
    normalize_all_playlist_positions(&mut store);
    save_playlist_store(&app, &store)?;
    playlist_tracks_for_store(&store, &playlist_id)
}

#[tauri::command]
fn reorder_playlist_tracks(
    app: tauri::AppHandle,
    playlist_id: String,
    entry_ids: Vec<String>,
) -> Result<Vec<PlaylistTrackOutput>, String> {
    let mut store = load_playlist_store(&app)?;
    let existing_ids = store
        .tracks
        .iter()
        .filter(|track| track.playlist_id == playlist_id)
        .map(|track| track.entry_id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    if !is_exact_id_order(&entry_ids, &existing_ids) {
        return Err("Playlist order does not match the current playlist tracks.".to_string());
    }

    for (index, entry_id) in entry_ids.iter().enumerate() {
        if let Some(track) = store
            .tracks
            .iter_mut()
            .find(|track| track.playlist_id == playlist_id && track.entry_id == *entry_id)
        {
            track.position = index as i64;
        }
    }
    touch_playlist(&mut store, &playlist_id);
    save_playlist_store(&app, &store)?;
    playlist_tracks_for_store(&store, &playlist_id)
}

#[tauri::command]
fn load_download_folder(app: tauri::AppHandle) -> Result<DownloadFolderOutput, String> {
    active_download_folder_output(&app)
}

async fn choose_folder_with_title(
    app: tauri::AppHandle,
    title: &'static str,
) -> Result<Option<String>, String> {
    let (sender, receiver) = std::sync::mpsc::channel();
    app.dialog()
        .file()
        .set_title(title)
        .pick_folder(move |selected| {
            let _ = sender.send(selected.map(|path| path.to_string()));
        });
    tauri::async_runtime::spawn_blocking(move || receiver.recv())
        .await
        .map_err(|error| error.to_string())?
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn choose_download_folder(app: tauri::AppHandle) -> Result<Option<String>, String> {
    choose_folder_with_title(app, "Choose download folder").await
}

#[tauri::command]
async fn choose_export_folder(app: tauri::AppHandle) -> Result<Option<String>, String> {
    choose_folder_with_title(app, "Choose export folder").await
}

#[tauri::command]
fn export_local_music(
    app: tauri::AppHandle,
    target_folder: String,
    clean_first: bool,
    selected_track_ids: Option<Vec<String>>,
    include_liked: Option<bool>,
    playlist_ids: Option<Vec<String>>,
) -> Result<MusicExportResultOutput, String> {
    let target = PathBuf::from(target_folder.trim());
    if target.as_os_str().is_empty() {
        return Err("Choose an export folder.".to_string());
    }
    fs::create_dir_all(&target).map_err(|error| error.to_string())?;
    if clean_first {
        clean_export(&target)?;
    }
    let downloads = repair_downloads(&app)?;
    let selected_track_ids = selected_track_ids
        .unwrap_or_default()
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
    let has_selection = !selected_track_ids.is_empty()
        || include_liked.unwrap_or(false)
        || playlist_ids.as_ref().is_some_and(|ids| !ids.is_empty());
    let downloads = if has_selection {
        downloads
            .into_iter()
            .filter(|download| selected_track_ids.contains(&download.track_id))
            .collect::<Vec<_>>()
    } else {
        downloads
    };
    let liked_tracks = if include_liked.unwrap_or(!has_selection) {
        load_liked_tracks_from_disk(&app)?
    } else {
        Vec::new()
    };
    let mut playlist_store = load_playlist_store(&app)?;
    if let Some(playlist_ids) = playlist_ids {
        let playlist_ids = playlist_ids
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>();
        playlist_store
            .playlists
            .retain(|playlist| playlist_ids.contains(&playlist.id));
        playlist_store
            .tracks
            .retain(|track| playlist_ids.contains(&track.playlist_id));
    } else if has_selection {
        playlist_store.playlists.clear();
        playlist_store.tracks.clear();
    }
    export_complete_downloads(&target, &downloads, &liked_tracks, &playlist_store)
}

#[tauri::command]
async fn export_music_selection(
    app: tauri::AppHandle,
    target_folder: String,
    clean_first: bool,
    direct_tracks: Vec<ExportTrackInput>,
    playlists: Vec<ExportPlaylistInput>,
) -> Result<MusicExportResultOutput, String> {
    let target = PathBuf::from(target_folder.trim());
    if target.as_os_str().is_empty() {
        return Err("Choose an export folder.".to_string());
    }
    fs::create_dir_all(&target).map_err(|error| error.to_string())?;
    if clean_first {
        clean_export(&target)?;
    }

    let profile = if export_selection_needs_remote(&direct_tracks, &playlists) {
        Some(require_saved_profile(&app)?)
    } else {
        None
    };
    export_selected_music(&target, profile.as_ref(), direct_tracks, playlists).await
}

#[tauri::command]
fn has_existing_export(target_folder: String) -> Result<bool, String> {
    let target = PathBuf::from(target_folder.trim());
    if target.as_os_str().is_empty() {
        return Ok(false);
    }
    Ok(target.join(EXPORT_MANIFEST_FILE_NAME).exists()
        || target
            .join(format!(
                "{}.m3u",
                safe_filename(ALL_DOWNLOADS_PLAYLIST_NAME)
            ))
            .exists()
        || target
            .join(format!("{}.m3u", safe_filename(LIKED_PLAYLIST_NAME)))
            .exists())
}

#[tauri::command]
fn save_download_folder(
    app: tauri::AppHandle,
    path: String,
) -> Result<DownloadFolderOutput, String> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err("Choose a folder before saving.".to_string());
    }
    let directory = PathBuf::from(trimmed);
    fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
    save_download_preferences(
        &app,
        &DownloadPreferences {
            custom_download_folder: Some(directory.to_string_lossy().to_string()),
        },
    )?;
    active_download_folder_output(&app)
}

#[tauri::command]
fn reset_download_folder(app: tauri::AppHandle) -> Result<DownloadFolderOutput, String> {
    save_download_preferences(
        &app,
        &DownloadPreferences {
            custom_download_folder: None,
        },
    )?;
    active_download_folder_output(&app)
}

#[tauri::command]
fn move_downloads_to_folder(
    app: tauri::AppHandle,
    path: String,
) -> Result<DownloadFolderMoveResultOutput, String> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err("Choose a folder before moving downloads.".to_string());
    }
    let target_root = PathBuf::from(trimmed);
    move_downloads_to_root(&app, target_root)
}

#[tauri::command]
fn move_downloads_to_default_folder(
    app: tauri::AppHandle,
) -> Result<DownloadFolderMoveResultOutput, String> {
    let target_root = default_download_folder(&app)?;
    move_downloads_to_root(&app, target_root)
}

#[tauri::command]
fn open_download_folder(app: tauri::AppHandle) -> Result<(), String> {
    let folder = active_download_folder(&app)?;
    fs::create_dir_all(&folder).map_err(|error| error.to_string())?;
    tauri_plugin_opener::open_path(folder, None::<&str>).map_err(|error| error.to_string())
}

#[tauri::command]
async fn download_track(
    app: tauri::AppHandle,
    track: TrackOutput,
) -> Result<Vec<DownloadedTrackOutput>, String> {
    let profile = require_saved_profile(&app)?;
    let mut downloads = repair_downloads(&app)?;

    if let Some(existing) = downloads
        .iter()
        .find(|download| download.track_id == track.id && download.state == "complete")
        .cloned()
    {
        let cover_path = ensure_album_cover(&app, &track).await.ok();
        downloads = upsert_download(
            downloads,
            DownloadedTrackOutput {
                updated_at: now_timestamp(),
                local_cover_path: cover_path.or(existing.local_cover_path),
                ..existing
            },
        );
        save_downloads(&app, &downloads)?;
        return Ok(downloads);
    }

    let local_path = local_path_for_track(&app, &track)?;
    let local_cover_path = ensure_album_cover(&app, &track).await.ok();
    let mut download = downloaded_track_from_track(&track, &local_path, "downloading");
    download.local_cover_path = local_cover_path;
    download.received_bytes = Some(0);
    downloads = upsert_download(downloads, download.clone());
    save_downloads(&app, &downloads)?;

    let partial_path = format!("{local_path}.partial");
    let result = async {
        delete_file_if_present(&partial_path)?;
        let bytes = download_track_bytes(&profile, &track.id).await?;
        if let Some(parent) = PathBuf::from(&local_path).parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        let mut partial_file =
            fs::File::create(&partial_path).map_err(|error| error.to_string())?;
        partial_file
            .write_all(&bytes)
            .map_err(|error| error.to_string())?;
        if bytes.is_empty() {
            return Err("Downloaded file was empty.".to_string());
        }
        delete_file_if_present(&local_path)?;
        fs::rename(&partial_path, &local_path).map_err(|error| error.to_string())?;
        Ok::<u64, String>(bytes.len() as u64)
    }
    .await;

    downloads = repair_downloads(&app)?;
    match result {
        Ok(size) => {
            let mut completed = downloaded_track_from_track(&track, &local_path, "complete");
            completed.bytes = Some(size);
            completed.received_bytes = Some(size);
            completed.total_bytes = Some(size);
            completed.local_cover_path = ensure_album_cover(&app, &track).await.ok();
            downloads = upsert_download(downloads, completed);
        }
        Err(message) => {
            let mut failed = downloaded_track_from_track(&track, &local_path, "failed");
            failed.error_message = Some(format!("Download failed: {message}"));
            failed.local_cover_path = ensure_album_cover(&app, &track).await.ok();
            downloads = upsert_download(downloads, failed);
        }
    }
    save_downloads(&app, &downloads)?;
    Ok(downloads)
}

#[tauri::command]
fn delete_download(
    app: tauri::AppHandle,
    track_id: String,
) -> Result<Vec<DownloadedTrackOutput>, String> {
    let downloads = repair_downloads(&app)?;
    let Some(existing) = downloads
        .iter()
        .find(|download| download.track_id == track_id)
        .cloned()
    else {
        return Ok(downloads);
    };
    let next_downloads = downloads
        .into_iter()
        .filter(|download| download.track_id != track_id)
        .collect::<Vec<_>>();
    let existing_cover_path = cover_path_for_download(&existing);
    let keep_cover = existing_cover_path.as_ref().is_some_and(|cover_path| {
        next_downloads
            .iter()
            .any(|download| cover_path_for_download(download).as_ref() == Some(cover_path))
    });

    delete_file_if_present(&existing.local_path)?;
    delete_file_if_present(&format!("{}.partial", existing.local_path))?;
    if !keep_cover {
        if let Some(cover_path) = existing_cover_path {
            delete_file_if_present(&cover_path)?;
            delete_file_if_present(&format!("{cover_path}.partial"))?;
        }
    }
    cleanup_unused_download_directory(&existing.local_path, &next_downloads)?;
    save_downloads(&app, &next_downloads)?;
    Ok(next_downloads)
}

#[tauri::command]
fn load_playback_preferences(app: tauri::AppHandle) -> Result<PlaybackPreferences, String> {
    load_playback_preferences_from_disk(&app)
}

#[tauri::command]
fn save_previous_track_threshold(
    app: tauri::AppHandle,
    seconds: u64,
) -> Result<PlaybackPreferences, String> {
    let preferences = PlaybackPreferences {
        previous_track_threshold_seconds: clamp_previous_track_threshold(seconds),
    };
    save_playback_preferences_to_disk(&app, &preferences)?;
    Ok(preferences)
}

async fn test_connection(profile: ServerProfileInput) -> Result<ServerProfileInput, String> {
    let base_uri = normalize_base_url(&profile.server_url)?;
    if profile.username.trim().is_empty() {
        return Err("Enter your server username.".to_string());
    }
    if profile.password.is_empty() {
        return Err("Enter your server password.".to_string());
    }

    let (salt, token) = subsonic_token(&profile.password);
    let mut uri = base_uri;
    let rest_path = join_url_path(uri.path(), "rest/ping.view");
    uri.set_path(&rest_path);
    uri.query_pairs_mut()
        .clear()
        .append_pair("u", profile.username.trim())
        .append_pair("t", &token)
        .append_pair("s", &salt)
        .append_pair("v", "1.16.1")
        .append_pair("c", "NekoFM")
        .append_pair("f", "json");

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(12))
        .build()
        .map_err(|error| format!("Connection failed: {error}"))?;

    let response = client.get(uri).send().await.map_err(format_reqwest_error)?;

    if !response.status().is_success() {
        return Err(format!("Server responded with HTTP {}.", response.status()));
    }

    let body = response
        .json::<SubsonicEnvelope>()
        .await
        .map_err(|_| "The server did not return a Subsonic response.".to_string())?;

    let subsonic_response = body
        .subsonic_response
        .ok_or_else(|| "The server did not return a Subsonic response.".to_string())?;

    if subsonic_response.status.as_deref() == Some("ok") {
        return Ok(profile);
    }

    if let Some(message) = subsonic_response
        .error
        .and_then(|error| error.message)
        .filter(|message| !message.is_empty())
    {
        return Err(message);
    }

    Err("The server rejected the connection.".to_string())
}

async fn get_subsonic(
    profile: &SavedServerProfile,
    endpoint: &str,
    parameters: &[(&str, &str)],
) -> Result<SubsonicResponse, String> {
    let mut uri = normalize_base_url(&profile.server_url)?;
    let rest_path = join_url_path(uri.path(), &format!("rest/{endpoint}"));
    uri.set_path(&rest_path);

    let (salt, token) = subsonic_token(&profile.password);
    {
        let mut query = uri.query_pairs_mut();
        query
            .clear()
            .append_pair("u", profile.username.trim())
            .append_pair("t", &token)
            .append_pair("s", &salt)
            .append_pair("v", "1.16.1")
            .append_pair("c", "NekoFM")
            .append_pair("f", "json");
        for (key, value) in parameters {
            query.append_pair(key, value);
        }
    }

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|error| format!("Server request failed: {error}"))?;

    let response = client.get(uri).send().await.map_err(format_reqwest_error)?;

    if !response.status().is_success() {
        return Err(format!("Server responded with HTTP {}.", response.status()));
    }

    let body = response
        .json::<SubsonicEnvelope>()
        .await
        .map_err(|_| "The server did not return a Subsonic response.".to_string())?;
    let subsonic_response = body
        .subsonic_response
        .ok_or_else(|| "The server did not return a Subsonic response.".to_string())?;

    if subsonic_response.status.as_deref() == Some("ok") {
        return Ok(subsonic_response);
    }

    if let Some(message) = subsonic_response
        .error
        .as_ref()
        .and_then(|error| error.message.as_ref())
        .filter(|message| !message.is_empty())
    {
        return Err(message.clone());
    }

    Err("The server rejected the request.".to_string())
}

fn save_profile_safely(
    app: &tauri::AppHandle,
    profile: &ServerProfileInput,
) -> ServerConnectionResult {
    if let Ok(session_profile) = saved_profile_from_input(profile) {
        if let Err(message) = set_session_profile(app, Some(session_profile)) {
            return ServerConnectionResult {
                is_success: true,
                message: format!("Connection works. Session credentials were not kept: {message}"),
            };
        }
    }

    match save_profile(app, profile) {
        Ok(()) => ServerConnectionResult {
            is_success: true,
            message: "Connection works.".to_string(),
        },
        Err(message) => ServerConnectionResult {
            is_success: true,
            message: format!("Connection works. Credentials were not saved: {message}"),
        },
    }
}

fn save_profile(app: &tauri::AppHandle, profile: &ServerProfileInput) -> Result<(), String> {
    let metadata = ServerProfileMetadata {
        server_url: profile.server_url.trim().to_string(),
        username: profile.username.trim().to_string(),
        remember_password: profile.remember_password,
    };
    let path = profile_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let json = serde_json::to_string_pretty(&metadata).map_err(|error| error.to_string())?;
    fs::write(path, json).map_err(|error| error.to_string())?;

    if profile.remember_password {
        save_password(app, &profile.password)?;
    } else {
        let _ = delete_password(app);
    }

    Ok(())
}

fn load_profile_metadata(app: &tauri::AppHandle) -> Result<Option<ServerProfileMetadata>, String> {
    let path = profile_path(app)?;
    if !path.exists() {
        return Ok(None);
    }

    let json = fs::read_to_string(path).map_err(|error| error.to_string())?;
    serde_json::from_str(&json)
        .map(Some)
        .map_err(|error| error.to_string())
}

fn require_saved_profile(app: &tauri::AppHandle) -> Result<SavedServerProfile, String> {
    if let Some(profile) = session_profile(app)? {
        return Ok(profile);
    }

    let metadata = load_profile_metadata(app)?
        .ok_or_else(|| "Connect to your server in Settings first.".to_string())?;
    if !metadata.remember_password {
        return Err(
            "Saved credentials do not include a password. Reconnect in Settings.".to_string(),
        );
    }
    let password = load_password(app).map_err(|_| {
        "Saved credentials do not include a password. Reconnect in Settings.".to_string()
    })?;
    if password.is_empty() {
        return Err(
            "Saved credentials do not include a password. Reconnect in Settings.".to_string(),
        );
    }

    Ok(SavedServerProfile {
        server_url: metadata.server_url,
        username: metadata.username,
        password,
    })
}

fn session_profile(app: &tauri::AppHandle) -> Result<Option<SavedServerProfile>, String> {
    let state = app.state::<SessionProfileState>();
    state
        .profile
        .lock()
        .map(|profile| profile.clone())
        .map_err(|_| "Session credentials could not be read.".to_string())
}

fn set_session_profile(
    app: &tauri::AppHandle,
    profile: Option<SavedServerProfile>,
) -> Result<(), String> {
    let state = app.state::<SessionProfileState>();
    let mut session = state
        .profile
        .lock()
        .map_err(|_| "Session credentials could not be updated.".to_string())?;
    *session = profile;
    Ok(())
}

fn saved_profile_from_input(profile: &ServerProfileInput) -> Result<SavedServerProfile, String> {
    normalize_base_url(&profile.server_url)?;
    if profile.username.trim().is_empty() {
        return Err("Enter your server username.".to_string());
    }
    if profile.password.is_empty() {
        return Err("Enter your server password.".to_string());
    }

    Ok(SavedServerProfile {
        server_url: profile.server_url.trim().to_string(),
        username: profile.username.trim().to_string(),
        password: profile.password.clone(),
    })
}

fn profile_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(PROFILE_FILE_NAME))
}

fn playback_preferences_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(PLAYBACK_PREFERENCES_FILE_NAME))
}

fn downloads_metadata_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(DOWNLOADS_FILE_NAME))
}

fn liked_tracks_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(LIKED_TRACKS_FILE_NAME))
}

fn playlists_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(PLAYLISTS_FILE_NAME))
}

fn downloads_database_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(DOWNLOADS_DATABASE_FILE_NAME))
}

fn open_download_database(app: &tauri::AppHandle) -> Result<Connection, String> {
    let path = downloads_database_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let connection = Connection::open(path).map_err(|error| error.to_string())?;
    initialize_download_database(&connection)?;
    Ok(connection)
}

fn initialize_download_database(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            r#"
            PRAGMA foreign_keys = ON;
            PRAGMA journal_mode = WAL;

            CREATE TABLE IF NOT EXISTS storage_migrations (
              name TEXT PRIMARY KEY NOT NULL,
              migrated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS downloaded_tracks (
              track_id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              track_number INTEGER NOT NULL,
              duration_seconds INTEGER NOT NULL,
              local_path TEXT NOT NULL,
              state TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              album_id TEXT,
              album_name TEXT,
              cover_art_uri TEXT,
              local_cover_path TEXT,
              suffix TEXT,
              bytes INTEGER,
              received_bytes INTEGER,
              total_bytes INTEGER,
              error_message TEXT
            );
            CREATE INDEX IF NOT EXISTS downloaded_tracks_album_idx
              ON downloaded_tracks(album_id, album_name);
            CREATE INDEX IF NOT EXISTS downloaded_tracks_updated_idx
              ON downloaded_tracks(updated_at DESC);

            CREATE TABLE IF NOT EXISTS liked_tracks (
              track_id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              track_number INTEGER NOT NULL,
              duration_seconds INTEGER NOT NULL,
              liked_at TEXT NOT NULL,
              position INTEGER NOT NULL DEFAULT 0,
              album_id TEXT,
              album_name TEXT,
              cover_art_id TEXT,
              cover_art_uri TEXT,
              suffix TEXT
            );
            CREATE INDEX IF NOT EXISTS liked_tracks_position_idx
              ON liked_tracks(position, liked_at DESC);
            CREATE INDEX IF NOT EXISTS liked_tracks_album_idx
              ON liked_tracks(album_id, album_name);

            CREATE TABLE IF NOT EXISTS playlists (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS playlists_updated_idx
              ON playlists(updated_at DESC);

            CREATE TABLE IF NOT EXISTS playlist_tracks (
              entry_id TEXT PRIMARY KEY NOT NULL,
              playlist_id TEXT NOT NULL,
              track_id TEXT NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              track_number INTEGER NOT NULL,
              duration_seconds INTEGER NOT NULL,
              position INTEGER NOT NULL,
              added_at TEXT NOT NULL,
              album_id TEXT,
              album_name TEXT,
              cover_art_id TEXT,
              cover_art_uri TEXT,
              suffix TEXT,
              FOREIGN KEY (playlist_id)
                REFERENCES playlists(id)
                ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS playlist_tracks_position_idx
              ON playlist_tracks(playlist_id, position);
            "#,
        )
        .map_err(|error| error.to_string())
}

fn download_preferences_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(DOWNLOAD_PREFERENCES_FILE_NAME))
}

fn default_download_folder(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join("downloads").join("tracks"))
}

fn active_download_folder(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    if let Some(custom) = load_download_preferences(app)?.custom_download_folder {
        let trimmed = custom.trim();
        if !trimmed.is_empty() {
            return Ok(PathBuf::from(trimmed));
        }
    }
    default_download_folder(app)
}

fn active_download_folder_output(app: &tauri::AppHandle) -> Result<DownloadFolderOutput, String> {
    let preferences = load_download_preferences(app)?;
    let is_custom = preferences
        .custom_download_folder
        .as_ref()
        .is_some_and(|path| !path.trim().is_empty());
    let path = active_download_folder(app)?;
    Ok(DownloadFolderOutput {
        path: path.to_string_lossy().to_string(),
        is_custom,
    })
}

fn load_download_preferences(app: &tauri::AppHandle) -> Result<DownloadPreferences, String> {
    let path = download_preferences_path(app)?;
    if !path.exists() {
        return Ok(DownloadPreferences {
            custom_download_folder: None,
        });
    }
    let json = fs::read_to_string(path).map_err(|error| error.to_string())?;
    serde_json::from_str(&json).map_err(|error| error.to_string())
}

fn save_download_preferences(
    app: &tauri::AppHandle,
    preferences: &DownloadPreferences,
) -> Result<(), String> {
    let path = download_preferences_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let json = serde_json::to_string_pretty(preferences).map_err(|error| error.to_string())?;
    fs::write(path, json).map_err(|error| error.to_string())
}

fn load_playback_preferences_from_disk(
    app: &tauri::AppHandle,
) -> Result<PlaybackPreferences, String> {
    let path = playback_preferences_path(app)?;
    if !path.exists() {
        return Ok(default_playback_preferences());
    }

    let json = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let mut preferences: PlaybackPreferences =
        serde_json::from_str(&json).map_err(|error| error.to_string())?;
    preferences.previous_track_threshold_seconds =
        clamp_previous_track_threshold(preferences.previous_track_threshold_seconds);
    Ok(preferences)
}

fn save_playback_preferences_to_disk(
    app: &tauri::AppHandle,
    preferences: &PlaybackPreferences,
) -> Result<(), String> {
    let path = playback_preferences_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let json = serde_json::to_string_pretty(preferences).map_err(|error| error.to_string())?;
    fs::write(path, json).map_err(|error| error.to_string())
}

fn default_playback_preferences() -> PlaybackPreferences {
    PlaybackPreferences {
        previous_track_threshold_seconds: DEFAULT_PREVIOUS_TRACK_THRESHOLD_SECONDS,
    }
}

fn clamp_previous_track_threshold(seconds: u64) -> u64 {
    seconds.clamp(
        MIN_PREVIOUS_TRACK_THRESHOLD_SECONDS,
        MAX_PREVIOUS_TRACK_THRESHOLD_SECONDS,
    )
}

fn keyring_entry() -> Result<keyring::Entry, String> {
    keyring::Entry::new(KEYCHAIN_SERVICE, KEYCHAIN_PASSWORD_ACCOUNT)
        .map_err(|error| error.to_string())
}

fn save_password(app: &tauri::AppHandle, password: &str) -> Result<(), String> {
    match keyring_entry().and_then(|entry| {
        entry
            .set_password(password)
            .map_err(|error| error.to_string())
    }) {
        Ok(()) => {
            let _ = save_password_fallback_for_app(app, password);
            Ok(())
        }
        Err(keychain_error) => {
            save_password_fallback_for_app(app, password).map_err(|fallback_error| {
                format!("{keychain_error}; fallback save failed: {fallback_error}")
            })
        }
    }
}

fn load_password(app: &tauri::AppHandle) -> Result<String, String> {
    match keyring_entry().and_then(|entry| entry.get_password().map_err(|error| error.to_string()))
    {
        Ok(password) => Ok(password),
        Err(keychain_error) => load_password_fallback_for_app(app).map_err(|fallback_error| {
            format!("{keychain_error}; fallback load failed: {fallback_error}")
        }),
    }
}

fn delete_password(app: &tauri::AppHandle) -> Result<(), String> {
    let keychain_result = keyring_entry()?
        .delete_credential()
        .map_err(|error| error.to_string());
    let fallback_result = delete_password_fallback_for_app(app);

    match (keychain_result, fallback_result) {
        (Ok(()), _) | (_, Ok(())) => Ok(()),
        (Err(keychain_error), Err(fallback_error)) => Err(format!(
            "{keychain_error}; fallback delete failed: {fallback_error}"
        )),
    }
}

fn password_fallback_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| error.to_string())?;
    Ok(directory.join(PASSWORD_FALLBACK_FILE_NAME))
}

fn save_password_fallback_for_app(app: &tauri::AppHandle, password: &str) -> Result<(), String> {
    let path = password_fallback_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(&path, password).map_err(|error| error.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let permissions = fs::Permissions::from_mode(0o600);
        fs::set_permissions(&path, permissions).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn load_password_fallback_for_app(app: &tauri::AppHandle) -> Result<String, String> {
    let path = password_fallback_path(app)?;
    fs::read_to_string(path)
        .map(|password| password.trim_end_matches(['\r', '\n']).to_string())
        .map_err(|error| error.to_string())
}

fn delete_password_fallback_for_app(app: &tauri::AppHandle) -> Result<(), String> {
    let path = password_fallback_path(app)?;
    if path.exists() {
        fs::remove_file(path).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn normalize_base_url(input: &str) -> Result<Url, String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err("Enter a valid server URL.".to_string());
    }

    let with_scheme = if trimmed.contains("://") {
        trimmed.to_string()
    } else {
        format!("http://{trimmed}")
    };

    let url = Url::parse(&with_scheme).map_err(|_| "Enter a valid server URL.".to_string())?;
    if url.host_str().is_none() {
        return Err("Enter a valid server URL.".to_string());
    }

    match url.scheme() {
        "http" | "https" => Ok(url),
        _ => Err("Server URL must use HTTP or HTTPS.".to_string()),
    }
}

fn join_url_path(base_path: &str, child_path: &str) -> String {
    let normalized_base = base_path.trim_end_matches('/');
    format!("{normalized_base}/{child_path}")
}

fn subsonic_token(password: &str) -> (String, String) {
    let mut bytes = [0_u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    let salt = bytes
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let token = format!("{:x}", md5::compute(format!("{password}{salt}")));
    (salt, token)
}

fn format_reqwest_error(error: reqwest::Error) -> String {
    if error.is_timeout() {
        return "Connection timed out.".to_string();
    }

    if error.is_connect() {
        return "Could not reach the server. Check the URL and network.".to_string();
    }

    error
        .status()
        .map(|status| format!("Server responded with HTTP {status}."))
        .unwrap_or_else(|| format!("Connection failed: {error}"))
}

fn album_from_subsonic(
    profile: &SavedServerProfile,
    json: &serde_json::Map<String, Value>,
) -> AlbumOutput {
    let cover_art_id = optional_string(json.get("coverArt"));
    AlbumOutput {
        id: string_value(json.get("id"), ""),
        name: string_value(json.get("name"), "Unknown album"),
        artist: string_value(json.get("artist"), "Unknown artist"),
        song_count: int_value(json.get("songCount")),
        duration_seconds: int_value(json.get("duration")),
        cover_art_uri: cover_art_uri(profile, cover_art_id.as_deref(), 512),
        cover_art_id,
        year: json.get("year").map(|_| int_value(json.get("year"))),
    }
}

fn track_from_subsonic(
    profile: &SavedServerProfile,
    json: &serde_json::Map<String, Value>,
) -> TrackOutput {
    let cover_art_id = optional_string(json.get("coverArt"));
    TrackOutput {
        id: string_value(json.get("id"), ""),
        title: string_value(json.get("title"), "Unknown track"),
        artist: string_value(json.get("artist"), "Unknown artist"),
        track_number: int_value(json.get("track")),
        duration_seconds: int_value(json.get("duration")),
        album_id: optional_string(json.get("albumId")),
        album_name: optional_string(json.get("album")),
        cover_art_uri: cover_art_uri(profile, cover_art_id.as_deref(), 512),
        cover_art_id,
        suffix: optional_string(json.get("suffix")),
    }
}

fn search_result_from_subsonic(
    profile: &SavedServerProfile,
    value: Option<&Value>,
) -> LibrarySearchResultOutput {
    let search_json = value.and_then(Value::as_object);
    let albums = search_json
        .and_then(|json| json.get("album"))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|value| value.as_object())
                .map(|json| album_from_subsonic(profile, json))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let tracks = search_json
        .and_then(|json| json.get("song"))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|value| value.as_object())
                .map(|json| track_from_subsonic(profile, json))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    LibrarySearchResultOutput { albums, tracks }
}

fn cover_art_uri(
    profile: &SavedServerProfile,
    cover_art_id: Option<&str>,
    size: i64,
) -> Option<String> {
    let cover_art_id = cover_art_id.filter(|value| !value.is_empty())?;
    let mut uri = normalize_base_url(&profile.server_url).ok()?;
    let rest_path = join_url_path(uri.path(), "rest/getCoverArt.view");
    uri.set_path(&rest_path);
    let (salt, token) = subsonic_token(&profile.password);
    uri.query_pairs_mut()
        .clear()
        .append_pair("u", profile.username.trim())
        .append_pair("t", &token)
        .append_pair("s", &salt)
        .append_pair("v", "1.16.1")
        .append_pair("c", "NekoFM")
        .append_pair("id", cover_art_id)
        .append_pair("size", &size.to_string());
    Some(uri.to_string())
}

fn stream_uri(profile: &SavedServerProfile, track_id: &str) -> Option<String> {
    if track_id.is_empty() {
        return None;
    }

    let mut uri = normalize_base_url(&profile.server_url).ok()?;
    let rest_path = join_url_path(uri.path(), "rest/stream.view");
    uri.set_path(&rest_path);
    let (salt, token) = subsonic_token(&profile.password);
    uri.query_pairs_mut()
        .clear()
        .append_pair("u", profile.username.trim())
        .append_pair("t", &token)
        .append_pair("s", &salt)
        .append_pair("v", "1.16.1")
        .append_pair("c", "NekoFM")
        .append_pair("id", track_id);
    Some(uri.to_string())
}

async fn download_track_bytes(
    profile: &SavedServerProfile,
    track_id: &str,
) -> Result<bytes::Bytes, String> {
    let uri = download_uri(profile, track_id)
        .ok_or_else(|| "Track download URL could not be created.".to_string())?;
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(600))
        .build()
        .map_err(|error| error.to_string())?;
    let response = client.get(uri).send().await.map_err(format_reqwest_error)?;
    if !response.status().is_success() {
        return Err(format!("Server responded with HTTP {}.", response.status()));
    }
    response.bytes().await.map_err(|error| error.to_string())
}

fn download_uri(profile: &SavedServerProfile, track_id: &str) -> Option<String> {
    if track_id.is_empty() {
        return None;
    }

    let mut uri = normalize_base_url(&profile.server_url).ok()?;
    let rest_path = join_url_path(uri.path(), "rest/download.view");
    uri.set_path(&rest_path);
    let (salt, token) = subsonic_token(&profile.password);
    uri.query_pairs_mut()
        .clear()
        .append_pair("u", profile.username.trim())
        .append_pair("t", &token)
        .append_pair("s", &salt)
        .append_pair("v", "1.16.1")
        .append_pair("c", "NekoFM")
        .append_pair("id", track_id);
    Some(uri.to_string())
}

async fn ensure_album_cover(app: &tauri::AppHandle, track: &TrackOutput) -> Result<String, String> {
    let cover_uri = track
        .cover_art_uri
        .as_ref()
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "Track has no cover art.".to_string())?;
    let cover_path = local_cover_path_for_track(app, track)?;
    let cover_file = PathBuf::from(&cover_path);
    if cover_file.exists()
        && cover_file
            .metadata()
            .map(|metadata| metadata.len())
            .unwrap_or(0)
            > 0
    {
        return Ok(cover_path);
    }
    if let Some(parent) = cover_file.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let partial_path = format!("{cover_path}.partial");
    delete_file_if_present(&partial_path)?;
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .get(cover_uri)
        .send()
        .await
        .map_err(format_reqwest_error)?;
    if !response.status().is_success() {
        return Err(format!("Server responded with HTTP {}.", response.status()));
    }
    let bytes = response.bytes().await.map_err(|error| error.to_string())?;
    if bytes.is_empty() {
        return Err("Downloaded cover was empty.".to_string());
    }
    fs::write(&partial_path, bytes).map_err(|error| error.to_string())?;
    delete_file_if_present(&cover_path)?;
    fs::rename(&partial_path, &cover_path).map_err(|error| error.to_string())?;
    Ok(cover_path)
}

fn load_downloads_from_disk(app: &tauri::AppHandle) -> Result<Vec<DownloadedTrackOutput>, String> {
    let connection = open_download_database(app)?;
    migrate_legacy_downloads_if_needed(app, &connection)?;
    let mut statement = connection
        .prepare(
            r#"
            SELECT track_id, title, artist, track_number, duration_seconds,
              local_path, state, updated_at, album_id, album_name, cover_art_uri,
              local_cover_path, suffix, bytes, received_bytes, total_bytes, error_message
            FROM downloaded_tracks
            ORDER BY updated_at DESC
            "#,
        )
        .map_err(|error| error.to_string())?;
    let tracks = statement
        .query_map([], downloaded_track_from_row)
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;
    drop(statement);
    Ok(tracks)
}

fn load_liked_tracks_from_disk(app: &tauri::AppHandle) -> Result<Vec<LikedTrackOutput>, String> {
    let connection = open_download_database(app)?;
    migrate_legacy_liked_tracks_if_needed(app, &connection)?;
    let mut statement = connection
        .prepare(
            r#"
            SELECT track_id, title, artist, track_number, duration_seconds,
              liked_at, position, album_id, album_name, cover_art_id, cover_art_uri, suffix
            FROM liked_tracks
            ORDER BY position, liked_at DESC
            "#,
        )
        .map_err(|error| error.to_string())?;
    let mut tracks = statement
        .query_map([], liked_track_from_row)
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;
    drop(statement);
    normalize_liked_positions(&mut tracks);
    Ok(tracks)
}

fn save_liked_tracks(app: &tauri::AppHandle, tracks: &[LikedTrackOutput]) -> Result<(), String> {
    let mut connection = open_download_database(app)?;
    let transaction = connection
        .transaction()
        .map_err(|error| error.to_string())?;
    transaction
        .execute("DELETE FROM liked_tracks", [])
        .map_err(|error| error.to_string())?;
    let mut sorted = tracks.to_vec();
    normalize_liked_positions(&mut sorted);
    {
        let mut statement = transaction
            .prepare(
                r#"
                INSERT INTO liked_tracks (
                  track_id, title, artist, track_number, duration_seconds,
                  liked_at, position, album_id, album_name, cover_art_id,
                  cover_art_uri, suffix
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
                "#,
            )
            .map_err(|error| error.to_string())?;
        for track in &sorted {
            statement
                .execute(params![
                    track.track_id,
                    track.title,
                    track.artist,
                    track.track_number,
                    track.duration_seconds,
                    track.liked_at,
                    track.position,
                    track.album_id,
                    track.album_name,
                    track.cover_art_id,
                    track.cover_art_uri,
                    track.suffix,
                ])
                .map_err(|error| error.to_string())?;
        }
    }
    transaction.commit().map_err(|error| error.to_string())
}

fn normalize_liked_positions(tracks: &mut Vec<LikedTrackOutput>) {
    tracks.sort_by(|left, right| {
        left.position
            .cmp(&right.position)
            .then_with(|| left.liked_at.cmp(&right.liked_at))
            .then_with(|| left.title.cmp(&right.title))
    });
    for (index, track) in tracks.iter_mut().enumerate() {
        track.position = index as i64;
    }
}

fn is_exact_id_order(
    requested_ids: &[String],
    existing_ids: &std::collections::BTreeSet<String>,
) -> bool {
    let requested_set = requested_ids
        .iter()
        .cloned()
        .collect::<std::collections::BTreeSet<_>>();
    requested_ids.len() == existing_ids.len() && requested_set == *existing_ids
}

fn liked_track_from_track(track: &TrackOutput, position: i64) -> LikedTrackOutput {
    LikedTrackOutput {
        track_id: track.id.clone(),
        title: track.title.clone(),
        artist: track.artist.clone(),
        track_number: track.track_number,
        duration_seconds: track.duration_seconds,
        liked_at: now_timestamp(),
        position,
        album_id: track.album_id.clone(),
        album_name: track.album_name.clone(),
        cover_art_id: track.cover_art_id.clone(),
        cover_art_uri: track.cover_art_uri.clone(),
        suffix: track.suffix.clone(),
    }
}

fn load_playlist_store(app: &tauri::AppHandle) -> Result<PlaylistStore, String> {
    let connection = open_download_database(app)?;
    migrate_legacy_playlists_if_needed(app, &connection)?;
    let mut playlists_statement = connection
        .prepare(
            r#"
            SELECT
              playlists.id,
              playlists.name,
              playlists.created_at,
              playlists.updated_at,
              COUNT(playlist_tracks.entry_id) AS track_count
            FROM playlists
            LEFT JOIN playlist_tracks
              ON playlist_tracks.playlist_id = playlists.id
            GROUP BY playlists.id
            ORDER BY playlists.updated_at DESC
            "#,
        )
        .map_err(|error| error.to_string())?;
    let playlists = playlists_statement
        .query_map([], playlist_from_row)
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;
    drop(playlists_statement);

    let mut tracks_statement = connection
        .prepare(
            r#"
            SELECT entry_id, playlist_id, track_id, title, artist, track_number,
              duration_seconds, position, added_at, album_id, album_name,
              cover_art_id, cover_art_uri, suffix
            FROM playlist_tracks
            ORDER BY playlist_id, position, added_at
            "#,
        )
        .map_err(|error| error.to_string())?;
    let tracks = tracks_statement
        .query_map([], playlist_track_from_row)
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;
    drop(tracks_statement);
    drop(connection);

    let mut store = PlaylistStore { playlists, tracks };
    normalize_all_playlist_positions(&mut store);
    Ok(store)
}

fn save_playlist_store(app: &tauri::AppHandle, store: &PlaylistStore) -> Result<(), String> {
    let mut connection = open_download_database(app)?;
    let transaction = connection
        .transaction()
        .map_err(|error| error.to_string())?;
    let mut next = store.clone();
    normalize_all_playlist_positions(&mut next);
    transaction
        .execute("DELETE FROM playlist_tracks", [])
        .map_err(|error| error.to_string())?;
    transaction
        .execute("DELETE FROM playlists", [])
        .map_err(|error| error.to_string())?;
    {
        let mut playlist_statement = transaction
            .prepare(
                r#"
                INSERT INTO playlists (id, name, created_at, updated_at)
                VALUES (?1, ?2, ?3, ?4)
                "#,
            )
            .map_err(|error| error.to_string())?;
        for playlist in &next.playlists {
            playlist_statement
                .execute(params![
                    playlist.id,
                    playlist.name,
                    playlist.created_at,
                    playlist.updated_at,
                ])
                .map_err(|error| error.to_string())?;
        }
    }
    {
        let mut track_statement = transaction
            .prepare(
                r#"
                INSERT INTO playlist_tracks (
                  entry_id, playlist_id, track_id, title, artist, track_number,
                  duration_seconds, position, added_at, album_id, album_name,
                  cover_art_id, cover_art_uri, suffix
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
                "#,
            )
            .map_err(|error| error.to_string())?;
        for track in &next.tracks {
            track_statement
                .execute(params![
                    track.entry_id,
                    track.playlist_id,
                    track.track_id,
                    track.title,
                    track.artist,
                    track.track_number,
                    track.duration_seconds,
                    track.position,
                    track.added_at,
                    track.album_id,
                    track.album_name,
                    track.cover_art_id,
                    track.cover_art_uri,
                    track.suffix,
                ])
                .map_err(|error| error.to_string())?;
        }
    }
    transaction.commit().map_err(|error| error.to_string())
}

fn downloaded_track_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<DownloadedTrackOutput> {
    Ok(DownloadedTrackOutput {
        track_id: row.get("track_id")?,
        title: row.get("title")?,
        artist: row.get("artist")?,
        track_number: row.get("track_number")?,
        duration_seconds: row.get("duration_seconds")?,
        local_path: row.get("local_path")?,
        state: row.get("state")?,
        updated_at: row.get("updated_at")?,
        album_id: row.get("album_id")?,
        album_name: row.get("album_name")?,
        cover_art_uri: row.get("cover_art_uri")?,
        local_cover_path: row.get("local_cover_path")?,
        suffix: row.get("suffix")?,
        bytes: option_i64_to_u64(row.get("bytes")?),
        received_bytes: option_i64_to_u64(row.get("received_bytes")?),
        total_bytes: option_i64_to_u64(row.get("total_bytes")?),
        error_message: row.get("error_message")?,
    })
}

fn liked_track_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LikedTrackOutput> {
    Ok(LikedTrackOutput {
        track_id: row.get("track_id")?,
        title: row.get("title")?,
        artist: row.get("artist")?,
        track_number: row.get("track_number")?,
        duration_seconds: row.get("duration_seconds")?,
        liked_at: row.get("liked_at")?,
        position: row.get("position")?,
        album_id: row.get("album_id")?,
        album_name: row.get("album_name")?,
        cover_art_id: row.get("cover_art_id")?,
        cover_art_uri: row.get("cover_art_uri")?,
        suffix: row.get("suffix")?,
    })
}

fn playlist_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PlaylistOutput> {
    Ok(PlaylistOutput {
        id: row.get("id")?,
        name: row.get("name")?,
        created_at: row.get("created_at")?,
        updated_at: row.get("updated_at")?,
        track_count: row.get("track_count")?,
    })
}

fn playlist_track_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PlaylistTrackOutput> {
    Ok(PlaylistTrackOutput {
        entry_id: row.get("entry_id")?,
        playlist_id: row.get("playlist_id")?,
        track_id: row.get("track_id")?,
        title: row.get("title")?,
        artist: row.get("artist")?,
        track_number: row.get("track_number")?,
        duration_seconds: row.get("duration_seconds")?,
        position: row.get("position")?,
        added_at: row.get("added_at")?,
        album_id: row.get("album_id")?,
        album_name: row.get("album_name")?,
        cover_art_id: row.get("cover_art_id")?,
        cover_art_uri: row.get("cover_art_uri")?,
        suffix: row.get("suffix")?,
    })
}

fn option_i64_to_u64(value: Option<i64>) -> Option<u64> {
    value.and_then(|number| u64::try_from(number).ok())
}

fn option_u64_to_i64(value: Option<u64>) -> Result<Option<i64>, String> {
    value
        .map(|number| {
            i64::try_from(number).map_err(|_| "Stored byte count is too large.".to_string())
        })
        .transpose()
}

fn load_legacy_downloads(app: &tauri::AppHandle) -> Result<Vec<DownloadedTrackOutput>, String> {
    let path = downloads_metadata_path(app)?;
    if !path.exists() {
        return Ok(Vec::new());
    }
    let json = fs::read_to_string(path).map_err(|error| error.to_string())?;
    serde_json::from_str(&json).map_err(|error| error.to_string())
}

fn load_legacy_liked_tracks(app: &tauri::AppHandle) -> Result<Vec<LikedTrackOutput>, String> {
    let path = liked_tracks_path(app)?;
    if !path.exists() {
        return Ok(Vec::new());
    }
    let json = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let mut tracks: Vec<LikedTrackOutput> =
        serde_json::from_str(&json).map_err(|error| error.to_string())?;
    normalize_liked_positions(&mut tracks);
    Ok(tracks)
}

fn load_legacy_playlist_store(app: &tauri::AppHandle) -> Result<PlaylistStore, String> {
    let path = playlists_path(app)?;
    if !path.exists() {
        return Ok(PlaylistStore {
            playlists: Vec::new(),
            tracks: Vec::new(),
        });
    }
    let json = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let mut store: PlaylistStore =
        serde_json::from_str(&json).map_err(|error| error.to_string())?;
    normalize_all_playlist_positions(&mut store);
    Ok(store)
}

fn migrate_legacy_downloads_if_needed(
    app: &tauri::AppHandle,
    connection: &Connection,
) -> Result<(), String> {
    let migration_name = "legacy_downloads_json_v1";
    if has_storage_migration(connection, migration_name)? {
        return Ok(());
    }

    let current_count = table_count(connection, "downloaded_tracks")?;
    if current_count == 0 {
        let legacy = load_legacy_downloads(app)?;
        if !legacy.is_empty() {
            insert_downloads(connection, &legacy)?;
            write_folder_manifests(&legacy)?;
        }
    }
    mark_storage_migration(connection, migration_name)
}

fn migrate_legacy_liked_tracks_if_needed(
    app: &tauri::AppHandle,
    connection: &Connection,
) -> Result<(), String> {
    let migration_name = "legacy_liked_tracks_json_v1";
    if has_storage_migration(connection, migration_name)? {
        return Ok(());
    }

    let current_count = table_count(connection, "liked_tracks")?;
    if current_count == 0 {
        let legacy = load_legacy_liked_tracks(app)?;
        if !legacy.is_empty() {
            insert_liked_tracks(connection, &legacy)?;
        }
    }
    mark_storage_migration(connection, migration_name)
}

fn migrate_legacy_playlists_if_needed(
    app: &tauri::AppHandle,
    connection: &Connection,
) -> Result<(), String> {
    let migration_name = "legacy_playlists_json_v1";
    if has_storage_migration(connection, migration_name)? {
        return Ok(());
    }

    let current_playlist_count = table_count(connection, "playlists")?;
    let current_track_count = table_count(connection, "playlist_tracks")?;
    if current_playlist_count == 0 && current_track_count == 0 {
        let legacy = load_legacy_playlist_store(app)?;
        if !legacy.playlists.is_empty() || !legacy.tracks.is_empty() {
            insert_playlist_store(connection, &legacy)?;
        }
    }
    mark_storage_migration(connection, migration_name)
}

fn has_storage_migration(connection: &Connection, name: &str) -> Result<bool, String> {
    let count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM storage_migrations WHERE name = ?1",
            params![name],
            |row| row.get(0),
        )
        .map_err(|error| error.to_string())?;
    Ok(count > 0)
}

fn mark_storage_migration(connection: &Connection, name: &str) -> Result<(), String> {
    connection
        .execute(
            "INSERT OR REPLACE INTO storage_migrations (name, migrated_at) VALUES (?1, ?2)",
            params![name, now_timestamp()],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn table_count(connection: &Connection, table: &str) -> Result<i64, String> {
    let sql = match table {
        "downloaded_tracks" => "SELECT COUNT(*) FROM downloaded_tracks",
        "liked_tracks" => "SELECT COUNT(*) FROM liked_tracks",
        "playlists" => "SELECT COUNT(*) FROM playlists",
        "playlist_tracks" => "SELECT COUNT(*) FROM playlist_tracks",
        _ => return Err("Unknown storage table.".to_string()),
    };
    connection
        .query_row(sql, [], |row| row.get(0))
        .map_err(|error| error.to_string())
}

fn insert_downloads(
    connection: &Connection,
    downloads: &[DownloadedTrackOutput],
) -> Result<(), String> {
    let mut sorted = downloads.to_vec();
    sorted.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    let mut statement = connection
        .prepare(
            r#"
            INSERT OR REPLACE INTO downloaded_tracks (
              track_id, title, artist, track_number, duration_seconds,
              local_path, state, updated_at, album_id, album_name, cover_art_uri,
              local_cover_path, suffix, bytes, received_bytes, total_bytes, error_message
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
            "#,
        )
        .map_err(|error| error.to_string())?;
    for download in &sorted {
        statement
            .execute(params![
                download.track_id,
                download.title,
                download.artist,
                download.track_number,
                download.duration_seconds,
                download.local_path,
                download.state,
                download.updated_at,
                download.album_id,
                download.album_name,
                download.cover_art_uri,
                download.local_cover_path,
                download.suffix,
                option_u64_to_i64(download.bytes)?,
                option_u64_to_i64(download.received_bytes)?,
                option_u64_to_i64(download.total_bytes)?,
                download.error_message,
            ])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn insert_liked_tracks(connection: &Connection, tracks: &[LikedTrackOutput]) -> Result<(), String> {
    let mut sorted = tracks.to_vec();
    normalize_liked_positions(&mut sorted);
    let mut statement = connection
        .prepare(
            r#"
            INSERT OR REPLACE INTO liked_tracks (
              track_id, title, artist, track_number, duration_seconds,
              liked_at, position, album_id, album_name, cover_art_id,
              cover_art_uri, suffix
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
            "#,
        )
        .map_err(|error| error.to_string())?;
    for track in &sorted {
        statement
            .execute(params![
                track.track_id,
                track.title,
                track.artist,
                track.track_number,
                track.duration_seconds,
                track.liked_at,
                track.position,
                track.album_id,
                track.album_name,
                track.cover_art_id,
                track.cover_art_uri,
                track.suffix,
            ])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn insert_playlist_store(connection: &Connection, store: &PlaylistStore) -> Result<(), String> {
    let mut next = store.clone();
    normalize_all_playlist_positions(&mut next);
    {
        let mut playlist_statement = connection
            .prepare(
                r#"
                INSERT OR REPLACE INTO playlists (id, name, created_at, updated_at)
                VALUES (?1, ?2, ?3, ?4)
                "#,
            )
            .map_err(|error| error.to_string())?;
        for playlist in &next.playlists {
            playlist_statement
                .execute(params![
                    playlist.id,
                    playlist.name,
                    playlist.created_at,
                    playlist.updated_at,
                ])
                .map_err(|error| error.to_string())?;
        }
    }
    {
        let mut track_statement = connection
            .prepare(
                r#"
                INSERT OR REPLACE INTO playlist_tracks (
                  entry_id, playlist_id, track_id, title, artist, track_number,
                  duration_seconds, position, added_at, album_id, album_name,
                  cover_art_id, cover_art_uri, suffix
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
                "#,
            )
            .map_err(|error| error.to_string())?;
        for track in &next.tracks {
            track_statement
                .execute(params![
                    track.entry_id,
                    track.playlist_id,
                    track.track_id,
                    track.title,
                    track.artist,
                    track.track_number,
                    track.duration_seconds,
                    track.position,
                    track.added_at,
                    track.album_id,
                    track.album_name,
                    track.cover_art_id,
                    track.cover_art_uri,
                    track.suffix,
                ])
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}

fn playlists_with_counts(store: &PlaylistStore) -> Vec<PlaylistOutput> {
    let mut playlists = store.playlists.clone();
    for playlist in &mut playlists {
        playlist.track_count = store
            .tracks
            .iter()
            .filter(|track| track.playlist_id == playlist.id)
            .count() as i64;
    }
    playlists.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    playlists
}

fn playlist_tracks_for_store(
    store: &PlaylistStore,
    playlist_id: &str,
) -> Result<Vec<PlaylistTrackOutput>, String> {
    let mut tracks = store
        .tracks
        .iter()
        .filter(|track| track.playlist_id == playlist_id)
        .cloned()
        .collect::<Vec<_>>();
    normalize_playlist_track_positions(&mut tracks);
    Ok(tracks)
}

fn normalize_all_playlist_positions(store: &mut PlaylistStore) {
    let playlist_ids = store
        .playlists
        .iter()
        .map(|playlist| playlist.id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    store
        .tracks
        .retain(|track| playlist_ids.contains(&track.playlist_id));
    for playlist_id in playlist_ids {
        let mut playlist_tracks = store
            .tracks
            .iter()
            .filter(|track| track.playlist_id == playlist_id)
            .cloned()
            .collect::<Vec<_>>();
        normalize_playlist_track_positions(&mut playlist_tracks);
        for normalized in playlist_tracks {
            if let Some(track) = store
                .tracks
                .iter_mut()
                .find(|track| track.entry_id == normalized.entry_id)
            {
                track.position = normalized.position;
            }
        }
    }
}

fn normalize_playlist_track_positions(tracks: &mut Vec<PlaylistTrackOutput>) {
    tracks.sort_by(|left, right| {
        left.position
            .cmp(&right.position)
            .then_with(|| left.added_at.cmp(&right.added_at))
            .then_with(|| left.entry_id.cmp(&right.entry_id))
    });
    for (index, track) in tracks.iter_mut().enumerate() {
        track.position = index as i64;
    }
}

fn touch_playlist(store: &mut PlaylistStore, playlist_id: &str) {
    let timestamp = now_timestamp();
    if let Some(playlist) = store
        .playlists
        .iter_mut()
        .find(|playlist| playlist.id == playlist_id)
    {
        playlist.updated_at = timestamp;
    }
}

fn playlist_track_from_track(
    playlist_id: &str,
    track: &TrackOutput,
    position: i64,
) -> PlaylistTrackOutput {
    let timestamp = now_timestamp();
    PlaylistTrackOutput {
        entry_id: format!("entry-{timestamp}-{position}-{}", track.id),
        playlist_id: playlist_id.to_string(),
        track_id: track.id.clone(),
        title: track.title.clone(),
        artist: track.artist.clone(),
        track_number: track.track_number,
        duration_seconds: track.duration_seconds,
        position,
        added_at: timestamp,
        album_id: track.album_id.clone(),
        album_name: track.album_name.clone(),
        cover_art_id: track.cover_art_id.clone(),
        cover_art_uri: track.cover_art_uri.clone(),
        suffix: track.suffix.clone(),
    }
}

fn save_downloads(
    app: &tauri::AppHandle,
    downloads: &[DownloadedTrackOutput],
) -> Result<(), String> {
    let mut connection = open_download_database(app)?;
    let transaction = connection
        .transaction()
        .map_err(|error| error.to_string())?;
    let mut sorted = downloads.to_vec();
    sorted.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    transaction
        .execute("DELETE FROM downloaded_tracks", [])
        .map_err(|error| error.to_string())?;
    {
        let mut statement = transaction
            .prepare(
                r#"
                INSERT INTO downloaded_tracks (
                  track_id, title, artist, track_number, duration_seconds,
                  local_path, state, updated_at, album_id, album_name, cover_art_uri,
                  local_cover_path, suffix, bytes, received_bytes, total_bytes, error_message
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
                "#,
            )
            .map_err(|error| error.to_string())?;
        for download in &sorted {
            statement
                .execute(params![
                    download.track_id,
                    download.title,
                    download.artist,
                    download.track_number,
                    download.duration_seconds,
                    download.local_path,
                    download.state,
                    download.updated_at,
                    download.album_id,
                    download.album_name,
                    download.cover_art_uri,
                    download.local_cover_path,
                    download.suffix,
                    option_u64_to_i64(download.bytes)?,
                    option_u64_to_i64(download.received_bytes)?,
                    option_u64_to_i64(download.total_bytes)?,
                    download.error_message,
                ])
                .map_err(|error| error.to_string())?;
        }
    }
    transaction.commit().map_err(|error| error.to_string())?;
    write_folder_manifests(&sorted)?;
    Ok(())
}

fn repair_downloads(app: &tauri::AppHandle) -> Result<Vec<DownloadedTrackOutput>, String> {
    Ok(repair_downloads_with_result(app)?.tracks)
}

fn repair_downloads_with_result(
    app: &tauri::AppHandle,
) -> Result<DownloadRepairResultOutput, String> {
    let mut repaired = Vec::new();
    let mut removed_downloads = Vec::new();
    let mut removed_audio_count = 0_i64;
    let mut cleared_cover_count = 0_i64;
    let mut recovered_cover_count = 0_i64;
    for mut download in load_downloads_from_disk(app)? {
        if download.state == "downloading" {
            download.state = "failed".to_string();
            download.error_message = Some("Download was interrupted.".to_string());
        }
        if download.state == "complete" && !is_usable_file(&download.local_path, download.bytes) {
            delete_file_if_present(&download.local_path)?;
            delete_file_if_present(&format!("{}.partial", download.local_path))?;
            removed_downloads.push(download);
            removed_audio_count += 1;
            continue;
        }
        if let Some(cover_path) = download
            .local_cover_path
            .as_ref()
            .filter(|path| !path.is_empty())
        {
            if !is_usable_file(cover_path, None) {
                if let Some(recovered_path) = recover_album_cover_path(&download) {
                    download.local_cover_path = Some(recovered_path);
                    recovered_cover_count += 1;
                } else {
                    download.local_cover_path = None;
                    cleared_cover_count += 1;
                }
            }
        } else if let Some(cover_path) = recover_album_cover_path(&download) {
            download.local_cover_path = Some(cover_path);
            recovered_cover_count += 1;
        }
        repaired.push(download);
    }
    for removed_download in &removed_downloads {
        let removed_cover_path = cover_path_for_download(removed_download);
        let keep_cover = removed_cover_path.as_ref().is_some_and(|cover_path| {
            repaired
                .iter()
                .any(|download| cover_path_for_download(download).as_ref() == Some(cover_path))
        });
        if !keep_cover {
            if let Some(cover_path) = removed_cover_path {
                delete_file_if_present(&cover_path)?;
                delete_file_if_present(&format!("{cover_path}.partial"))?;
            }
        }
        cleanup_unused_download_directory(&removed_download.local_path, &repaired)?;
    }
    save_downloads(app, &repaired)?;
    Ok(DownloadRepairResultOutput {
        tracks: repaired,
        removed_audio_count,
        cleared_cover_count,
        recovered_cover_count,
        downloaded_cover_count: 0,
    })
}

async fn repair_missing_album_covers(
    app: &tauri::AppHandle,
    mut result: DownloadRepairResultOutput,
) -> Result<DownloadRepairResultOutput, String> {
    let mut downloaded_cover_count = 0_i64;
    let mut changed_cover_metadata = false;
    let mut cover_paths_by_folder = std::collections::BTreeMap::<PathBuf, String>::new();

    for download in &mut result.tracks {
        if download.state != "complete"
            || download
                .local_cover_path
                .as_ref()
                .is_some_and(|path| !path.is_empty())
            || download
                .cover_art_uri
                .as_ref()
                .is_none_or(|uri| uri.is_empty())
            || !is_usable_file(&download.local_path, download.bytes)
        {
            continue;
        }

        let album_folder = match PathBuf::from(&download.local_path).parent() {
            Some(folder) => folder.to_path_buf(),
            None => continue,
        };

        if let Some(existing_cover_path) = cover_paths_by_folder.get(&album_folder) {
            download.local_cover_path = Some(existing_cover_path.clone());
            changed_cover_metadata = true;
            continue;
        }

        if let Some(recovered_path) = recover_album_cover_path(download) {
            cover_paths_by_folder.insert(album_folder, recovered_path.clone());
            download.local_cover_path = Some(recovered_path);
            result.recovered_cover_count += 1;
            changed_cover_metadata = true;
            continue;
        }

        let track = track_output_from_download(download.clone());
        if let Ok(downloaded_path) = ensure_album_cover(app, &track).await {
            cover_paths_by_folder.insert(album_folder, downloaded_path.clone());
            download.local_cover_path = Some(downloaded_path);
            downloaded_cover_count += 1;
            changed_cover_metadata = true;
        }
    }

    if downloaded_cover_count > 0 {
        result.downloaded_cover_count += downloaded_cover_count;
    }
    if changed_cover_metadata {
        save_downloads(app, &result.tracks)?;
    }

    Ok(result)
}

fn complete_download_for_track(
    app: &tauri::AppHandle,
    track_id: &str,
) -> Result<Option<DownloadedTrackOutput>, String> {
    Ok(repair_downloads(app)?.into_iter().find(|download| {
        download.track_id == track_id
            && download.state == "complete"
            && is_usable_file(&download.local_path, download.bytes)
    }))
}

fn downloaded_album_details(app: &tauri::AppHandle) -> Result<Vec<AlbumDetailOutput>, String> {
    let mut grouped: std::collections::BTreeMap<String, Vec<DownloadedTrackOutput>> =
        std::collections::BTreeMap::new();
    for download in repair_downloads(app)? {
        if download.state != "complete" || !is_usable_file(&download.local_path, download.bytes) {
            continue;
        }
        let key = download
            .album_id
            .clone()
            .or_else(|| download.album_name.clone())
            .unwrap_or_else(|| "downloads".to_string());
        grouped.entry(key).or_default().push(download);
    }

    let mut details = Vec::new();
    for (key, mut tracks) in grouped {
        tracks.sort_by(|left, right| {
            left.track_number
                .cmp(&right.track_number)
                .then_with(|| left.title.cmp(&right.title))
        });
        let Some(first) = tracks.first().cloned() else {
            continue;
        };
        let duration_seconds = tracks
            .iter()
            .map(|track| track.duration_seconds)
            .sum::<i64>();
        let album = AlbumOutput {
            id: first.album_id.clone().unwrap_or(key),
            name: first
                .album_name
                .clone()
                .unwrap_or_else(|| "Downloads".to_string()),
            artist: first.artist.clone(),
            song_count: tracks.len() as i64,
            duration_seconds,
            cover_art_id: None,
            cover_art_uri: cover_path_for_download(&first)
                .filter(|path| is_usable_file(path, None))
                .map(|path| format!("file://{path}"))
                .or(first.cover_art_uri.clone()),
            year: None,
        };
        let output_tracks = tracks
            .into_iter()
            .map(track_output_from_download)
            .collect::<Vec<_>>();
        details.push(AlbumDetailOutput {
            album,
            tracks: output_tracks,
        });
    }
    details.sort_by(|left, right| left.album.name.cmp(&right.album.name));
    Ok(details)
}

fn search_downloaded_details(
    app: &tauri::AppHandle,
    query: &str,
) -> Result<LibrarySearchResultOutput, String> {
    let lower_query = query.to_lowercase();
    let trimmed_lower_query = lower_query.trim();
    let normalized_query = normalize_search_text(query);
    if trimmed_lower_query.len() < 2 {
        return Ok(LibrarySearchResultOutput {
            albums: Vec::new(),
            tracks: Vec::new(),
        });
    }

    let mut albums = Vec::new();
    let mut tracks = Vec::new();
    for detail in downloaded_album_details(app)? {
        if matches_search(
            trimmed_lower_query,
            &normalized_query,
            &detail.album.name,
            Some(&detail.album.artist),
            None,
        ) {
            albums.push(detail.album.clone());
        }

        for track in detail.tracks {
            if matches_search(
                trimmed_lower_query,
                &normalized_query,
                &track.title,
                Some(&track.artist),
                track.album_name.as_deref(),
            ) {
                tracks.push(track);
            }
        }
    }

    Ok(LibrarySearchResultOutput { albums, tracks })
}

fn matches_search(
    lower_query: &str,
    normalized_query: &str,
    first: &str,
    second: Option<&str>,
    third: Option<&str>,
) -> bool {
    let values = [Some(first), second, third];
    values
        .iter()
        .flatten()
        .any(|value| value.to_lowercase().contains(lower_query))
        || (!normalized_query.is_empty()
            && values
                .iter()
                .flatten()
                .any(|value| normalize_search_text(value).contains(normalized_query)))
}

fn normalize_search_text(value: &str) -> String {
    let mut output = String::new();
    let mut last_was_separator = false;
    for character in value.to_lowercase().chars() {
        let is_separator = character.is_whitespace()
            || matches!(
                character,
                '-' | '_' | '.' | ',' | ':' | ';' | '(' | ')' | '[' | ']' | '{' | '}'
            );
        if is_separator {
            if !last_was_separator && !output.is_empty() {
                output.push(' ');
                last_was_separator = true;
            }
        } else {
            output.push(character);
            last_was_separator = false;
        }
    }
    output.trim().to_string()
}

fn track_output_from_download(download: DownloadedTrackOutput) -> TrackOutput {
    let cover_art_uri = cover_path_for_download(&download)
        .filter(|path| is_usable_file(path, None))
        .map(|path| format!("file://{path}"))
        .or_else(|| download.cover_art_uri.clone());
    TrackOutput {
        id: download.track_id,
        title: download.title,
        artist: download.artist,
        track_number: download.track_number,
        duration_seconds: download.duration_seconds,
        album_id: download.album_id,
        album_name: download.album_name,
        cover_art_id: None,
        cover_art_uri,
        suffix: download.suffix,
    }
}

fn upsert_download(
    downloads: Vec<DownloadedTrackOutput>,
    item: DownloadedTrackOutput,
) -> Vec<DownloadedTrackOutput> {
    let mut next = vec![item.clone()];
    next.extend(
        downloads
            .into_iter()
            .filter(|download| download.track_id != item.track_id),
    );
    next.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    next
}

fn downloaded_track_from_track(
    track: &TrackOutput,
    local_path: &str,
    state: &str,
) -> DownloadedTrackOutput {
    DownloadedTrackOutput {
        track_id: track.id.clone(),
        title: track.title.clone(),
        artist: track.artist.clone(),
        track_number: track.track_number,
        duration_seconds: track.duration_seconds,
        local_path: local_path.to_string(),
        state: state.to_string(),
        updated_at: now_timestamp(),
        album_id: track.album_id.clone(),
        album_name: track.album_name.clone(),
        cover_art_uri: track.cover_art_uri.clone(),
        local_cover_path: None,
        suffix: track.suffix.clone(),
        bytes: None,
        received_bytes: None,
        total_bytes: None,
        error_message: None,
    }
}

fn local_path_for_track(app: &tauri::AppHandle, track: &TrackOutput) -> Result<String, String> {
    let directory = album_directory_for_track(app, track)?;
    let extension = clean_extension(track.suffix.as_deref());
    let title = safe_filename(&track.title);
    let number = if track.track_number > 0 {
        format!("{:02} - ", track.track_number)
    } else {
        String::new()
    };
    let filename = if let Some(extension) = extension {
        format!("{number}{title} - {}.{extension}", track.id)
    } else {
        format!("{number}{title} - {}", track.id)
    };
    Ok(directory
        .join(safe_filename(&filename))
        .to_string_lossy()
        .to_string())
}

fn local_cover_path_for_track(
    app: &tauri::AppHandle,
    track: &TrackOutput,
) -> Result<String, String> {
    Ok(album_directory_for_track(app, track)?
        .join("cover.jpg")
        .to_string_lossy()
        .to_string())
}

fn album_directory_for_track(
    app: &tauri::AppHandle,
    track: &TrackOutput,
) -> Result<PathBuf, String> {
    let root = active_download_folder(app)?;
    album_directory_for_track_in_root(track, &root)
}

fn album_directory_for_track_in_root(
    track: &TrackOutput,
    root: &PathBuf,
) -> Result<PathBuf, String> {
    let album_name = track.album_name.as_deref().unwrap_or("Unknown Album");
    let artist_folder_name = safe_filename(&track.artist);
    let album_folder_name = safe_filename(album_name);
    let directory = root.join(artist_folder_name).join(album_folder_name);
    fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
    Ok(directory)
}

fn local_path_for_track_in_directory(track: &TrackOutput, directory: &PathBuf) -> String {
    let extension = clean_extension(track.suffix.as_deref());
    let title = safe_filename(&track.title);
    let number = if track.track_number > 0 {
        format!("{:02} - ", track.track_number)
    } else {
        String::new()
    };
    let filename = if let Some(extension) = extension {
        format!("{number}{title} - {}.{extension}", track.id)
    } else {
        format!("{number}{title} - {}", track.id)
    };
    directory
        .join(safe_filename(&filename))
        .to_string_lossy()
        .to_string()
}

fn move_downloads_to_root(
    app: &tauri::AppHandle,
    target_root: PathBuf,
) -> Result<DownloadFolderMoveResultOutput, String> {
    fs::create_dir_all(&target_root).map_err(|error| error.to_string())?;
    let downloads = repair_downloads(app)?;
    let mut moved_downloads = Vec::new();
    let mut moved_cover_paths = std::collections::BTreeMap::<String, String>::new();
    let mut moved_audio_count = 0_i64;
    let mut moved_cover_count = 0_i64;
    let mut skipped_count = 0_i64;

    for download in downloads {
        let track = track_output_from_download(download.clone());
        let destination_directory = album_directory_for_track_in_root(&track, &target_root)?;
        let destination_audio_path =
            local_path_for_track_in_directory(&track, &destination_directory);
        let mut next_download = DownloadedTrackOutput {
            local_path: destination_audio_path.clone(),
            updated_at: now_timestamp(),
            ..download.clone()
        };

        if download.state == "complete" {
            let copied_audio = copy_verified_file(
                &download.local_path,
                &destination_audio_path,
                download.bytes,
            )?;
            if copied_audio {
                moved_audio_count += 1;
                delete_file_if_different(&download.local_path, &destination_audio_path)?;
                delete_file_if_present(&format!("{}.partial", download.local_path))?;
            } else {
                skipped_count += 1;
                moved_downloads.push(download);
                continue;
            }
        } else {
            delete_file_if_present(&format!("{}.partial", download.local_path))?;
        }

        if let Some(cover_path) =
            cover_path_for_download(&download).filter(|path| is_usable_file(path, None))
        {
            let destination_cover_path = destination_directory
                .join("cover.jpg")
                .to_string_lossy()
                .to_string();
            if let Some(existing_destination) = moved_cover_paths.get(&cover_path) {
                next_download.local_cover_path = Some(existing_destination.clone());
            } else if copy_verified_file(&cover_path, &destination_cover_path, None)? {
                moved_cover_count += 1;
                moved_cover_paths.insert(cover_path.clone(), destination_cover_path.clone());
                delete_file_if_different(&cover_path, &destination_cover_path)?;
                delete_file_if_present(&format!("{cover_path}.partial"))?;
                next_download.local_cover_path = Some(destination_cover_path);
            } else {
                next_download.local_cover_path = None;
            }
        }

        moved_downloads.push(next_download);
    }

    save_downloads(app, &moved_downloads)?;
    Ok(DownloadFolderMoveResultOutput {
        moved_audio_count,
        moved_cover_count,
        skipped_count,
        total_count: moved_downloads.len() as i64,
    })
}

fn cover_path_for_download(download: &DownloadedTrackOutput) -> Option<String> {
    if let Some(path) = download
        .local_cover_path
        .as_ref()
        .filter(|path| !path.is_empty())
    {
        return Some(path.clone());
    }
    if download.local_path.is_empty() {
        return None;
    }
    PathBuf::from(&download.local_path)
        .parent()
        .map(|parent| parent.join("cover.jpg").to_string_lossy().to_string())
}

fn recover_album_cover_path(download: &DownloadedTrackOutput) -> Option<String> {
    if download.local_path.is_empty() {
        return None;
    }
    PathBuf::from(&download.local_path)
        .parent()
        .map(|parent| parent.join("cover.jpg").to_string_lossy().to_string())
        .filter(|path| is_usable_file(path, None))
}

fn write_folder_manifests(downloads: &[DownloadedTrackOutput]) -> Result<(), String> {
    let mut groups: std::collections::BTreeMap<PathBuf, Vec<DownloadedTrackOutput>> =
        std::collections::BTreeMap::new();
    for download in downloads {
        if download.local_path.is_empty() {
            continue;
        }
        if let Some(parent) = PathBuf::from(&download.local_path).parent() {
            groups
                .entry(parent.to_path_buf())
                .or_default()
                .push(download.clone());
        }
    }
    for (directory, tracks) in groups {
        if !directory.exists() {
            continue;
        }
        let manifest = directory.join(DOWNLOADS_MANIFEST_FILE_NAME);
        let json = serde_json::to_string_pretty(&tracks).map_err(|error| error.to_string())?;
        fs::write(manifest, json).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn cleanup_unused_download_directory(
    local_path: &str,
    remaining_downloads: &[DownloadedTrackOutput],
) -> Result<(), String> {
    if local_path.is_empty() {
        return Ok(());
    }
    let Some(directory) = PathBuf::from(local_path)
        .parent()
        .map(|path| path.to_path_buf())
    else {
        return Ok(());
    };
    let is_still_used = remaining_downloads.iter().any(|download| {
        if download.local_path.is_empty() {
            return false;
        }
        PathBuf::from(&download.local_path)
            .parent()
            .is_some_and(|parent| parent == directory)
    });
    if is_still_used {
        return Ok(());
    }

    delete_file_if_present(
        &directory
            .join(DOWNLOADS_MANIFEST_FILE_NAME)
            .to_string_lossy(),
    )?;
    remove_directory_if_empty(&directory)?;
    if let Some(parent) = directory.parent() {
        remove_directory_if_empty(parent)?;
    }
    Ok(())
}

fn remove_directory_if_empty(directory: &std::path::Path) -> Result<(), String> {
    if !directory.exists() {
        return Ok(());
    }
    let mut entries = fs::read_dir(directory).map_err(|error| error.to_string())?;
    if entries.next().is_none() {
        fs::remove_dir(directory).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn export_request_has_usable_local_download(request: &ExportTrackInput) -> bool {
    request.local_download.as_ref().is_some_and(|download| {
        download.state == "complete" && is_usable_file(&download.local_path, download.bytes)
    })
}

fn insert_export_request(
    unique_tracks: &mut std::collections::BTreeMap<String, ExportTrackInput>,
    request: ExportTrackInput,
) {
    let new_has_local = export_request_has_usable_local_download(&request);
    match unique_tracks.get(&request.track.id) {
        Some(existing) if export_request_has_usable_local_download(existing) || !new_has_local => {}
        _ => {
            unique_tracks.insert(request.track.id.clone(), request);
        }
    }
}

fn export_selection_needs_remote(
    direct_tracks: &[ExportTrackInput],
    playlists: &[ExportPlaylistInput],
) -> bool {
    let mut selected_track_has_local = std::collections::BTreeMap::<String, bool>::new();
    for request in direct_tracks {
        let has_local = export_request_has_usable_local_download(request);
        selected_track_has_local
            .entry(request.track.id.clone())
            .and_modify(|current| *current = *current || has_local)
            .or_insert(has_local);
    }
    for playlist in playlists {
        for request in &playlist.tracks {
            let has_local = export_request_has_usable_local_download(request);
            selected_track_has_local
                .entry(request.track.id.clone())
                .and_modify(|current| *current = *current || has_local)
                .or_insert(has_local);
        }
    }
    selected_track_has_local
        .values()
        .any(|has_local| !has_local)
}

async fn export_selected_music(
    target: &PathBuf,
    profile: Option<&SavedServerProfile>,
    direct_tracks: Vec<ExportTrackInput>,
    playlists: Vec<ExportPlaylistInput>,
) -> Result<MusicExportResultOutput, String> {
    let mut unique_tracks = std::collections::BTreeMap::<String, ExportTrackInput>::new();
    for request in direct_tracks {
        insert_export_request(&mut unique_tracks, request);
    }
    for playlist in &playlists {
        for request in &playlist.tracks {
            insert_export_request(&mut unique_tracks, request.clone());
        }
    }

    let mut sorted_tracks = unique_tracks.into_values().collect::<Vec<_>>();
    sorted_tracks.sort_by(|left, right| compare_tracks_for_export(&left.track, &right.track));

    let mut exported_by_id = std::collections::BTreeMap::<String, ExportedTrack>::new();
    let mut copied_cover_sources = std::collections::BTreeSet::<String>::new();
    let mut reserved_relative_paths = std::collections::BTreeSet::<String>::new();
    let mut artifact_relative_paths = std::collections::BTreeSet::<String>::new();
    let mut copied_track_count = 0_i64;
    let mut downloaded_track_count = 0_i64;
    let mut copied_cover_count = 0_i64;
    let mut downloaded_cover_count = 0_i64;
    let mut skipped_track_count = 0_i64;
    let mut collision_count = 0_i64;

    for request in sorted_tracks {
        let track = request.track;
        let album_directory = target
            .join("Music")
            .join(safe_filename(&track.artist))
            .join(safe_filename(
                track.album_name.as_deref().unwrap_or("Unknown Album"),
            ));
        fs::create_dir_all(&album_directory).map_err(|error| error.to_string())?;
        let destination = unique_export_destination_for_track(
            target,
            &album_directory,
            &track,
            &mut reserved_relative_paths,
        )?;
        if export_filename_for_track(&track)
            != destination
                .file_name()
                .map(|value| value.to_string_lossy().to_string())
                .unwrap_or_default()
        {
            collision_count += 1;
        }

        let mut did_export_track = false;
        if let Some(local_download) = request.local_download.as_ref() {
            if local_download.state == "complete"
                && is_usable_file(&local_download.local_path, local_download.bytes)
            {
                fs::copy(&local_download.local_path, &destination)
                    .map_err(|error| error.to_string())?;
                copied_track_count += 1;
                did_export_track = true;
            }
        }

        if !did_export_track {
            let Some(profile) = profile else {
                skipped_track_count += 1;
                continue;
            };
            let partial_destination = destination.with_extension(format!(
                "{}partial",
                destination
                    .extension()
                    .map(|extension| format!("{}.", extension.to_string_lossy()))
                    .unwrap_or_default()
            ));
            delete_file_if_present(&partial_destination.to_string_lossy())?;
            let bytes = download_track_bytes(profile, &track.id).await?;
            if !bytes.is_empty() {
                fs::write(&partial_destination, bytes).map_err(|error| error.to_string())?;
                delete_file_if_present(&destination.to_string_lossy())?;
                fs::rename(&partial_destination, &destination)
                    .map_err(|error| error.to_string())?;
                downloaded_track_count += 1;
                did_export_track = true;
            }
        }

        if !did_export_track {
            skipped_track_count += 1;
            continue;
        }

        let relative_path = relative_export_path(target, &destination)?;
        artifact_relative_paths.insert(relative_path.clone());
        exported_by_id.insert(
            track.id.clone(),
            ExportedTrack {
                title: track.title.clone(),
                artist: track.artist.clone(),
                duration_seconds: track.duration_seconds,
                relative_path,
            },
        );

        let destination_cover = album_directory.join("cover.jpg");
        if let Some(local_download) = request.local_download.as_ref() {
            if let Some(cover_path) = cover_path_for_download(local_download)
                .filter(|path| !copied_cover_sources.contains(path) && is_usable_file(path, None))
            {
                fs::copy(&cover_path, &destination_cover).map_err(|error| error.to_string())?;
                artifact_relative_paths.insert(relative_export_path(target, &destination_cover)?);
                copied_cover_sources.insert(cover_path);
                copied_cover_count += 1;
                continue;
            }
        }

        if !is_usable_file(&destination_cover.to_string_lossy(), None) {
            if let Some(cover_uri) = track
                .cover_art_uri
                .as_ref()
                .filter(|value| !value.is_empty())
            {
                if download_export_cover(cover_uri, &destination_cover).await? {
                    artifact_relative_paths
                        .insert(relative_export_path(target, &destination_cover)?);
                    downloaded_cover_count += 1;
                }
            }
        }
    }

    let playlists_directory = target.join("Playlists");
    let mut playlist_count = 0_i64;
    let mut playlist_entry_count = 0_i64;
    let mut skipped_playlist_entry_count = 0_i64;
    for playlist in playlists {
        let mut exported_tracks = Vec::<ExportedTrack>::new();
        for request in playlist.tracks {
            if let Some(exported) = exported_by_id.get(&request.track.id) {
                exported_tracks.push(exported.clone());
            } else {
                skipped_playlist_entry_count += 1;
            }
        }
        if exported_tracks.is_empty() {
            continue;
        }
        fs::create_dir_all(&playlists_directory).map_err(|error| error.to_string())?;
        let playlist_path =
            playlists_directory.join(format!("{}.m3u", safe_filename(&playlist.name)));
        write_m3u(&playlist_path, &exported_tracks)?;
        artifact_relative_paths.insert(relative_export_path(target, &playlist_path)?);
        playlist_count += 1;
        playlist_entry_count += exported_tracks.len() as i64;
    }

    let manifest_paths = artifact_relative_paths.into_iter().collect::<Vec<_>>();
    write_export_manifest(target, manifest_paths)?;

    let exported_track_count = copied_track_count + downloaded_track_count;
    Ok(MusicExportResultOutput {
        exported_track_count,
        copied_track_count,
        downloaded_track_count,
        copied_cover_count,
        downloaded_cover_count,
        skipped_track_count,
        playlist_count,
        playlist_entry_count,
        skipped_playlist_entry_count,
        collision_count,
        message: format!(
            "Exported {exported_track_count} tracks ({copied_track_count} copied, {downloaded_track_count} downloaded), {playlist_count} playlists, {skipped_track_count} skipped tracks, {skipped_playlist_entry_count} skipped playlist entries, and {collision_count} filename fixes."
        ),
    })
}

async fn download_export_cover(cover_uri: &str, destination: &PathBuf) -> Result<bool, String> {
    let partial_path = destination.with_file_name(format!(
        "{}.partial",
        destination
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_else(|| "cover.jpg".to_string())
    ));
    delete_file_if_present(&partial_path.to_string_lossy())?;
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .get(cover_uri)
        .send()
        .await
        .map_err(format_reqwest_error)?;
    if !response.status().is_success() {
        return Ok(false);
    }
    let bytes = response.bytes().await.map_err(|error| error.to_string())?;
    if bytes.is_empty() {
        return Ok(false);
    }
    fs::write(&partial_path, bytes).map_err(|error| error.to_string())?;
    delete_file_if_present(&destination.to_string_lossy())?;
    fs::rename(&partial_path, destination).map_err(|error| error.to_string())?;
    Ok(true)
}

fn export_complete_downloads(
    target: &PathBuf,
    downloads: &[DownloadedTrackOutput],
    liked_tracks: &[LikedTrackOutput],
    playlist_store: &PlaylistStore,
) -> Result<MusicExportResultOutput, String> {
    let complete_downloads = downloads
        .iter()
        .filter(|download| {
            download.state == "complete" && is_usable_file(&download.local_path, download.bytes)
        })
        .cloned()
        .collect::<Vec<_>>();
    let mut exported_by_id = std::collections::BTreeMap::<String, ExportedTrack>::new();
    let mut reserved_relative_paths = std::collections::BTreeSet::<String>::new();
    let mut artifact_relative_paths = std::collections::BTreeSet::<String>::new();
    let mut copied_cover_sources = std::collections::BTreeSet::<String>::new();
    let mut exported_track_count = 0_i64;
    let mut copied_cover_count = 0_i64;
    let mut skipped_track_count = 0_i64;
    let mut collision_count = 0_i64;

    let mut sorted_downloads = complete_downloads;
    sorted_downloads.sort_by(compare_downloads_for_export);
    for download in sorted_downloads {
        let source = PathBuf::from(&download.local_path);
        if !is_usable_file(&download.local_path, download.bytes) {
            skipped_track_count += 1;
            continue;
        }
        let album_directory = target
            .join("Music")
            .join(safe_filename(&download.artist))
            .join(safe_filename(
                download.album_name.as_deref().unwrap_or("Unknown Album"),
            ));
        fs::create_dir_all(&album_directory).map_err(|error| error.to_string())?;
        let destination = unique_export_destination(
            target,
            &album_directory,
            &download,
            &mut reserved_relative_paths,
        )?;
        if export_filename_for_download(&download)
            != destination
                .file_name()
                .map(|value| value.to_string_lossy().to_string())
                .unwrap_or_default()
        {
            collision_count += 1;
        }
        fs::copy(&source, &destination).map_err(|error| error.to_string())?;
        let relative_path = relative_export_path(target, &destination)?;
        artifact_relative_paths.insert(relative_path.clone());
        exported_by_id.insert(
            download.track_id.clone(),
            ExportedTrack {
                title: download.title.clone(),
                artist: download.artist.clone(),
                duration_seconds: download.duration_seconds,
                relative_path,
            },
        );
        exported_track_count += 1;

        if let Some(cover_path) = cover_path_for_download(&download)
            .filter(|path| !copied_cover_sources.contains(path) && is_usable_file(path, None))
        {
            let destination_cover = album_directory.join("cover.jpg");
            fs::copy(&cover_path, &destination_cover).map_err(|error| error.to_string())?;
            artifact_relative_paths.insert(relative_export_path(target, &destination_cover)?);
            copied_cover_sources.insert(cover_path);
            copied_cover_count += 1;
        }
    }

    let mut playlist_count = 0_i64;
    let mut playlist_entry_count = 0_i64;
    let mut skipped_playlist_entry_count = 0_i64;

    let all_downloads_tracks = exported_by_id.values().cloned().collect::<Vec<_>>();
    if !all_downloads_tracks.is_empty() {
        let playlist_path = target.join(format!(
            "{}.m3u",
            safe_filename(ALL_DOWNLOADS_PLAYLIST_NAME)
        ));
        write_m3u(&playlist_path, &all_downloads_tracks)?;
        artifact_relative_paths.insert(relative_export_path(target, &playlist_path)?);
        playlist_count += 1;
        playlist_entry_count += all_downloads_tracks.len() as i64;
    }

    let liked_exported = liked_tracks
        .iter()
        .filter_map(|liked| exported_by_id.get(&liked.track_id).cloned())
        .collect::<Vec<_>>();
    if !liked_exported.is_empty() {
        let playlist_path = target.join(format!("{}.m3u", safe_filename(LIKED_PLAYLIST_NAME)));
        write_m3u(&playlist_path, &liked_exported)?;
        artifact_relative_paths.insert(relative_export_path(target, &playlist_path)?);
        playlist_count += 1;
        playlist_entry_count += liked_exported.len() as i64;
    }
    skipped_playlist_entry_count += liked_tracks
        .iter()
        .filter(|liked| !exported_by_id.contains_key(&liked.track_id))
        .count() as i64;

    let playlists_directory = target.join("Playlists");
    for playlist in playlists_with_counts(playlist_store) {
        let mut playlist_tracks = playlist_tracks_for_store(playlist_store, &playlist.id)?;
        normalize_playlist_track_positions(&mut playlist_tracks);
        let mut exported_tracks = Vec::new();
        for track in playlist_tracks {
            if let Some(exported) = exported_by_id.get(&track.track_id) {
                exported_tracks.push(exported.clone());
            } else {
                skipped_playlist_entry_count += 1;
            }
        }
        if exported_tracks.is_empty() {
            continue;
        }
        fs::create_dir_all(&playlists_directory).map_err(|error| error.to_string())?;
        let playlist_path =
            playlists_directory.join(format!("{}.m3u", safe_filename(&playlist.name)));
        write_m3u(&playlist_path, &exported_tracks)?;
        artifact_relative_paths.insert(relative_export_path(target, &playlist_path)?);
        playlist_count += 1;
        playlist_entry_count += exported_tracks.len() as i64;
    }

    let manifest_paths = artifact_relative_paths.into_iter().collect::<Vec<_>>();
    write_export_manifest(target, manifest_paths)?;

    Ok(MusicExportResultOutput {
        exported_track_count,
        copied_track_count: exported_track_count,
        downloaded_track_count: 0,
        copied_cover_count,
        downloaded_cover_count: 0,
        skipped_track_count,
        playlist_count,
        playlist_entry_count,
        skipped_playlist_entry_count,
        collision_count,
        message: format!(
            "Exported {exported_track_count} local tracks, {playlist_count} playlists, {skipped_track_count} skipped tracks, {skipped_playlist_entry_count} skipped playlist entries, and {collision_count} filename fixes."
        ),
    })
}

#[derive(Debug, Clone)]
struct ExportedTrack {
    title: String,
    artist: String,
    duration_seconds: i64,
    relative_path: String,
}

fn write_m3u(path: &PathBuf, tracks: &[ExportedTrack]) -> Result<(), String> {
    let mut lines = vec!["#EXTM3U".to_string()];
    for track in tracks {
        lines.push(format!(
            "#EXTINF:{},{} - {}",
            track.duration_seconds, track.artist, track.title
        ));
        lines.push(track.relative_path.clone());
    }
    fs::write(path, format!("{}\n", lines.join("\n"))).map_err(|error| error.to_string())
}

fn compare_downloads_for_export(
    left: &DownloadedTrackOutput,
    right: &DownloadedTrackOutput,
) -> std::cmp::Ordering {
    left.artist
        .cmp(&right.artist)
        .then_with(|| left.album_name.cmp(&right.album_name))
        .then_with(|| left.track_number.cmp(&right.track_number))
        .then_with(|| left.title.cmp(&right.title))
}

fn compare_tracks_for_export(left: &TrackOutput, right: &TrackOutput) -> std::cmp::Ordering {
    left.artist
        .cmp(&right.artist)
        .then_with(|| left.album_name.cmp(&right.album_name))
        .then_with(|| left.track_number.cmp(&right.track_number))
        .then_with(|| left.title.cmp(&right.title))
}

fn unique_export_destination(
    root: &PathBuf,
    album_directory: &PathBuf,
    download: &DownloadedTrackOutput,
    reserved_relative_paths: &mut std::collections::BTreeSet<String>,
) -> Result<PathBuf, String> {
    let filename = export_filename_for_download(download);
    let extension = clean_extension(download.suffix.as_deref());
    let stem = extension
        .as_ref()
        .and_then(|extension| filename.strip_suffix(&format!(".{extension}")))
        .unwrap_or(&filename)
        .to_string();
    for index in 0.. {
        let candidate_name = if index == 0 {
            filename.clone()
        } else if let Some(extension) = extension.as_ref() {
            format!("{stem} ({index}).{extension}")
        } else {
            format!("{stem} ({index})")
        };
        let candidate = album_directory.join(candidate_name);
        let relative = relative_export_path(root, &candidate)?;
        if reserved_relative_paths.insert(relative) {
            return Ok(candidate);
        }
    }
    Err("Could not choose an export filename.".to_string())
}

fn unique_export_destination_for_track(
    root: &PathBuf,
    album_directory: &PathBuf,
    track: &TrackOutput,
    reserved_relative_paths: &mut std::collections::BTreeSet<String>,
) -> Result<PathBuf, String> {
    let filename = export_filename_for_track(track);
    let extension = clean_extension(track.suffix.as_deref());
    let stem = extension
        .as_ref()
        .and_then(|extension| filename.strip_suffix(&format!(".{extension}")))
        .unwrap_or(&filename)
        .to_string();
    for index in 0.. {
        let candidate_name = if index == 0 {
            filename.clone()
        } else if let Some(extension) = extension.as_ref() {
            format!("{stem} ({index}).{extension}")
        } else {
            format!("{stem} ({index})")
        };
        let candidate = album_directory.join(candidate_name);
        let relative = relative_export_path(root, &candidate)?;
        if reserved_relative_paths.insert(relative) {
            return Ok(candidate);
        }
    }
    Err("Could not choose an export filename.".to_string())
}

fn export_filename_for_download(download: &DownloadedTrackOutput) -> String {
    export_filename_for_track(&TrackOutput {
        id: download.track_id.clone(),
        title: download.title.clone(),
        artist: download.artist.clone(),
        track_number: download.track_number,
        duration_seconds: download.duration_seconds,
        album_id: download.album_id.clone(),
        album_name: download.album_name.clone(),
        cover_art_id: None,
        cover_art_uri: download.cover_art_uri.clone(),
        suffix: download.suffix.clone(),
    })
}

fn export_filename_for_track(track: &TrackOutput) -> String {
    let extension = clean_extension(track.suffix.as_deref());
    let title = safe_filename(&track.title);
    let number = if track.track_number > 0 {
        format!("{:02} - ", track.track_number)
    } else {
        String::new()
    };
    if let Some(extension) = extension {
        safe_filename(&format!("{number}{title}.{extension}"))
    } else {
        safe_filename(&format!("{number}{title}"))
    }
}

fn relative_export_path(root: &PathBuf, file: &PathBuf) -> Result<String, String> {
    let relative = file.strip_prefix(root).map_err(|error| error.to_string())?;
    Ok(relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy().to_string())
        .collect::<Vec<_>>()
        .join("/"))
}

fn write_export_manifest(target: &PathBuf, relative_paths: Vec<String>) -> Result<(), String> {
    let paths = relative_paths
        .into_iter()
        .filter(|path| !path.is_empty() && !is_unsafe_relative_path(path))
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let manifest = serde_json::json!({
        "version": 1,
        "generatedBy": "NekoFM",
        "paths": paths,
    });
    let manifest_path = target.join(EXPORT_MANIFEST_FILE_NAME);
    let manifest_json =
        serde_json::to_string_pretty(&manifest).map_err(|error| error.to_string())?;
    fs::write(&manifest_path, manifest_json).map_err(|error| error.to_string())
}

fn read_export_manifest_paths(
    target: &PathBuf,
) -> Result<std::collections::BTreeSet<String>, String> {
    let manifest_path = target.join(EXPORT_MANIFEST_FILE_NAME);
    if !manifest_path.exists() {
        return Ok(std::collections::BTreeSet::new());
    }

    let json = fs::read_to_string(&manifest_path).map_err(|error| error.to_string())?;
    let Ok(value) = serde_json::from_str::<Value>(&json) else {
        return Ok(std::collections::BTreeSet::new());
    };
    let paths_value = match value {
        Value::Array(paths) => paths,
        Value::Object(mut object) => object
            .remove("paths")
            .and_then(|paths| paths.as_array().cloned())
            .unwrap_or_default(),
        _ => Vec::new(),
    };

    Ok(paths_value
        .into_iter()
        .filter_map(|path| path.as_str().map(ToString::to_string))
        .filter(|path| !is_unsafe_relative_path(path))
        .collect())
}

fn is_unsafe_relative_path(path: &str) -> bool {
    path.starts_with('/')
        || path.starts_with('\\')
        || path.split('/').any(|part| part == "..")
        || path.split('\\').any(|part| part == "..")
}

fn clean_export(target: &PathBuf) -> Result<i64, String> {
    let mut relative_paths = read_export_manifest_paths(target)?;
    relative_paths.insert(format!(
        "{}.m3u",
        safe_filename(ALL_DOWNLOADS_PLAYLIST_NAME)
    ));
    relative_paths.insert(format!("{}.m3u", safe_filename(LIKED_PLAYLIST_NAME)));
    relative_paths.insert(EXPORT_MANIFEST_FILE_NAME.to_string());

    let mut deleted_count = 0_i64;
    for relative_path in relative_paths {
        let relative = PathBuf::from(&relative_path);
        if relative
            .components()
            .any(|component| matches!(component, std::path::Component::ParentDir))
        {
            continue;
        }
        let candidate = target.join(&relative_path);
        if !candidate.starts_with(target) {
            continue;
        }
        match fs::remove_file(&candidate) {
            Ok(()) => deleted_count += 1,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.to_string()),
        }
    }
    Ok(deleted_count)
}

fn is_usable_file(path: &str, expected_bytes: Option<u64>) -> bool {
    if path.is_empty() {
        return false;
    }
    let Ok(metadata) = fs::metadata(path) else {
        return false;
    };
    let size = metadata.len();
    size > 0 && expected_bytes.is_none_or(|expected| expected == size)
}

fn delete_file_if_present(path: &str) -> Result<(), String> {
    if path.is_empty() {
        return Ok(());
    }
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.to_string()),
    }
}

fn delete_file_if_different(source_path: &str, destination_path: &str) -> Result<(), String> {
    if source_path == destination_path {
        return Ok(());
    }
    delete_file_if_present(source_path)
}

fn copy_verified_file(
    source_path: &str,
    destination_path: &str,
    expected_bytes: Option<u64>,
) -> Result<bool, String> {
    if !is_usable_file(source_path, expected_bytes) {
        return Ok(false);
    }
    if source_path == destination_path {
        return Ok(true);
    }
    if let Some(parent) = PathBuf::from(destination_path).parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::copy(source_path, destination_path).map_err(|error| error.to_string())?;
    Ok(is_usable_file(destination_path, expected_bytes))
}

fn safe_filename(value: &str) -> String {
    let mut output = String::new();
    let mut last_was_separator = false;
    for character in value.chars() {
        let is_allowed = character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-');
        if is_allowed {
            output.push(character);
            last_was_separator = false;
        } else if !last_was_separator {
            output.push('_');
            last_was_separator = true;
        }
    }
    let trimmed = output.trim_matches('_');
    if trimmed.is_empty() || trimmed == "." || trimmed == ".." {
        "track".to_string()
    } else {
        trimmed.to_string()
    }
}

fn clean_extension(value: Option<&str>) -> Option<String> {
    let extension = value?
        .to_lowercase()
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .collect::<String>();
    if extension.is_empty() {
        None
    } else {
        Some(extension)
    }
}

fn now_timestamp() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("{seconds}")
}

fn string_value(value: Option<&Value>, fallback: &str) -> String {
    value
        .and_then(Value::as_str)
        .map(ToString::to_string)
        .or_else(|| value.map(|item| item.to_string()))
        .filter(|item| !item.is_empty())
        .unwrap_or_else(|| fallback.to_string())
}

fn optional_string(value: Option<&Value>) -> Option<String> {
    let text = string_value(value, "");
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

fn int_value(value: Option<&Value>) -> i64 {
    match value {
        Some(Value::Number(number)) => number.as_i64().unwrap_or_else(|| {
            number
                .as_f64()
                .map(|value| value as i64)
                .unwrap_or_default()
        }),
        Some(Value::String(text)) => text.parse::<i64>().unwrap_or_default(),
        _ => 0,
    }
}

fn server_scan_message(is_scanning: bool, scanned_count: i64) -> String {
    if is_scanning {
        if scanned_count > 0 {
            return format!("Server scan started. {scanned_count} items scanned so far.");
        }
        return "Server scan started.".to_string();
    }
    if scanned_count > 0 {
        return format!("Server scan finished. {scanned_count} items checked.");
    }
    "Server scan request was accepted.".to_string()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(SessionProfileState::default())
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            choose_download_folder,
            choose_export_folder,
            add_track_to_playlist,
            create_playlist,
            delete_playlist,
            open_download_folder,
            get_album,
            get_albums,
            get_playback_source,
            get_stream_uri,
            has_existing_export,
            load_downloaded_album_details,
            load_download_folder,
            load_downloads,
            load_liked_tracks,
            load_playback_preferences,
            load_playlist_tracks,
            load_playlists,
            load_server_profile,
            delete_download,
            download_track,
            export_local_music,
            export_music_selection,
            move_downloads_to_default_folder,
            move_downloads_to_folder,
            remove_playlist_entry,
            recheck_downloads,
            reorder_liked_tracks,
            reorder_playlist_tracks,
            rename_playlist,
            reset_download_folder,
            save_download_folder,
            save_previous_track_threshold,
            search_downloaded_library,
            search_library,
            start_server_scan,
            start_server_scan_with_profile,
            test_server_connection,
            toggle_liked_track,
            unlike_track
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_export_dir(name: &str) -> PathBuf {
        let directory =
            std::env::temp_dir().join(format!("nekofm-export-test-{name}-{}", now_timestamp()));
        fs::create_dir_all(&directory).expect("create temp export dir");
        directory
    }

    fn temp_download_dir(name: &str) -> PathBuf {
        let directory =
            std::env::temp_dir().join(format!("nekofm-download-test-{name}-{}", now_timestamp()));
        fs::create_dir_all(&directory).expect("create temp download dir");
        directory
    }

    fn test_download(track_id: &str, local_path: &PathBuf) -> DownloadedTrackOutput {
        DownloadedTrackOutput {
            track_id: track_id.to_string(),
            title: format!("Song {track_id}"),
            artist: "Artist".to_string(),
            track_number: 1,
            duration_seconds: 180,
            local_path: local_path.to_string_lossy().to_string(),
            state: "complete".to_string(),
            updated_at: now_timestamp(),
            album_id: Some("album".to_string()),
            album_name: Some("Album".to_string()),
            cover_art_uri: None,
            local_cover_path: None,
            suffix: Some("flac".to_string()),
            bytes: None,
            received_bytes: None,
            total_bytes: None,
            error_message: None,
        }
    }

    fn test_track(track_id: &str) -> TrackOutput {
        TrackOutput {
            id: track_id.to_string(),
            title: format!("Song {track_id}"),
            artist: "Artist".to_string(),
            track_number: 1,
            duration_seconds: 180,
            album_id: Some("album".to_string()),
            album_name: Some("Album".to_string()),
            cover_art_id: Some("cover".to_string()),
            cover_art_uri: Some("http://example.test/cover.jpg".to_string()),
            suffix: Some("flac".to_string()),
        }
    }

    #[test]
    fn exact_id_order_rejects_duplicate_or_missing_ids() {
        let existing = ["a".to_string(), "b".to_string()]
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>();

        assert!(is_exact_id_order(
            &["b".to_string(), "a".to_string()],
            &existing
        ));
        assert!(!is_exact_id_order(&["a".to_string()], &existing));
        assert!(!is_exact_id_order(
            &["a".to_string(), "a".to_string()],
            &existing
        ));
        assert!(!is_exact_id_order(
            &["a".to_string(), "c".to_string()],
            &existing
        ));
    }

    #[test]
    fn playlist_tracks_keep_duplicate_song_entries_independent() {
        let track = test_track("same-song");
        let mut first = playlist_track_from_track("playlist", &track, 0);
        let mut second = playlist_track_from_track("playlist", &track, 1);
        first.position = 1;
        second.position = 0;
        let first_entry_id = first.entry_id.clone();
        let second_entry_id = second.entry_id.clone();

        let store = PlaylistStore {
            playlists: vec![PlaylistOutput {
                id: "playlist".to_string(),
                name: "Playlist".to_string(),
                created_at: "2026-06-05T00:00:00Z".to_string(),
                updated_at: "2026-06-05T00:00:00Z".to_string(),
                track_count: 0,
            }],
            tracks: vec![first, second],
        };

        let ordered = playlist_tracks_for_store(&store, "playlist").expect("load tracks");
        assert_eq!(ordered.len(), 2);
        assert_eq!(ordered[0].track_id, "same-song");
        assert_eq!(ordered[1].track_id, "same-song");
        assert_eq!(ordered[0].entry_id, second_entry_id);
        assert_eq!(ordered[1].entry_id, first_entry_id);
        assert_ne!(ordered[0].entry_id, ordered[1].entry_id);
        assert_eq!(ordered[0].position, 0);
        assert_eq!(ordered[1].position, 1);
    }

    #[test]
    fn export_manifest_round_trips_versioned_paths() {
        let directory = temp_export_dir("versioned");
        write_export_manifest(
            &directory,
            vec![
                "Music/Artist/Album/01 - Song.flac".to_string(),
                "../unsafe.flac".to_string(),
                "Music/Artist/Album/01 - Song.flac".to_string(),
            ],
        )
        .expect("write manifest");

        let paths = read_export_manifest_paths(&directory).expect("read manifest");
        assert_eq!(paths.len(), 1);
        assert!(paths.contains("Music/Artist/Album/01 - Song.flac"));

        fs::remove_dir_all(directory).expect("remove temp export dir");
    }

    #[test]
    fn export_manifest_still_reads_legacy_array_format() {
        let directory = temp_export_dir("legacy");
        let manifest_path = directory.join(EXPORT_MANIFEST_FILE_NAME);
        fs::write(
            &manifest_path,
            serde_json::to_string(&vec!["Music/Artist/Album/02 - Song.flac", "/unsafe.flac"])
                .expect("encode legacy manifest"),
        )
        .expect("write legacy manifest");

        let paths = read_export_manifest_paths(&directory).expect("read legacy manifest");
        assert_eq!(paths.len(), 1);
        assert!(paths.contains("Music/Artist/Album/02 - Song.flac"));

        fs::remove_dir_all(directory).expect("remove temp export dir");
    }

    #[test]
    fn export_manifest_ignores_invalid_json() {
        let directory = temp_export_dir("invalid");
        let manifest_path = directory.join(EXPORT_MANIFEST_FILE_NAME);
        fs::write(&manifest_path, "{not json").expect("write invalid manifest");

        let paths = read_export_manifest_paths(&directory).expect("read invalid manifest");
        assert!(paths.is_empty());

        fs::remove_dir_all(directory).expect("remove temp export dir");
    }

    #[test]
    fn storage_migration_marker_prevents_legacy_reimport_after_empty_table() {
        let connection = Connection::open_in_memory().expect("open in-memory sqlite");
        initialize_download_database(&connection).expect("initialize database");

        assert!(
            !has_storage_migration(&connection, "legacy_liked_tracks_json_v1")
                .expect("check migration")
        );
        assert_eq!(
            table_count(&connection, "liked_tracks").expect("count liked tracks"),
            0,
        );

        mark_storage_migration(&connection, "legacy_liked_tracks_json_v1").expect("mark migration");

        assert!(
            has_storage_migration(&connection, "legacy_liked_tracks_json_v1")
                .expect("check migration")
        );
        assert_eq!(
            table_count(&connection, "liked_tracks").expect("count liked tracks"),
            0,
        );
    }

    #[test]
    fn cleanup_unused_download_directory_removes_empty_album_and_artist_folders() {
        let root = temp_download_dir("cleanup-empty");
        let album_dir = root.join("Artist").join("Album");
        fs::create_dir_all(&album_dir).expect("create album dir");
        let audio_path = album_dir.join("01 - Song.flac");
        fs::write(&audio_path, "audio").expect("write audio");
        fs::write(album_dir.join(DOWNLOADS_MANIFEST_FILE_NAME), "[]").expect("write manifest");
        fs::remove_file(&audio_path).expect("remove audio before cleanup");

        cleanup_unused_download_directory(&audio_path.to_string_lossy(), &[])
            .expect("cleanup unused dir");

        assert!(!album_dir.exists());
        assert!(!root.join("Artist").exists());
        assert!(root.exists());

        fs::remove_dir_all(root).expect("remove temp download dir");
    }

    #[test]
    fn cleanup_unused_download_directory_keeps_folder_with_user_file() {
        let root = temp_download_dir("cleanup-user-file");
        let album_dir = root.join("Artist").join("Album");
        fs::create_dir_all(&album_dir).expect("create album dir");
        let audio_path = album_dir.join("01 - Song.flac");
        fs::write(&audio_path, "audio").expect("write audio");
        fs::write(album_dir.join(DOWNLOADS_MANIFEST_FILE_NAME), "[]").expect("write manifest");
        fs::write(album_dir.join("notes.txt"), "keep me").expect("write user file");
        fs::remove_file(&audio_path).expect("remove audio before cleanup");

        cleanup_unused_download_directory(&audio_path.to_string_lossy(), &[])
            .expect("cleanup unused dir");

        assert!(album_dir.exists());
        assert!(album_dir.join("notes.txt").exists());
        assert!(!album_dir.join(DOWNLOADS_MANIFEST_FILE_NAME).exists());

        fs::remove_dir_all(root).expect("remove temp download dir");
    }

    #[test]
    fn cleanup_unused_download_directory_keeps_folder_used_by_remaining_download() {
        let root = temp_download_dir("cleanup-still-used");
        let album_dir = root.join("Artist").join("Album");
        fs::create_dir_all(&album_dir).expect("create album dir");
        let removed_audio_path = album_dir.join("01 - Removed.flac");
        let kept_audio_path = album_dir.join("02 - Kept.flac");
        fs::write(&removed_audio_path, "removed").expect("write removed audio");
        fs::write(&kept_audio_path, "kept").expect("write kept audio");
        fs::write(album_dir.join(DOWNLOADS_MANIFEST_FILE_NAME), "[]").expect("write manifest");

        cleanup_unused_download_directory(
            &removed_audio_path.to_string_lossy(),
            &[test_download("kept", &kept_audio_path)],
        )
        .expect("cleanup still-used dir");

        assert!(album_dir.exists());
        assert!(album_dir.join(DOWNLOADS_MANIFEST_FILE_NAME).exists());

        fs::remove_dir_all(root).expect("remove temp download dir");
    }
}
