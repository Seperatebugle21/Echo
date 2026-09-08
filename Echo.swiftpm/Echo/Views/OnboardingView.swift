import SwiftUI

struct EchoOnboardingView: View {

    enum Step: Int, CaseIterable {
        case welcome
        case library
        case learning
        case fetch
        case spotify
        case ready
    }

    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var direction: CGFloat = 1
    @State private var contentVisible = false
    @State private var ambientMotion = false
    @State private var spotify = SpotifyManager.shared

    private let horizontalPadding: CGFloat = 24

    var body: some View {

        ZStack {

            onboardingBackground

            VStack(spacing: 0) {

                topBar

                ZStack {

                    page(for: step)
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

                footer
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {

            contentVisible = false

            withAnimation(
                .easeOut(duration: 0.65)
            ) {
                contentVisible = true
            }

            withAnimation(
                .easeInOut(duration: 7.5)
                    .repeatForever(
                        autoreverses: true
                    )
            ) {
                ambientMotion = true
            }
        }
        .onChange(
            of: spotify.isConnected
        ) { _, connected in

            guard
                connected,
                step == .spotify
            else {
                return
            }

            move(
                to: .ready,
                direction: 1
            )
        }
        .onChange(
            of: step
        ) { _, newStep in

            guard
                newStep == .spotify,
                spotify.isConnected
            else {
                return
            }

            Task {

                try? await Task.sleep(
                    nanoseconds: 450_000_000
                )

                guard
                    step == .spotify,
                    spotify.isConnected
                else {
                    return
                }

                await MainActor.run {

                    move(
                        to: .ready,
                        direction: 1
                    )
                }
            }
        }
    }


    // MARK: - Background

    private var onboardingBackground: some View {

        GeometryReader { proxy in

            ZStack {

                Color(.systemBackground)

                Circle()
                    .fill(
                        Color.accentColor
                            .opacity(0.08)
                    )
                    .frame(
                        width: proxy.size.width * 0.95,
                        height: proxy.size.width * 0.95
                    )
                    .blur(radius: 70)
                    .offset(
                        x: ambientMotion
                            ? proxy.size.width * 0.22
                            : -proxy.size.width * 0.15,
                        y: -proxy.size.height * 0.24
                    )

                Circle()
                    .fill(
                        Color.primary
                            .opacity(0.035)
                    )
                    .frame(
                        width: proxy.size.width * 0.72,
                        height: proxy.size.width * 0.72
                    )
                    .blur(radius: 60)
                    .offset(
                        x: ambientMotion
                            ? -proxy.size.width * 0.24
                            : proxy.size.width * 0.18,
                        y: proxy.size.height * 0.30
                    )
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }


    // MARK: - Top Bar

    private var topBar: some View {

        HStack(spacing: 16) {

            if step != .welcome &&
                step != .ready
            {

                Button {

                    goBack()

                } label: {

                    Image(
                        systemName:
                            "chevron.left"
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .contentShape(
                        Circle()
                    )
                }
                .buttonStyle(.plain)
                .background(
                    .thinMaterial,
                    in: Circle()
                )
                .accessibilityLabel(
                    Text(
                        "onboarding_back_accessibility"
                    )
                )

            } else {

                Color.clear
                    .frame(
                        width: 40,
                        height: 40
                    )
            }

            Spacer()

            progressDots

            Spacer()

            Color.clear
                .frame(
                    width: 40,
                    height: 40
                )
        }
        .padding(
            .horizontal,
            horizontalPadding
        )
        .padding(.top, 10)
        .padding(.bottom, 8)
    }


    private var progressDots: some View {

        HStack(spacing: 7) {

            ForEach(
                Step.allCases,
                id: \.rawValue
            ) { item in

                Capsule()
                    .fill(
                        item == step
                            ? Color.primary
                            : Color.secondary
                                .opacity(0.22)
                    )
                    .frame(
                        width: item == step
                            ? 22
                            : 7,
                        height: 7
                    )
                    .animation(
                        .spring(
                            response: 0.42,
                            dampingFraction: 0.82
                        ),
                        value: step
                    )
            }
        }
        .accessibilityHidden(true)
    }


    // MARK: - Pages

    @ViewBuilder
    private func page(
        for step: Step
    ) -> some View {

        switch step {

        case .welcome:
            welcomePage

        case .library:
            libraryPage

        case .learning:
            learningPage

        case .fetch:
            fetchPage

        case .spotify:
            spotifyPage

        case .ready:
            readyPage
        }
    }


    private var welcomePage: some View {

        onboardingScroll {

            VStack(spacing: 28) {

                heroSymbol(
                    "waveform.circle.fill",
                    rotation: ambientMotion
                        ? 2
                        : -2
                )

                VStack(spacing: 12) {

                    Text(
                        "onboarding_welcome_title"
                    )
                    .font(
                        .system(
                            size: 38,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .multilineTextAlignment(.center)

                    Text(
                        "onboarding_welcome_subtitle"
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                }

                HStack(spacing: 10) {

                    onboardingChip(
                        icon: "square.stack.3d.up.fill",
                        key: "onboarding_welcome_chip_library"
                    )

                    onboardingChip(
                        icon: "arrow.down.circle.fill",
                        key: "onboarding_welcome_chip_fetch"
                    )

                    onboardingChip(
                        icon: "sparkles",
                        key: "onboarding_welcome_chip_personal"
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 24)
        }
    }


    private var libraryPage: some View {

        onboardingScroll {

            VStack(spacing: 24) {

                pageHeader(
                    symbol: "square.stack.3d.up.fill",
                    titleKey: "onboarding_library_title",
                    subtitleKey: "onboarding_library_subtitle"
                )

                libraryPreview

                VStack(spacing: 12) {

                    featureRow(
                        icon: "music.note",
                        titleKey: "onboarding_library_feature_songs_title",
                        bodyKey: "onboarding_library_feature_songs_body"
                    )

                    featureRow(
                        icon: "music.note.list",
                        titleKey: "onboarding_library_feature_playlists_title",
                        bodyKey: "onboarding_library_feature_playlists_body"
                    )

                    featureRow(
                        icon: "photo.on.rectangle.angled",
                        titleKey: "onboarding_library_feature_metadata_title",
                        bodyKey: "onboarding_library_feature_metadata_body"
                    )
                }
            }
        }
    }


    private var learningPage: some View {

        onboardingScroll {

            VStack(spacing: 24) {

                pageHeader(
                    symbol: "sparkles",
                    titleKey: "onboarding_learning_title",
                    subtitleKey: "onboarding_learning_subtitle"
                )

                learningPreview

                VStack(spacing: 12) {

                    featureRow(
                        icon: "play.circle.fill",
                        titleKey: "onboarding_learning_feature_listens_title",
                        bodyKey: "onboarding_learning_feature_listens_body"
                    )

                    featureRow(
                        icon: "slider.horizontal.3",
                        titleKey: "onboarding_learning_feature_adapts_title",
                        bodyKey: "onboarding_learning_feature_adapts_body"
                    )

                    featureRow(
                        icon: "binoculars.fill",
                        titleKey: "onboarding_learning_feature_discovery_title",
                        bodyKey: "onboarding_learning_feature_discovery_body"
                    )
                }
            }
        }
    }


    private var fetchPage: some View {

        onboardingScroll {

            VStack(spacing: 24) {

                pageHeader(
                    symbol: "arrow.down.circle.fill",
                    titleKey: "onboarding_fetch_title",
                    subtitleKey: "onboarding_fetch_subtitle"
                )

                fetchFlowPreview

                Text(
                    "onboarding_fetch_engine_badge"
                )
                .font(
                    .footnote
                        .weight(.semibold)
                )
                .foregroundStyle(.secondary)
                .padding(
                    .horizontal,
                    14
                )
                .padding(
                    .vertical,
                    8
                )
                .background(
                    .thinMaterial,
                    in: Capsule()
                )

                VStack(spacing: 12) {

                    featureRow(
                        icon: "magnifyingglass",
                        titleKey: "onboarding_fetch_feature_find_title",
                        bodyKey: "onboarding_fetch_feature_find_body"
                    )

                    featureRow(
                        icon: "terminal.fill",
                        titleKey: "onboarding_fetch_feature_download_title",
                        bodyKey: "onboarding_fetch_feature_download_body"
                    )

                    featureRow(
                        icon: "checkmark.circle.fill",
                        titleKey: "onboarding_fetch_feature_ready_title",
                        bodyKey: "onboarding_fetch_feature_ready_body"
                    )
                }
            }
        }
    }


    private var spotifyPage: some View {

        onboardingScroll {

            VStack(spacing: 24) {

                ZStack {

                    Circle()
                        .fill(
                            Color.green
                                .opacity(0.13)
                        )
                        .frame(
                            width: 128,
                            height: 128
                        )
                        .scaleEffect(
                            ambientMotion
                                ? 1.04
                                : 0.97
                        )

                    Image(
                        systemName:
                            spotify.isConnected
                                ? "checkmark.circle.fill"
                                : "music.note"
                    )
                    .font(
                        .system(
                            size: 48,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        spotify.isConnected
                            ? Color.green
                            : Color.primary
                    )
                    .contentTransition(
                        .symbolEffect(.replace)
                    )
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {

                    Text(
                        LocalizedStringKey(
                            spotify.isConnected
                                ? "onboarding_spotify_connected_title"
                                : "onboarding_spotify_title"
                        )
                    )
                    .font(
                        .system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .multilineTextAlignment(.center)

                    Text(
                        LocalizedStringKey(
                            spotify.isConnected
                                ? "onboarding_spotify_connected_body"
                                : "onboarding_spotify_body"
                        )
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                }

                if !spotify.isConnected {

                    Text(
                        "onboarding_spotify_optional_badge"
                    )
                    .font(
                        .footnote
                            .weight(.semibold)
                    )
                    .padding(
                        .horizontal,
                        14
                    )
                    .padding(
                        .vertical,
                        8
                    )
                    .background(
                        Color.green
                            .opacity(0.11),
                        in: Capsule()
                    )

                    VStack(spacing: 12) {

                        featureRow(
                            icon: "magnifyingglass",
                            titleKey: "onboarding_spotify_feature_search_title",
                            bodyKey: "onboarding_spotify_feature_search_body"
                        )

                        featureRow(
                            icon: "heart.text.square.fill",
                            titleKey: "onboarding_spotify_feature_library_title",
                            bodyKey: "onboarding_spotify_feature_library_body"
                        )

                        featureRow(
                            icon: "music.note.list",
                            titleKey: "onboarding_spotify_feature_playlists_title",
                            bodyKey: "onboarding_spotify_feature_playlists_body"
                        )
                    }
                }
            }
        }
    }


    private var readyPage: some View {

        onboardingScroll {

            VStack(spacing: 28) {

                ZStack {

                    Circle()
                        .stroke(
                            Color.accentColor
                                .opacity(0.16),
                            lineWidth: 2
                        )
                        .frame(
                            width: 150,
                            height: 150
                        )
                        .scaleEffect(
                            ambientMotion
                                ? 1.08
                                : 0.94
                        )

                    Circle()
                        .fill(
                            Color.accentColor
                                .opacity(0.11)
                        )
                        .frame(
                            width: 122,
                            height: 122
                        )

                    Image(
                        systemName:
                            "checkmark"
                    )
                    .font(
                        .system(
                            size: 47,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        Color.accentColor
                    )
                    .scaleEffect(
                        contentVisible
                            ? 1
                            : 0.55
                    )
                }
                .accessibilityHidden(true)

                VStack(spacing: 12) {

                    Text(
                        "onboarding_ready_title"
                    )
                    .font(
                        .system(
                            size: 36,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .multilineTextAlignment(.center)

                    Text(
                        "onboarding_ready_subtitle"
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                }

                VStack(spacing: 10) {

                    readyLine(
                        icon: "square.stack.3d.up.fill",
                        key: "onboarding_ready_library"
                    )

                    readyLine(
                        icon: "sparkles",
                        key: "onboarding_ready_learning"
                    )

                    readyLine(
                        icon: "arrow.down.circle.fill",
                        key: "onboarding_ready_fetch"
                    )
                }

                Text(
                    "onboarding_ready_footer"
                )
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
        }
    }


    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {

        VStack(spacing: 10) {

            if step == .spotify {

                if spotify.isConnected {

                    HStack(spacing: 10) {

                        ProgressView()

                        Text(
                            "onboarding_spotify_finishing"
                        )
                        .font(
                            .subheadline
                                .weight(.medium)
                        )
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 52
                    )

                } else {

                    Button {

                        spotify.connect()

                    } label: {

                        HStack(spacing: 9) {

                            Image(
                                systemName:
                                    "link"
                            )

                            Text(
                                "onboarding_spotify_connect"
                            )
                        }
                        .font(
                            .headline
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                        .frame(
                            height: 54
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .controlSize(.large)

                    Button {

                        move(
                            to: .ready,
                            direction: 1
                        )

                    } label: {

                        Text(
                            "onboarding_spotify_skip"
                        )
                        .font(
                            .headline
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                        .frame(
                            height: 48
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

            } else if step == .ready {

                Button {

                    finishOnboarding()

                } label: {

                    Text(
                        "onboarding_done"
                    )
                    .font(.headline)
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(
                        height: 54
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .controlSize(.large)

            } else {

                Button {

                    goForward()

                } label: {

                    HStack(spacing: 8) {

                        Text(
                            "onboarding_continue"
                        )

                        Image(
                            systemName:
                                "arrow.right"
                        )
                    }
                    .font(.headline)
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(
                        height: 54
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .controlSize(.large)
            }
        }
        .padding(
            .horizontal,
            horizontalPadding
        )
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            .ultraThinMaterial
        )
    }


    // MARK: - Reusable UI

    private func onboardingScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {

        ScrollView(
            .vertical,
            showsIndicators: false
        ) {

            content()
                .frame(
                    maxWidth: 620
                )
                .padding(
                    .horizontal,
                    horizontalPadding
                )
                .padding(.bottom, 26)
                .frame(
                    maxWidth: .infinity
                )
                .opacity(
                    contentVisible
                        ? 1
                        : 0
                )
                .offset(
                    y: contentVisible
                        ? 0
                        : 14
                )
        }
        .scrollBounceBehavior(
            .basedOnSize
        )
    }


    private func pageHeader(
        symbol: String,
        titleKey: LocalizedStringKey,
        subtitleKey: LocalizedStringKey
    ) -> some View {

        VStack(spacing: 18) {

            heroSymbol(
                symbol,
                rotation: 0
            )
            .scaleEffect(0.80)

            VStack(spacing: 10) {

                Text(
                    titleKey
                )
                .font(
                    .system(
                        size: 31,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .multilineTextAlignment(.center)

                Text(
                    subtitleKey
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
        }
    }


    private func heroSymbol(
        _ systemName: String,
        rotation: Double
    ) -> some View {

        ZStack {

            Circle()
                .stroke(
                    Color.accentColor
                        .opacity(0.13),
                    lineWidth: 2
                )
                .frame(
                    width: 146,
                    height: 146
                )
                .scaleEffect(
                    ambientMotion
                        ? 1.06
                        : 0.96
                )

            Circle()
                .fill(
                    Color.accentColor
                        .opacity(0.11)
                )
                .frame(
                    width: 118,
                    height: 118
                )

            Image(
                systemName:
                    systemName
            )
            .font(
                .system(
                    size: 47,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.accentColor
            )
            .rotationEffect(
                .degrees(rotation)
            )
        }
        .accessibilityHidden(true)
    }


    private func onboardingChip(
        icon: String,
        key: LocalizedStringKey
    ) -> some View {

        VStack(spacing: 7) {

            Image(
                systemName:
                    icon
            )
            .font(
                .system(
                    size: 18,
                    weight: .semibold
                )
            )

            Text(
                key
            )
            .font(
                .caption2
                    .weight(.semibold)
            )
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
        }
        .frame(
            maxWidth: .infinity
        )
        .frame(
            minHeight: 82
        )
        .padding(
            .horizontal,
            7
        )
        .background(
            .thinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }


    private func featureRow(
        icon: String,
        titleKey: LocalizedStringKey,
        bodyKey: LocalizedStringKey
    ) -> some View {

        HStack(
            alignment: .top,
            spacing: 14
        ) {

            Image(
                systemName:
                    icon
            )
            .font(
                .system(
                    size: 18,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.accentColor
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                Color.accentColor
                    .opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
            )
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {

                Text(
                    titleKey
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(.primary)

                Text(
                    bodyKey
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer(
                minLength: 0
            )
        }
        .padding(14)
        .background(
            .thinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }


    private var libraryPreview: some View {

        HStack(spacing: 10) {

            libraryTile(
                icon: "music.note",
                key: "onboarding_library_tile_songs",
                offset: ambientMotion
                    ? -3
                    : 3
            )

            libraryTile(
                icon: "music.note.list",
                key: "onboarding_library_tile_playlists",
                offset: ambientMotion
                    ? 3
                    : -3
            )

            libraryTile(
                icon: "heart.fill",
                key: "onboarding_library_tile_favorites",
                offset: ambientMotion
                    ? -2
                    : 2
            )
        }
        .padding(.vertical, 6)
    }


    private func libraryTile(
        icon: String,
        key: LocalizedStringKey,
        offset: CGFloat
    ) -> some View {

        VStack(spacing: 12) {

            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(
                Color.accentColor
                    .opacity(0.10)
            )
            .aspectRatio(
                1,
                contentMode: .fit
            )
            .overlay {

                Image(
                    systemName:
                        icon
                )
                .font(
                    .system(
                        size: 27,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    Color.accentColor
                )
            }

            Text(
                key
            )
            .font(
                .caption
                    .weight(.semibold)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(9)
        .background(
            .thinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .offset(
            y: offset
        )
    }


    private var learningPreview: some View {

        HStack(
            alignment: .bottom,
            spacing: 9
        ) {

            ForEach(
                Array(
                    [0.64, 0.91, 0.73, 1.0, 0.82]
                        .enumerated()
                ),
                id: \.offset
            ) { index, value in

                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .fill(
                    index == 3
                        ? Color.accentColor
                        : Color.secondary
                            .opacity(0.20)
                )
                .frame(
                    height:
                        112
                        * (
                            ambientMotion
                                ? value
                                : max(
                                    0.40,
                                    value - 0.13
                                )
                        )
                )
                .overlay(
                    alignment: .top
                ) {

                    if index == 3 {

                        Image(
                            systemName:
                                "sparkles"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            Color.white
                        )
                        .padding(.top, 9)
                    }
                }
            }
        }
        .frame(
            height: 126
        )
        .padding(
            .horizontal,
            26
        )
        .padding(
            .vertical,
            20
        )
        .background(
            .thinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
        .animation(
            .easeInOut(duration: 2.1),
            value: ambientMotion
        )
        .accessibilityHidden(true)
    }


    private var fetchFlowPreview: some View {

        HStack(spacing: 8) {

            fetchNode(
                icon: "magnifyingglass",
                key: "onboarding_fetch_node_find"
            )

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .caption
                    .weight(.bold)
            )
            .foregroundStyle(.tertiary)

            fetchNode(
                icon: "arrow.down.circle.fill",
                key: "onboarding_fetch_node_download"
            )

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .caption
                    .weight(.bold)
            )
            .foregroundStyle(.tertiary)

            fetchNode(
                icon: "music.note",
                key: "onboarding_fetch_node_library"
            )
        }
        .padding(14)
        .background(
            .thinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
    }


    private func fetchNode(
        icon: String,
        key: LocalizedStringKey
    ) -> some View {

        VStack(spacing: 8) {

            Image(
                systemName:
                    icon
            )
            .font(
                .system(
                    size: 20,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.accentColor
            )
            .frame(
                width: 46,
                height: 46
            )
            .background(
                Color.accentColor
                    .opacity(0.10),
                in: Circle()
            )

            Text(
                key
            )
            .font(
                .caption2
                    .weight(.semibold)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(
            maxWidth: .infinity
        )
    }


    private func readyLine(
        icon: String,
        key: LocalizedStringKey
    ) -> some View {

        HStack(spacing: 12) {

            Image(
                systemName:
                    "checkmark.circle.fill"
            )
            .foregroundStyle(
                Color.accentColor
            )

            Image(
                systemName:
                    icon
            )
            .foregroundStyle(
                .secondary
            )

            Text(
                key
            )
            .font(
                .subheadline
                    .weight(.medium)
            )

            Spacer()
        }
        .padding(
            .horizontal,
            16
        )
        .frame(
            minHeight: 50
        )
        .background(
            .thinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
        )
    }


    // MARK: - Navigation

    private var pageTransition:
        AnyTransition
    {

        if direction >= 0 {

            return .asymmetric(
                insertion:
                    .move(
                        edge: .trailing
                    )
                    .combined(
                        with: .opacity
                    ),
                removal:
                    .move(
                        edge: .leading
                    )
                    .combined(
                        with: .opacity
                    )
            )

        } else {

            return .asymmetric(
                insertion:
                    .move(
                        edge: .leading
                    )
                    .combined(
                        with: .opacity
                    ),
                removal:
                    .move(
                        edge: .trailing
                    )
                    .combined(
                        with: .opacity
                    )
            )
        }
    }


    private func goForward() {

        guard let next =
            Step(
                rawValue:
                    step.rawValue + 1
            )
        else {
            return
        }

        move(
            to: next,
            direction: 1
        )
    }


    private func goBack() {

        guard let previous =
            Step(
                rawValue:
                    step.rawValue - 1
            )
        else {
            return
        }

        move(
            to: previous,
            direction: -1
        )
    }


    private func move(
        to newStep: Step,
        direction newDirection: CGFloat
    ) {

        guard
            newStep != step
        else {
            return
        }

        direction =
            newDirection

        contentVisible =
            false

        withAnimation(
            .spring(
                response: 0.58,
                dampingFraction: 0.86,
                blendDuration: 0.15
            )
        ) {

            step =
                newStep
        }

        Task {

            try? await Task.sleep(
                nanoseconds: 90_000_000
            )

            await MainActor.run {

                withAnimation(
                    .easeOut(
                        duration: 0.48
                    )
                ) {

                    contentVisible =
                        true
                }
            }
        }
    }


    private func finishOnboarding() {

        withAnimation(
            .easeInOut(
                duration: 0.45
            )
        ) {

            contentVisible =
                false
        }

        Task {

            try? await Task.sleep(
                nanoseconds: 220_000_000
            )

            await MainActor.run {

                onFinished()
            }
        }
    }
}


#Preview {

    EchoOnboardingView(
        onFinished: {}
    )
}
