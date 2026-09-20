# Smart playlist validation

The `Smart playlist checks` workflow compiles and runs the actual Foundation models,
then typechecks all iOS application sources against the simulator SDK. It does not
archive, sign or publish an IPA, or resolve the app's unused Python dependencies.

On a Mac, the same commands are in `.github/workflows/smart-playlists.yml`.

Device checks before release:

- Create a regular playlist and verify adding, reordering and removing songs still works.
- Create each of the four smart examples; change all/any, text, dates, sort and limits.
- Cancel rule editing and verify no change; save and reopen to verify persistence.
- Change a favorite, import music and let a song qualify: counts and membership update.
- Start Never Played, let a song qualify and confirm the existing queue stays intact.
- Skip early, pause, seek near the end, replay, use Control Center and Siri: only actual
  listening counts, once per playback, at half the track or four minutes.
- Relaunch with existing playlists: manual membership, dates, artwork and favorites survive.
- Advance a rolling date boundary or foreground the app: date rules refresh within a minute.
- Check the editor with large text and VoiceOver, and in Dutch, English, French and German.

Existing `dateAdded` and `lastPlayed` values are retained. Missing play counts start
at zero; old counts are not inferred. Never Played means no known last-played date
and no recorded qualifying plays. Forgotten Favorites requires a known older listen.
