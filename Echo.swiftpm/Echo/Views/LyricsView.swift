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
    
    // Aangepaste ankerpositie: 35% vanaf de bovenkant (iets boven het midden)
    private let customScrollAnchor = UnitPoint(x: 0.5, y: 0.35)
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                    // Subtiele blur: veel minder heftig dan voorheen (max 3pt)
                                    .blur(radius: calculateBlur(for: distance))
                                    .opacity(calculateOpacity(for: distance))
                                    // Zachte scale zonder dat de tekst-layout opnieuw wordt berekend
                                    .scaleEffect(isCurrent ? 1.03 : 1.0, anchor: .leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentLineIndex)
                            .animation(.easeInOut(duration: 0.2), value: isUserScrolling)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 100)
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    isUserScrolling = true
                    scrollResetTimer?.invalidate()
                    scrollResetTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        withAnimation {
                            isUserScrolling = false
                        }
                    }
                }
            )
            .onChange(of: currentLineIndex) { _, newIndex in
                guard !lines.isEmpty, !isUserScrolling else { return }
                
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    // Scrollt nu naar de aangepaste positie (iets boven het midden)
                    proxy.scrollTo(newIndex, anchor: customScrollAnchor)
                }
            }
        }
        .navigationTitle(Text(LocalizedStringKey("lyrics_navigation_title")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            parseLyrics()
        }
        .onChange(of: audioPlayer.currentSyncedLyrics) { _, _ in parseLyrics() }
        .onChange(of: audioPlayer.currentLyrics) { _, _ in parseLyrics() }
    }
    
    // MARK: - Subtiele Effecten
    
    private func calculateBlur(for distance: Int) -> CGFloat {
        if isUserScrolling { return 0 }
        if distance <= 0 { return 0 }
        
        // Milde vervaging: max 3.5pt blur voor regels ver eronder
        return min(CGFloat(distance) * 0.8, 3.5)
    }
    
    private func calculateOpacity(for distance: Int) -> Double {
        if isUserScrolling { return 1.0 }
        if distance == 0 { return 1.0 }
        
        if distance < 0 {
            // Vorige zinnen
            return max(1.0 - Double(abs(distance)) * 0.2, 0.35)
        } else {
            // Komende zinnen
            return max(1.0 - Double(distance) * 0.15, 0.4)
        }
    }
    
    // MARK: - Subviews & Logic
    
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
