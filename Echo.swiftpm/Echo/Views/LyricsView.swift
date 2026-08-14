import SwiftUI

// MARK: - Models
struct LyricWord: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let startTime: Double
    let words: [LyricWord]
    
    // Helper om de volledige regeltekst op te halen
    var rawText: String {
        words.map { $0.text }.joined(separator: " ")
    }
}

// MARK: - Main View
struct LyricsView: View {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var lines: [LyricLine] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
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

// MARK: - Views & Layouts
private extension LyricsView {
    
    @ViewBuilder
    var lyricsListView: some View {
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
            let isCurrentLine = index == currentLineIndex
            
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    audioPlayer.seek(to: line.startTime)
                }
            } label: {
                LyricLineWordByWordView(
                    line: line,
                    currentTime: audioPlayer.currentTime,
                    isCurrentLine: isCurrentLine
                )
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}

// MARK: - Word-by-Word Line Component
private struct LyricLineWordByWordView: View {
    let line: LyricLine
    let currentTime: Double
    let isCurrentLine: Bool
    
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(line.words) { word in
                let isWordPassed = currentTime >= word.time
                
                Text(word.text)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    // Als de regel niet actief is, is alles gedimd.
                    // Als de regel WEL actief is, lichten de al gezongen woorden op!
                    .foregroundStyle(
                        isCurrentLine
                        ? (isWordPassed ? Color.primary : Color.primary.opacity(0.3))
                        : Color.secondary.opacity(0.4)
                    )
                    .blur(radius: isCurrentLine ? 0 : 0.4)
                    .animation(.easeInOut(duration: 0.15), value: isWordPassed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Custom Flow Layout (Zorgt dat woorden netjes afbreken per regel)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flow(subviews: subviews, proposal: proposal)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = flow(subviews: subviews, proposal: proposal, bounds: bounds)
    }

    private func flow(subviews: Subviews, proposal: ProposedViewSize, bounds: CGRect? = nil) -> (size: CGSize, Void) {
        var width: CGFloat = 0
        var height: CGFloat = 0
        var x: CGFloat = bounds?.minX ?? 0
        var y: CGFloat = bounds?.minY ?? 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > (bounds?.minX ?? 0) + maxWidth {
                x = bounds?.minX ?? 0
                y += size.height + spacing
            }
            
            if let bounds = bounds {
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            }
            
            x += size.width + spacing
            width = max(width, x)
            height = max(height, y + size.height)
        }

        return (CGSize(width: width, height: height - (bounds?.minY ?? 0)), ())
    }
}

// MARK: - Advanced LRC / Word-by-Word Parser
private extension LyricsView {
    
    var currentLineIndex: Int {
        guard !lines.isEmpty else { return 0 }
        
        var activeIndex = 0
        for (index, line) in lines.enumerated() {
            if line.startTime <= audioPlayer.currentTime {
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
    
    func parseLine(_ rawLine: String) -> LyricLine? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }
        
        // Regex zoekt naar timestamp patronen zoals [00:12.34] of <00:12.34>
        let pattern = "(?:\\[|<)(\\d+):(\\d+(?:\\.\\d+)?)(?:\\]|>)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let nsString = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))
        
        guard !matches.isEmpty else { return nil }
        
        var words: [LyricWord] = []
        var lineStartTime: Double? = nil
        
        // Als er maar 1 timestamp aan het begin staat (standaard LRC):
        if matches.count == 1 && matches[0].range.location == 0 {
            let time = parseTime(nsString: nsString, match: matches[0])
            lineStartTime = time
            
            let text = nsString.substring(from: matches[0].range.length).trimmingCharacters(in: .whitespaces)
            let rawWords = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            // Verdeel de regel in losse woorden op dezelfde starttijd
            words = rawWords.map { LyricWord(time: time, text: $0) }
        } else {
            // Woord-voor-woord LRC indeling: [00:10.00] Woord1 [00:10.50] Woord2
            for i in 0..<matches.count {
                let match = matches[i]
                let time = parseTime(nsString: nsString, match: match)
                if lineStartTime == nil { lineStartTime = time }
                
                let wordStartIndex = match.range.location + match.range.length
                let wordEndIndex = (i + 1 < matches.count) ? matches[i + 1].range.location : nsString.length
                
                let wordText = nsString.substring(with: NSRange(location: wordStartIndex, length: wordEndIndex - wordStartIndex))
                    .trimmingCharacters(in: .whitespaces)
                
                if !wordText.isEmpty {
                    words.append(LyricWord(time: time, text: wordText))
                }
            }
        }
        
        guard let startTime = lineStartTime, !words.isEmpty else { return nil }
        return LyricLine(startTime: startTime, words: words)
    }
    
    func parseTime(nsString: NSString, match: NSTextCheckingResult) -> Double {
        let minutes = Double(nsString.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(nsString.substring(with: match.range(at: 2))) ?? 0
        return minutes * 60 + seconds
    }
}
