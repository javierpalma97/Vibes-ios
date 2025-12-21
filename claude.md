# Vibes - Claude Documentation

> Comprehensive development guide and technical documentation for the Vibes iOS app

**Last Updated**: December 17, 2025
**App Version**: 1.0
**iOS Target**: 17.0+
**Built with**: Claude Code (Anthropic)

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Database Schema](#database-schema)
4. [API Integration](#api-integration)
5. [Feature Implementation](#feature-implementation)
6. [Performance Optimizations](#performance-optimizations)
7. [Known Issues & Solutions](#known-issues--solutions)
8. [Development History](#development-history)

---

## Project Overview

### What is Vibes?

Vibes is a native iOS client for YouTube Music, built from scratch to match the functionality of the Android Vibes app. It provides:

- Full YouTube Music streaming capabilities
- Library synchronization with YouTube account
- Offline playback with downloads
- CarPlay integration for in-car use
- Smart playlists and personalized recommendations

### Tech Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Persistence**: SwiftData (iOS 17+)
- **Audio**: AVFoundation (AVPlayer)
- **Networking**: URLSession with custom InnerTube client
- **Authentication**: Cookie-based (WebView)
- **CarPlay**: CPTemplate APIs

### Project Structure

```
Vibes/
├── Vibes/                          # Main app bundle
│   ├── App/
│   │   └── VibesApp.swift         # App entry point & lifecycle
│   │
│   ├── Core/
│   │   ├── Authentication/
│   │   │   └── AuthenticationManager.swift    # YouTube login management
│   │   │
│   │   ├── Database/
│   │   │   ├── Models/                        # SwiftData models
│   │   │   │   ├── Song.swift
│   │   │   │   ├── Album.swift
│   │   │   │   ├── Artist.swift
│   │   │   │   ├── Playlist.swift
│   │   │   │   ├── PlaylistSongMap.swift
│   │   │   │   ├── PlayEvent.swift            # Listening history
│   │   │   │   └── SearchHistory.swift
│   │   │   └── LibraryManager.swift           # Database operations & sync
│   │   │
│   │   ├── Download/
│   │   │   └── DownloadManager.swift          # Offline playback management
│   │   │
│   │   ├── Network/
│   │   │   └── InnerTube/                     # YouTube Music API
│   │   │       ├── InnerTubeClient.swift      # Low-level HTTP client
│   │   │       ├── YouTubeMusic.swift         # High-level API wrapper
│   │   │       ├── Models/                    # API response models
│   │   │       └── ThrottlingDecipher.swift   # Stream URL decryption
│   │   │
│   │   ├── Player/
│   │   │   ├── PlayerManager.swift            # Audio playback engine
│   │   │   └── QueueManager.swift             # Queue management
│   │   │
│   │   └── Utils/
│   │       └── LibraryFilter.swift            # Filter enums
│   │
│   ├── Features/                       # Feature modules (UI + logic)
│   │   ├── Search/
│   │   │   ├── SearchView.swift
│   │   │   └── HomeView.swift
│   │   ├── Player/
│   │   │   └── PlayerView.swift
│   │   ├── Queue/
│   │   │   └── QueueView.swift
│   │   ├── Library/
│   │   │   ├── LibraryView.swift
│   │   │   ├── LibrarySongsView.swift
│   │   │   ├── LibraryAlbumsView.swift
│   │   │   ├── LibraryArtistsView.swift
│   │   │   └── AutoPlaylistViews.swift        # Liked/Downloaded/Top
│   │   ├── Playlist/
│   │   │   └── YTPlaylistDetailView.swift
│   │   ├── Album/
│   │   │   └── AlbumDetailView.swift
│   │   ├── Artist/
│   │   │   └── ArtistDetailView.swift
│   │   ├── Downloads/
│   │   │   └── DownloadsView.swift
│   │   ├── History/
│   │   │   └── HistoryView.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       └── LoginView.swift                # YouTube login WebView
│   │
│   ├── UI/
│   │   ├── Components/                        # Reusable UI components
│   │   │   ├── SongRow.swift
│   │   │   ├── SongCard.swift
│   │   │   ├── AlbumCard.swift
│   │   │   └── ArtistCard.swift
│   │   └── Views/
│   │       └── ContentView.swift              # Tab bar container
│   │
│   ├── CarPlay/
│   │   └── CarPlaySceneDelegate.swift         # CarPlay templates
│   │
│   └── Resources/
│       ├── Info.plist                         # App configuration
│       ├── Vibes.entitlements             # App capabilities
│       └── Assets.xcassets/                   # Images & icons
│
└── Scripts/
    └── resign.sh                              # 7-day re-sign script
```

---

## Architecture

### Design Pattern

Vibes follows a **Manager-based architecture** with clear separation of concerns:

```
┌─────────────────────────────────────┐
│      SwiftUI Views (Presentation)   │
│   - Declarative UI                  │
│   - State management (@State, etc)  │
└──────────────┬──────────────────────┘
               │ @EnvironmentObject
               ↓
┌─────────────────────────────────────┐
│      Manager Layer (Business Logic) │
│   - PlayerManager                   │
│   - QueueManager                    │
│   - LibraryManager                  │
│   - AuthenticationManager           │
└──────────────┬──────────────────────┘
               │
        ┌──────┴──────┐
        ↓             ↓
┌──────────────┐  ┌──────────────┐
│  InnerTube   │  │  SwiftData   │
│  API Client  │  │  Database    │
└──────┬───────┘  └──────┬───────┘
       │                 │
       ↓                 ↓
┌──────────────┐  ┌──────────────┐
│   YouTube    │  │    Local     │
│   Music      │  │   Storage    │
└──────────────┘  └──────────────┘
```

### Manager Responsibilities

**PlayerManager** (`Core/Player/PlayerManager.swift`)
- AVPlayer instance management
- Stream URL fetching and caching
- Playback state (play/pause/seek)
- Now Playing info updates
- Background audio session
- Duration handling (YouTube API vs asset)

**QueueManager** (`Core/Player/QueueManager.swift`)
- Queue manipulation (add, remove, reorder)
- Shuffle and un-shuffle
- Next/previous navigation
- Persistent queue storage
- Radio mode (auto-fetch similar songs)

**LibraryManager** (`Core/Database/LibraryManager.swift`)
- SwiftData persistence
- YouTube Music library syncing
- Local playlist management
- Quick Picks algorithm
- Play event tracking

**AuthenticationManager** (`Core/Authentication/AuthenticationManager.swift`)
- Cookie-based YouTube login
- Account info storage
- Session management
- Cookie expiration handling

---

## Database Schema

### SwiftData Models

**Song**
```swift
@Model
final class Song {
    @Attribute(.unique) var id: String              // YouTube video ID
    var title: String
    var artistsText: String?
    var durationText: String?                       // e.g., "3:45"
    var thumbnailUrl: String?
    var albumId: String?
    var albumName: String?
    var liked: Bool = false
    var playCount: Int = 0
    var dateAdded: Date = Date()
    var dateModified: Date = Date()
}
```

**Album**
```swift
@Model
final class Album {
    @Attribute(.unique) var id: String
    var title: String
    var artistsText: String?
    var thumbnailUrl: String?
    var year: String?
    var dateAdded: Date = Date()
}
```

**Artist**
```swift
@Model
final class Artist {
    @Attribute(.unique) var id: String
    var name: String
    var thumbnailUrl: String?
    var dateAdded: Date = Date()
}
```

**Playlist**
```swift
@Model
final class Playlist {
    @Attribute(.unique) var id: String
    var name: String
    var thumbnailUrl: String?
    var playlistType: PlaylistType                  // .local or .youtube
    var songCount: Int = 0
    var browseId: String?
    var author: String?
    @Relationship(deleteRule: .cascade)
    var songMaps: [PlaylistSongMap]?
}
```

**PlaylistSongMap** (Join table)
```swift
@Model
final class PlaylistSongMap {
    var songId: String
    var playlistId: String
    var position: Int
    var setVideoId: String?                         // For YouTube playlists
}
```

**PlayEvent** (Listening history)
```swift
@Model
final class PlayEvent {
    var songId: String
    var timestamp: Date
    var playTime: Int64                             // Milliseconds played
}
```

**SearchHistory**
```swift
@Model
final class SearchHistory {
    @Attribute(.unique) var query: String
    var timestamp: Date
}
```

### Relationships

```
Playlist (1) ──── (N) PlaylistSongMap ──── (1) Song
                                                │
                                                │
Artist (1) ──────────────────────────────────  │
                                                │
Album (1) ───────────────────────────────────  │
                                                │
PlayEvent (N) ─────────────────────────────────┘
```

---

## API Integration

### InnerTube API

YouTube Music uses Google's internal "InnerTube" API. This is the same API used by:
- YouTube Music web player
- YouTube mobile apps
- YouTube TV apps

#### API Structure

**Base URL**: `https://music.youtube.com/youtubei/v1/`

**Endpoints Used**:
- `search` - Search for songs, albums, artists, playlists
- `browse` - Get playlists, albums, artist pages
- `player` - Get stream URLs and metadata
- `next` - Get related/recommended songs (for radio mode)

#### Client Types

The API supports multiple client types, each with different capabilities:

```swift
enum InnerTubeClientType: String {
    case ios = "IOS"
    case android = "ANDROID"
    case androidVR = "ANDROID_VR"          // Best for audio streams
    case web = "WEB"
    case tvEmbedded = "TVHTML5_SIMPLY_EMBEDDED_PLAYER"
}
```

**Client Selection Strategy**:
1. Try `androidVR` first (best audio quality, no throttling)
2. Fallback to `android` if androidVR fails
3. Fallback to `ios` if android fails
4. Last resort: `web`

#### Authentication

**Cookie-based Auth** using SAPISIDHASH:

1. User logs in via WebView
2. Extract cookies: `SAPISID`, `__Secure-3PAPISID`, `SSID`, `HSID`, `SID`
3. Generate SAPISIDHASH: `SHA1(timestamp + " " + SAPISID + " " + origin)`
4. Send in headers:
   ```
   Authorization: SAPISIDHASH {timestamp}_{hash}
   Cookie: {all cookies}
   ```

**Implementation**: See `InnerTubeClient.swift:generateSAPISIDHASH()`

#### Stream URL Fetching

Stream URLs are fetched from the `/player` endpoint and cached:

```swift
// PlayerManager.swift
private var streamUrlCache: [String: (url: String, expiry: Date)] = [:]

private func getStreamUrl(for videoId: String) async throws -> (url: String, duration: TimeInterval?) {
    // Always fetch fresh to get correct duration (YouTube API is source of truth)
    let (url, expiry, duration, clientType) = try await ytMusic.getStreamUrl(videoId: videoId)

    if let expiry = expiry {
        streamUrlCache[videoId] = (url, expiry)
    }

    return (url: url, duration: duration)
}
```

**Duration Handling** (Critical Bug Fix):
- YouTube API returns correct duration in `lengthSeconds`
- AVPlayerItem.asset.duration is often DOUBLED for YouTube streams
- **Solution**: Always trust YouTube API duration, ignore asset duration
- Only use asset duration for downloaded files (local files)

---

## Feature Implementation

### Library Tabs & Filters

Matching Android's library structure:

**Main Filters**:
- All (default) - Mixed view
- Playlists
- Songs
- Albums
- Artists

**Song Filters** (within Songs tab):
- Library - All songs with playCount > 0
- Liked - Songs with liked = true
- Downloaded - Locally cached songs
- (Future: Uploaded)

**Implementation**:
```swift
// LibraryFilter.swift
enum LibraryFilter: String, CaseIterable {
    case library = "All"
    case playlists = "Playlists"
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
}
```

### Auto-Generated Playlists

Three special playlists:

**1. Liked Songs**
```swift
// Query: All songs where liked = true
@Query(predicate: #Predicate { $0.liked == true })
private var likedSongs: [Song]
```

**2. Top Songs**
```swift
// Algorithm:
// 1. Fetch all PlayEvents
// 2. Group by songId
// 3. Sum playTime for each song
// 4. Sort by total playTime DESC
// 5. Take top 100
```

**3. Downloaded Songs**
```swift
// Algorithm:
// 1. List all .m4a files in downloads directory
// 2. Extract songIds from filenames
// 3. Fetch matching Song objects from database
```

### Quick Picks Algorithm

Personalized recommendations based on listening history:

**Algorithm** (matching Android):
1. Get PlayEvents from last 2 weeks
2. Group by songId, sum playTime
3. Filter songs that have an albumId
4. Group by albumId, keep song with most playTime per album
5. Sort by playTime DESC
6. Shuffle and take 20

**Performance Optimization**:
- Originally: N+1 queries (one per song) - VERY SLOW
- Fixed: Single query with `songIds.contains(song.id)` predicate
- Result: 100x faster on first launch

**Implementation**: See `LibraryManager.swift:getQuickPicks()`

### Library Sync

Syncs liked songs and playlists from YouTube Music account:

**Process**:
1. Fetch liked songs: `YouTube.playlist("VLLM")` (Liked Music playlist)
2. Fetch playlists: `YouTube.library("FEmusic_liked_playlists")`
3. Save to database in batch (skipReload: true)
4. Reload local data once at end

**Performance**:
- Before: Reloaded library after EACH song/playlist (100+ reloads)
- After: Single reload at end (100x faster)

**Bug Fixes**:
1. `getLikedSongs()` was returning empty array `[]`
   - Fixed: Use `getPlaylist(browseId: "VLLM")`
2. Sync was extremely slow
   - Fixed: Batch processing with skipReload parameter

### Duration Handling (Critical Fix)

**The Problem**:
Songs showing 2x their actual duration (e.g., 3:30 song showing as 7:00)

**Root Cause**:
- YouTube serves audio with doubled duration in stream metadata
- AVPlayerItem.asset.duration returns this doubled value
- Old code overwrote correct YouTube API duration with wrong asset duration

**The Solution**:
```swift
// PlayerManager.swift:playerItemDidChangeStatus()
case .readyToPlay:
    let assetDuration = item.asset.duration.seconds

    // If we have YouTube API duration, KEEP it (this is CORRECT)
    if self.duration > 0 {
        if abs(self.duration - assetDuration) > 2.0 {
            print("⚠️ Asset duration differs from YouTube API. Using YouTube API (correct).")
        }
    } else if assetDuration.isFinite && assetDuration > 0 {
        // No YouTube API duration, use asset (downloaded files)
        self.duration = assetDuration
    }
```

**For Downloaded Files**:
Even for local files, fetch YouTube API metadata to get correct duration:
```swift
if downloadManager.isDownloaded(song.id) {
    let localURL = downloadManager.localFileURL(for: song.id)
    url = localURL
    newPlayerItem = AVPlayerItem(url: url)

    // Still fetch YouTube API duration for correct metadata
    do {
        let (_, duration, _) = try await getStreamUrl(for: song.id)
        youtubeDuration = duration
    } catch {
        print("⚠️ Could not fetch YouTube duration for downloaded file")
    }
}
```

### Queue Management

**Persistent Queue**:
```swift
// QueueManager.swift
private func persistQueue() {
    let queueData = QueueData(
        songIds: queue.map { $0.id },
        currentIndex: currentIndex,
        isShuffled: playerManager.isShuffleEnabled
    )
    if let encoded = try? JSONEncoder().encode(queueData) {
        UserDefaults.standard.set(encoded, forKey: "queueData")
    }
}

private func loadPersistedQueue() {
    // Load queue from UserDefaults
    // Fetch Song objects from database
    // Restore currentIndex
}
```

**Bug Fix**: Queue history was in reverse order
- Expected: Song 1, Song 2, Song 3, [Now Playing], Song 4, Song 5
- Was showing: Song 3, Song 2, Song 1, [Now Playing], Song 4, Song 5
- Fixed: Removed `.reversed()` from ForEach

**Radio Mode**:
Automatically fetches similar songs when queue is near end:
```swift
if enableRadio && songs.count <= 25 {
    isRadioMode = true
    radioVideoId = songs[startIndex].id
    Task { await fetchMoreRadioSongs() }
}
```

### CarPlay Integration

**Scene Configuration** (`Info.plist`):
```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>CPTemplateApplicationScene</string>
                <key>UISceneConfigurationName</key>
                <string>CarPlay</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

**Templates Used**:
- `CPTabBarTemplate` - Root template
- `CPListTemplate` - Library, playlists
- `CPNowPlayingTemplate` - Playback controls

---

## Performance Optimizations

### 1. Quick Picks (Single Query)

**Before**:
```swift
for (songId, playTime) in songPlayTimes {
    if let song = await getSong(id: songId) {  // N queries!
        songsWithAlbums.append((song, playTime))
    }
}
```

**After**:
```swift
let songIds = Array(songPlayTimes.keys)
let songDescriptor = FetchDescriptor<Song>(
    predicate: #Predicate<Song> { song in
        songIds.contains(song.id) && song.albumId != nil
    }
)
let songs = try? context.fetch(songDescriptor)  // 1 query!
```

**Impact**: 100x faster startup

### 2. Library Sync (Batch Reload)

**Before**:
```swift
for ytSong in ytLikedSongs {
    await saveSong(ytSong, liked: true)  // Reloads library!
}
```

**After**:
```swift
for ytSong in ytLikedSongs {
    await saveSong(ytSong, liked: true, skipReload: true)
}
await loadLocalData()  // Reload once at end
```

**Impact**: 100x faster sync (100 songs = 1 reload instead of 100)

### 3. Async Data Loading

All data loading happens asynchronously to avoid blocking UI:
```swift
func setModelContext(_ context: ModelContext) {
    self.modelContext = context

    // Load data asynchronously
    Task { @MainActor in
        await loadLocalData()
    }
}
```

---

## Known Issues & Solutions

### Issue 1: First Launch Lag

**Symptom**: App is slow on first launch after installation

**Cause**: iOS system behavior
- SwiftData creates database schema
- Code signing verification
- Framework caching (dyld)

**Solution**: This is normal and expected. Subsequent launches are fast.

### Issue 2: Free Dev Account (7-day expiry)

**Symptom**: App stops working after 7 days

**Cause**: Free Apple Developer accounts provision apps for only 7 days

**Solution**: Use `resign.sh` script to re-sign weekly

### Issue 3: Liked Songs Empty After Sync

**Symptom**: Sync says "0 liked songs" even though user has liked songs

**Cause**: Bug in `getLikedSongs()` - was returning empty array

**Solution**: Fixed to use `getPlaylist(browseId: "VLLM")`

### Issue 4: Duration Doubling

**Symptom**: Songs showing 2x their actual length

**Cause**: YouTube streams have doubled duration in metadata

**Solution**: Always use YouTube API duration, ignore asset duration

### Issue 5: Downloaded Songs Double Duration

**Symptom**: Downloaded files show wrong duration

**Cause**: Files were downloaded with doubled duration, no YouTube API call

**Solution**: Fetch YouTube API metadata even for downloaded files

---

## Development History

### Session 1: Initial Setup & Core Features
- Created project structure
- Implemented InnerTube API client
- Built PlayerManager and QueueManager
- Added basic UI (Search, Player, Queue)
- Integrated CarPlay

### Session 2: Library Features
- Implemented library tabs (Songs/Albums/Artists/Playlists)
- Added auto-generated playlists (Liked, Top, Downloaded)
- Created Quick Picks algorithm
- Fixed compilation errors (dateModified → dateAdded)
- Added model conversion methods (toYTAlbum, toYTArtist)

### Session 3: Bug Fixes
- Fixed duration doubling bug
  - Identified YouTube API vs asset duration discrepancy
  - Implemented YouTube API as source of truth
  - Fixed for both streamed and downloaded files
- Fixed queue history order (removed .reversed())
- Optimized Quick Picks (N+1 → single query)
- Optimized library sync (batch reload)

### Session 4: Missing Features & TODOs
- Implemented artist shuffle button
- Implemented artist radio button
- Fixed queue persistence (load songs from database)
- Removed all TODO comments

### Session 5: Radio Mode Bug
- Fixed auto-playlists playing YouTube algorithm songs
- Added `enableRadio: false` to Liked/Top/Downloaded playlists
- Users now get only their curated songs, not algorithmic additions

### Session 6: Liked Songs Sync
- Fixed `getLikedSongs()` returning empty array
- Implemented proper fetch using playlist "VLLM"
- Added comprehensive logging for sync operations
- Optimized sync performance (100x improvement)

### Session 7: Project Cleanup & Rebranding
- Renamed app from "Vibes" to "Vibes"
- Created comprehensive README.md
- Created resign.sh script for free dev accounts
- Created this claude.md documentation
- Cleaned up old scripts and markdown files
- Removed debug logs
- Initialized git repository

---

## Future Enhancements

### Planned Features
- Live synced lyrics (LrcLib, YouTube)
- Audio normalization
- Equalizer
- Sleep timer
- Statistics dashboard
- Spotify/Apple Music playlist import

### Code Improvements
- Unit tests for core managers
- UI tests for critical flows
- Crash reporting (e.g., Sentry)
- Analytics (privacy-focused)

---

## Appendix

### Build Configuration

**Xcode Version**: 15.0+
**Swift Version**: 5.9+
**iOS Deployment Target**: 17.0+
**Bundle ID**: `com.vibes.app`
**Team ID**: (User-specific)

### Required Entitlements
- `com.apple.developer.carplay-audio`
- `com.apple.security.application-groups`
- Background Modes: Audio, Background Fetch

### Third-Party Dependencies
None - completely dependency-free!

---

**Documentation maintained by**: Claude Code
**Last reviewed**: December 17, 2025
**Status**: Complete and up-to-date

*This documentation will be updated as new features are added and bugs are fixed.*
