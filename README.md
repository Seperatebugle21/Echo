# Echo

A native music and podcast player for iPhone and iPad, built with Swift and SwiftUI.

Echo brings your local music collection, podcast subscriptions, and audio discovery into one app. Organize your library, transfer Spotify playlists, download audio for offline listening, and control playback from your Home Screen.

This README describes the **Widget** branch. Echo requires **iOS or iPadOS 26.0 or later**.

## Features

### Local music library

Build a personal library from imported audio files and listen offline. Organize music into playlists, browse songs, albums, and artists, and edit track metadata and artwork. Favorites, listening history, and library-based recommendations help you return to the music you play most.

### Podcasts, online and offline

Discover podcasts through Apple's podcast search and access episodes from publishers' public RSS feeds. Save shows and episodes, download audio for offline listening, and resume unfinished episodes from your saved playback position.

Podcast playback shares Echo's player and queue with music, with adjustable playback speed, skip controls, AirPlay, and Lock Screen integration. Transcripts are available when supplied by the publisher in a supported format.

### Spotify integration and playlist transfer

Connect Spotify to browse your library, search its catalog, and transfer playlists into Echo. The transfer process reuses matching songs already in your local library and queues missing tracks through Fetch while preserving their playlist positions.

Spotify provides catalog and playlist information. Audio availability depends on the sources configured in Echo's Fetch system.

### Audio discovery and downloads

Fetch brings audio search, link resolution, downloads, and library import into a single workflow. The app includes YouTube and YouTube Music search, Spotify link handling, direct MP3 sources, and integrations with yt-dlp and Apify.

Downloads support selectable output bitrates of 128, 192, and 320 kbps, with metadata and artwork processing. Available sources and download results depend on the selected provider and its configuration.

### Playback and sound control

Play music in the background, manage a shared music and podcast queue, and route audio to AirPlay devices. A six-band equalizer provides presets and custom adjustments for local music playback.

The mini-player and full-screen player provide a consistent listening interface across the app, with system playback controls available while the device is locked.

### Lyrics with synchronized playback

Echo retrieves lyrics through LRCLIB, Musixmatch, and Genius. When synchronized lyrics are available, the lyrics view follows playback and supports seeking to individual lines. Plain lyrics provide a fallback when timing information is unavailable.

Provider availability, credentials, and track matching determine which lyrics can be displayed.

### Interactive Home Screen widgets

Access playback through four player widget layouts and a Quick Picks widget based on Echo's Home recommendations. Supported layouts provide playback controls and favorite actions, while Quick Picks starts selected songs directly.

A Lock Screen launcher provides quick access to Echo. Widgets share playback information and artwork with the app through an App Group.

## Installation

### Install an IPA with SideStore

