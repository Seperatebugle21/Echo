import SwiftUI

// MARK: - Models
struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
}

// MARK: - Main Lyrics View
struct LyricsView: View {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var lines: [LyricLine] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if lines.isEmpty {
                        emptyStateView
                    } else {
                        lyricsListView
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 60)
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                scrollToActiveLine(proxy: proxy, index: newIndex)
            }
        }
        .navigationTitle(Text(LocalizedStringKey("lyrics_navigation_title")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: parseLyrics)
        .onChange(of: audioPlayer.currentSyncedLyrics) { _, _ in parseLyrics() }
        .onChange(of: audioPlayer.currentLyrics) { _, _ in parseLyrics() }
    }
}

// MARK: - Subviews & Views Logic
private extension LyricsView {
    
    @ViewBuilder
    var lyricsListView: some View {
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
            let isActive = index == currentLineIndex
            
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    audioPlayer.seek(to: line.time)
                }
            } label: {
                LyricRowView(text: line.text, isActive: isActive)
            }
            .buttonStyle(.plain)
            .id(index)
        }
    }
    
    @ViewBuilder
    var emptyStateView: some View {
        if let lyrics = audioPlayer.currentLyrics, !lyrics.isEmpty {
            plainLyricsView(lyrics)
        } else if audioPlayer.lyricsNeedsInternet {
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

    @ViewBuilder
    func plainLyricsView(_ lyrics: String) -> some View {
        Text(lyrics)
            .font(.system(.title3, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .lineSpacing(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func scrollToActiveLine(proxy: ScrollViewProxy, index: Int) {
        guard !lines.isEmpty else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}

// MARK: - Lyric Row Component
private struct LyricRowView: View {
    let text: String
    let isActive: Bool
    
    var body: some View {
        Text(text)
            .font(.system(isActive ? .title : .title2, design: .rounded, weight: .bold))
            .foregroundStyle(isActive ? .primary : .secondary)
            .opacity(isActive ? 1.0 : 0.4)
            .blur(radius: isActive ? 0 : 0.4)
            .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - Parsing Logic
private extension LyricsView {
    
    var currentLineIndex: Int {
        guard !lines.isEmpty else { return 0 }
        
        var activeIndex = 0
        for (index, line) in lines.enumerated() {
            if line.time <= audioPlayer.currentTime {
                activeIndex = index
            } else {
                break
            }
        }
        return activeIndex
    }
    
    func parseLyrics() {
        guard let synced = audioPlayer.currentSyncedLyrics, !synced.isEmpty else {
            lines = []
            return
        }
        
        lines = synced
            .components(separatedBy: .newlines)
            .compactMap { parseLine($0) }
    }
    
    func parseLine(_ line: String) -> LyricLine? {
        guard line.hasPrefix("["), let closingBracket = line.firstIndex(of: "]") else {
            return nil
        }
        
        let timeString = String(line[line.index(after: line.startIndex)..<closingBracket])
        let text = String(line[line.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
        
        // Ondersteunt zowel [01:23] als [01:23.45]
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]) else {
            return nil
        }
        
        return LyricLine(
            time: minutes * 60 + seconds,
            text: text.isEmpty ? "🎵" : text
        )
    }
}
