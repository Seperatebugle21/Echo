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
- 138 new string-catalog keys with English, Dutch, French and German values. Existing catalog entries are unchanged.

## Validation available on Windows

The Foundation-based production playlist models, evaluator and transition DSP were compiled with Swift and exercised using the same test methods as the new XCTest suite, through a lightweight assertion runner because this Windows toolchain does not ship XCTest. The podcast release detector and Codable follow storage were also exercised; the generated Windows model subset excludes only the CryptoKit-dependent artwork/playback hash accessors.

Seventeen logic cases passed in Swift 5 language mode with optimized whole-module compilation: decade boundaries, missing metadata, any/all rules and ordering, legacy storage, daily windows, equal-power headroom, tempo compatibility/fallback, synthetic beat detection, offset beat phase, episode deduplication/future dates, follow persistence, metadata batch preservation, precomputed listening windows and background persistence with stale-snapshot/deletion protection.

The two compiler errors reported by GitHub Actions run 37038588065 were addressed: the evaluator's local results no longer shadow its `matches` function, and beat-phase selection uses explicit loops instead of an expression that exceeded Xcode's type-checking limit. A new iOS archive still needs to confirm the fix on Xcode.

All app and test Swift files were checked with `swiftc -frontend -parse`. The string catalog was parsed, all four translations and format arguments checked, and existing values compared with the Git baseline. Both background-refresh manifests and both preview WAV files were validated. Parsing is not iOS SDK type-checking.

## Navigation performance repair

The genre/year migration previously mutated the observable song array up to three times per track. Each mutation synchronously encoded and atomically wrote the entire library, including artwork, and requested artist/widget updates. Metadata now publishes one change per batch of at most 24 songs and requests only relevant metadata values. JSON encoding and atomic persistence run on a coalescing serial utility queue. Backgrounding requests an immediate save and holds an iOS background task until persistence completes. Loading the library no longer writes it straight back to disk.

Playlist evaluation previously recalculated listening windows in every sort comparison. Counts are now computed once per required window. The library also reuses its song index and smart results while their inputs are unchanged. Cache invalidation observes song/favorite/listening revisions, rule changes and the playlist clock. Artist work is debounced; metadata and podcast checks run independently from Fetch initialization.

A Windows Swift 5-mode optimized benchmark evaluated the same playlist five times for 1,500 synthetic tracks with 90 days of counts. The previous evaluator took 5.012 seconds; the updated evaluator took 0.057 seconds and produced identical playlists. This measures evaluator CPU work, not navigation latency on an iPhone. Native build and device responsiveness still need verification.

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

## Audio and playlist reliability update

Local playback now has asynchronous open/decoder/control queues and locked UI snapshots, with preparing, playing, paused, seeking, transitioning, recovering and failed states. Seek reuses the decoder rather than rebuilding a graph. Old commands and buffer callbacks are rejected by generation/version; only render progress confirms playback. Converter starvation triggers refill rather than premature completion. The prepared two-deck graph bypasses tempo processing at unity rate. EQ configurations are captured before audio-queue delivery and persistence is coalesced while dragging.

A two-second no-progress watchdog (plus output latency) rebuilds once at the intended position. Another failure exposes a localized retry action. Incoming promotion updates the recovery URL and progress baseline. Opening a new track remains possible after failure. Final played-back callbacks cover very short tracks that finish between progress samples. Listening updates occur once per actual start, outside the critical start path; view-level duplicate registrations were removed. Album artwork for the lock screen is decoded by the shared background thumbnail cache. Podcasts retain their AVPlayer path.

The playlist editor is shared between normal and smart creation/editing, retaining name/cover drafts across the mode switch. Forty-eight text-free JPEG covers are bundled: 24 original procedural gradients/patterns/symbols and 24 illustrations generated separately with the imagegen tool for this app. Their files are 512 pixels square and decoded as small thumbnails outside the main thread. Custom photos are orientation-corrected and cropped with drag/zoom, VoiceOver directional actions and explicit confirmation to a 1024-pixel square JPEG. Unknown built-in IDs fall back to the default icon. Built-in IDs and automatic name keys are optional Codable fields; no legacy name-origin guesses are made. Name resolution explicitly uses the selected app-language bundle. Manually entered names remain literal, including spacing.

The equalizer uses theme materials, an interpolated curve, six accessible faders and preset tiles. Accessibility text sizes switch to horizontal controls. Reset, six original bands, gain limits, presets, headroom and saved configuration remain available; live EQ updates do not restart the engine.

The three additional Windows logic cases cover cover/name migration with literal legacy names, explicit four-language bundles, and crop coverage/pan bounds. The live iOS engine suite was rewritten for asynchronous playback and includes format replacement, paused seek, gapless promotion, rapid replacements/seeks, corrupt-file recovery, temporary empty converter output, and one-time stall recovery followed by an actionable failure. Debug-only fault injection is absent from Release. These native cases have not been executed here.

## Native latency protocol

Use the same physical iPhone, build, route and local files for all runs. Test 100, 1,000 and 5,000 library tracks, each with sparse and dense listening history. Perform at least 30 cold local starts, warm starts and playing/paused seeks per condition. Include MP3/AAC/WAV, 22.05/44.1/48 kHz, very short/silent/corrupt files and repeated rapid selections. Inspect the Playback OSLog category's `First advancing render` events (or `onFirstRender` in a native test harness). They use the player's render host/sample clock and include preparation rather than measuring only the UI play icon; the monitor observes them at most 50 ms later. Independently confirm output on iPhone because rendered frames do not establish audible route behavior.

Record median, P95, maximum, recoveries and failures. Targets are P95 <500 ms for warm starts/seeks and <1 second for cold starts. No start/seek target has been measured or claimed on Windows. Run the injected starvation/stall cases, then repeat queue/repeat/preview/interruption/AirPlay/lockscreen/widget scenarios listed above. Check cover cancel/orientation/storage, both editor modes, literal and automatic names after language/preset changes, and EQ with all themes and accessibility settings.

EOF in a separate empty converter output waits for render-clock tail completion and output latency; it does not inject or trim silence. Very short incoming tracks are promoted at completion if they finish between monitor ticks. Both very-short-track scenarios have explicit native regression tests.
