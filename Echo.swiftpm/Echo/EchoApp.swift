import SwiftUI

@main
struct EchoApp: App {

    @UIApplicationDelegateAdaptor(
    EchoAppDelegate.self
    )
    private var appDelegate

    @AppStorage("selectedLanguage")
    private var selectedLanguage: String = "en"

    @AppStorage("appearanceMode")
    private var appearanceMode = "system"

    @Environment(\.scenePhase)
    private var scenePhase


    // BELANGRIJK:
    // FetchManager gebruikt MusicLibraryManager.shared.
    // De UI moet exact dezelfde instance gebruiken.

    @State private var library =
        MusicLibraryManager.shared

    @State private var audioPlayer =
        AudioPlayerManager.shared


    var body: some Scene {

        WindowGroup {

            ContentView()

                .environment(
                    \.locale,
                    Locale(
                        identifier:
                            selectedLanguage
                    )
                )

                .id(
                    selectedLanguage
                )

                .environment(
                    library
                )

                .environment(
                    audioPlayer
                )

                .preferredColorScheme(
                    colorScheme
                )


                // MARK: - Spotify Callback

                .onOpenURL { url in

                    Task {

                        await SpotifyManager.shared
                            .handleCallback(
                                url: url
                            )
                    }
                }


                // MARK: - Fetch Completed

                .onReceive(
                    NotificationCenter
                        .default
                        .publisher(
                            for:
                                .echoFetchCompleted
                        )
                ) { _ in

                    // Normaal staat het nummer al direct
                    // in MusicLibraryManager.shared.
                    //
                    // De sync blijft als extra safeguard
                    // voor bestanden in Documents.

                    library
                        .syncDocumentsFolder()
                }
        }


        // MARK: - Scene Phase

      .onChange(
    of:
        scenePhase
) { _, newPhase in

    if newPhase ==
        .active {

        library
            .syncDocumentsFolder()


        // Een background download kan klaar zijn
        // terwijl de telefoon gelockt was.
        //
        // Nu mag de normale Fetch pipeline
        // verdergaan naar LAME.

        FetchDownloadEngine.shared
            .resumeLiveCompletedTransfers()


        Task {

            await FetchManager.shared
                .restoreBackgroundDownloads()
        }
    }
}

    // MARK: - Appearance

    var colorScheme:
        ColorScheme? {

        switch appearanceMode {

        case "dark":

            return .dark


        case "light":

            return .light


        default:

            return nil
        }
    }
}
