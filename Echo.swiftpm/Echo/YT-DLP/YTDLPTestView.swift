import SwiftUI
import UIKit
import YoutubeDL

struct YTDLPTestView: View {

    @State private var youtubeURL = ""

    @State private var status =
        "Klaar om te testen"

    @State private var details = ""

    @State private var isRunning = false

    @State private var success = false


    @AppStorage("ytdlpLastStage")
    private var lastStage =
        "Nog geen test uitgevoerd"


    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 20
                ) {

                    // MARK: Title

                    Text("yt-dlp Test")
                        .font(.largeTitle)
                        .fontWeight(.bold)


                    Text(
                        "Test de ingebouwde yt-dlp engine op deze iPhone."
                    )
                    .foregroundStyle(.secondary)


                    // MARK: Last stage

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        Text("Laatste stap")
                            .font(.headline)

                        Text(lastStage)
                            .font(.caption)
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


                    // MARK: URL

                    TextField(
                        "https://youtube.com/watch?v=...",
                        text: $youtubeURL
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(
                        .never
                    )
                    .autocorrectionDisabled()
                    .padding()
                    .background(
                        Color.secondary.opacity(0.1)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )


                    Button {

                        if let string =
                            UIPasteboard
                                .general
                                .string {

                            youtubeURL =
                                string
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


                    // MARK: Test 1

                    Button {

                        downloadModule()

                    } label: {

                        Label(
                            "1. Download yt-dlp module",
                            systemImage:
                                "arrow.down.circle"
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(isRunning)


                    // MARK: Test 2

                    Button {

                        testPythonEngine()

                    } label: {

                        Label(
                            "2. Start Python engine",
                            systemImage:
                                "terminal"
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)


                    // MARK: Test 3

                    Button {

                        extractURL()

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
                                "3. Analyseer YouTube URL"
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


                    // MARK: Result

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
                        ? Color.green.opacity(
                            0.12
                        )
                        : Color.secondary.opacity(
                            0.1
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )


                    Button("Reset diagnose") {

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

    private func downloadModule() {

        isRunning = true
        success = false

        status =
            "yt-dlp module downloaden..."

        details = ""

        lastStage =
            "TEST 1 - module download gestart"


        Task {

            do {

                try await YoutubeDL
                    .downloadPythonModule()


                await MainActor.run {

                    lastStage =
                        "TEST 1 OK"

                    status =
                        "yt-dlp module beschikbaar"

                    details =
                        "De Python-module is succesvol gedownload."

                    success = true

                    isRunning = false
                }


            } catch {

                showError(
                    stage: "TEST 1 ERROR",
                    error: error
                )
            }
        }
    }


    // MARK: - Test 2

    private func testPythonEngine() {

        isRunning = true
        success = false

        status =
            "Python executor starten..."

        details = ""

        lastStage =
            "TEST 2 - serial executor aangeroepen"


        Task {

            do {

                try await
                    YTDLPRunner
                    .shared
                    .prepare()


                await MainActor.run {

                    lastStage =
                        "TEST 2 OK"

                    status =
                        "Python runner klaar"

                    details =
                        """
                        YoutubeDL engine is aangemaakt \
                        op de vaste Python serial executor.
                        """

                    success = true

                    isRunning = false
                }


            } catch {

                showError(
                    stage: "TEST 2 ERROR",
                    error: error
                )
            }
        }
    }


    // MARK: - Test 3

    private func extractURL() {

        let value =
            youtubeURL
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard let url =
            URL(string: value) else {

            status =
                "Ongeldige URL"

            return
        }


        isRunning = true
        success = false

        details = ""

        status =
            "yt-dlp analyseert YouTube..."

        lastStage =
            "TEST 3 - extract gestart"


        Task {

            do {

                let result =
                    try await
                    YTDLPRunner
                    .shared
                    .extract(
                        url: url
                    )


                var text = ""

                text +=
                    "Titel: \(result.title)\n"


                if let uploader =
                    result.uploader {

                    text +=
                        "Uploader: \(uploader)\n"
                }


                if let duration =
                    result.duration {

                    let total =
                        Int(duration)

                    text +=
                        String(
                            format:
                                "Duur: %d:%02d\n",
                            total / 60,
                            total % 60
                        )
                }


                text +=
                    "Formats: \(result.formatCount)\n"

                text +=
                    "Audio-only: \(result.audioFormatCount)\n"


                if let formatID =
                    result.formatID {

                    text +=
                        "\nBESTE AUDIO\n"

                    text +=
                        "Format ID: \(formatID)\n"
                }


                if let ext =
                    result.fileExtension {

                    text +=
                        "Extensie: \(ext)\n"
                }


                if let codec =
                    result.audioCodec {

                    text +=
                        "Codec: \(codec)\n"
                }


                if let bitrate =
                    result.bitrate {

                    text +=
                        "Bitrate: \(Int(bitrate)) kbps\n"
                }


                if let directURL =
                    result.directURL {

                    text +=
                        "\nDirect audio URL:\n"

                    text +=
                        directURL
                }


                await MainActor.run {

                    lastStage =
                        "TEST 3 OK"

                    status =
                        "yt-dlp werkt"

                    details =
                        text

                    success = true

                    isRunning = false
                }


            } catch {

                showError(
                    stage:
                        "TEST 3 ERROR",
                    error:
                        error
                )
            }
        }
    }


    // MARK: - Error

    private func showError(
        stage: String,
        error: Error
    ) {

        Task {

            await MainActor.run {

                lastStage = stage

                status =
                    "Test mislukt"

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
