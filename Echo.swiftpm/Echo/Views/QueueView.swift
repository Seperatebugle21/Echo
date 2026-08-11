import SwiftUI

struct QueueView: View {
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAutoNext = true
    @State private var editMode: EditMode = .inactive
    @State private var selectedSongIDs = Set<UUID>() // Slaat de geselecteerde nummers op
    
    var body: some View {
        
        NavigationStack {
            
            List(selection: $selectedSongIDs) {
                
                // MARK: - Herhaal Status Banner
                if audioPlayer.repeatMode != .off {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: audioPlayer.repeatMode == .one ? "repeat.1" : "repeat")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audioPlayer.repeatMode == .one ? LocalLocalizedStringKey("repeat_one_active") : LocalLocalizedStringKey("repeat_all_active"))
                                    .font(.subheadline)
                                    .bold()
                                
                                Text(audioPlayer.repeatMode == .one 
                                     ? LocalLocalizedStringKey("repeat_one_description") 
                                     : LocalLocalizedStringKey("repeat_all_description"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // MARK: - Nu Afgespeeld
                if let current = audioPlayer.currentSong {
                    Section(LocalizedStringKey("queue_now_playing")) {
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
                
                // MARK: - Handmatige Wachtrij (Selecteerbaar)
                let upcomingSongs = Array(audioPlayer.queue.dropFirst(audioPlayer.currentIndex + 1))
                
                if !upcomingSongs.isEmpty {
                    Section(LocalizedStringKey("queue_up_next")) {
                        ForEach(upcomingSongs) { song in
                            songRow(for: song)
                                .tag(song.id) // Nodig voor de selectiemodus
                        }
                        .onMove { from, to in
                            // Pas de offsets aan vanwege dropFirst
                            let actualFrom = IndexSet(from.map { $0 + audioPlayer.currentIndex + 1 })
                            let actualTo = to + audioPlayer.currentIndex + 1
                            audioPlayer.queue.move(fromOffsets: actualFrom, toOffset: actualTo)
                        }
                    }
                }
                
                // MARK: - Automatische Wachtrij
                if !audioPlayer.autoNextQueue.isEmpty {
                    Section {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showAutoNext.toggle()
                            }
                        } label: {
                            HStack {
                                Label(LocalizedStringKey("queue_auto_next"), systemImage: "sparkles")
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
                        Text(LocalizedStringKey("queue_recommended"))
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(LocalizedStringKey("queue_title"))
            .navigationBarTitleDisplayMode(.inline)
            
            // MARK: - Toolbar met Verwijderknop
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode.isEditing {
                        Button(LocalizedStringKey("action_delete"), role: .destructive) {
                            deleteSelectedSongs()
                        }
                        .disabled(selectedSongIDs.isEmpty) // Alleen inklikbaar als er iets gekozen is
                    } else {
                        Button(LocalizedStringKey("action_close")) {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? LocalLocalizedStringKey("action_done") : LocalLocalizedStringKey("action_edit")) {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                            if !editMode.isEditing {
                                selectedSongIDs.removeAll()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Logica voor Verwijderen
    private func deleteSelectedSongs() {
        withAnimation {
            audioPlayer.queue.removeAll { song in
                selectedSongIDs.contains(song.id)
            }
            selectedSongIDs.removeAll()
            editMode = .inactive
        }
    }
    
    // MARK: - Helper Views
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