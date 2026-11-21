import SwiftUI

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}

struct LyricsView: View {
    @AppStorage("developerShowLyricsSources") private var showLyricsSources = false
    @State private var selectedProvider = LyricsProvider.automatic
    
    @Environment(AudioPlayerManager.self)
    private var audioPlayer
    
    @State private var lines: [LyricLine] = []
    @State private var isUserScrolling = false
    @State private var scrollResetTimer: Timer?
    @State private var backdrop: UIImage?
    
    // 35% vanaf de bovenkant
    private let customScrollAnchor =
        UnitPoint(x: 0.5, y: 0.35)
    
    
    var body: some View {
        
        ZStack {
            
            // MARK: - Background
            
            lyricsBackground
                .ignoresSafeArea()
            
            
            // MARK: - Lyrics
            
            ScrollViewReader { proxy in
                
                ScrollView(
                    .vertical,
                    showsIndicators: false
                ) {
                    
                    VStack(
                        alignment: .leading,
                        spacing: 22
                    ) {
                        
                        if lines.isEmpty {
                            
                            if let lyrics =
                                audioPlayer.currentLyrics,
                               !lyrics.isEmpty
                            {
                                
                                plainLyricsView(lyrics)
                                
                            } else if !audioPlayer.isLoadingLyrics {
                                
                                unavailableLyricsView
                            }
                            
                        } else {
                            
                            ForEach(
                                Array(lines.enumerated()),
                                id: \.offset
                            ) { index, line in
                                
                                let distance =
                                    index - currentLineIndex
                                
                                let isCurrent =
                                    index == currentLineIndex
                                
                                
                                Button {
                                    
                                    audioPlayer.seek(
                                        to: line.time
                                    )
                                    
                                } label: {
                                    
                                    Text(line.text)
                                        .font(
                                            .system(
                                                size: 24,
                                                weight: .bold,
                                                design: .rounded
                                            )
                                        )
                                        
                                        // Wit voor alle lyrics
                                        .foregroundStyle(
                                                isCurrent
                                                ? Color.white
                                                : Color.white.opacity(0.48)
                                        )
                                        
                                        .blur(
                                            radius:
                                                calculateBlur(
                                                    for: distance
                                                )
                                        )
                                        
                                        .opacity(
                                            calculateOpacity(
                                                for: distance
                                            )
                                        )
                                        
                                        .scaleEffect(
                                            isCurrent
                                            ? 1.04
                                            : 1.0,
                                            anchor: .leading
                                        )
                                        // The sung line glows softly.
                                        .shadow(
                                            color: .white.opacity(isCurrent ? 0.35 : 0),
                                            radius: isCurrent ? 12 : 0
                                        )
                                        
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .leading
                                        )
                                }
                                .buttonStyle(.plain)
                                .id(index)
                                
                                .animation(
                                    .spring(
                                        response: 0.35,
                                        dampingFraction: 0.85
                                    ),
                                    value:
                                        currentLineIndex
                                )
                                
                                .animation(
                                    .easeInOut(
                                        duration: 0.2
                                    ),
                                    value:
                                        isUserScrolling
                                )
                            }
                        }
                        if showLyricsSources { sourceControls }
                        if audioPlayer.isLoadingLyrics {
                            ProgressView("lyrics_searching").tint(.white).foregroundStyle(.white)
                        }
                        if let key = audioPlayer.lyricsStatusKey {
                            Text(LocalizedStringKey(key)).font(.footnote).foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 100)
                }
                
                .simultaneousGesture(
                    
                    DragGesture()
                        .onChanged { _ in
                            
                            isUserScrolling = true
                            
                            scrollResetTimer?
                                .invalidate()
                            
                            scrollResetTimer =
                                Timer.scheduledTimer(
                                    withTimeInterval: 3.0,
                                    repeats: false
                                ) { _ in
                                    
                                    withAnimation {
                                        isUserScrolling = false
                                    }
                                }
                        }
                )
                
                .onChange(
                    of: currentLineIndex
                ) { _, newIndex in
                    
                    guard
                        !lines.isEmpty,
                        !isUserScrolling
                    else {
                        return
                    }
                    
                    withAnimation(
                        .spring(
                            response: 0.45,
                            dampingFraction: 0.82
                        )
                    ) {
                        
                        proxy.scrollTo(
                            newIndex,
                            anchor:
                                customScrollAnchor
                        )
                    }
                }
            }
        }
        
        // MARK: - Navigation
        
        .echoBackground()

        .navigationTitle(
            Text(
                LocalizedStringKey(
                    "lyrics_navigation_title"
                )
            )
        )
        
        .navigationBarTitleDisplayMode(
            .inline
        )
        
        .toolbarBackground(
            .hidden,
            for: .navigationBar
        )
        
        .toolbarColorScheme(
            .dark,
            for: .navigationBar
        )
        
        
        // MARK: - Updates
        
        .onChange(of: audioPlayer.currentSong?.id) { selectedProvider = .automatic }
        .onChange(of: showLyricsSources) { if !showLyricsSources { selectedProvider = .automatic } }
        .onAppear {
            parseLyrics()
        }
        
        .onChange(
            of:
                audioPlayer.currentSyncedLyrics
        ) { _, _ in
            
            parseLyrics()
        }
        
        .onChange(
            of:
                audioPlayer.currentLyrics
        ) { _, _ in
            
            parseLyrics()
        }
        
        .onDisappear {
            
            scrollResetTimer?
                .invalidate()
        }
    }
    
    
    // MARK: - Background
    
