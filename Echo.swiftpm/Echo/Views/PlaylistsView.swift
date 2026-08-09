import SwiftUI
import PhotosUI


struct PlaylistsView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    
    @State private var showCreatePlaylist = false
    @State private var selectedPlaylist: Playlist?
    @State private var showDeleteConfirmation = false
    @State private var showRenameSheet = false
    @State private var renameText = ""
    
    @State private var selectedImage: PhotosPickerItem?
    @State private var playlistImage: UIImage?
    @State private var imageData: Data?
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                NavigationLink {
                    
                    FavoritesView()
                    
                } label: {
                    
                    HStack(spacing: 12) {
                        
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .frame(
                                width: 50,
                                height: 50
                            )
                            .background(.thinMaterial)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12
                                )
                            )
                        
                        VStack(alignment: .leading) {
                            
                            Text("Favorieten")
                                .font(.headline)
                            
                            Text("\(library.favoriteSongs.count) nummers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                
                ForEach(library.playlists) { playlist in
                    
                    NavigationLink {
                        
                        PlaylistDetailView(
                            playlist: playlist
                        )
                        
                    } label: {
                        
                        HStack {
                            
                            if let data = playlist.imageData,
                               let image = UIImage(data: data) {
                                
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: 55,
                                        height: 55
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 14
                                        )
                                    )
                                
                            } else {
                                
                                Image(systemName: "music.note.list")
                                    .font(.title2)
                                    .frame(
                                        width: 55,
                                        height: 55
                                    )
                                    .background(.thinMaterial)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 14
                                        )
                                    )
                            }
                            
                            
                            VStack(alignment: .leading, spacing: 4) {
                                
                                Text(playlist.name)
                                    .font(.headline)
                                
                                Text("\(playlist.songIDs.count) nummers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    
                    .contextMenu {
                        
                        Button {
                            
                            renameText = playlist.name
                            selectedPlaylist = playlist
                            
                            if let data = playlist.imageData,
                               let image = UIImage(data: data) {
                                
                                playlistImage = image
                                imageData = data
                                
                            } else {
                                
                                playlistImage = nil
                                imageData = nil
                            }
                            
                            selectedImage = nil
                            
                            showRenameSheet = true
                            
                        } label: {
                            
                            Label(
                                "wijzig playlist",
                                systemImage: "pencil"
                            )
                        }
                        
                        
                        
                        Button(role: .destructive) {
                            
                            selectedPlaylist = playlist
                            showDeleteConfirmation = true
                            
                        } label: {
                            
                            Label(
                                "Verwijder playlist",
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            
            .navigationTitle("Playlists")
            
            
            .toolbar {
                
                Button {
                    
                    showCreatePlaylist = true
                    
                } label: {
                    
                    Image(systemName: "plus")
                }
            }
            
            
            .sheet(isPresented: $showCreatePlaylist) {
                
                CreatePlaylistView()
            }
            
            .sheet(isPresented: $showRenameSheet) {
                
                NavigationStack {
                    
                    Form {
                        
                        Section {
                            
                            HStack {
                                
                                Spacer()
                                
                                PhotosPicker(
                                    selection: $selectedImage,
                                    matching: .images
                                ) {
                                    
                                    ZStack(alignment: .bottomTrailing) {
                                        
                                        if let playlistImage {
                                            
                                            Image(uiImage: playlistImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 140, height: 140)
                                                .clipShape(
                                                    RoundedRectangle(cornerRadius: 20)
                                                )
                                            
                                        } else {
                                            
                                            Image(systemName: "music.note")
                                                .font(.system(size: 60))
                                                .frame(width: 140, height: 140)
                                                .background(.thinMaterial)
                                                .clipShape(
                                                    RoundedRectangle(cornerRadius: 20)
                                                )
                                        }
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.title3)
                                            .foregroundStyle(.white)
                                            .padding(8)
                                            .background(.gray)
                                            .clipShape(Circle())
                                            .offset(x: -6, y: -6)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                        
                        Section("Naam") {
                            
                            TextField(
                                "Naam",
                                text: $renameText
                            )
                        }
                    }
                    .onChange(of: selectedImage) {
                        
                        Task {
                            
                            if let data = try? await selectedImage?
                                .loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                
                                playlistImage = image
                                imageData = data
                            }
                        }
                    }
                    
                    .navigationTitle("Info wijzigen")
                    
                    .toolbar {
                        
                        ToolbarItem(placement: .topBarTrailing) {
                            
                            Button("Bewaar") {
                                
                                if let index = library.playlists.firstIndex(
                                    where: {
                                        $0.id == selectedPlaylist?.id
                                    }
                                ) {
                                    
                                    library.playlists[index].name = renameText
                                    library.playlists[index].imageData = imageData
                                }
                                
                                showRenameSheet = false
                            }
                        }
                    }
                }
            }
            
            .alert(
                "Playlist verwijderen?",
                isPresented: $showDeleteConfirmation
            ) {
                
                Button(
                    "Annuleer",
                    role: .cancel
                ) {}
                
                
                Button(
                    "Verwijder",
                    role: .destructive
                ) {
                    
                    if let playlist = selectedPlaylist {
                        
                        library.playlists.removeAll {
                            $0.id == playlist.id
                        }
                    }
                }
                
            } message: {
                
                Text(
                    "De playlist wordt verwijderd. De nummers blijven in je bibliotheek."
                )
            }
        }
    }
}


#Preview {
    
    PlaylistsView()
        .environment(MusicLibraryManager())
}
