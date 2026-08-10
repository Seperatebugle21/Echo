import SwiftUI

struct QueueView: View {
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAutoNext = true // Standaard opengeklapt voor beter overzicht
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                // MARK: - Herhaal Status Banner
                if audioPlayer.repeatMode != .off {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: audioPlayer.repeatMode == .one ? "repeat.1" : "repeat")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audioPlayer.repeatMode == .one ? "Herhaal 1 actief" : "Herhaal alles actief")
                                    .font(.subheadline)
                                    .bold()
                                
                                Text(audioPlayer.repeatMode == .one 
                                     ? "Het huidige nummer wordt oneindig herhaald." 
                                     : "De huidige wachtrij blijft herhalen. Automatische nummers worden niet afgespeeld.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // MARK: - Nu Afgespeeld
                if let current = audioPlayer.currentSong {
                    
                    Section("Nu afgespeeld") {
                        
                        HStack(spacing: 12) {
                            
                            songCoverImage(for: current)
                            
                            VStack(alignment: .leading) {
                                Text(current.title)
                                    .font(.headline)
                                
                                Text(current.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                // MARK: - Handmatige Wachtrij
                let upcomingSongs = Array(audioPlayer.queue.dropFirst(audioPlayer.currentIndex + 1))
                
                if !upcomingSongs.isEmpty {
                    Section("Volgende") {
                        
                        ForEach(upcomingSongs) { song in
                            
                            Button {
                                audioPlayer.playFromQueue(song)
                            } label: {
                                songRow(for: song)
                            }
                            .buttonStyle(.plain)
                        }
                        .onMove { from, to in
                            audioPlayer.queue.move(
                                fromOffsets: from,
                                toOffset: to
                            )
                        }
                    }
                }
                
                // MARK: - Automatische Wachtrij (Remake)
                if !audioPlayer.autoNextQueue.isEmpty {
                    Section {
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showAutoNext.toggle()
                            }
                        } label: {
                            HStack {
                                Label("Automatisch volgende", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Image(systemName: showAutoNext ? "chevron.down" : "chevron.right")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if showAutoNext {
                            ForEach(audioPlayer.autoNextQueue) { song in
                                Button {
                                    // Direct afspelen uit de auto-wachtrij
                                    if let url = audioPlayer.getURL(for: song) {
                                        audioPlayer.play(song: song, url: url, queue: [])
                                    }
                                } label: {
                                    songRow(for: song)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Aanbevolen")
                    }
                }
            }
            .navigationTitle("Wachtrij")
            .navigationBarTitleDisplayMode(.inline)
            
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sluit") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }
    
    // MARK: - Helper Views (Schoon & Herbruikbaar)
    
    @ViewBuilder
    private func songCoverImage(for song: Song) -> some View {
        if let data = song.coverData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    @ViewBuilder
    private func songRow(for song: Song) -> some View {
        HStack(spacing: 12) {
            songCoverImage(for: song)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
    }
}
