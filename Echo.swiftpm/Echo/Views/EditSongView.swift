import SwiftUI

struct EditSongView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    
    let song: Song
    
    @State private var title: String
    @State private var artist: String
    
    @Environment(\.dismiss) private var dismiss
    
    
    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
    }
    
    
    var body: some View {
        
        NavigationStack {
            
            Form {
                
                TextField("Titel", text: $title)
                
                TextField("Artiest", text: $artist)
                
            }
            .navigationTitle("Wijzig info")
            .toolbar {
                
                Button("Bewaar") {
                    
                    library.updateSong(
                        song,
                        title: title,
                        artist: artist
                    )
                    
                    dismiss()
                }
            }
        }
    }
}

