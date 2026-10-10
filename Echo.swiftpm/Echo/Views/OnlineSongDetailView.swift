import SwiftUI

struct OnlineSongDetailView: View {
    let track: OnlineMusicTrack
    @State private var downloading = false
    @State private var result: String?
    private let downloads = CatalogDownloads.shared

    private var status: String? { downloads.statusKey(track) }
    private var downloadDisabled: Bool {
        downloading || downloads.busy || status == "catalog_downloaded" || status == "catalog_queued"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CatalogArtwork(url: track.artworkURL, size: 220)
                VStack(spacing: 6) {
                    Text(track.title).font(.title2.bold())
                    Text(track.artistName).font(.headline).foregroundStyle(.secondary)
                    if let album = track.album, !album.isEmpty {
                        Text(album).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)

                Divider()
                VStack(spacing: 14) {
                    informationRow("spotifytrackdetailview_artist", value: track.artistName)
                    if let album = track.album, !album.isEmpty {
                        informationRow("spotifytrackdetailview_album", value: album)
                    }
                    if track.durationMS > 0 {
                        informationRow("spotifytrackdetailview_duration", value: durationText)
                    }
                    informationRow("catalog_song_provider", value: track.provider.name)
                    if let recordingID = track.recordingID, !recordingID.isEmpty {
                        informationRow("catalog_song_recording_id", value: recordingID)
                    }
                    if track.provider == .spotify {
                        informationRow("spotifytrackdetailview_method", value: ApifySettings.shared.downloadMethod.title)
                    }
                }

                if let status {
                    Text(LocalizedStringKey(status)).font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    Task { await download() }
                } label: {
                    HStack {
                        if downloading { ProgressView().tint(.white) }
                        Label("spotifytrackdetailview_download", systemImage: "arrow.down.circle.fill")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(downloadDisabled)
            }
            .padding(24)
        }
        .echoBackground()
        .navigationTitle("spotifytrackdetailview_song")
        .navigationBarTitleDisplayMode(.inline)
        .alert("catalog_download_result_title", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("spotifytrackdetailview_ok") { result = nil }
        } message: { Text(result ?? "") }
    }

    private func informationRow(_ title: LocalizedStringKey, value: String) -> some View {
        LabeledContent { Text(value).multilineTextAlignment(.trailing) } label: { Text(title) }
            .font(.subheadline)
    }

    private var durationText: String {
        let seconds = track.durationMS / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func download() async {
        guard !downloadDisabled else { return }
        downloading = true
        defer { downloading = false }
        result = await downloads.enqueue([track]).message
    }
}
