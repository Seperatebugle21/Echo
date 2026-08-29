import SwiftUI
import UIKit


// MARK: - Inline URL Section

struct FetchURLInlineSection:
    View {

    @State private var urlText =
        ""

    @State private var isResolving =
        false

    @State private var resolved:
        FetchURLResolvedContent?

    @State private var errorMessage:
        String?


    var body: some View {

        Section {

            HStack(
                spacing:
                    8
            ) {

                TextField(
                    "Spotify or YouTube Music URL",
                    text:
                        $urlText
                )
                .textInputAutocapitalization(
                    .never
                )
                .autocorrectionDisabled()
                .keyboardType(
                    .URL
                )


                if !urlText.isEmpty {

                    Button {

                        urlText =
                            ""

                    } label: {

                        Image(
                            systemName:
                                "xmark.circle.fill"
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                }


                Button {

                    paste()

                } label: {

                    Image(
                        systemName:
                            "doc.on.clipboard"
                    )
                }
                .buttonStyle(
                    .plain
                )
            }


            Button {

                resolve()

            } label: {

                HStack {

                    Spacer()


                    if isResolving {

                        ProgressView()
                            .controlSize(
                                .small
                            )


                        Text(
                            "Loading..."
                        )

                    } else {

                        Label(
                            "Fetch URL",
                            systemImage:
                                "arrow.down.circle"
                        )
                    }


                    Spacer()
                }
            }
            .disabled(
                urlText
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty
                ||
                isResolving
            )

        } header: {

            Text(
                "URL"
            )

        } footer: {

            Text(
                "Paste a Spotify or YouTube Music song or playlist link."
            )
        }

        .sheet(
            item:
                $resolved
        ) {
            content in


            FetchURLPreviewView(
                content:
                    content
            )
        }

        .alert(
            "Could Not Open URL",
            isPresented:
                Binding(
                    get: {

                        errorMessage !=
                            nil
                    },
                    set: {
                        newValue in


                        if !newValue {

                            errorMessage =
                                nil
                        }
                    }
                )
        ) {

            Button(
                "OK",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                "Unknown error."
            )
        }
    }


    // MARK: Resolve

    private func resolve() {

        guard !isResolving else {

            return
        }


        isResolving =
            true

        errorMessage =
            nil


        let input =
            urlText


        Task {

            do {

                let result =
                    try await
                    FetchURLResolver.shared
                        .resolve(
                            input
                        )


                resolved =
                    result


            } catch {

                errorMessage =
                    error.localizedDescription
            }


            isResolving =
                false
        }
    }


    // MARK: Paste

    private func paste() {

        guard let string =
            UIPasteboard.general
                .string
        else {

            return
        }


        urlText =
            string
    }
}


// MARK: - Navigation Bar URL Input

struct FetchURLInputSheet:
    View {

    @Environment(
        \.dismiss
    )
    private var dismiss


    @State private var urlText =
        ""

    @State private var isResolving =
        false

    @State private var resolved:
        FetchURLResolvedContent?

    @State private var errorMessage:
        String?


    var body: some View {

        NavigationStack {

            Form {

                Section {

                    HStack(
                        spacing:
                            8
                    ) {

                        TextField(
                            "Paste URL",
                            text:
                                $urlText
                        )
                        .textInputAutocapitalization(
                            .never
                        )
                        .autocorrectionDisabled()
                        .keyboardType(
                            .URL
                        )


                        Button {

                            paste()

                        } label: {

                            Image(
                                systemName:
                                    "doc.on.clipboard"
                            )
                        }
                    }


                    Button {

                        resolve()

                    } label: {

                        HStack {

                            Spacer()


                            if isResolving {

                                ProgressView()
                                    .controlSize(
                                        .small
                                    )


                                Text(
                                    "Loading..."
                                )

                            } else {

                                Label(
                                    "Fetch URL",
                                    systemImage:
                                        "arrow.down.circle"
                                )
                            }


                            Spacer()
                        }
                    }
                    .disabled(
                        urlText
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                        ||
                        isResolving
                    )

                } header: {

                    Text(
                        "URL"
                    )

                } footer: {

                    Text(
                        "Spotify and YouTube Music songs and playlists are supported."
                    )
                }
            }

            .navigationTitle(
                "Fetch URL"
            )

            .navigationBarTitleDisplayMode(
                .inline
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button(
                        "Done"
                    ) {

                        dismiss()
                    }
                }
            }
        }

        .sheet(
            item:
                $resolved
        ) {
            content in


            FetchURLPreviewView(
                content:
                    content
            )
        }

        .alert(
            "Could Not Open URL",
            isPresented:
                Binding(
                    get: {

                        errorMessage !=
                            nil
                    },
                    set: {
                        newValue in


                        if !newValue {

                            errorMessage =
                                nil
                        }
                    }
                )
        ) {

            Button(
                "OK",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                "Unknown error."
            )
        }
    }


    private func resolve() {

        guard !isResolving else {

            return
        }


        isResolving =
            true

        errorMessage =
            nil


        let input =
            urlText


        Task {

            do {

                resolved =
                    try await
                    FetchURLResolver.shared
                        .resolve(
                            input
                        )


            } catch {

                errorMessage =
                    error.localizedDescription
            }


            isResolving =
                false
        }
    }


    private func paste() {

        guard let string =
            UIPasteboard.general
                .string
        else {

            return
        }


        urlText =
            string
    }
}


// MARK: - Preview

struct FetchURLPreviewView:
    View {

    let content:
        FetchURLResolvedContent


    @Environment(
        \.dismiss
    )
    private var dismiss


    @State private var manager =
        FetchManager.shared


    @State private var isStarting =
        false


    @State private var showStarted =
        false


    @State private var errorMessage:
        String?


    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    spacing:
                        20
                ) {

                    artwork


                    VStack(
                        spacing:
                            5
                    ) {

                        Text(
                            content.title
                        )
                        .font(
                            .title2
                                .bold()
                        )
                        .multilineTextAlignment(
                            .center
                        )


                        Text(
                            subtitle
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .multilineTextAlignment(
                            .center
                        )


                        HStack(
                            spacing:
                                5
                        ) {

                            Image(
                                systemName:
                                    sourceIcon
                            )


                            Text(
                                content
                                    .sourceTitle
                            )
                        }
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .padding(
                            .top,
                            2
                        )
                    }


                    if content.isPlaylist {

                        playlistTracks
                    }


                    Button {

                        startDownload()

                    } label: {

                        HStack {

                            Spacer()


                            if isStarting {

                                ProgressView()
                                    .tint(
                                        .white
                                    )


                            } else {

                                Label(
                                    downloadButtonTitle,
                                    systemImage:
                                        "arrow.down.circle.fill"
                                )
                            }


                            Spacer()
                        }
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .controlSize(
                        .large
                    )
                    .disabled(
                        isStarting
                    )
                }
                .padding(
                    20
                )
            }

            .navigationTitle(
                content.isPlaylist
                ?
                "Playlist"
                :
                "Song"
            )

            .navigationBarTitleDisplayMode(
                .inline
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button(
                        "Done"
                    ) {

                        dismiss()
                    }
                }
            }
        }

        .alert(
            "Added to Fetch",
            isPresented:
                $showStarted
        ) {

            Button(
                "Done"
            ) {

                dismiss()
            }


            Button(
                "View Downloads"
            ) {

                dismiss()


                DispatchQueue.main
                    .async {

                        NotificationCenter
                            .default
                            .post(
                                name:
                                    .echoOpenFetchDownloads,
                                object:
                                    nil
                            )
                    }
            }

        } message: {

            if content.isPlaylist {

                Text(
                    "\(content.trackCount) songs were added to the download queue."
                )

            } else {

                Text(
                    "The song was added to the download queue."
                )
            }
        }

        .alert(
            "Download Failed",
            isPresented:
                Binding(
                    get: {

                        errorMessage !=
                            nil
                    },
                    set: {
                        value in


                        if !value {

                            errorMessage =
                                nil
                        }
                    }
                )
        ) {

            Button(
                "OK",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                errorMessage
                ??
                "Unknown error."
            )
        }
    }


    // MARK: - Artwork

    private var artwork:
        some View {

        AsyncImage(
            url:
                content.artworkURL
        ) {
            image in


            image
                .resizable()
                .scaledToFill()

        } placeholder: {

            RoundedRectangle(
                cornerRadius:
                    22
            )
            .fill(
                .secondary
                    .opacity(
                        0.12
                    )
            )
            .overlay {

                Image(
                    systemName:
                        content.isPlaylist
                        ?
                        "music.note.list"
                        :
                        "music.note"
                )
                .font(
                    .system(
                        size:
                            52
                    )
                )
                .foregroundStyle(
                    .secondary
                )
            }
        }
        .frame(
            width:
                230,
            height:
                230
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius:
                    22
            )
        )
    }


    // MARK: - Playlist Tracks

    @ViewBuilder
    private var playlistTracks:
        some View {

        VStack(
            alignment:
                .leading,
            spacing:
                0
        ) {

            HStack {

                Text(
                    "Songs"
                )
                .font(
                    .headline
                )


                Spacer()


                Text(
                    "\(content.trackCount)"
                )
                .foregroundStyle(
                    .secondary
                )
            }
            .padding(
                .bottom,
                10
            )


            ForEach(
                Array(
                    playlistRows
                        .prefix(
                            12
                        )
                )
            ) {
                row in


                HStack(
                    spacing:
                        10
                ) {

                    AsyncImage(
                        url:
                            row.artworkURL
                    ) {
                        image in


                        image
                            .resizable()
                            .scaledToFill()

                    } placeholder: {

                        RoundedRectangle(
                            cornerRadius:
                                6
                        )
                        .fill(
                            .secondary
                                .opacity(
                                    0.12
                                )
                        )
                    }
                    .frame(
                        width:
                            42,
                        height:
                            42
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:
                                6
                        )
                    )


                    VStack(
                        alignment:
                            .leading,
                        spacing:
                            2
                    ) {

                        Text(
                            row.title
                        )
                        .lineLimit(
                            1
                        )


                        Text(
                            row.artist
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(
                            1
                        )
                    }


                    Spacer()
                }
                .padding(
                    .vertical,
                    6
                )


                Divider()
            }


            if playlistRows.count >
                12 {

                Text(
                    "+ \(playlistRows.count - 12) more songs"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )
