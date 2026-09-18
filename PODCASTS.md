# Podcasts in Echo

This change is based on the `Widget` branch. It adds Apple podcast search, public RSS episode lists, streaming, offline downloads, saved shows and episodes, and shared playback controls.

## Behaviour

- The default tabs are Home, Library, Podcasts, Fetch and Search. Only the old default arrangement migrates automatically. Custom arrangements and subsequent removal of Podcasts are preserved.
- Search uses Apple's iTunes Search API and the device's storefront region. Only results with a public HTTP(S) feed are offered. Episodes come from that publisher's RSS feed; Apple subscriber-only audio is not included.
- An episode menu offers save/unsave, play next, mark played/unplayed, download/cancel, and delete download. Its ellipsis has a 44-point touch target.
- Library contains Saved Podcasts, Saved Episodes and Downloads. Saving is independent of downloading and of saving the parent show.
- Podcast playback uses AVPlayer through the existing AudioPlayerManager and existing mini/full player surfaces. Music continues to use the existing equalized local player. Only one playback engine is active.
- Podcast controls include 15 seconds back, 30 seconds forward, speed selection, queueing, AirPlay and lock-screen metadata. Playback position is saved periodically and when pausing/switching/backgrounding.
- The background download session has its own identifier, persists pending jobs, and restores them at launch. A missing OS download task is retried from the beginning. Downloads move to Application Support and are excluded from backup. iOS controls background scheduling; force quitting can stop transfers until the next launch.
- Covers and feed metadata are cached for offline browsing. Downloaded audio is preferred for playback. The app's existing widgets can display and reopen podcast playback.
- All 46 new interface string keys are in the existing Localizable.xcstrings, with English, Dutch, French and German values. Podcast metadata is displayed in its original language.
- Podcast symbols use `dot.radiowaves.left.and.right`. Library shows separate podcast folders at the bottom using the existing CollectionCard style. Continue listening shows at most the two most recently listened-to unfinished episodes. The podcast home has an accent gradient header and material-backed show rows.

## Validation performed

- Parsed every changed/new Swift source with a Swift syntax grammar: no syntax errors. This does not replace Swift type-checking against the iOS SDK.
- Validated the string catalog as JSON; verified all new keys in all four languages and that existing translations are unchanged.
- Checked the diff for whitespace errors with the repository's CRLF line endings allowed.
- Live Apple search for `mysterieuze verhalen` returned `Mysterieuze Verhalen`; its public feed returned 16 audio episodes with publication dates, durations and descriptions at the time of validation.

## Xcode validation still required

This implementation was edited on Windows, so no Xcode build, XCTest run, Simulator run or physical-device test has been performed here.

Generate the project with `xcodegen generate --spec project.yml`. Run the new `EchoPodcastTests` scheme on an available iOS 26+ Simulator. These tests cover feed parsing, duplicate GUIDs, invalid/missing metadata, stable playback IDs, persistence and tab migration. The Widget build workflow now runs this scheme before its existing build steps.

Before release, also exercise:

1. Search, open a show, expand descriptions, save the show and a separate episode, and find both from Library.
2. Queue a podcast during music, and music during a podcast; check that only one audio engine plays and Next honours the queue.
3. Resume a partially played episode after switching content/relaunching; test scrubbing, playback speeds, interruptions and disconnecting headphones.
4. Download, cancel/retry, background/relaunch, then use airplane mode. Verify deleting a download preserves the saved episode and listening state.
5. Test the mini-player/full-player transition, Reduce Motion, VoiceOver, Dynamic Type and the 44-point menu target on iPhone and iPad.
6. Check lock-screen controls, player widgets, all four app languages, and unchanged music playback/lyrics/equalizer behaviour.

The public feed determines which episodes are available; some publishers limit archived episodes or omit dates/durations. Missing fields are omitted rather than invented.
