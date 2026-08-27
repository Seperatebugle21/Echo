import SwiftUI
import YoutubeDL
import UIKit

struct YTDLPTestView: View {

    @State private var youtubeURL = ""

    @State private var status = "Klaar om te testen"
    @State private var title = ""
    @State private var uploader = ""
    @State private var duration = ""
    @State private var ytdlpVersion = ""

    @State private var audioFormat = ""
    @State private var audioCodec = ""
    @State private var audioBitrate = ""
    @State private var directAudioURL = ""

    @State private var isLoading = false
    @State private var succeeded = false
    @State private var errorMessage = ""

    private let ytdlp = YoutubeDL()

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 20
                ) {

                    // MARK: - Header

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {

                        Text("yt-dlp Test")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text(
                            "Test of yt-dlp volledig lokaal in Echo kan draaien."
                        )
                        .foregroundStyle(.secondary)
                    }


                    // MARK: - URL

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {

                        Text("YouTube URL")
                            .font(.headline)

                        TextField(
                            "https://youtube.com/watch?v=...",
                            text: $youtubeURL
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(14)
                        .background(
                            Color.secondary.opacity(0.12)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12
                            )
                        )
                    }


                    // MARK: - Paste button

                    Button {

                        if let text = UIPasteboard
                            .general
                            .string {

                            youtubeURL = text
                        }

                    } label: {

                        Label(
                            "Plak URL",
                            systemImage: "doc.on.clipboard"
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                        .padding()
                    }
                    .buttonStyle(.bordered)


                    // MARK: - Test button

                    Button {

                        runTest()

                    } label: {

                        HStack {

                            if isLoading {

                                ProgressView()
                                    .tint(.white)

                            } else {

                                Image(
                                    systemName:
                                        "play.fill"
                                )
                            }

                            Text(
                                isLoading
                                    ? "yt-dlp bezig..."
                                    : "Test yt-dlp"
                            )
                        }
                        .frame(
                            maxWidth: .infinity
                        )
                        .padding()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(
                        isLoading ||
                        youtubeURL
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )


                    // MARK: - Status

                    statusCard


                    // MARK: - Result

                    if succeeded {

                        resultCard
                    }


                    // MARK: - Error

                    if !errorMessage.isEmpty {

                        errorCard
                    }
                }
                .padding()
            }
            .navigationTitle("yt-dlp")
            .navigationBarTitleDisplayMode(
                .inline
            )
        }
    }


    // MARK: - Status card

    private var statusCard: some View {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            HStack {

                Image(
                    systemName:
                        succeeded
                        ? "checkmark.circle.fill"
                        : isLoading
                        ? "arrow.triangle.2.circlepath"
                        : "circle"
                )

                Text("Status")
                    .font(.headline)
            }

            Text(status)
                .font(.body)

            if !ytdlpVersion.isEmpty {

                Divider()

                HStack {

                    Text("yt-dlp")

                    Spacer()

                    Text(ytdlpVersion)
                        .foregroundStyle(
                            .secondary
                        )
                }
            }
        }
        .padding()
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.secondary.opacity(0.1)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16
            )
        )
    }


    // MARK: - Result card

    private var resultCard: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Label(
                "yt-dlp werkt",
                systemImage:
                    "checkmark.circle.fill"
            )
            .font(.title3)
            .fontWeight(.semibold)


            Divider()


            resultRow(
                title: "Titel",
                value: title
            )


            if !uploader.isEmpty {

                resultRow(
                    title: "Uploader",
                    value: uploader
                )
            }


            if !duration.isEmpty {

                resultRow(
                    title: "Duur",
                    value: duration
                )
            }


            Divider()


            Text("Geselecteerde audio")
                .font(.headline)


            resultRow(
                title: "Format",
                value: audioFormat
            )


            resultRow(
                title: "Codec",
                value: audioCodec
            )


            resultRow(
                title: "Bitrate",
                value: audioBitrate
            )


            if !directAudioURL.isEmpty {

                Divider()

                Text("Directe audio URL")
                    .font(.headline)

                Text(directAudioURL)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .textSelection(
                        .enabled
                    )
            }
        }
        .padding()
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.green.opacity(0.12)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16
            )
        )
    }


    // MARK: - Error card

    private var errorCard: some View {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            Label(
                "Fout",
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .font(.headline)


            Text(errorMessage)
                .font(.caption)
                .textSelection(.enabled)
        }
        .padding()
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.red.opacity(0.12)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16
            )
        )
    }


    // MARK: - Result row

    private func resultRow(
        title: String,
        value: String
    ) -> some View {

        HStack(
            alignment: .top
        ) {

            Text(title)
                .foregroundStyle(
                    .secondary
                )

            Spacer()

            Text(value)
                .multilineTextAlignment(
                    .trailing
                )
                .textSelection(.enabled)
        }
    }


    // MARK: - Run yt-dlp

    private func runTest() {

        let string = youtubeURL
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )


        guard let url = URL(
            string: string
        ) else {

            errorMessage =
                "De URL is ongeldig."

            return
        }


        isLoading = true
        succeeded = false

        errorMessage = ""

        title = ""
        uploader = ""
        duration = ""

        audioFormat = ""
        audioCodec = ""
        audioBitrate = ""
        directAudioURL = ""

        status =
            "Python en yt-dlp worden gestart..."


        Task {

            do {

                await MainActor.run {

                    status =
                        "Video wordt geanalyseerd..."
                }


                let (
                    formats,
                    info
                ) = try await ytdlp
                    .extractInfo(
                        url: url
                    )


                await MainActor.run {

                    status =
                        "Audioformaten zoeken..."
                }


                // Alleen echte audio-only streams.
                let audioFormats =
                    formats.filter {

                        $0.vcodec == "none" &&
                        $0.acodec != "none"

                    }


                // Kies hoogste audio bitrate.
                let bestAudio =
                    audioFormats.max {

                        let bitrate1 =
                            $0.abr ?? 0

                        let bitrate2 =
                            $1.abr ?? 0

                        return bitrate1
                            < bitrate2
                    }


                guard let bestAudio else {

                    throw YTDLPTestError
                        .noAudioFormat
                }


                let durationText:
                    String

                if let seconds =
                    info.duration {

                    let total =
                        Int(seconds)

                    let minutes =
                        total / 60

                    let remaining =
                        total % 60

                    durationText =
                        String(
                            format:
                                "%d:%02d",
                            minutes,
                            remaining
                        )

                } else {

                    durationText = ""
                }


                let bitrateText:
                    String

                if let bitrate =
                    bestAudio.abr {

                    bitrateText =
                        "\(Int(bitrate)) kbps"

                } else {

                    bitrateText =
                        "Onbekend"
                }


                await MainActor.run {

                    title =
                        info.title

                    uploader =
                        info.uploader
                        ?? info.channel
                        ?? ""

                    duration =
                        durationText

                    ytdlpVersion =
                        ytdlp.version
                        ?? "onbekend"

                    audioFormat =
                        "\(bestAudio.format_id) • \(bestAudio.ext)"

                    audioCodec =
                        bestAudio.acodec
                        ?? "onbekend"

                    audioBitrate =
                        bitrateText

                    directAudioURL =
                        bestAudio.url

                    status =
                        "Succes — yt-dlp draait op deze iPhone."

                    succeeded = true

                    isLoading = false
                }


            } catch {

                await MainActor.run {

                    status =
                        "Test mislukt"

                    succeeded = false

                    isLoading = false

                    errorMessage =
                        String(
                            describing:
                                error
                        )
                }
            }
        }
    }
}


// MARK: - Errors

private enum YTDLPTestError:
    LocalizedError {

    case noAudioFormat

    var errorDescription:
        String? {

        switch self {

        case .noAudioFormat:

            return """
            yt-dlp heeft de video gevonden, \
            maar er werd geen bruikbaar \
            audio-only formaat gevonden.
            """
        }
    }
}
