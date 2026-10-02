# Widget branch feature update

## Included

- Custom solid/gradient backgrounds, color presets, a live preview, black/white text and a visual dark-background selector. Album-based full-player visuals are retained.
- Library add actions for normal/smart playlists, audio import and Fetch navigation. Hidden destinations open without changing saved tabs.
- Smart playlist presets and an editable rule builder, including genre and release-year/decade filters. Results are evaluated centrally and track library, favorites, listening and calendar changes. Siri also evaluates smart playlists.
- Asynchronous genre/year enrichment for existing and newly imported files; editable genre/year fields. File creation dates are not treated as release years.
- Persistent daily listening counts alongside existing lifetime totals. Playback starts are registered centrally; pause/resume, podcasts and previews do not add music plays.
- Direct, gapless, adjustable 1–12-second crossfade and automatic beat-matched Mix modes for local music. One audio graph uses two normalized PCM decks, shared EQ, mono/stereo processing, equal-power gain envelopes and latency-aware scheduling.
- Mix analyzes intro/outro energy and periodic onsets, aligns reliable beats, limits tempo adjustment to ±8%, and preserves pitch. Incompatible or uncertain beats use an automatic energy-based crossfade.
- Built-in and library-based transition previews, limited to 20 seconds, with normal playback restoration. The two bundled WAV recordings are original synthesized examples created for this change; no third-party music is included.
- Per-show podcast notifications, baseline/deduplication storage, background refresh and notification navigation. Following remains independent of saving a podcast.
- 115 new string-catalog keys with English, Dutch, French and German values. Existing catalog entries are unchanged.

## Validation available on Windows

The Foundation-based production playlist models, evaluator and transition DSP were compiled with Swift and exercised using the same test methods as the new XCTest suite, through a lightweight assertion runner because this Windows toolchain does not ship XCTest. The podcast release detector and Codable follow storage were also exercised; the generated Windows model subset excludes only the CryptoKit-dependent artwork/playback hash accessors.

Ten logic cases passed: decade boundaries, missing metadata, any/all rules and ordering, legacy storage, daily windows, equal-power headroom, tempo compatibility/fallback, synthetic beat detection, episode deduplication/future dates and follow persistence.

All app and test Swift files were checked with `swiftc -frontend -parse`. The string catalog was parsed, all four translations and format arguments checked, and existing values compared with the Git baseline. Both background-refresh manifests and both preview WAV files were validated. Parsing is not iOS SDK type-checking.

## Required Mac validation

No iOS build, native XCTest run, simulator UI inspection or physical-device audio test has been performed in the Windows workspace. In particular, audible continuity, pitch-unit latency, AirPlay and interruption behavior still require device validation.

```sh
xcodegen generate --spec project.yml
xcodebuild -project Echo.xcodeproj -scheme EchoFeatureTests \
  -destination 'platform=iOS Simulator,name=YOUR_IOS_26_SIMULATOR' test
xcodebuild -project Echo.xcodeproj -scheme EchoPodcastTests \
  -destination 'platform=iOS Simulator,name=YOUR_IOS_26_SIMULATOR' test
```

The `EchoFeatureTests` scheme includes the pure logic tests, podcast release tests, legacy/custom theme persistence and native engine tests for seeking, format replacement and one-time gapless promotion. Existing artist, lyrics and widget schemes remain available.

Before release, exercise:

1. All theme modes, sheets, gradients and black/white text with Dynamic Type, VoiceOver and Reduce Motion.
2. All Library actions with Fetch/Podcasts tabs both visible and hidden; smart playlists with empty/missing tags and newly imported/played/favorited songs.
3. Direct/gapless/crossfade/Mix on short and long files, mono/stereo, different sample rates, repeat-one/all and auto-next. Check beat-aligned music and the nonrhythmic fallback.
4. Pause/resume, seek, reorder/remove queue entries, change transition settings, lock the screen, interrupt playback and disconnect headphones during an overlap.
5. Built-in/custom previews while music or a podcast is paused/playing; close, cancel, switch tracks and verify queue/position restoration and unchanged listening counters/widgets.
6. Enable/deny/revoke notification permission; follow/unfollow shows; detect multiple/undated/future episodes; cold-start from a notification; retry offline feeds.
7. Verify AirPlay, lock-screen metadata, EQ, lyrics and widgets on a physical device.

Without a server, iOS chooses background refresh timing. The requested one-hour earliest date is not a delivery guarantee. See [Apple background-task documentation](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).
