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


    @AppStorage(
        "hasCompletedEchoOnboarding"
    )
    private var hasCompletedEchoOnboarding =
        false


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

            Group {

                if hasCompletedEchoOnboarding {

                    ContentView()
                        .transition(
                            .opacity
                        )

                } else {

                    EchoOnboardingView {

                        withAnimation(
                            .easeInOut(
                                duration: 0.55
                            )
                        ) {

                            hasCompletedEchoOnboarding =
                                true
                        }
                    }
                    .transition(
                        .opacity
                    )
                }
            }

            .animation(
                .easeInOut(
                    duration: 0.55
                ),
                value:
                    hasCompletedEchoOnboarding
            )


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
                .active
            {

                library
                    .syncDocumentsFolder()


                FetchDownloadEngine.shared
                    .resumeLiveCompletedTransfers()


                Task {

                    await FetchManager.shared
                        .restoreBackgroundDownloads()
                }
            }
        }
    }


    // MARK: - Appearance

    private var colorScheme:
        ColorScheme?
    {

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
