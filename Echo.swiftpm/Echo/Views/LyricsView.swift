import SwiftUI


struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}


struct LyricsView: View {
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var lines: [LyricLine] = []
    
    
    
    func parseSyncedLyrics(_ lyrics: String) -> [LyricLine] {
        
        var lines: [LyricLine] = []
        
        for line in lyrics.components(separatedBy: "\n") {
            
            guard line.hasPrefix("[") else {
                continue
            }
            
            guard let end = line.firstIndex(of: "]") else {
                continue
            }
            
            let timeString = String(
                line[line.index(after: line.startIndex)..<end]
            )
            
            let text = String(
                line[line.index(after: end)...]
            )
            
            let parts = timeString.split(separator: ":")
            
            if parts.count == 2,
               let minutes = Double(parts[0]),
               let seconds = Double(parts[1]) {
                
                let total = minutes * 60 + seconds
                
                lines.append(
                    LyricLine(
                        time: total,
                        text: text
                    )
                )
            }
        }
        
        return lines
    }
    
    
    var body: some View {
        
        ScrollViewReader { proxy in
            
            ScrollView {
                
                VStack(alignment: .leading, spacing: 22) {
                    
                    
                    if lines.isEmpty {
                        
                        if let lyrics = audioPlayer.currentLyrics,
                           !lyrics.isEmpty {
                            
                            plainLyricsView(lyrics)
                            
                        } else {
                            
                            if audioPlayer.lyricsNeedsInternet {
                                
                                ContentUnavailableView(
                                    "Wifi-verbinding nodig",
                                    systemImage: "wifi",
                                    description: Text(
                                        "Er zijn nog geen lyrics opgeslagen voor dit nummer. Verbind met internet om de lyrics op te halen. Als je toch verbonden bent met wifi of mobiele data, probeer dan het lied te herstarten."
                                    )
                                )
                                
                            } else {
                                
                                ContentUnavailableView(
                                    "Geen lyrics",
                                    systemImage: "text.quote",
                                    description: Text(
                                        "Voor dit nummer zijn geen lyrics beschikbaar."
                                    )
                                )
                            }
                        }
                        
                    } else {
                        
                        ForEach(Array(lines.enumerated()), id: \.offset) {
                            index, line in
                            
                            Button {
                                audioPlayer.seek(to: line.time)
                            } label: {
                                Text(line.text)
                                    .font(
                                        index == currentLineIndex
                                        ? .title2
                                        : .title3
                                    )
                                    .fontWeight(
                                        index == currentLineIndex
                                        ? .bold
                                        : .bold
                                    )
                                    .foregroundStyle(
                                        index == currentLineIndex
                                        ? .primary
                                        : .secondary
                                    )
                                    .opacity(
                                        index == currentLineIndex
                                        ? 1
                                        : 0.50
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 32,
                                        alignment: .leading
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(
                                .easeInOut(duration: 0.30),
                                value: currentLineIndex
                            )
                                
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .onChange(of: currentLineIndex) {
                
                guard !lines.isEmpty else {
                    return
                }
                
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(
                        currentLineIndex,
                        anchor: .center
                    )
                }
            }
        }
        .navigationTitle("Lyrics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            
                
                    print("Current lyrics:", audioPlayer.currentLyrics ?? "LEEG")
                    print("Synced:", audioPlayer.currentSyncedLyrics ?? "LEEG")
                    parseLyrics()
                
        }
        .onChange(of: audioPlayer.currentSyncedLyrics) { _, _ in
            parseLyrics()
        }
        .onChange(of: audioPlayer.currentLyrics) { _, _ in
            parseLyrics()
        }
    }
    
    
    private var currentLineIndex: Int {
        
        guard !lines.isEmpty else {
            return 0
        }
        
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
            .compactMap { line in
                
                parseLine(line)
            }
    }
    
    
     private func parseLine(
        _ line: String
    ) -> LyricLine? {
        
        guard line.hasPrefix("[") else {
            return nil
        }
        
        guard let closingBracket = line.firstIndex(
            of: "]"
        ) else {
            return nil
        }
        
        let timeString = String(
            line[line.index(after: line.startIndex)..<closingBracket]
        )
        
        let text = String(
            line[line.index(after: closingBracket)...]
        )
            .trimmingCharacters(
                in: .whitespaces
            )
        
        
        let components = timeString.split(
            separator: ":"
        )
        
        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1])
        else {
            return nil
        }
        
        
        return LyricLine(
            time: minutes * 60 + seconds,
            text: text
        )
    }
    
    
    @ViewBuilder
    private func plainLyricsView(
        _ lyrics: String
    ) -> some View {
        
        Text(lyrics)
            .font(.title3)
            .foregroundStyle(.primary)
            .lineSpacing(8)
    }
}



