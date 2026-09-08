import SwiftUI
import PhotosUI

struct PlaylistsView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @State private var showCreatePlaylist = false
    @State private var selectedPlaylist: Playlist?
    @State private var showDeleteConfirmation = false
    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var selectedImage: PhotosPickerItem?
    @State private var playlistImage: UIImage?
    @State private var imageData: Data?

    private let columns = [
        GridItem(
            .adaptive(minimum: 148, maximum: 220),
            spacing: 16,
            alignment: .top
        )
    ]

    private var totalPlaylistSongCount: Int {
        library.playlists.reduce(0) { result, playlist in
            result + library.songCount(in: playlist)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                PlaylistOverviewSummary(
                    playlists: library.playlists,
                    playlistCount: library.playlists.count,
                    songCount: totalPlaylistSongCount,
                    createAction: showCreatePlaylistSheet
                )

                favoritesSection
                playlistsSection
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .navigationTitle("playlists_title")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistView()
        }
        .sheet(isPresented: $showRenameSheet) {
            renamePlaylistSheet
        }
        .alert(
            "delete_playlist_alert_title",
            isPresented: $showDeleteConfirmation
        ) {
            Button("action_cancel", role: .cancel) {}
            Button("action_delete", role: .destructive) {
                if let selectedPlaylist {
                    library.deletePlaylist(selectedPlaylist)
                }
            }
        } message: {
            Text("delete_playlist_alert_message")
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("favorites_title")
                .font(.title2.bold())

            NavigationLink {
                FavoritesView()
            } label: {
                FavoritesOverviewCard(songs: library.favoriteSongs)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("playlists_title")
                .font(.title2.bold())

            if library.playlists.isEmpty {
                ContentUnavailableView {
                    Label(
                        "playlists_title",
                        systemImage: "music.note.list"
                    )
                } description: {
                    Text("create_playlist_navigation_title")
                } actions: {
                    Button(
                        "create_playlist_navigation_title",
                        action: showCreatePlaylistSheet
                    )
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistOverviewCard(
                                playlist: playlist,
                                songCount: library.songCount(in: playlist)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                preparePlaylistForEditing(playlist)
                            } label: {
                                Label(
                                    "action_edit_playlist",
                                    systemImage: "pencil"
                                )
                            }

                            Button(role: .destructive) {
                                selectedPlaylist = playlist
                                showDeleteConfirmation = true
                            } label: {
                                Label(
                                    "action_delete_playlist",
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var renamePlaylistSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()

                        PhotosPicker(
                            selection: $selectedImage,
                            matching: .images
                        ) {
                            PlaylistEditArtwork(image: playlistImage)
                        }

                        Spacer()
                    }
                }

                Section("playlist_name_section") {
                    TextField(
                        "playlist_name_placeholder",
                        text: $renameText
                    )
                }
            }
            .onChange(of: selectedImage) {
                loadSelectedImage()
            }
            .navigationTitle("edit_info_title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action_cancel") {
                        showRenameSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("action_save", action: savePlaylistChanges)
                        .disabled(
                            renameText
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                }
            }
        }
    }

    private func showCreatePlaylistSheet() {
        showCreatePlaylist = true
    }

    private func preparePlaylistForEditing(_ playlist: Playlist) {
        renameText = playlist.name
        selectedPlaylist = playlist
        imageData = playlist.imageData
        playlistImage = playlist.imageData.flatMap(UIImage.init(data:))
        selectedImage = nil
        showRenameSheet = true
    }

    private func loadSelectedImage() {
        Task {
            guard
                let data = try? await selectedImage?.loadTransferable(
                    type: Data.self
                ),
                let image = UIImage(data: data)
            else {
                return
            }

            playlistImage = image
            imageData = data
        }
    }

    private func savePlaylistChanges() {
        guard
            let selectedPlaylist,
            let index = library.playlists.firstIndex(
                where: { $0.id == selectedPlaylist.id }
            )
        else {
            return
        }

        library.playlists[index].name = renameText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        library.playlists[index].imageData = imageData
        showRenameSheet = false
    }
}

private struct PlaylistOverviewSummary: View {

    let playlists: [Playlist]
    let playlistCount: Int
    let songCount: Int
    let createAction: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            PlaylistStackArtwork(playlists: playlists)
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 9) {
                Text(
                    String(
                        format: String(localized: "libraryview_playlists_count"),
                        playlistCount
                    )
                )
                .font(.headline)

                Text("songs_count_format \(songCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: createAction) {
                    Label(
                        "create_playlist_navigation_title",
                        systemImage: "plus"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }
}

private struct FavoritesOverviewCard: View {

    let songs: [Song]

    var body: some View {
        HStack(spacing: 16) {
            FavoritesFeatureArtwork(songs: songs)
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 6) {
                Text("favorites_title")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text("songs_count_format \(songs.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 24))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaylistOverviewCard: View {

    let playlist: Playlist
    let songCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaylistOverviewArtwork(playlist: playlist)
                .aspectRatio(1, contentMode: .fit)

            Text(playlist.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("songs_count_format \(songCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaylistOverviewArtwork: View {

    let playlist: Playlist

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)

            if
                let data = playlist.imageData,
                let image = UIImage(data: data)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 38, weight: .medium))

                    Text(playlist.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }
            }
        }
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 22))
    }
}

private struct PlaylistEditArtwork: View {

    let image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 140)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 20))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 60))
                    .frame(width: 140, height: 140)
                    .background(.thinMaterial)
                    .clipShape(.rect(cornerRadius: 20))
            }

            Image(systemName: "camera.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(8)
                .background(.gray, in: Circle())
                .offset(x: -6, y: -6)
        }
        .accessibilityLabel("action_edit_playlist")
    }
}
