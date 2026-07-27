//! Thin music-server provider boundary.
//!
//! UI and Tauri commands talk to helpers here instead of sprinkling raw
//! Subsonic endpoint strings across the app. Navidrome is the only
//! implementation for now; other Subsonic-compatible servers can plug in later.

use crate::{
    album_from_subsonic, get_subsonic, search_result_from_subsonic, track_from_subsonic,
    AlbumOutput, LibrarySearchResultOutput, SavedServerProfile, TrackOutput,
};
use serde_json::Value;

const ALBUM_PAGE_SIZE: i64 = 500;

/// Fetch every album page from the server (alphabetical by name).
pub async fn fetch_all_albums(profile: &SavedServerProfile) -> Result<Vec<AlbumOutput>, String> {
    let mut albums = Vec::new();
    let mut offset: i64 = 0;
    loop {
        let size = ALBUM_PAGE_SIZE.to_string();
        let offset_text = offset.to_string();
        let response = get_subsonic(
            profile,
            "getAlbumList2.view",
            &[
                ("type", "alphabeticalByName"),
                ("size", size.as_str()),
                ("offset", offset_text.as_str()),
            ],
        )
        .await?;

        let page = response
            .data
            .get("albumList2")
            .and_then(|value| value.get("album"))
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(|value| value.as_object())
                    .map(|json| album_from_subsonic(profile, json))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        let page_len = page.len();
        if page_len == 0 {
            break;
        }
        albums.extend(page);
        if page_len < ALBUM_PAGE_SIZE as usize {
            break;
        }
        offset += ALBUM_PAGE_SIZE;
    }
    Ok(albums)
}

pub async fn fetch_album_detail(
    profile: &SavedServerProfile,
    album_id: &str,
) -> Result<(AlbumOutput, Vec<TrackOutput>), String> {
    let response = get_subsonic(profile, "getAlbum.view", &[("id", album_id)]).await?;
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
                .map(|json| track_from_subsonic(profile, json))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Ok((album_from_subsonic(profile, album_json), tracks))
}

pub async fn search_library(
    profile: &SavedServerProfile,
    query: &str,
) -> Result<LibrarySearchResultOutput, String> {
    let response = get_subsonic(
        profile,
        "search3.view",
        &[
            ("query", query),
            ("artistCount", "0"),
            ("albumCount", "20"),
            ("songCount", "50"),
        ],
    )
    .await?;
    Ok(search_result_from_subsonic(
        profile,
        response.data.get("searchResult3"),
    ))
}

/// Star a track on the server (Subsonic `star.view`).
pub async fn star_track(profile: &SavedServerProfile, track_id: &str) -> Result<(), String> {
    get_subsonic(profile, "star.view", &[("id", track_id)]).await?;
    Ok(())
}

/// Remove a star on the server (Subsonic `unstar.view`).
pub async fn unstar_track(profile: &SavedServerProfile, track_id: &str) -> Result<(), String> {
    get_subsonic(profile, "unstar.view", &[("id", track_id)]).await?;
    Ok(())
}

/// Load starred songs from the server (`getStarred2.view`).
pub async fn fetch_starred_tracks(
    profile: &SavedServerProfile,
) -> Result<Vec<TrackOutput>, String> {
    let response = get_subsonic(profile, "getStarred2.view", &[]).await?;
    let songs = response
        .data
        .get("starred2")
        .and_then(|value| value.get("song"))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|value| value.as_object())
                .map(|json| track_from_subsonic(profile, json))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Ok(songs)
}
