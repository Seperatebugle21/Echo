import SwiftUI

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}

struct LyricsView: View {
    
    @Environment(AudioPlayerManager.self)
    private var audioPlayer
    
    @State private var lines: [LyricLine] = []
    @State private var isUserScrolling = false
    @State private var scrollResetTimer: Timer?
    
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
                                
                            } else {
                                
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
                                            Color.white
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
                                            ? 1.03
                                            : 1.0,
                                            anchor: .leading
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
    private var lyricsBackground: some View {
        
        if
            let song =
                audioPlayer.currentSong,
            let data =
                song.coverData
                ?? song.imageData,
            let image =
                UIImage(data: data)
        {
            
            GeometryReader { geometry in
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    
                    .frame(
                        width:
                            geometry.size.width,
                        height:
                            geometry.size.height
                    )
                    
                    .scaleEffect(1.4)
                    
                    // Zware blur zoals Now Playing
                    .blur(radius: 70)
                    
                    .saturation(1.2)
                    
                    // Donker genoeg zodat witte tekst
                    // altijd leesbaar blijft
                    .overlay {
                        
                        Color.black
                            .opacity(0.38)
                    }
                    
                    .overlay {
                        
                        LinearGradient(
                            colors: [
                                
                                Color.black
                                    .opacity(0.12),
                                
                                Color.black
                                    .opacity(0.18),
                                
                                Color.black
                                    .opacity(0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    
                    .clipped()
            }
            
        } else {
            
            Color.black
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
        
        if isUserScrolling {
            return 1.0
        }
        
        if distance == 0 {
            return 1.0
        }
        
        if distance < 0 {
            
            // Vorige lyrics
            
            return max(
                1.0
                - Double(abs(distance)) * 0.18,
                0.35
            )
            
        } else {
            
            // Volgende lyrics
            
            return max(
                1.0
                - Double(distance) * 0.13,
                0.42
            )
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
