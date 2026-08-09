import SwiftUI

struct QueueView: View {
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAutoNext = false
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                if let current = audioPlayer.currentSong {
                    
                    Section("Nu afgespeeld") {
                        
                        HStack(spacing: 12) {
                            
                            if let data = current.coverData,
                               let image = UIImage(data: data) {
                                
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                            } else {
                                
                                Image(systemName: "music.note")
                                    .frame(width: 50, height: 50)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            
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
                
                
                Section("Volgende") {
                    
                    ForEach(
                        Array(audioPlayer.queue.dropFirst(audioPlayer.currentIndex + 1))
                    ) { song in
                        
                        Button {
                            
                            audioPlayer.playFromQueue(song)
                            
                        } label: {
                            
                            HStack(spacing: 12) {
                                
                                if let data = song.coverData,
                                   let image = UIImage(data: data) {
                                    
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                } else {
                                    
                                    Image(systemName: "music.note")
                                        .frame(width: 50, height: 50)
                                        .background(.thinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                
                                VStack(alignment: .leading) {
                                    
                                    Text(song.title)
                                        .foregroundStyle(.primary)
                                    
                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
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
                
                
                
                Section {
                    
                    Button {
                        withAnimation {
                            showAutoNext.toggle()
                        }
                    } label: {
                        
                        HStack {
                            Text("Automatisch volgende")
                            
                            Spacer()
                            
                            Image(
                                systemName: showAutoNext
                                ? "chevron.down"
                                : "chevron.right"
                            )
                        }
                    }
                    
                    
                    if showAutoNext {
                        
                        ForEach(audioPlayer.autoNextQueue) { song in
                            
                            HStack {
                                
                                Text(song.title)
                                
                                Spacer()
                                
                                Text(song.artist)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
}
