import SwiftUI
import PhotosUI

struct CreatePlaylistView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    
    @State private var selectedImage: PhotosPickerItem?
    @State private var playlistImage: UIImage?
    @State private var imageData: Data?
    
    var body: some View {
        
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
                        .accessibilityLabel(LocalizedStringKey("select_cover_image_accessibility"))
                        
                        Spacer()
                    }
                }
                
                Section(header: Text(LocalizedStringKey("playlist_name_section_header"))) {
                    TextField(
                        LocalizedStringKey("playlist_name_placeholder"),
                        text: $name
                    )
                }
            }
            .navigationTitle(Text(LocalizedStringKey("create_playlist_navigation_title")))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedImage) {
                Task {
                    if let data = try? await selectedImage?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        playlistImage = image
                        imageData = data
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("cancel_action")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("create_action")) {
                        let trimmed = name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        
                        guard !trimmed.isEmpty else { return }
                        
                        library.createPlaylist(
                            name: trimmed,
                            imageData: imageData
                        )
                        
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

#Preview {
    CreatePlaylistView()
        .environment(MusicLibraryManager())
}