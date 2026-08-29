import SwiftUI


struct FetchView: View {

    @State private var manager =
        FetchManager.shared

    @State private var fetchSettings =
        FetchSettings.shared

    @State private var apifySettings =
        ApifySettings.shared

    @State private var spotify =
        SpotifyManager.shared

    @State private var library =
        MusicLibraryManager.shared


    // MARK: - Apify Usage

    @State private var apifyUsage:
        ApifyUsageInfo?

    @State private var apifyUsageLoading =
        false

    @State private var apifyUsageError:
        String?


    // MARK: - Navigation

    @State private var fetchNavigationID =
        UUID()

    @State private var showDownloadsFromTrack =
        false

    @State private var showURLInput =
        false


    // MARK: - Inline URL Preview

    @State private var inlineURLPreview:
        FetchURLResolvedContent?


    var body: some View {

        NavigationStack {

            List {

                methodSection


                // Existing Spotify integration

                spotifySection


                // Login-free search sources

                musicSearchSection


                // Inline URL downloader

                FetchURLInlineSection {
                    content in

                    inlineURLPreview =
                        content
                }


                if apifySettings.downloadMethod ==
                    .youtube {

                    apifySection
                }


                downloadsSection

                outputSection


                if !manager.items.isEmpty {

                    recentSection
                }
            }

            .navigationTitle(
                "Fetch"
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button {

                        showURLInput =
                            true

                    } label: {

                        Image(
                            systemName:
                                "link"
                        )
                    }
                    .accessibilityLabel(
                        "Fetch URL"
                    )
                }
            }

            .task {

                await refreshForCurrentMethod()
            }

            .onChange(
                of:
                    apifySettings.downloadMethod
            ) {
                _,
                newMethod in


                Task {

                    if newMethod ==
                        .youtube {

                        await loadApifyUsage()

                    } else {

                        apifyUsage =
                            nil

                        apifyUsageError =
                            nil

                        apifyUsageLoading =
                            false
                    }
                }
            }
        }

        .id(
            fetchNavigationID
        )


        // MARK: - Open Downloads Notification

        .onReceive(
            NotificationCenter.default
                .publisher(
                    for:
                        .echoOpenFetchDownloads
                )
        ) {
            _ in


            fetchNavigationID =
                UUID()


            DispatchQueue.main.async {

                showDownloadsFromTrack =
                    true
            }
        }


        // MARK: - Duplicate Alert

        .alert(
            Text(
                "alert_duplicate_title"
            ),
            isPresented:
                Bindable(library)
                    .showDuplicateAlert
        ) {

            Button(
                String(
                    localized:
                        "action_skip"
                )
            ) {

                library.resolveDuplicate(
                    choice:
                        .skip,
                    applyToAll:
                        false
                )
            }


            Button(
                String(
                    localized:
                        "action_replace"
                ),
                role:
                    .destructive
            ) {

                library.resolveDuplicate(
                    choice:
                        .replace,
                    applyToAll:
                        false
                )
            }


            Button(
                String(
                    localized:
                        "action_skip_all"
                )
            ) {

                library.resolveDuplicate(
                    choice:
                        .skip,
                    applyToAll:
                        true
                )
            }


            Button(
                String(
                    localized:
                        "action_replace_all"
                ),
                role:
                    .destructive
            ) {

                library.resolveDuplicate(
                    choice:
                        .replace,
                    applyToAll:
                        true
                )
            }


            Button(
                String(
                    localized:
                        "action_cancel"
                ),
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                "alert_duplicate_message \(library.duplicateSongName)"
            )
        }


        // MARK: - Downloads Sheet

        .sheet(
            isPresented:
                $showDownloadsFromTrack
        ) {

            NavigationStack {

                FetchQueueView()

                    .navigationTitle(
                        "Downloads"
                    )

                    .navigationBarTitleDisplayMode(
                        .inline
                    )

                    .toolbar {

                        ToolbarItem(
                            placement:
                                .topBarTrailing
                        ) {

                            Button(
                                "Done"
                            ) {

                                showDownloadsFromTrack =
                                    false
                            }
                        }
                    }
            }
        }


        // MARK: - Toolbar URL Sheet

        .sheet(
            isPresented:
                $showURLInput
        ) {

            FetchURLInputSheet()
        }


        // MARK: - Inline URL Preview Sheet
        //
        // Important:
        // This sheet is presented by FetchView itself,
        // NOT by the Section inside the List.
        //
        // That prevents the sheet from instantly
        // disappearing during a List refresh.

