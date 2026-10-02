import SwiftUI

struct EditSongView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    
    let song: Song
    
    @State private var title: String
    @State private var artist: String
    @State private var genre: String
    @State private var year: String
    
    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
        _genre = State(initialValue: song.genre ?? "")
        _year = State(initialValue: song.releaseYear.map(String.init) ?? "")
    }
    
    var body: some View {
        
        NavigationStack {
            
            Form {
                Section(header: Text(LocalizedStringKey("song_details_section"))) {
                    TextField(
                        LocalizedStringKey("song_title_placeholder"),
                        text: $title
                    )
                    
                    TextField(
                        LocalizedStringKey("song_artist_placeholder"),
                        text: $artist
                    )
                    TextField("smart_field_genre", text: $genre)
                    TextField("smart_field_releaseYear", text: $year).keyboardType(.numberPad)
                }
            }
            .echoBackground()
            .navigationTitle(Text(LocalizedStringKey("edit_song_navigation_title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("cancel_action")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("save_action")) {
                        library.updateSong(
                            song,
                            title: title,
                            artist: artist,
                            genre: genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : genre,
                            releaseYear: Int(year)
                        )
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}