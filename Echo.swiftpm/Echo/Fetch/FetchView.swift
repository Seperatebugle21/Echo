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

    @State private var apifyUsage:
        ApifyUsageInfo?

    @State private var apifyUsageLoading =
        false

    @State private var apifyUsageError:
        String?

    @State private var fetchNavigationID =
        UUID()

    @State private var showDownloadsFromTrack =
        false

    @State private var showURLInput =
        false

    @State private var inlineURLPreview:
        FetchURLResolvedContent?

    var body: some View {

        NavigationStack {

            List {

                methodSection

                spotifySection

                musicSearchSection

                FetchURLInlineSection { content in
                    inlineURLPreview = content
                }

                if
                    apifySettings.downloadMethod
                    == .youtube
                {
                    apifySection
                }

                downloadsSection

                outputSection

                if !manager.items.isEmpty {
                    recentSection
                }
            }

            .navigationTitle(
                "fetchview_title"
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button {

                        showURLInput = true

                    } label: {

                        Image(
                            systemName: "link"
                        )
                    }
                    .accessibilityLabel(
                        "fetchview_fetch_url"
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

                    if newMethod == .youtube {

                        await loadApifyUsage()

                    } else {

                        apifyUsage = nil
                        apifyUsageError = nil
                        apifyUsageLoading = false
                    }
                }
            }
        }

        .id(fetchNavigationID)

        .onReceive(
            NotificationCenter.default
                .publisher(
                    for:
                        .echoOpenFetchDownloads
                )
        ) { _ in

            fetchNavigationID = UUID()

            DispatchQueue.main.async {

                showDownloadsFromTrack = true
            }
        }

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
                    choice: .skip,
                    applyToAll: false
                )
            }

            Button(
                String(
                    localized:
                        "action_replace"
                ),
                role: .destructive
            ) {

                library.resolveDuplicate(
                    choice: .replace,
                    applyToAll: false
                )
            }

            Button(
                String(
                    localized:
                        "action_skip_all"
                )
            ) {

                library.resolveDuplicate(
                    choice: .skip,
                    applyToAll: true
                )
            }

            Button(
                String(
                    localized:
                        "action_replace_all"
                ),
                role: .destructive
            ) {

                library.resolveDuplicate(
                    choice: .replace,
                    applyToAll: true
                )
            }

            Button(
                String(
                    localized:
                        "action_cancel"
                ),
                role: .cancel
            ) {}

        } message: {

            Text(
                "alert_duplicate_message \(library.duplicateSongName)"
            )
        }

        .sheet(
            isPresented:
                $showDownloadsFromTrack
        ) {

            NavigationStack {

                FetchQueueView()
                    .navigationTitle(
                        "fetchview_downloads"
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
                                "fetchview_done"
                            ) {

                                showDownloadsFromTrack = false
                            }
                        }
                    }
            }
        }

        .sheet(
            isPresented:
                $showURLInput
        ) {

            FetchURLInputSheet()
        }

        .sheet(
            item:
                $inlineURLPreview
        ) { content in

            NavigationStack {

                FetchURLPreviewView(
                    content: content
                )
            }
        }
    }

    private var methodSection:
        some View {

        Section {

            Picker(
                "fetchview_method",
                selection:
                    $apifySettings.downloadMethod
            ) {

                ForEach(
                    ApifyDownloadMethod.allCases
                ) { method in

                    Text(
                        method.title
                    )
                    .tag(method)
                }
            }
            .pickerStyle(.segmented)

            HStack(
                spacing: 12
            ) {

                Image(
                    systemName:
                        methodIcon
                )
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 30)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {

                    Text(
                        apifySettings
                            .downloadMethod
                            .title
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Text(
                        methodDescription
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)

        } header: {

            Text(
                "fetchview_download_method"
            )
        }
    }

    @ViewBuilder
    private var spotifySection:
        some View {

        Section {

            if spotify.isConnected {

                HStack {

                    Label(
                        "fetchview_spotify",
                        systemImage:
                            "checkmark.circle.fill"
                    )

                    Spacer()

                    Text(
                        "fetchview_connected"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.green)
                }

                NavigationLink {

                    SpotifyLibraryView()

                } label: {

                    Label(
                        "fetchview_your_library",
                        systemImage:
                            "music.note.list"
                    )
                }

                NavigationLink {

                    SpotifySearchView()

                } label: {

                    Label(
                        "fetchview_search_spotify",
                        systemImage:
                            "magnifyingglass"
                    )
                }

            } else {

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {

                    HStack(
                        spacing: 12
                    ) {

                        Image(
                            systemName:
                                "music.note"
                        )
                        .font(.title2)
                        .frame(width: 32)

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {

                            Text(
                                "fetchview_connect_spotify"
                            )
                            .font(.headline)

                            Text(
                                "fetchview_connect_spotify_description"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {

                        spotify.connect()

                    } label: {

                        HStack {

                            Spacer()

                            Label(
                                "fetchview_connect_spotify",
                                systemImage:
                                    "person.crop.circle.badge.plus"
                            )

                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 5)
            }

        } header: {

            Text(
                "fetchview_spotify"
            )

        } footer: {

            if spotify.isConnected {

                Text(
                    "fetchview_spotify_connected_footer"
                )

            } else {

                Text(
                    "fetchview_spotify_optional_footer"
                )
            }
        }
    }

    private var musicSearchSection:
        some View {

        Section {

            NavigationLink {

                MusicBrainzSearchView()

            } label: {

                Label(
                    "fetchview_search_musicbrainz",
                    systemImage:
                        "music.note.list"
                )
            }

            NavigationLink {

                YouTubeMusicSearchView()

            } label: {

                Label(
                    "fetchview_search_youtube_music",
                    systemImage:
                        "play.rectangle.fill"
                )
            }

        } header: {

            Text(
                "fetchview_music"
            )

        } footer: {

            Text(
                "fetchview_music_search_footer"
            )
        }
    }

    @ViewBuilder
    private var apifySection:
        some View {

        Section {

            NavigationLink {

                ApifyAccountsView()

            } label: {

                HStack {

                    Label(
                        "fetchview_apify_account",
                        systemImage:
                            "person.crop.circle"
                    )

                    Spacer()

                    if let account =
                        apifySettings.activeAccount
                    {

                        Text(
                            account.name
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    } else {

                        Text(
                            "fetchview_not_configured"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !apifySettings.isConfigured {

                Label(
                    "fetchview_add_apify_account_usage",
                    systemImage:
                        "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

            } else if apifyUsageLoading {

                HStack(
                    spacing: 10
                ) {

                    ProgressView()

                    Text(
                        "fetchview_loading_usage"
                    )
                    .foregroundStyle(.secondary)
                }

            } else if let usage =
                apifyUsage
            {

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {

                    HStack {

                        Text(
                            "fetchview_usage"
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
                        .foregroundStyle(.secondary)
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
                            systemImage: "cpu"
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)

            } else if let apifyUsageError {

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {

                    Label(
                        "fetchview_usage_unavailable",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .font(
                        .subheadline
                            .weight(.medium)
                    )

                    Text(
                        apifyUsageError
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button(
                        "fetchview_try_again"
                    ) {

                        Task {

                            await loadApifyUsage()
                        }
                    }
                }
                .padding(.vertical, 3)
            }

        } header: {

            Text(
                "fetchview_apify"
            )

        } footer: {

            Text(
                "fetchview_apify_footer"
            )
        }
    }

    private var downloadsSection:
        some View {

        Section {

            NavigationLink {

                FetchQueueView()

            } label: {

                HStack {

                    Label(
                        "fetchview_downloads",
                        systemImage:
                            "arrow.down.circle"
                    )

                    Spacer()

                    if activeDownloadCount > 0 {

                        Text(
                            String(
                                format:
                                    String(
                                        localized:
                                            "fetchview_active_downloads"
                                    ),
                                activeDownloadCount
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    } else if !manager.items.isEmpty {

                        Text(
                            "\(manager.items.count)"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }

        } header: {

            Text(
                "fetchview_downloads"
            )
        }
    }

    private var outputSection:
        some View {

        Section {

            Picker(
                "fetchview_audio_quality",
                selection:
                    $fetchSettings.quality
            ) {

                ForEach(
                    FetchQuality.allCases
                ) { quality in

                    Text(
                        quality.title
                    )
                    .tag(quality)
                }
            }

            Toggle(
                isOn:
                    $fetchSettings.embedArtwork
            ) {

                Label(
                    "fetchview_artwork",
                    systemImage: "photo"
                )
            }

        } header: {

            Text(
                "fetchview_output"
            )

        } footer: {

            Text(
                "fetchview_output_footer"
            )
        }
    }

    private var recentSection:
        some View {

        Section {

            ForEach(
                Array(
                    manager.items
                        .reversed()
                        .prefix(4)
                )
            ) { item in

                FetchItemRow(
                    item: item
                )
            }

            if manager.items.count > 4 {

                NavigationLink {

                    FetchQueueView()

                } label: {

                    Text(
                        "fetchview_view_all_downloads"
                    )
                }
            }

        } header: {

            Text(
                "fetchview_recent"
            )
        }
    }

    private var activeDownloadCount:
        Int {

        manager.items
            .filter { item in

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

            return String(
                localized:
                    "fetchview_method_apify_description"
            )

        case .spotify:

            return String(
                localized:
                    "fetchview_method_ytdlp_description"
            )
        }
    }

    private func refreshForCurrentMethod()
        async
    {

        if
            apifySettings.downloadMethod
            == .youtube
        {

            await loadApifyUsage()
        }
    }

    private func loadApifyUsage()
        async
    {

        guard
            apifySettings.downloadMethod
            == .youtube
        else {
            return
        }

        guard
            apifySettings.isConfigured
        else {

            apifyUsage = nil
            apifyUsageLoading = false
            apifyUsageError = nil
            return
        }

        apifyUsageLoading = true
        apifyUsageError = nil

        do {

            apifyUsage =
                try await
                ApifyUsageAPI.shared
                    .getUsage()

        } catch {

            apifyUsage = nil
            apifyUsageError =
                error.localizedDescription
        }

        apifyUsageLoading = false
    }
}
