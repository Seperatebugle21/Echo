import Foundation
import PythonKit
import YoutubeDL


/// Smoke test for the embedded Python runtime, used by CI in the simulator.
///
/// Launch the app with `-EchoPythonSelfTest`. It starts Python, imports the
/// standard library modules yt-dlp relies on, downloads/imports yt-dlp and
/// writes the outcome to `Documents/python-self-test.json`.
/// Without the launch argument nothing happens.
enum PythonSelfTest {

    static let launchArgument =
        "-EchoPythonSelfTest"


    static let reportFileName =
        "python-self-test.json"


    static func runIfRequested() {

        guard ProcessInfo.processInfo
            .arguments
            .contains(launchArgument)
        else {
            return
        }


        Task.detached(
            priority: .userInitiated
        ) {

            await run()
        }
    }


    static func run() async {

        var report: [String: String] = [
            "status": "running"
        ]

        write(report)


        var failures: [String] = []


        // 1. Interpreter and standard library

        do {

            let python =
                try await PythonRuntime.run {

                    () throws -> [String: String] in

                    var result: [String: String] = [:]

                    let sys =
                        Python.import("sys")

                    result["python"] =
                        String(sys.version)
                        ?? "?"

                    result["platform"] =
                        String(sys.platform)
                        ?? "?"


                    let modules = [
                        "ssl", "hashlib", "sqlite3", "zlib", "bz2",
                        "lzma", "ctypes", "json", "_decimal",
                        "xml.etree.ElementTree", "http.cookiejar",
                        "asyncio", "uuid", "socket", "select",
                    ]

                    for name in modules {

                        do {
                            _ = try Python.attemptImport(name)
                            result["module.\(name)"] = "ok"
                        } catch {
                            result["module.\(name)"] = "FAILED: \(error)"
                        }
                    }


                    result["openssl"] =
                        String(
                            Python.import("ssl")
                                .OPENSSL_VERSION
                        )
                        ?? "?"

                    return result
                }


            report.merge(python) { $1 }

            failures += python
                .filter { $0.value.hasPrefix("FAILED") }
                .map(\.key)


            if !(python["python"] ?? "")
                .hasPrefix(PythonRuntime.pythonVersion) {

                failures.append("python-version")
            }

        } catch {

            report["python"] = "FAILED: \(error)"
            failures.append("python")
        }

        write(report)


        // 2. yt-dlp download + import

        do {

            try await YoutubeDL.ensurePythonModule()

            let version =
                try await YTDLPRunner.shared
                    .installedVersion()

            report["yt_dlp"] =
                version ?? "FAILED: missing"

            if version == nil {
                failures.append("yt_dlp")
            }

        } catch {

            report["yt_dlp"] = "FAILED: \(error)"
            failures.append("yt_dlp")
        }

        write(report)


        // 3. A real search. Informational only: YouTube may block CI
        //    machines, so this does not decide the outcome.

        do {

            let result =
                try await YTDLPRunner.shared
                    .search(
                        title: "Never Gonna Give You Up",
                        artist: "Rick Astley"
                    )

            report["search"] =
                "ok: \(result.title)"

        } catch {

            report["search"] =
                "error (informational): \(error)"
        }


        report["failures"] =
            failures.joined(separator: ",")

        report["status"] =
            failures.isEmpty ? "passed" : "failed"

        write(report)
    }


    private static func write(
        _ report: [String: String]
    ) {

        guard let documents =
            FileManager.default
                .urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )
                .first,
            let data =
                try? JSONSerialization
                    .data(
                        withJSONObject: report,
                        options: [.prettyPrinted, .sortedKeys]
                    )
        else {
            return
        }


        try? data.write(
            to: documents
                .appendingPathComponent(reportFileName),
            options: .atomic
        )


        print("PythonSelfTest:", report)
    }
}
