import Foundation
import YoutubeDL

// MARK: - Fixed serial executor
//
// PythonKit / CPython must stay on one serial execution context.
// A normal Task or actor is not sufficient on iOS.

final class YTDLPSerialExecutor: SerialExecutor, @unchecked Sendable {

    static let shared = YTDLPSerialExecutor()

    private let queue = DispatchQueue(
        label: "com.echomusic.ytdlp.python",
        qos: .utility
    )

    private init() {}

    func enqueue(_ job: UnownedJob) {

        let executor = asUnownedSerialExecutor()

        queue.async {

            job.runSynchronously(
                on: executor
            )
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {

        UnownedSerialExecutor(
            ordinary: self
        )
    }
}


// MARK: - Python actor

actor YTDLPRunner {

    static let shared = YTDLPRunner()

    // Force every actor operation onto our fixed serial executor.
    nonisolated var unownedExecutor: UnownedSerialExecutor {

        YTDLPSerialExecutor.shared
            .asUnownedSerialExecutor()
    }


    // Important:
    // create YoutubeDL ON the Python actor,
    // not from SwiftUI / MainActor.

    private var engine: YoutubeDL?


    private init() {}


    // MARK: Result

    struct Result: Sendable {

        let title: String

        let uploader: String?

        let duration: Double?

        let formatCount: Int

        let audioFormatCount: Int

        let formatID: String?

        let fileExtension: String?

        let audioCodec: String?

        let bitrate: Double?

        let directURL: String?
    }


    // MARK: Prepare

    func prepare() async throws {

        if engine != nil {
            return
        }

        // The Python files can already have been downloaded
        // by test 1. Creating the object happens here,
        // on the Python executor.

        engine = YoutubeDL()
    }


    // MARK: Extract

    func extract(
    url: URL
) async throws -> Result {

    if engine == nil {
        try await prepare()
    }

    guard engine != nil else {
        throw RunnerError.engineUnavailable
    }

    throw RunnerError.extractInfoDisabled
}


  enum RunnerError: LocalizedError {

    case engineUnavailable
    case extractInfoDisabled

    var errorDescription: String? {

        switch self {

        case .engineUnavailable:
            return "YoutubeDL engine kon niet worden aangemaakt."

        case .extractInfoDisabled:
            return """
            Python werkt, maar extractInfo() is tijdelijk uitgeschakeld \
            omdat deze functie op iOS een native crash veroorzaakt.
            """
        }
    }
}
}
