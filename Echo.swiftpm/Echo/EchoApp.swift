import SwiftUI


@main
struct EchoApp: App {

    @UIApplicationDelegateAdaptor(
        EchoAppDelegate.self
    )
    private var appDelegate


    @AppStorage(
        "selectedLanguage"
    )
    private var selectedLanguage:
        String = "en"


    @AppStorage(
        "appearanceMode"
    )
    private var appearanceMode =
        "system"


    @Environment(
        \.scenePhase
    )
    private var scenePhase


    @State private var library =
        MusicLibraryManager.shared


    @State private var audioPlayer =
        AudioPlayerManager.shared


    var body: some Scene {

        WindowGroup {

            ContentView()

                // MARK: - Language

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


                // MARK: - Shared Managers

                .environment(
                    library
                )

                .environment(
                    audioPlayer
                )


                // MARK: - Appearance

                .preferredColorScheme(
                    colorScheme
                )


                // MARK: - Prepare Background Fetch

                .task {

                    FetchDownloadEngine.shared
                        .prepare()


                    await FetchManager.shared
                        .restoreBackgroundDownloads()
                }


                // MARK: - Spotify Callback

                .onOpenURL { url in

                    Task {

                        await SpotifyManager.shared
                            .handleCallback(
                                url:
                                    url
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

                // Refresh files that may have been
                // completed in the background.

                library
                    .syncDocumentsFolder()


                // If a background URLSession transfer
                // finished while Echo was suspended,
                // resume the existing async pipeline.

                FetchDownloadEngine.shared
                    .resumeLiveCompletedTransfers()


                // Also recover transfers after a full
                // app relaunch.

                Task {

                    await FetchManager.shared
                        .restoreBackgroundDownloads()
                }
            }
        }
    }


    // MARK: - Appearance

    private var colorScheme:
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
