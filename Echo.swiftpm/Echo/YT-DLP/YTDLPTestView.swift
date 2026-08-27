import SwiftUI
import UIKit
import YoutubeDL

struct YTDLPTestView: View {

    @State private var youtubeURL = ""

    @State private var status = "Klaar"
    @State private var details = ""

    @State private var isRunning = false

    @AppStorage("ytdlpLastStage")
    private var lastStage = "Nog geen test uitgevoerd"

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 20
                ) {

                    Text("yt-dlp Diagnose")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(
                        "Deze test controleert stap voor stap waar yt-dlp op de iPhone stopt."
                    )
                    .foregroundStyle(.secondary)


                    // MARK: Last stage

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        Text("Laatste opgeslagen stap")
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


                    // MARK: URL

                    TextField(
                        "https://youtube.com/watch?v=...",
                        text: $youtubeURL
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
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


                    // MARK: Module download test

                    Button {

                        testModuleDownload()

                    } label: {

                        Label(
                            "1. Test yt-dlp bestanden",
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


                    // MARK: Python test

                    Button {

                        testPython()

                    } label: {

                        Label(
                            "2. Start Python + yt-dlp",
                            systemImage:
                                "terminal"
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)


                    // MARK: URL test

                    Button {

                        testURL()

                    } label: {

                        Label(
                            "3. Analyseer YouTube URL",
                            systemImage:
                                "play.circle"
                        )
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


                    if isRunning {

                        HStack {

                            ProgressView()

                            Text(status)
                        }
                    }


                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        Text("Resultaat")
                            .font(.headline)

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
                        Color.secondary.opacity(
                            0.1
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )


                    Button(
                        "Reset diagnose"
                    ) {

                        lastStage =
                            "Nog geen test uitgevoerd"

                        status = "Klaar"
                        details = ""
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
    // Alleen yt-dlp Python-module downloaden.
    // Python wordt hier nog NIET uitgevoerd.

    private func testModuleDownload() {

        isRunning = true

        status =
            "yt-dlp bestanden downloaden..."

        details = ""

        lastStage =
            "TEST 1 GESTART - module downloaden"


        Task {

            do {

                try await YoutubeDL
                    .downloadPythonModule()


                await MainActor.run {

                    lastStage =
                        "TEST 1 OK - yt-dlp module gedownload"

                    status =
                        "Test 1 geslaagd"

                    details =
                        """
                        De yt-dlp Python-bestanden kunnen \
                        worden gedownload en opgeslagen.
                        """

                    isRunning = false
                }

            } catch {

                await MainActor.run {

                    lastStage =
                        "TEST 1 ERROR"

                    status =
                        "Test 1 mislukt"

                    details =
                        String(
                            describing: error
                        )

                    isRunning = false
                }
            }
        }
    }


    // MARK: - Test 2
    //
    // Dit is de belangrijke test:
    // embedded Python initialiseren +
    // yt_dlp module importeren.

    private func testPython() {

        isRunning = true

        status =
            "Embedded Python starten..."

        details = ""

        lastStage =
            "TEST 2 GESTART - Python initialiseren"


        Task {

            do {

                lastStage =
                    "TEST 2 - YtDlp initializer wordt aangeroepen"

                let engine =
                    try await YoutubeDL.YtDlp()


                await MainActor.run {

                    _ = engine

                    lastStage =
                        "TEST 2 OK - Python + yt-dlp geladen"

                    status =
                        "Python werkt"

                    details =
                        """
                        Embedded Python is gestart en \
                        de yt_dlp Python-module kon \
                        worden geladen.
                        """

                    isRunning = false
                }

            } catch {

                await MainActor.run {

                    lastStage =
                        "TEST 2 ERROR"

                    status =
                        "Python test mislukt"

                    details =
                        String(
                            describing: error
                        )

                    isRunning = false
                }
            }
        }
    }


    // MARK: - Test 3
    //
    // Gebruik dezelfde globale yt_dlp(argv:)
    // route als het voorbeeldproject van de maker.

    private func testURL() {

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

            return
        }


        isRunning = true

        status =
            "YouTube URL analyseren..."

        details = ""

        lastStage =
            "TEST 3 GESTART - yt-dlp command"


        Task {

            do {

                var logLines: [String] = []


                lastStage =
                    "TEST 3 - yt_dlp() wordt uitgevoerd"


                try await yt_dlp(

                    argv: [

                        "--skip-download",

                        "--no-playlist",

                        "--no-check-certificates",

                        "--verbose",

                        url.absoluteString
                    ],

                    progress: nil,

                    log: { level, message in

                        let line =
                            "[\(level)] \(message)"

                        logLines.append(
                            line
                        )

                    },

                    makeTranscodeProgressBlock:
                        nil
                )


                await MainActor.run {

                    lastStage =
                        "TEST 3 OK - YouTube verwerkt"

                    status =
                        "yt-dlp werkt"

                    details =
                        logLines
                            .suffix(40)
                            .joined(
                                separator: "\n"
                            )

                    isRunning = false
                }


            } catch {

                await MainActor.run {

                    lastStage =
                        "TEST 3 ERROR"

                    status =
                        "YouTube test mislukt"

                    let logs =
                        logLines
                            .suffix(40)
                            .joined(
                                separator: "\n"
                            )

                    details =
                        """
                        \(String(describing: error))

                        ---- LOG ----
                        \(logs)
                        """

                    isRunning = false
                }
            }
        }
    }
}
