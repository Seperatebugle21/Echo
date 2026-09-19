import SwiftUI

struct PodcastTranscriptView: View {
    let episode: PodcastEpisode
    @Environment(\.dismiss) private var dismiss
    @State private var transcript: String?
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading {
                    ProgressView("podcasts_loading").frame(maxWidth: .infinity).padding(40)
                } else if let transcript {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(episode.title).font(.title2.bold())
                        Text(transcript).font(.body).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                } else if failed {
                    ContentUnavailableView {
                        Label("podcasts_transcript_error", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("podcasts_retry") { retry += 1 }
                    }
                } else {
                    ContentUnavailableView("podcasts_transcript_unavailable", systemImage: "text.bubble",
                        description: Text("podcasts_transcript_unavailable_detail"))
                }
            }
            .echoBackground()
            .navigationTitle("podcasts_transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action_close") { dismiss() }
                }
            }
            .task(id: retry) {
                loading = true
                failed = false
                do {
                    let text = try await PodcastCatalog.shared.transcript(for: episode)
                    try Task.checkCancellation()
                    transcript = text
                } catch {
                    guard !Task.isCancelled else { return }
                    failed = true
                }
                loading = false
            }
        }
    }
}