1. Open the [Widget build workflow](https://github.com/Seperatebugle21/Echo/actions/workflows/WidgetBuild.yml) and select a successful run for the `Widget` branch.
2. Download the `Echo-Release-IPA` artifact and extract `Echo.ipa`.
3. Install the IPA through SideStore, retaining the `EchoWidget` extension.
4. Open Echo and import music or start playback before adding widgets from the Home Screen widget gallery.

The workflow packages an IPA for signing during installation. Both the app and its widget extension must retain access to the same App Group for widgets to receive library and playback data.

See [Widget setup and troubleshooting](WIDGETS.md) for signing requirements and SideStore-specific details.

### Build from source

#### Requirements

- A Mac with Xcode and an iOS 26 SDK.
- XcodeGen 2.45.4 or later.
- An Apple signing team with provisioning that supports the app, widget extension, and shared App Group for device installation.

#### Generate the Xcode project

```bash
git clone --branch Widget --single-branch https://github.com/Seperatebugle21/Echo.git
cd Echo
brew install xcodegen
xcodegen generate --spec project.yml
open Echo.xcodeproj
```

In Xcode:

1. Select the signing team for both `Echo` and `EchoWidget`.
2. Register and enable `group.com.echomusic.app` for both targets, using matching provisioning profiles.
3. Select the `Echo` scheme and an iOS 26 or later device.
4. Build and run the app.

The default bundle identifiers are `com.echomusic.app` and `com.echomusic.app.widget`. If you change them for your signing setup, keep the App Group configuration consistent across both targets.

Release archives also require `ECHO_PYTHON_BIN` to point to the resolved Python dependency's iOS device static library. The [build workflow](.github/workflows/WidgetBuild.yml) documents dependency resolution, Python linking, runtime verification, and IPA packaging.

The repository includes a Swift Playgrounds package, but Swift Playgrounds alone cannot package the WidgetKit extension. Use the generated Xcode project for the complete app with widgets.

## Service configuration

Local music playback works with imported files. Online features use external services and may require additional configuration.

| Integration | Purpose | Configuration or availability |
| --- | --- | --- |
| Spotify | Catalog search, library access, and playlist transfer | Spotify authentication for account features |
| Apple podcast search and public RSS feeds | Podcast discovery and episodes | Internet access; episode availability is determined by the publisher |
| LRCLIB | Plain and synchronized lyrics | Availability depends on the matching track |
| Musixmatch | Lyrics lookup | API key |
| Genius | Lyrics lookup | Access token |
| Apify | Provider-backed audio resolution | Account and provider configuration |
| yt-dlp | Audio source resolution | Embedded Python runtime and a supported source |

Downloaded podcast episodes and imported music can be played offline. New searches, streams, and uncached online content require a connection. Podcast access is based on public feeds; Apple subscriber-only audio is not included.

## Architecture

Echo uses SwiftUI for its interface and Apple's audio frameworks for playback. Local music uses an equalized audio player, while podcasts use `AVPlayer`, coordinated through a shared playback manager.

| Component | Location |
| --- | --- |
| App entry point, views, and models | `Echo.swiftpm/Echo/` |
| Playback, library, lyrics, and recommendations | `Echo.swiftpm/Echo/Managers/` |
| Audio discovery and downloads | `Echo.swiftpm/Echo/Fetch/` |
| Spotify integration | `Echo.swiftpm/Echo/Spotify/` |
| Podcast discovery, storage, and playback support | `Echo.swiftpm/Echo/Podcasts/` |
| Shared widget models and intents | `Echo.swiftpm/Echo/Widgets/` |
| WidgetKit extension | `EchoWidget/` |
| Native audio encoding wrapper | `Packages/EchoNativeAudio/` |
| Signing and extension configuration | `Configuration/` |
| XcodeGen project definition | `project.yml` |
| Unit tests | `Tests/` |

Dependencies include SwiftSoup, YoutubeDL-iOS, PythonKit, Python-iOS, and LAME through the native audio package. Swift Package Manager resolves the dependencies declared by the project.

## Testing

Generate the Xcode project, then run the relevant test scheme on an available iOS 26 or later Simulator:

- `EchoArtistTests`: artist credits and related model behavior.
- `EchoLyricsTests`: lyrics parsing and matching.
- `EchoWidgetModelTests`: widget snapshots, playback links, and shared storage configuration.
- `EchoPodcastTests`: podcast feeds, transcripts, persistence, and tab migration.

Device validation is also needed for background playback, AirPlay, interactive widgets, download behavior, and signing. The presence of a test scheme does not establish that a particular build has passed it.

## Contributing

Use [GitHub Issues](https://github.com/Seperatebugle21/Echo/issues) to report bugs or propose substantial improvements. For bug reports, include the branch or commit, device model, iOS version, installation method, and steps to reproduce the problem.

Keep pull requests focused, describe the resulting behavior, and include relevant build, test, or device validation. Changes to widget sharing or signing should account for both the app and extension.

## Documentation

- [Widgets: setup, shared storage, signing, and validation](WIDGETS.md)
- [Podcasts: behavior, architecture, and validation](PODCASTS.md)
- [Build and IPA packaging workflow](.github/workflows/WidgetBuild.yml)

## License

This branch currently does not include a license file. No open-source license is declared for Echo in this README. Third-party dependencies remain subject to their respective licenses.
