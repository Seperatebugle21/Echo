# Player options and audio settings

Now Playing opens an anchored options popover from the ellipsis beside the song title. It reuses Echo Flow, shuffle, playlist selection, lyrics, artist/album detail screens, and the native AirPlay route picker. Podcast options remain available. Existing bottom-row shortcuts are retained.

The sleep timer offers 15/30/45/60 minutes, a custom 1–720 minute duration, and the end of the current song/episode. The playback manager owns the timer, independent of view lifetime. Timed deadlines continue across pauses; playback checks an overdue deadline before resuming after suspension. End-of-item stops before repeat/automatic advance and cancels prepared transitions. Selecting another item cancels an end-of-item timer but retains a timed deadline. Timers are session-scoped and do not persist after process termination.

Audio settings use the existing customization materials and cards. Each transition has its own explanation. The preview includes both track cards, source selection, a transition schematic, and actual per-track playback progress. Preview cancellation uses a generation guard so an older cancelled preview cannot stop a newer one.

Toolbar content receives a locally scoped primary tint. Explicit destructive colors and active content accents are retained; app-wide tint is unchanged.

## Validation

- 45 portable XCTest cases passed, including four new sleep-timer policy cases.
- All 215 Swift source files parsed with Swift 6.2 in the Linux workspace.
- Twenty new string keys have English, Dutch, French, and German translations; existing entries are unchanged.
- Native compilation is provided by the Widget GitHub Actions archive workflow after push.
- Physical-device checks remain necessary for locked-screen timer expiration, AirPlay presentation, end-of-item during an active crossfade/Mix, preview restoration, large accessibility text, and toolbar contrast in all themes. Linux syntax checks do not verify SwiftUI layout or iOS runtime behavior.
