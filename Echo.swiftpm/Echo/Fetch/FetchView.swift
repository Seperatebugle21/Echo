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


    // MARK: - Body

    var body: some View {

        NavigationStack {

            ScrollView {

                LazyVStack(
                    alignment: .leading,
                    spacing: 32
                ) {

                    header

                    urlImportSection

                    spotifySection

                    musicSearchSection

                    downloadsSection

                    outputSection

                    if apifySettings.downloadMethod == .youtube {
                        apifySection
                    }

                    if !manager.items.isEmpty {
                        recentSection
                    }
                }
                .padding(.bottom, 120)
            }
            .refreshable {
                await refreshForCurrentMethod()
            }
            .task {
                await refreshForCurrentMethod()
            }
            .onChange(
                of: apifySettings.downloadMethod
            ) { _, newMethod in

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
                    for: .echoOpenFetchDownloads
                )
        ) { _ in

            fetchNavigationID = UUID()

            DispatchQueue.main.async {
                showDownloadsFromTrack = true
            }
        }
        .alert(
            Text("alert_duplicate_title"),
            isPresented:
                Bindable(library)
                    .showDuplicateAlert
        ) {

            Button(
                String(
                    localized: "action_skip"
                )
            ) {

                library.resolveDuplicate(
                    choice: .skip,
                    applyToAll: false
                )
            }

            Button(
                String(
                    localized: "action_replace"
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
                    localized: "action_skip_all"
                )
            ) {

                library.resolveDuplicate(
                    choice: .skip,
                    applyToAll: true
                )
            }

            Button(
                String(
                    localized: "action_replace_all"
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
                    localized: "action_cancel"
                ),
                role: .cancel
            ) {}

        } message: {

            Text(
                "alert_duplicate_message \(library.duplicateSongName)"
            )
        }
        .sheet(
            isPresented: $showDownloadsFromTrack
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
                            placement: .topBarTrailing
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
            isPresented: $showURLInput
        ) {

            FetchURLInputSheet()
        }
    }


    // MARK: - Header

    private var header: some View {

        HStack(
            alignment: .center
        ) {

            Text("fetchview_title")
                .font(.largeTitle.bold())

            Spacer()

            Button {

                showURLInput = true

            } label: {

                Image(
                    systemName: "link"
                )
                .font(
                    .title3
                        .weight(.medium)
                )
                .foregroundStyle(.primary)
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    .thinMaterial,
                    in: Circle()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "fetchview_fetch_url"
            )
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }


    // MARK: - URL Import

    private var urlImportSection: some View {

        Button {

            showURLInput = true

        } label: {

            HStack(
                spacing: 17
            ) {

                Image(
                    systemName: "link.badge.plus"
                )
                .font(
                    .system(
                        size: 25,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
                .frame(
                    width: 58,
                    height: 58
                )
                .background(
                    Color.accentColor,
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {

                    Text("fetchurlviews_url")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("fetchurlviews_inline_footer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(
                    systemName: "chevron.right"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
            )
            .overlay {

                RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.07),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }


    // MARK: - Spotify

    @ViewBuilder
    private var spotifySection: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            HStack {

                Text("fetchview_spotify")
                    .font(.title2.bold())

                Spacer()

                if spotify.isConnected {

                    Label(
                        "fetchview_connected",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(.green)

                } else {

                    Text("fetchview_not_configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if spotify.isConnected {

                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {

                    LazyHStack(
                        spacing: 16
                    ) {

                        NavigationLink {

                            SpotifyLibraryView()

                        } label: {

                            FetchSourceCard(
                                title:
                                    "fetchview_your_library",
                                systemImage:
                                    "music.note.list",
                                tint:
                                    .green
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {

                            SpotifySearchView()

                        } label: {

                            FetchSourceCard(
                                title:
                                    "fetchview_search_spotify",
                                systemImage:
                                    "magnifyingglass",
                                tint:
                                    .green
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

            } else {

                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {

                    HStack(
                        alignment: .top,
                        spacing: 14
                    ) {

                        Image(
                            systemName: "music.note"
                        )
                        .font(
                            .system(
                                size: 22,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.green)
                        .frame(
                            width: 48,
                            height: 48
                        )
                        .background(
                            Color.green.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {

                            Text(
                                "fetchview_connect_spotify"
                            )
                            .font(.headline)

                            Text(
                                "fetchview_connect_spotify_description"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {

                        spotify.connect()

                    } label: {

                        Label(
                            "fetchview_connect_spotify",
                            systemImage:
                                "person.crop.circle.badge.plus"
                        )
                        .fontWeight(.semibold)
                        .frame(
                            maxWidth: .infinity
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(18)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(
                        cornerRadius: 23,
                        style: .continuous
                    )
                )
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 23,
                        style: .continuous
                    )
                    .stroke(
                        Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
                }
                .padding(.horizontal)
            }
        }
    }


    // MARK: - Music Search

    private var musicSearchSection: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Text("fetchview_music")
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {

                LazyHStack(
                    spacing: 16
                ) {

                    // YouTube Music staat nu eerst.

                    NavigationLink {

                        YouTubeMusicSearchView()

                    } label: {

                        FetchSourceCard(
                            title:
                                "fetchview_search_youtube_music",
                            systemImage:
                                "play.rectangle.fill",
                            tint:
                                .red
                        )
                    }
                    .buttonStyle(.plain)

                    // MusicBrainz staat nu als tweede.

                    NavigationLink {

                        MusicBrainzSearchView()

                    } label: {

                        FetchSourceCard(
                            title:
                                "fetchview_search_musicbrainz",
                            systemImage:
                                "music.note.list",
                            tint:
                                .purple
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            Text("fetchview_music_search_footer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }


    // MARK: - Downloads

    private var downloadsSection: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Text("fetchview_downloads")
                .font(.title2.bold())
                .padding(.horizontal)

            NavigationLink {

                FetchQueueView()

            } label: {

                HStack(
                    spacing: 16
                ) {

                    ZStack {

                        RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                        .fill(
                            Color.blue.opacity(0.12)
                        )

                        if activeDownloadCount > 0 {

                            ProgressView()
                                .controlSize(.regular)

                        } else {

                            Image(
                                systemName:
                                    "arrow.down.circle.fill"
                            )
                            .font(.title2)
                            .foregroundStyle(.blue)
                        }
                    }
                    .frame(
                        width: 54,
                        height: 54
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {

                        Text("fetchview_downloads")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if activeDownloadCount > 0 {

                            Text(activeDownloadsText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                        } else if manager.items.isEmpty {

                            Text(
                                "fetchqueueview_no_downloads_description"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        } else {

                            Text(
                                "\(manager.items.count)"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !manager.items.isEmpty {

                        Text("\(manager.items.count)")
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Color.primary.opacity(0.06),
                                in: Capsule()
                            )
                    }

                    Image(
                        systemName: "chevron.right"
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(.tertiary)
                }
                .padding(18)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(
                        cornerRadius: 23,
                        style: .continuous
                    )
                )
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 23,
                        style: .continuous
                    )
                    .stroke(
                        Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }


    // MARK: - Output

    private var outputSection: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Text("fetchview_output")
                .font(.title2.bold())
                .padding(.horizontal)

            VStack(spacing: 0) {

                HStack(
                    spacing: 14
                ) {

                    Image(
                        systemName: "waveform"
                    )
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        Color.orange.opacity(0.12),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )

                    Text("fetchview_audio_quality")
                        .font(.body)

                    Spacer()

                    Picker(
                        "fetchview_audio_quality",
                        selection:
                            $fetchSettings.quality
                    ) {

                        ForEach(
                            FetchQuality.allCases
                        ) { quality in

                            Text(quality.title)
                                .tag(quality)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .padding(16)

                Divider()
                    .padding(.leading, 72)

                Toggle(
                    isOn:
                        $fetchSettings.embedArtwork
                ) {

                    HStack(
                        spacing: 14
                    ) {

                        Image(
                            systemName: "photo"
                        )
                        .font(.headline)
                        .foregroundStyle(.pink)
                        .frame(
                            width: 42,
                            height: 42
                        )
                        .background(
                            Color.pink.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )

                        Text("fetchview_artwork")
                    }
                }
                .padding(16)
            }
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
            )
            .overlay {

                RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.07),
                    lineWidth: 1
                )
            }
            .padding(.horizontal)

            Text("fetchview_output_footer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }


    // MARK: - Apify

    @ViewBuilder
    private var apifySection: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Text("fetchview_apify")
                .font(.title2.bold())
                .padding(.horizontal)

            VStack(
                alignment: .leading,
                spacing: 16
            ) {

                NavigationLink {

                    ApifyAccountsView()

                } label: {

                    HStack(
                        spacing: 14
                    ) {

                        Image(
                            systemName:
                                "person.crop.circle"
                        )
                        .font(.title3)
                        .foregroundStyle(.indigo)
                        .frame(
                            width: 46,
                            height: 46
                        )
                        .background(
                            Color.indigo.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {

                            Text(
                                "fetchview_apify_account"
                            )
                            .font(.headline)
                            .foregroundStyle(.primary)

                            if let account =
                                apifySettings.activeAccount
                            {

                                Text(account.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                            } else {

                                Text(
                                    "fetchview_not_configured"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(
                            systemName: "chevron.right"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if !apifySettings.isConfigured {

                    Label(
                        "fetchview_add_apify_account_usage",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                } else if apifyUsageLoading {

                    HStack(spacing: 10) {

                        ProgressView()

                        Text("fetchview_loading_usage")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                } else if let usage = apifyUsage {

                    Divider()

                    VStack(
                        alignment: .leading,
                        spacing: 11
                    ) {

                        HStack {

                            Text("fetchview_usage")
                                .font(
                                    .subheadline
                                        .weight(.semibold)
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }

                        ProgressView(
                            value:
                                usage.usageFraction
                        )
                        .tint(.indigo)

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

                } else if let apifyUsageError {

                    Divider()

                    VStack(
                        alignment: .leading,
                        spacing: 9
                    ) {

                        Label(
                            "fetchview_usage_unavailable",
                            systemImage:
                                "exclamationmark.triangle.fill"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(.orange)

                        Text(apifyUsageError)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(
                            "fetchview_try_again"
                        ) {

                            Task {
                                await loadApifyUsage()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(18)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
            )
            .overlay {

                RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.07),
                    lineWidth: 1
                )
            }
            .padding(.horizontal)

            Text("fetchview_apify_footer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }


    // MARK: - Recent Downloads

    private var recentSection: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            HStack {

                Text("fetchview_recent")
                    .font(.title2.bold())

                Spacer()

                if manager.items.count > 4 {

                    NavigationLink {

                        FetchQueueView()

                    } label: {

                        Text(
                            "fetchview_view_all_downloads"
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                    }
                }
            }
            .padding(.horizontal)

            VStack(spacing: 0) {

                ForEach(recentItems) { item in

                    FetchItemRow(
                        item: item
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if item.id != recentItems.last?.id {

                        Divider()
                            .padding(.leading, 84)
                    }
                }
            }
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
            )
            .overlay {

                RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.07),
                    lineWidth: 1
                )
            }
            .padding(.horizontal)
        }
    }


    // MARK: - Values

    private var recentItems: [FetchItem] {

        Array(
            manager.items
                .reversed()
                .prefix(4)
        )
    }

    private var activeDownloadCount: Int {

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

    private var activeDownloadsText: String {

        String(
            format:
                String(
                    localized:
                        "fetchview_active_downloads"
                ),
            activeDownloadCount
        )
    }


    // MARK: - Refresh

    private func refreshForCurrentMethod() async {

        if apifySettings.downloadMethod == .youtube {
            await loadApifyUsage()
        }
    }

    private func loadApifyUsage() async {

        guard
            apifySettings.downloadMethod == .youtube
        else {
            return
        }

        guard apifySettings.isConfigured else {

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


// MARK: - Source Card

Card

