import SwiftUI
import PhotosUI


struct PlaylistsView: View {

    @Environment(MusicLibraryManager.self)
    private var library


    @State private var showCreatePlaylist =
        false

    @State private var selectedPlaylist:
        Playlist?

    @State private var showDeleteConfirmation =
        false

    @State private var showRenameSheet =
        false

    @State private var renameText = ""


    @State private var selectedImage:
        PhotosPickerItem?

    @State private var playlistImage:
        UIImage?

    @State private var imageData:
        Data?



    // MARK: - Body

    var body: some View {

        List {


            // MARK: Favorites

            NavigationLink {

                FavoritesView()

            } label: {

                HStack(
                    spacing: 12
                ) {

                    ZStack {

                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                        .fill(.thinMaterial)


                        Image(
                            systemName:
                                "heart.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            .red
                        )
                    }

                    .frame(
                        width: 50,
                        height: 50
                    )


                    VStack(
                        alignment: .leading
                    ) {

                        Text(
                            LocalizedStringKey(
                                "favorites_title"
                            )
                        )
                        .font(.headline)


                        Text(
                            "songs_count_format \(library.favoriteSongs.count)"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }


                    Spacer()
                }
            }



            // MARK: Playlists

            ForEach(
                library.playlists
            ) { playlist in

                NavigationLink {

                    PlaylistDetailView(
                        playlist:
                            playlist
                    )

                } label: {

                    HStack(
                        spacing: 12
                    ) {

                        playlistArtwork(
                            playlist
                        )


                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {

                            Text(
                                playlist.name
                            )
                            .font(.headline)


                            Text(
                                "songs_count_format \(playlist.songIDs.count)"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }


                        Spacer()
                    }

                    .padding(
                        .vertical,
                        4
                    )
                }


                .contextMenu {


                    // MARK: Edit

                    Button {

                        renameText =
                            playlist.name

                        selectedPlaylist =
                            playlist


                        if
                            let data =
                                playlist.imageData,
                            let image =
                                UIImage(
                                    data: data
                                )
                        {

                            playlistImage =
                                image

                            imageData =
                                data

                        } else {

                            playlistImage =
                                nil

                            imageData =
                                nil
                        }


                        selectedImage = nil

                        showRenameSheet =
                            true

                    } label: {

                        Label(
                            LocalizedStringKey(
                                "action_edit_playlist"
                            ),
                            systemImage:
                                "pencil"
                        )
                    }



                    // MARK: Delete

                    Button(
                        role: .destructive
                    ) {

                        selectedPlaylist =
                            playlist

                        showDeleteConfirmation =
                            true

                    } label: {

                        Label(
                            LocalizedStringKey(
                                "action_delete_playlist"
                            ),
                            systemImage:
                                "trash"
                        )
                    }
                }
            }


            // MiniPlayer ruimte

            Color.clear
                .frame(height: 105)
                .listRowBackground(
                    Color.clear
                )
                .listRowSeparator(
                    .hidden
                )
        }


        .navigationTitle(
            LocalizedStringKey(
                "playlists_title"
            )
        )

        .navigationBarTitleDisplayMode(
            .large
        )


        // MARK: Toolbar

        .toolbar {

            ToolbarItem(
                placement:
                    .topBarTrailing
            ) {

                Button {

                    showCreatePlaylist =
                        true

                } label: {

                    Image(
                        systemName: "plus"
                    )
                }
            }
        }



        // MARK: Create

        .sheet(
            isPresented:
                $showCreatePlaylist
        ) {

            CreatePlaylistView()
        }



        // MARK: Rename

        .sheet(
            isPresented:
                $showRenameSheet
        ) {

            NavigationStack {

                Form {

                    Section {

                        HStack {

                            Spacer()


                            PhotosPicker(
                                selection:
                                    $selectedImage,
                                matching:
                                    .images
                            ) {

                                ZStack(
                                    alignment:
                                        .bottomTrailing
                                ) {

                                    if
                                        let playlistImage
                                    {

                                        Image(
                                            uiImage:
                                                playlistImage
                                        )
                                        .resizable()
                                        .scaledToFill()
                                        .frame(
                                            width: 140,
                                            height: 140
                                        )
                                        .clipped()
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius:
                                                    20
                                            )
                                        )

                                    } else {

                                        Image(
                                            systemName:
                                                "music.note"
                                        )
                                        .font(
                                            .system(
                                                size: 60
                                            )
                                        )
                                        .frame(
                                            width: 140,
                                            height: 140
                                        )
                                        .background(
                                            .thinMaterial
                                        )
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius:
                                                    20
                                            )
                                        )
                                    }


                                    Image(
                                        systemName:
                                            "camera.fill"
                                    )
                                    .font(.title3)
                                    .foregroundStyle(
                                        .white
                                    )
                                    .padding(8)
                                    .background(
                                        .gray
                                    )
                                    .clipShape(
                                        Circle()
                                    )
                                    .offset(
                                        x: -6,
                                        y: -6
                                    )
                                }
                            }


                            Spacer()
                        }
                    }


                    Section(
                        LocalizedStringKey(
                            "playlist_name_section"
                        )
                    ) {

                        TextField(
                            LocalizedStringKey(
                                "playlist_name_placeholder"
                            ),
                            text:
                                $renameText
                        )
                    }
                }


                .onChange(
                    of: selectedImage
                ) {

                    Task {

                        if
                            let data =
                                try?
                                await selectedImage?
                                    .loadTransferable(
                                        type:
                                            Data.self
                                    ),
                            let image =
                                UIImage(
                                    data: data
                                )
                        {

                            playlistImage =
                                image

                            imageData =
                                data
                        }
                    }
                }


                .navigationTitle(
                    LocalizedStringKey(
                        "edit_info_title"
                    )
                )


                .toolbar {

                    ToolbarItem(
                        placement:
                            .topBarTrailing
                    ) {

                        Button(
                            LocalizedStringKey(
                                "action_save"
                            )
                        ) {

                            if
                                let index =
                                    library
                                        .playlists
                                        .firstIndex(
                                            where: {

                                                $0.id
                                                ==
                                                selectedPlaylist?
                                                    .id
                                            }
                                        )
                            {

                                library
                                    .playlists[index]
                                    .name =
                                        renameText


                                library
                                    .playlists[index]
                                    .imageData =
                                        imageData
                            }


                            showRenameSheet =
                                false
                        }
                    }
                }
            }
        }



        // MARK: Delete

        .alert(
            LocalizedStringKey(
                "delete_playlist_alert_title"
            ),
            isPresented:
                $showDeleteConfirmation
        ) {

            Button(
                LocalizedStringKey(
                    "action_cancel"
                ),
                role: .cancel
            ) {}


            Button(
                LocalizedStringKey(
                    "action_delete"
                ),
                role: .destructive
            ) {

                if
                    let playlist =
                        selectedPlaylist
                {

                    library.playlists
                        .removeAll {

                            $0.id
                            ==
                            playlist.id
                        }
                }
            }

        } message: {

            Text(
                LocalizedStringKey(
                    "delete_playlist_alert_message"
                )
            )
        }
    }



    // MARK: Artwork

    @ViewBuilder
    private func playlistArtwork(
        _ playlist: Playlist
    ) -> some View {

        if
            let data =
                playlist.imageData,
            let image =
                UIImage(data: data)
        {

            Image(
                uiImage: image
            )
            .resizable()
            .scaledToFill()
            .frame(
                width: 55,
                height: 55
            )
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14
                )
            )

        } else {

            Image(
                systemName:
                    "music.note.list"
            )
            .font(.title2)
            .frame(
                width: 55,
                height: 55
            )
            .background(
                .thinMaterial
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14
                )
            )
        }
    }
}
