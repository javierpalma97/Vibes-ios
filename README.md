# Vibes

> A beautiful, native iOS client for YouTube Music built with SwiftUI

[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Latest-green.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-Personal%20Use-red.svg)](#license)

## Overview

Vibes is a full-featured YouTube Music client for iOS that brings the power of YouTube Music to your iPhone with a beautiful native interface. Stream millions of songs, manage your library, create playlists, and enjoy seamless playback with full CarPlay support.

### Key Features

- **Stream Music** - Access YouTube Music's entire catalog
- **Library Sync** - Sync liked songs and playlists from your YouTube account
- **CarPlay** - Full integration with your car's display
- **Offline Playback** - Download songs for offline listening
- **Smart Playlists** - Auto-generated playlists (Liked, Downloaded, Top Songs)
- **Quick Picks** - Personalized recommendations based on your listening history
- **Background Audio** - Keep the music playing while using other apps
- **Lyrics Support** - Synced and unsynced lyrics with real-time highlighting
- **Dynamic Themes** - Album art-based color themes for immersive playback
- **Listening Stats** - Track your listening habits with detailed statistics
- **Siri Shortcuts** - Control playback with App Intents
- **Sleep Timer** - Auto-stop playback after a set duration

## Screenshots

*Coming soon*

## Installation

### Requirements

- macOS with Xcode 15.0 or later
- iOS 17.0+ device
- Apple Developer account (free or paid)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url> Vibes-ios
   cd Vibes-ios
   ```

2. **Open in Xcode**
   ```bash
   open Vibes/Vibes.xcodeproj
   ```

3. **Configure signing**
   - Select the "Vibes" target
   - Go to "Signing & Capabilities"
   - Select your Team from the dropdown
   - Xcode will handle the rest

4. **Build and run**
   - Select your iOS device or simulator (Cmd+R)
   - The app will build and install automatically

### Free Apple Developer Account

If you're using a free Apple Developer account, apps expire after 7 days. Use the provided resign script to renew:

```bash
chmod +x resign.sh
./resign.sh
```

This will automatically re-sign the app with your development certificate.

## Features

### Playback
- High-quality audio streaming from YouTube Music
- Background playback with lock screen controls
- Gapless playback
- Shuffle and repeat modes
- AirPlay and Bluetooth support
- Radio mode (auto-play similar songs)

### Library Management
- Sync liked songs from YouTube Music
- Sync playlists from your account
- Create and manage local playlists
- Filter library by Songs, Albums, Artists, Playlists
- Auto-generated playlists:
  - **Liked Songs** - All your liked tracks
  - **Downloaded** - Offline-ready songs
  - **Top Songs** - Your most-played tracks

### Discovery
- **Home Tab** - Personalized home feed with Quick Picks and recommendations
- **Search** - Search songs, albums, artists, playlists with search history
- **Charts** - Browse trending music charts
- **Browse** - Explore moods, genres, and curated content
- **New Releases** - Discover latest music releases
- **Artist Pages** - Full discography and artist information
- **Album Details** - Complete tracklists and album information
- **Quick Picks** - Personalized recommendations based on listening history

### Queue Management
- View and edit upcoming songs
- Add to queue or play next
- Reorder queue items with drag and drop
- View playback history
- Persistent queue (survives app restarts)

### Additional Features
- **Lyrics** - Synced lyrics with real-time line highlighting and tap-to-seek
- **Dynamic Themes** - Album art-based color extraction for immersive UI
- **Listening Statistics** - Track songs played, listen time, top songs, and top artists
- **Sleep Timer** - Auto-stop playback after a set duration
- **App Intents** - Siri shortcuts for playing songs, artists, and playlists
- **Playback History** - View your recently played tracks
- **Downloads Management** - Manage offline downloads
- **Account Management** - View and manage your YouTube account

### CarPlay Integration
- Browse your library in the car
- Full playback controls
- Now Playing display
- Voice control support

## Architecture

Vibes is built with modern iOS development best practices:

### Technologies

- **SwiftUI** - Declarative UI framework
- **SwiftData** - Apple's modern persistence layer
- **AVFoundation** - High-performance audio playback
- **Combine** - Reactive programming for data flow
- **CarPlay Framework** - Seamless in-car integration

### Project Structure

```
Vibes/
├── Vibes/
│   ├── App/                    # App entry point & lifecycle
│   ├── Core/
│   │   ├── AppIntents/         # Siri shortcuts (PlaySong, PlayArtist, PlayPlaylist)
│   │   ├── Authentication/     # YouTube login & account management
│   │   ├── Database/          # SwiftData models & managers
│   │   ├── Download/          # Offline playback management
│   │   ├── Lyrics/            # Lyrics fetching and display
│   │   ├── Network/           # InnerTube API client
│   │   ├── Player/            # Audio playback engine
│   │   ├── Theme/             # Dynamic theme extraction from album art
│   │   └── Utils/             # Shared utilities
│   ├── Features/              # Feature modules
│   │   ├── Account/           # Account management
│   │   ├── Album/             # Album detail views
│   │   ├── Artist/           # Artist detail views
│   │   ├── Browse/            # Browse moods and genres
│   │   ├── Charts/            # Music charts
│   │   ├── Downloads/         # Download management
│   │   ├── History/           # Playback history
│   │   ├── Library/           # Library views (Songs, Albums, Artists, Playlists)
│   │   ├── NewReleases/       # New releases
│   │   ├── Player/            # Player view with lyrics
│   │   ├── Playlist/          # Playlist detail views
│   │   ├── Queue/             # Queue management
│   │   ├── Search/            # Search and home views
│   │   ├── Settings/          # Settings and login
│   │   └── Stats/             # Listening statistics
│   ├── UI/                    # Reusable components & views
│   ├── CarPlay/               # CarPlay integration
│   └── Resources/             # Assets, Info.plist, entitlements
└── Scripts/
    └── resign.sh              # Re-sign script for free dev accounts
```

### Data Flow

```
UI Layer (SwiftUI Views)
    ↓
Manager Layer
    ├── PlayerManager         # Audio playback
    ├── QueueManager         # Queue management
    ├── LibraryManager       # Database & sync
    ├── AuthManager          # Authentication
    ├── LyricsManager        # Lyrics fetching & display
    └── ThemeManager         # Dynamic theme extraction
    ↓
Service Layer
    ├── InnerTube API        # YouTube Music
    ├── SwiftData            # Local persistence
    └── DownloadManager      # Offline storage
```

## How It Works

### YouTube Music API

Vibes uses YouTube's internal InnerTube API - the same API powering the official YouTube Music web player. This provides:

- Full search capabilities
- High-quality audio streaming
- Access to user libraries (with authentication)
- Metadata (thumbnails, artist info, album art)

**Authentication** uses cookies extracted from a WebView login flow, ensuring your credentials remain secure.

### Performance Optimizations

- **Batch operations** - Library sync processes items in bulk
- **Query optimization** - Single database queries instead of N+1
- **Async loading** - Data loads asynchronously to keep UI responsive
- **Stream caching** - Reduces API calls for frequently played songs

## Configuration

For detailed setup instructions, see [claude.md](claude.md).

### Required Capabilities

- **CarPlay (Audio)** - Enables CarPlay support
- **App Groups** - Data sharing between app and CarPlay
- **Background Modes** - Audio playback and background fetch

### Entitlements

The app requires these entitlements (already configured in `Vibes.entitlements`):
- CarPlay Audio App
- App Groups (`group.com.vibes.app`)
- Background Modes (audio, fetch)

## Usage

### Getting Started

1. **Launch the app** - Grant permissions if prompted
2. **Sign in** (optional) - Library tab > Sign in to YouTube Music
3. **Search music** - Use the Search tab
4. **Play a song** - Tap any track to start playback
5. **Explore** - Browse artists, albums, and playlists

### YouTube Account

To sync your library:
1. Tap "Sign in to YouTube Music" in the Library tab
2. Log in with your Google account
3. The app will sync your liked songs and playlists
4. Pull down to refresh for manual sync

### CarPlay

1. Connect your iPhone to CarPlay (USB or wireless)
2. Launch Vibes on your iPhone
3. Select Vibes from the CarPlay app drawer
4. Control playback directly from your car

## Troubleshooting

### Common Issues

**App won't build**
- Verify iOS Deployment Target is 17.0+
- Check all source files are in the target
- Clean build folder (Cmd+Shift+K) and rebuild

**YouTube login fails**
- Check network connection
- Try logging in to YouTube Music in Safari first
- Clear Safari cookies and try again

**No audio playback**
- Ensure Background Modes > Audio is enabled
- Check device volume and audio output
- Verify audio permissions in Settings

**CarPlay doesn't show**
- Verify CarPlay entitlement is in project
- Check Info.plist CarPlay scene configuration
- Restart Xcode and rebuild
- Try disconnecting and reconnecting CarPlay

**7-day certificate expired**
- Run `./resign.sh` to re-sign
- Or rebuild from Xcode

## Development

See [claude.md](claude.md) for comprehensive development documentation, including:
- Complete architecture overview
- Implementation details for each feature
- Database schema and relationships
- API integration guide
- Testing strategies

## Known Limitations

- Uses reverse-engineered APIs (may break if YouTube changes their backend)
- Free developer accounts require weekly re-signing
- Some advanced YouTube Music features not yet implemented
- Stream URLs expire after ~6 hours (automatically refreshed)

## Legal & Disclaimer

⚠️ **IMPORTANT NOTICE**

- This app uses **reverse-engineered YouTube Music APIs**
- It is **NOT** affiliated with, endorsed by, or supported by Google/YouTube
- This is for **educational and personal use ONLY**
- **DO NOT** distribute this app:
  - Not on the App Store (will be rejected)
  - Not as IPA files for sideloading
  - Not as source code claiming it as your own
- YouTube may change their API at any time, breaking functionality
- Using unofficial APIs may violate YouTube's Terms of Service
- **Use at your own risk**

## License

**For Personal Use Only**

This project is provided as-is for educational and personal use. It uses reverse-engineered APIs which may violate YouTube's Terms of Service. Not licensed for commercial distribution or App Store publication.

## Credits

- **Original Concept**: Inspired by Vibes for Android
- **iOS Implementation**: Built with Claude Code (Anthropic)
- **InnerTube API**: Reverse-engineered YouTube Music protocol

---

**Made with ❤️ for music lovers**

*Enjoy the vibes!* 🎵
