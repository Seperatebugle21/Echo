import SwiftUI
import UIKit
import YoutubeDL

struct YTDLPTestView: View {

    @State private var youtubeURL = ""

    @State private var status = "Klaar om te testen"
    @State private var details = ""

    @State private var isRunning = false
    @State private var success = false

    @AppStorage("ytdlpLastStage")
    private var lastStage = "Nog geen test uitgevoerd"

    private let ytdlp = YoutubeDL()

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 20
                ) {

                    Text("yt-dlp Test")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(
                        "Test stap voor stap of yt-dlp op deze iPhone werkt."
                    )
                    .foregroundStyle(.secondary)


                    // MARK: - Last stage

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        Text("Laatste stap")
                            .font(.headline)

                        Text(lastStage)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background(
                        Color.orange.opacity(0.12)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )


                    // MARK: - URL

                    TextField(
                        "https://youtube.com/watch?v=...",
                        text: $youtubeURL
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(
                        Color.secondary.opacity(0.10)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )


                    Button {

                        if let text =
                            UIPasteboard.general.string {

                            youtubeURL = text
                        }

                    } label: {

                        Label(
                            "Plak URL",
                            systemImage:
                                "doc.on.clipboard"
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                    }
                    .buttonStyle(.bordered)


                    // MARK: - Test 1

                    Button {

                        testModuleDownload()

                    } label: {

                        HStack {

                            Image(
                                systemName:
                                    "arrow.down.circle"
                            )

                            Text(
                                "1. Download yt-dlp module"
                            )
                        }
                        .frame(
                            maxWidth: .infinity
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(isRunning)


                    // MARK: - Test 2

                    Button {

                        testExtractInfo()

                    } label: {

                        HStack {

                            if isRunning {

                                ProgressView()

                            } else {

                                Image(
                                    systemName:
                                        "play.circle"
                                )
                            }

                            Text(
                                "2. Test YouTube URL"
                            )
                        }
                        .frame(
                            maxWidth: .infinity
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isRunning ||
                        youtubeURL
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    )


                    // MARK: - Status

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {

                        HStack {

                            Image(
                                systemName:
                                    success
                                    ? "checkmark.circle.fill"
                                    : "info.circle"
                            )

                            Text("Status")
                                .font(.headline)
                        }

                        Text(status)

                        if !details.isEmpty {

                            Divider()

                            Text(details)
                                .font(.caption)
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
                        success
                        ? Color.green.opacity(0.12)
                        : Color.secondary.opacity(0.10)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )


                    Button("Reset") {

                        lastStage =
                            "Nog geen test uitgevoerd"

                        status =
                            "Klaar om te testen"

                        details = ""

                        success = false
                    }
                    .foregroundStyle(.red)
                }
                .padding()
            }
            .navigationTitle("yt-dlp")
            .navigationBarTitleDisplayMode(
                .inline
            )
        }
    }


    // MARK: - Test 1
    //
    // Alleen het yt-dlp Python bestand downloaden.
    // Python wordt hier nog niet uitgevoerd.

    private func testModuleDownload() {

        isRunning = true
        success = false

        status =
            "yt-dlp module downloaden..."

        details = ""

        lastStage =
            "TEST 1 gestart"


        Task {

            do {

                try await YoutubeDL
                    .downloadPythonModule()


                await MainActor.run {

                    lastStage =
                        "TEST 1 OK"

                    status =
                        "yt-dlp module is gedownload."

                    details =
                        "De yt-dlp Python-module staat nu lokaal in de app."

                    success = true
                    isRunning = false
                }

            } catch {

                await MainActor.run {

                    lastStage =
                        "TEST 1 ERROR"

                    status =
                        "Download mislukt"

                    details =
                        String(
                            describing: error
                        )

                    success = false
                    isRunning = false
                }
            }
        }
    }


    // MARK: - Test 2
    //
    // Dit start embedded Python,
    // importeert yt_dlp
    // en analyseert de YouTube URL.

    private func testExtractInfo() {

        let string =
            youtubeURL
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard let url =
            URL(string: string) else {

            status =
                "Ongeldige URL"

            details = ""

            return
        }


        isRunning = true
        success = false

        status =
            "Python + yt-dlp starten..."

        details = ""

        lastStage =
            "TEST 2 gestart - Python initialiseren"


        Task {

            do {

                await MainActor.run {

                    lastStage =
                        "TEST 2 - extractInfo wordt uitgevoerd"

                    status =
                        "YouTube wordt geanalyseerd..."
                }


                let result =
                    try await ytdlp
                        .extractInfo(
                            url: url
                        )


                let formats =
                    result.0

                let info =
                    result.1


                let audioFormats =
                    formats.filter {

                        $0.isAudioOnly
                    }


                let bestAudio =
                    audioFormats.max {

                        ($0.abr ?? 0)
                        <
                        ($1.abr ?? 0)
                    }


                var resultText = ""

                resultText +=
                    "Titel: \(info.title)\n"


                if let uploader =
                    info.uploader {

                    resultText +=
                        "Uploader: \(uploader)\n"
                }


                if let duration =
                    info.duration {

                    let seconds =
                        Int(duration)

                    let minutes =
                        seconds / 60

                    let remaining =
                        seconds % 60

                    resultText +=
                        String(
                            format:
                                "Duur: %d:%02d\n",
                            minutes,
                            remaining
                        )
                }


                resultText +=
                    "Formats gevonden: \(formats.count)\n"

                resultText +=
                    "Audio-only formats: \(audioFormats.count)\n"


                if let bestAudio {

                    resultText +=
                        "\nBESTE AUDIO\n"

                    resultText +=
                        "Format ID: \(bestAudio.format_id)\n"

                    resultText +=
                        "Extensie: \(bestAudio.ext)\n"

                    resultText +=
                        "Codec: \(bestAudio.acodec ?? "onbekend")\n"

                    if let abr =
                        bestAudio.abr {

                        resultText +=
                            "Bitrate: \(Int(abr)) kbps\n"
                    }

                    resultText +=
                        "\nDirecte URL:\n\(bestAudio.url)"
                }


                await MainActor.run {

                    lastStage =
                        "TEST 2 OK"

                    status =
                        "yt-dlp werkt op deze iPhone."

                    details =
                        resultText

                    success = true
                    isRunning = false
                }


            } catch {

                await MainActor.run {

                    lastStage =
                        "TEST 2 ERROR"

                    status =
                        "yt-dlp fout"

                    details =
                        String(
                            describing:
                                error
                        )

                    success = false
                    isRunning = false
                }
            }
        }
    }
}
