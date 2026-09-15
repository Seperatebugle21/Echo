# Echo widgets

Echo has five separately selectable Home Screen widgets plus the existing circular Lock Screen launcher:

1. **Speler · Zachte cover** (medium): inset rounded artwork, adaptive dark background, favorite and previous/play-pause/next.
2. **Speler · Albumcover** (small): full artwork with title and artist overlay; tap to start that song.
3. **Speler · Volle cover** (medium): full-height artwork on the left, metadata and controls on the right.
4. **Speler · Compact** (small): thumbnail, favorite, title/artist and transport controls.
5. **Quick Picks** (medium): the first four available recommendations from the same HomeSessionManager selection used by Home, with real artwork and individual playback buttons.

The existing recent-songs widget kind is retained for Quick Picks, so already installed instances migrate. The lock-screen launcher remains unchanged.

## Data and playback

The app writes the displayed song, playing/favorite state and up to four Quick Picks to an atomic JSON snapshot in the shared App Group. Artwork is downsampled to 360 pixels, embedded in the snapshot and cached in the app. The extension needs no network access or access to private audio files to display covers.

Updates are requested on library, current-song and playing/favorite changes, and on app startup and scene transitions. Consecutive mutations are coalesced; unchanged content is not rewritten. Gallery examples are generated only for previews, never substituted for real library data.

AudioPlaybackIntent routes controls to the app process, using AudioPlayerManager. Quick Picks selects the exact song UUID. The extension compiles the shared intent definition with ECHO_WIDGET_EXTENSION; player implementation is linked only in the app. Existing echo://play links remain supported.

## Build and installation

1. Register group.com.echomusic.app as an App Group in the Apple Developer portal.
2. Enable the SAME App Group for com.echomusic.app and com.echomusic.app.widget and regenerate both provisioning profiles.
3. Install XcodeGen, run `xcodegen generate --spec project.yml`, open Echo.xcodeproj and select the signing team for BOTH targets.
4. Build/install the Echo scheme and open Echo once to publish the library snapshot.
5. Add the widgets through the Home Screen widget gallery.

Swift Playgrounds alone cannot package this WidgetKit extension. The WidgetBuild workflow builds without a developer certificate, then adds ad-hoc Mach-O signatures carrying the App Group entitlement to both executables. It verifies the embedded groups before packaging; SideStore performs the final signing with the user's profiles. These ad-hoc signatures are metadata for the installer, not installable enterprise signatures.

## SideStore installation

Build the updated Widget branch with WidgetBuild.yml and download Echo-Release-IPA from the successful run. Install the new Echo.ipa through SideStore, retaining the EchoWidget extension. Update the existing app, open Echo once and start a song, then check the widgets. Refreshing the old installed IPA alone does not include this code/build fix.

SideStore writes the actual provisioned groups into each bundle's ALTAppGroups Info.plist entry. The shared snapshot code now resolves matching group.com.echomusic.app.<team> entries from that metadata, checking container access, with the original group as fallback for standard signing. It does not guess team IDs or select unrelated groups. Both processes use the same resolution logic and stable ordering. This covers SideStore's normal group suffix mapping; a custom replacement of the entire bundle/group namespace is not supported by this resolver.

The packaging workflow also preserves echo:// links; previously its Spotify URL configuration replaced the Echo launcher scheme.

If the installer omits the group entitlement entirely, the resolver cannot grant missing access: the connection state remains visible and the app logs the storage failure. A successful archive is not proof that the final installation has shared access.

Implementation references: [SideStore metadata key](https://github.com/SideStore/SideStore/blob/develop/Shared/Extensions/Bundle%2BAltStore.swift), [metadata population](https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift), [group provisioning](https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift).

## Validation

Run the EchoWidgetModelTests scheme on an available iOS Simulator. WidgetBuild runs these tests before archiving. They cover the previous JSON format, state/artwork round-tripping, missing artwork, empty libraries and legacy playback URLs.

Five additional tests cover SideStore group selection, standard signing, denied/unrelated groups, missing permissions and consistent selection across app/extension metadata ordering.

EchoWidgetPreviews.swift contains all five layouts and an empty-state preview.

Device checks still required:
- Install with valid shared entitlements; import tracks with artwork and open Echo.
- Add all five widgets; compare with Home Quick Picks.
- Play/pause/skip from the widget with Echo foregrounded, backgrounded and after a cold launch.
- Toggle favorites in both places, edit artwork, delete a displayed song, then delete/reimport the entire library.
- Inspect small/medium widgets, long titles, larger text and tinted Home Screen appearance.
- Validate after device locking/unlocking and app relaunch; system widget scheduling can delay updates.

This change was prepared on Windows. Swift parsing, project paths and App Group declarations were checked; Xcode compilation, XCTest execution and actual device rendering have not been run locally.