        .sheet(
            item:
                $inlineURLPreview
        ) {
            content in

            NavigationStack {

                FetchURLPreviewView(
                    content:
                        content
                )
            }
        }
    }


    // MARK: - Download Method

    private var methodSection:
        some View {

        Section {

            Picker(
                "Method",
                selection:
                    $apifySettings.downloadMethod
            ) {

                ForEach(
                    ApifyDownloadMethod.allCases
                ) {
                    method in


                    Text(
                        method.title
                    )
                    .tag(
                        method
                    )
                }
            }
            .pickerStyle(
                .segmented
            )


            HStack(
                spacing:
                    12
            ) {

                Image(
                    systemName:
                        methodIcon
                )
                .font(
                    .title3
                )
                .foregroundStyle(
                    .secondary
                )
                .frame(
                    width:
                        30
                )


                VStack(
                    alignment:
                        .leading,
                    spacing:
                        2
                ) {

                    Text(
                        apifySettings
                            .downloadMethod
                            .title
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )


                    Text(
                        methodDescription
                    )
                    .font(
                        .caption
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
            .padding(
                .vertical,
                3
            )

        } header: {

            Text(
                "Download Method"
            )
        }
    }


    // MARK: - Spotify

    @ViewBuilder
    private var spotifySection:
        some View {

        Section {

            if spotify.isConnected {

                HStack {

                    Label(
                        "Spotify",
                        systemImage:
                            "checkmark.circle.fill"
                    )


                    Spacer()


                    Text(
                        "Connected"
                    )
                    .font(
                        .subheadline
                    )
                    .foregroundStyle(
                        .green
                    )
                }


                NavigationLink {

                    SpotifyLibraryView()

                } label: {

                    Label(
                        "Your Library",
                        systemImage:
                            "music.note.list"
                    )
                }


                NavigationLink {

                    SpotifySearchView()

                } label: {

                    Label(
                        "Search Spotify",
                        systemImage:
                            "magnifyingglass"
                    )
                }

            } else {

                VStack(
                    alignment:
                        .leading,
                    spacing:
                        10
                ) {

                    HStack(
                        spacing:
                            12
                    ) {

                        Image(
                            systemName:
                                "music.note"
                        )
                        .font(
                            .title2
                        )
                        .frame(
                            width:
                                32
                        )


                        VStack(
                            alignment:
                                .leading,
                            spacing:
                                2
                        ) {

                            Text(
                                "Connect Spotify"
                            )
                            .font(
                                .headline
                            )


                            Text(
                                "Connect your account to browse your library and search Spotify."
                            )
                            .font(
                                .caption
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }


                    Button {

                        spotify.connect()

                    } label: {

                        HStack {

                            Spacer()


                            Label(
                                "Connect Spotify",
                                systemImage:
                                    "person.crop.circle.badge.plus"
                            )


                            Spacer()
                        }
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                }
                .padding(
                    .vertical,
                    5
                )
            }

        } header: {

            Text(
                "Spotify"
            )

        } footer: {

            if spotify.isConnected {

                Text(
                    "Choose music from your Spotify library or search the Spotify catalog."
                )

            } else {

                Text(
                    "Spotify is optional. You can also search music without an account below."
                )
            }
        }
    }


    // MARK: - Music Search

    private var musicSearchSection:
        some View {

        Section {

            NavigationLink {

                MusicBrainzSearchView()

            } label: {

                Label(
                    "Search MusicBrainz",
                    systemImage:
                        "music.note.list"
                )
            }


            NavigationLink {

                YouTubeMusicSearchView()

            } label: {

                Label(
                    "Search YouTube Music",
                    systemImage:
                        "play.rectangle.fill"
                )
            }

        } header: {

            Text(
                "Music"
            )

        } footer: {

            Text(
                "Search MusicBrainz or YouTube without requiring a Spotify account."
            )
        }
    }


    // MARK: - Apify

    @ViewBuilder
    private var apifySection:
        some View {

        Section {

            NavigationLink {

                ApifyAccountsView()

            } label: {

                HStack {

                    Label(
                        "Apify Account",
                        systemImage:
                            "person.crop.circle"
                    )


                    Spacer()


                    if let account =
                        apifySettings.activeAccount {

                        Text(
                            account.name
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(
                            1
                        )

                    } else {

                        Text(
                            "Not configured"
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }


            if !apifySettings.isConfigured {

                Label(
                    "Add an Apify account to view usage.",
                    systemImage:
                        "info.circle"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )


            } else if apifyUsageLoading {

                HStack(
                    spacing:
                        10
                ) {

                    ProgressView()


                    Text(
                        "Loading usage…"
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }


            } else if let usage =
                apifyUsage {

                VStack(
                    alignment:
                        .leading,
                    spacing:
                        10
                ) {

                    HStack {

                        Text(
                            "Usage"
                        )


                        Spacer()


                        Text(
                            String(
                                format:
                                    "$%.2f / $%.2f",
                                usage.usedUSD,
                                usage.maxUSD
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .monospacedDigit()
                    }


                    ProgressView(
                        value:
                            usage.usageFraction
                    )


                    HStack {

                        Label(
                            String(
                                format:
                                    "%.3f CU",
                                usage.actorComputeUnits
                            ),
                            systemImage:
                                "cpu"
                        )


                        Spacer()


                        Label(
                            String(
                                format:
                                    "%.3f GB",
                                usage.externalTransferGB
                            ),
                            systemImage:
                                "arrow.up.arrow.down"
                        )
                    }
                    .font(
                        .caption
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
                .padding(
                    .vertical,
                    3
                )


            } else if let apifyUsageError {

                VStack(
                    alignment:
                        .leading,
                    spacing:
                        8
                ) {

                    Label(
                        "Usage unavailable",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .font(
                        .subheadline
                            .weight(
                                .medium
                            )
                    )


                    Text(
                        apifyUsageError
                    )
                    .font(
                        .caption
                    )
                    .foregroundStyle(
                        .secondary
                    )


                    Button(
                        "Try Again"
                    ) {

                        Task {

                            await loadApifyUsage()
                        }
                    }
                }
                .padding(
                    .vertical,
                    3
                )
            }

        } header: {

            Text(
                "Apify"
            )

        } footer: {

            Text(
                "Apify usage is only relevant when the Apify download method is selected."
            )
        }
    }


    // MARK: - Downloads

    private var downloadsSection:
        some View {

        Section {

            NavigationLink {

                FetchQueueView()

            } label: {

                HStack {

                    Label(
                        "Downloads",
                        systemImage:
                            "arrow.down.circle"
                    )


                    Spacer()


                    if activeDownloadCount >
                        0 {

                        Text(
                            "\(activeDownloadCount) active"
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )

                    } else if !manager.items.isEmpty {

                        Text(
                            "\(manager.items.count)"
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }

        } header: {

            Text(
                "Downloads"
            )
        }
    }


    // MARK: - Output

    private var outputSection:
        some View {

        Section {

            Picker(
                "Audio Quality",
                selection:
                    $fetchSettings.quality
            ) {

                ForEach(
                    FetchQuality.allCases
                ) {
                    quality in


                    Text(
                        quality.title
                    )
                    .tag(
                        quality
                    )
                }
            }


            Toggle(
                isOn:
                    $fetchSettings.embedMetadata
            ) {

                Label(
                    "Metadata",
                    systemImage:
                        "text.badge.checkmark"
                )
            }


            Toggle(
                isOn:
                    $fetchSettings.embedArtwork
            ) {

                Label(
                    "Artwork",
                    systemImage:
                        "photo"
                )
            }

        } header: {

            Text(
                "Output"
            )

        } footer: {

            Text(
                "Downloaded songs are saved as MP3 files in your Echo library."
            )
        }
    }


    // MARK: - Recent

    private var recentSection:
        some View {

        Section {

            ForEach(
                Array(
                    manager.items
                        .reversed()
                        .prefix(
                            4
                        )
                )
            ) {
                item in


                FetchItemRow(
                    item:
                        item
                )
            }


            if manager.items.count >
                4 {

                NavigationLink {

                    FetchQueueView()

                } label: {

                    Text(
                        "View All Downloads"
                    )
                }
            }

        } header: {

            Text(
                "Recent"
            )
        }
    }


    // MARK: - Active Downloads

    private var activeDownloadCount:
        Int {

        manager.items
            .filter {
                item in


                switch item.status {

                case .preparing,
                     .downloading,
                     .processing:

                    return true


                default:

                    return false
                }
            }
            .count
    }


    // MARK: - Method Presentation

    private var methodIcon:
        String {

        switch apifySettings.downloadMethod {

        case .youtube:

            return "cloud"


        case .spotify:

            return "terminal"
        }
    }


    private var methodDescription:
        String {

        switch apifySettings.downloadMethod {

        case .youtube:

            return
                "Downloads are processed through your configured Apify account."


        case .spotify:

            return
                "Audio is resolved locally with the embedded yt-dlp engine."
        }
    }


    // MARK: - Refresh

    private func refreshForCurrentMethod()
        async {

        if apifySettings.downloadMethod ==
            .youtube {

            await loadApifyUsage()
        }
    }


    // MARK: - Apify Usage

    private func loadApifyUsage()
        async {

        guard
            apifySettings.downloadMethod ==
                .youtube
        else {

            return
        }


        guard
            apifySettings.isConfigured
        else {

            apifyUsage =
                nil

            apifyUsageLoading =
                false

            apifyUsageError =
                nil

            return
        }


        apifyUsageLoading =
            true

        apifyUsageError =
            nil


        do {

            apifyUsage =
                try await
                ApifyUsageAPI.shared
                    .getUsage()

        } catch {

            apifyUsage =
                nil


            apifyUsageError =
                error.localizedDescription
        }


        apifyUsageLoading =
            false
    }
}