    @ViewBuilder
    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if audioPlayer.currentLyrics != nil || audioPlayer.currentSyncedLyrics != nil {
                HStack {
                    Text(LocalizedStringKey(audioPlayer.currentLyricsSource?.titleKey ?? "lyrics_source_unknown"))
                    Text(verbatim: "·")
                    Text(LocalizedStringKey(lines.isEmpty ? "lyrics_plain" : "lyrics_synchronized"))
                }
                .font(.caption)
            }
            Picker("lyrics_choose_source", selection: $selectedProvider) {
                ForEach(LyricsProvider.allCases) { provider in
                    Text(LocalizedStringKey(provider.titleKey)).tag(provider)
                }
            }
            .pickerStyle(.menu)
            Button {
                audioPlayer.refreshLyrics(provider: selectedProvider)
            } label: {
                Label("lyrics_search_again", systemImage: "arrow.clockwise")
            }
            .disabled(audioPlayer.isLoadingLyrics || audioPlayer.currentSong == nil)
            if let url = audioPlayer.currentLyricsSourceURL, url.scheme == "https" {
                Link("lyrics_open_source", destination: url)
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
    }

    /// Prepared once per song, off the main thread. The view body runs on every
    /// playback tick, so it must never decode or blur the artwork itself.
    private var lyricsBackground: some View {
        EchoLivingBackdrop(image: backdrop, dim: 0.4)
            .task(id: audioPlayer.currentSong?.id) {
                let song = audioPlayer.currentSong
                let prepared = await PlayerArtworkImages.prepareBackdrop(song?.coverData ?? song?.imageData)
                guard !Task.isCancelled else { return }
                backdrop = prepared
            }
    }
    
    
    // MARK: - Effects
    
    private func calculateBlur(
        for distance: Int
    ) -> CGFloat {
        
        if isUserScrolling {
            return 0
        }
        
        if distance <= 0 {
            return 0
        }
        
        return min(
            CGFloat(distance) * 0.8,
            3.5
        )
    }
    
    
    private func calculateOpacity(
    for distance: Int
) -> Double {

    // Huidige regel altijd volledig helder
    if distance == 0 {
        return 1.0
    }

    // Tijdens scrollen blijven de andere regels
    // nog steeds duidelijk minder fel
    if isUserScrolling {
        return 0.82
    }

    if distance < 0 {

        // Vorige regels
        switch abs(distance) {

        case 1:
            return 0.82

        case 2:
            return 0.68

        case 3:
            return 0.55

        default:
            return 0.45
        }

    } else {

        // Volgende regels
        switch distance {

        case 1:
            return 0.78

        case 2:
            return 0.64

        case 3:
            return 0.52

        default:
            return 0.42
        }
    }
}
    
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var unavailableLyricsView: some View {
        
        if audioPlayer.lyricsNeedsInternet {
            
            ContentUnavailableView(
                LocalizedStringKey(
                    "lyrics_wifi_needed_title"
                ),
                systemImage: "wifi",
                description:
                    Text(
                        LocalizedStringKey(
                            "lyrics_wifi_needed_description"
                        )
                    )
            )
            .foregroundStyle(.white)
            
        } else {
            
            ContentUnavailableView(
                LocalizedStringKey(
                    "lyrics_unavailable_title"
                ),
                systemImage: "text.quote",
                description:
                    Text(
                        LocalizedStringKey(
                            "lyrics_unavailable_description"
                        )
                    )
            )
            .foregroundStyle(.white)
        }
    }
    
    
    // MARK: - Current Line
    
    private var currentLineIndex: Int {
        
        guard !lines.isEmpty else {
            return 0
        }
        
        var result = 0
        
        for index in lines.indices {
            
            if
                lines[index].time
                <= audioPlayer.currentTime
            {
                
                result = index
                
            } else {
                
                break
            }
        }
        
        return result
    }
    
    
    // MARK: - Parse Lyrics
    
    private func parseLyrics() {
        
        guard
            let synced =
                audioPlayer.currentSyncedLyrics
        else {
            
            lines = []
            return
        }
        
        lines =
            synced
            .components(
                separatedBy: .newlines
            )
            .compactMap {
                parseLine($0)
            }
    }
    
    
    private func parseLine(
    _ line: String
) -> LyricLine? {

    guard line.hasPrefix("[") else {
        return nil
    }

    guard let closingBracket =
        line.firstIndex(of: "]")
    else {
        return nil
    }

    let timeStart =
        line.index(
            after: line.startIndex
        )

    let timeString =
        String(
            line[
                timeStart..<closingBracket
            ]
        )

    let textStart =
        line.index(
            after: closingBracket
        )

    let text =
        String(
            line[textStart...]
        )
        .trimmingCharacters(
            in: .whitespaces
        )

    let components =
        timeString.split(
            separator: ":"
        )

    guard
        components.count == 2,
        let minutes =
            Double(components[0]),
        let seconds =
            Double(components[1])
    else {
        return nil
    }

    return LyricLine(
        time: minutes * 60 + seconds,
        text: text
    )
}
    
    
    // MARK: - Plain Lyrics
    
    @ViewBuilder
    private func plainLyricsView(
        _ lyrics: String
    ) -> some View {
        
        Text(lyrics)
            .font(
                .system(
                    size: 22,
                    weight: .semibold,
                    design: .rounded
                )
            )
            .foregroundStyle(.white)
            .lineSpacing(9)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
    }
}
