import SwiftUI

struct PlaylistPickerView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    
    let songs: [Song]
    
    // Convenience initializer voor wanneer je slechts 1 nummer meegeeft
    init(song: Song) {
        self.songs = [song]
    }
    
    // Initializer voor meerdere nummers
    init(songs: [Song]) {
        self.songs = songs
    }
    
    // Controleert of alle geselecteerde nummers al favoriet zijn
    private var areAllFavorites: Bool {
        guard !songs.isEmpty else { return false }
        return songs.allSatisfy { library.isFavorite($0) }
    }
    
    // Controleert of alle geselecteerde nummers in een specifieke playlist staan
    private func areAllInPlaylist(_ playlist: Playlist) -> Bool {
        guard !songs.isEmpty else { return false }
        let ids = Set(library.songs(in: playlist).map(\.id))
        return songs.allSatisfy { ids.contains($0.id) }
    }

    private func blockedUntil(_ playlist: Playlist) -> Date? {
        let now = SmartPlaylistClock.shared.now
        return songs.compactMap { playlist.smartOverrides?[$0.id]?.excludedUntil }
            .filter { $0 > now }.max()
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Favorieten
                Button {
                    for song in songs {
                        if !library.isFavorite(song) {
                            library.toggleFavorite(song)
                        }
                    }
                    dismiss()
                } label: {
                    playlistRow(
                        image: nil,
                        systemImage: "heart.fill",
                        title: Text(LocalizedStringKey("favorites_title")),
                        count: library.favoriteSongs.count,
                        isSelected: areAllFavorites
                    )
                }
                
                // Eigen playlists
                ForEach(library.playlists.filter { $0.smartDefinition == nil }) { playlist in
                    Button {
                        for song in songs {
                            library.addSong(song, to: playlist)
                        }
                        dismiss()
                    } label: {
                        playlistRow(
                            image: playlist.imageData,
                            builtin: playlist.builtinCoverID,
                            systemImage: "music.note.list",
                            title: Text(playlist.displayName()),
                            count: library.songCount(in: playlist),
                            isSelected: areAllInPlaylist(playlist)
                        )
                    }
                }
                Section {
                    ForEach(library.playlists.filter { $0.smartDefinition != nil }) { playlist in
                        let blocked = blockedUntil(playlist)
                        Button {
                            for song in songs { library.addSong(song, to: playlist) }
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                playlistRow(image: playlist.imageData, builtin: playlist.builtinCoverID,
                                    systemImage: "sparkles", title: Text(playlist.displayName()),
                                    count: library.songCount(in: playlist), isSelected: areAllInPlaylist(playlist))
                                if let blocked {
                                    Text(String(format: String(localized: "smart_add_available", locale: locale),
                                        blocked.formatted(.dateTime.day().month().hour().minute().locale(locale))))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.disabled(blocked != nil)
                    }
                } header: {
                    Text("smart_picker_section")
                } footer: {
                    Text("smart_manual_detail")
                }
            }
            .echoBackground()
            .navigationTitle(LocalizedStringKey("choose_playlist_title"))
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("action_cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func playlistRow(
        image: Data?,
        builtin: String? = nil,
        systemImage: String,
        title: Text,
        count: Int,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            PlaylistCoverArtwork(data: image, builtin: builtin, pixels: 128, symbol: systemImage)
                .frame(width: 55, height: 55).clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("songs_count_format \(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
