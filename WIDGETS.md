# Echo widgets

Echo now includes two WidgetKit widgets:

- **Echo openen** - a circular Lock Screen widget that shows the Echo logo
  and opens the app.
- **Recente nummers** - a medium Home Screen widget with four album covers.
  Tapping a cover opens Echo and immediately starts that local song.

The song widget shows recently played songs first and fills any remaining
positions with recently added songs. The app writes small artwork thumbnails
to the shared app-group container whenever the library changes.

## Xcode setup

The original `.swiftpm` app remains available for Swift Playgrounds, but
Swift Playgrounds app packages cannot contain a WidgetKit extension. Use the
generated Xcode project when building the widget-enabled app:

1. Register `group.com.echomusic.app` as an App Group in the Apple Developer
   portal.
2. Enable that App Group for both bundle identifiers:
   `com.echomusic.app` and `com.echomusic.app.widget`.
3. Install XcodeGen and run `xcodegen generate --spec project.yml`.
4. Open `Echo.xcodeproj`, select your development team for both targets,
   and run the **Echo** scheme.

The existing `PlaylistTransferer.yml` workflow performs project generation
automatically and verifies that `EchoWidget.appex` is embedded in the
archive.
