import SwiftUI

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}

struct LyricsView: View {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var lines: [LyricLine] = []
    @State private var isUserScrolling = false
    @State private var scrollResetTimer: Timer?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if lines.isEmpty {
                        if let lyrics = audioPlayer.currentLyrics, !lyrics.isEmpty {
                            plainLyricsView(lyrics)
                        } else {
                            unavailableLyricsView
                        }
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            let distance = index - currentLineIndex
                            let isCurrent = index == currentLineIndex
                            
                            Button {
                                audioPlayer.seek(to: line.time)
                            } label: {
                                Text(line.text)
                                    .font(.system(size: isCurrent ? 28 : 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                    // Blur-effect: als de gebruiker scrolt is de blur 0, anders neemt de blur toe naarmate de regel verder onder/boven de huidige regel staat.
                                    .blur(radius: calculateBlur(for: distance))
                                    .opacity(calculateOpacity(for: distance))
                                    .scaleEffect(isCurrent ? 1.02 : 0.98, anchor: .leading)
                                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentLineIndex)
                            .animation(.easeInOut(duration: 0.25), value: isUserScrolling)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 80)
            }
            // Detecteer scroll-interacties van de gebruiker
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    isUserScrolling = true
                    // Reset timer bij elke sleepbeweging
                    scrollResetTimer?.invalidate()
                    // Zorg dat het verwazigingseffect weer terugkomt 3 seconden nadat de gebruiker stopt met scrollen
                    scrollResetTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        withAnimation {
                            isUserScrolling = false
                        }
                    }
                }
            )
            .onChange(of: currentLineIndex) { _, newIndex in
                guard !lines.isEmpty, !isUserScrolling else { return }
                
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .navigationTitle(Text(LocalizedStringKey("lyrics_navigation_title")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            parseLyrics()
        }
        .onChange(of: audioPlayer.currentSyncedLyrics) { _, _ in parseLyrics() }
        .onChange(of: audioPlayer.currentLyrics) { _, _ in parseLyrics() }
    }
    
    // MARK: - Helper Modifiers voor visuele effecten
    
    /// Berekent de hoeveelheid Blur op basis van hoe ver de regel verwijderd is van de actieve regel
    private func calculateBlur(for distance: Int) -> CGFloat {
        if isUserScrolling { return 0 } // Geen blur tijdens handmatig scrollen
        if distance <= 0 { return 0 }   // Regel is al geweest of is de actieve regel
        
        // Zorgt ervoor dat regels eronder steeds waziger worden (max 8pt blur)
        return min(CGFloat(distance) * 2.2, 8.0)
    }
    
    /// Berekent de transparantie op basis van de afstand tot de actieve regel
    private func calculateOpacity(for distance: Int) -> Double {
        if isUserScrolling { return 1.0 } // Volledig leesbaar tijdens scrollen
        if distance == 0 { return 1.0 }   // Actieve regel
        
        if distance < 0 {
            // Regels die al geweest zijn vervagen licht
            return max(1.0 - Double(abs(distance)) * 0.25, 0.3)
        } else {
            // Regels die nog moeten komen worden steeds transparanter
            return max(1.0 - Double(distance) * 0.2, 0.15)
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var unavailableLyricsView: some View {
        if audioPlayer.lyricsNeedsInternet {
            ContentUnavailableView(
                LocalizedStringKey("lyrics_wifi_needed_title"),
                systemImage: "wifi",
                description: Text(LocalizedStringKey("lyrics_wifi_needed_description"))
            )
        } else {
            ContentUnavailableView(
                LocalizedStringKey("lyrics_unavailable_title"),
                systemImage: "text.quote",
                description: Text(LocalizedStringKey("lyrics_unavailable_description"))
            )
        }
    }

    private var currentLineIndex: Int {
        guard !lines.isEmpty else { return 0 }
        var result = 0
        for index in lines.indices {
            if lines[index].time <= audioPlayer.currentTime {
                result = index
            } else {
                break
            }
        }
        return result
    }

    private func parseLyrics() {
        guard let synced = audioPlayer.currentSyncedLyrics else {
            lines = []
            return
        }
        
        lines = synced
            .components(separatedBy: .newlines)
            .compactMap { parseLine($0) }
    }

    private func parseLine(_ line: String) -> LyricLine? {
        guard line.hasPrefix("[") else { return nil }
        guard let closingBracket = line.firstIndex(of: "]") else { return nil }
        
        let timeString = String(line[line.index(after: line.startIndex)..<closingBracket])
        let text = String(line[line.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
        
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]) else { return nil }
        
        return LyricLine(time: minutes * 60 + seconds, text: text)
    }

    @ViewBuilder
    private func plainLyricsView(_ lyrics: String) -> some View {
        Text(lyrics)
            .font(.title3)
            .foregroundStyle(.primary)
            .lineSpacing(8)
    }
}
