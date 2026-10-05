import Foundation

/// Owns CPU and file work separately from observable UI state.
enum FetchTransferWork {
    static func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try await operation()
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func merge(parts: [URL], destination: URL, expectedBytes: Int64) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var written: Int64 = 0
        for part in parts {
            try Task.checkCancellation()
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            while let data = try input.read(upToCount: 512 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: data)
                written += Int64(data.count)
            }
        }
        guard written == expectedBytes else { throw FetchTransferError.incompleteDownload }
    }
}

enum FetchTransferError: LocalizedError {
    case incompleteDownload
    var errorDescription: String? { String(localized: "fetch_incomplete_download") }
}

struct FetchRetryBudget: Sendable {
    private(set) var used: Int
    init(used: Int = 0) { self.used = max(0, used) }
    mutating func consume(after error: Error? = nil) -> Bool {
        guard used == 0, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return false }
        used = 1
        return true
    }
}

struct FetchProgressGate: Sendable {
    private var lastTime: TimeInterval?
    private var lastValue = -1.0
    mutating func publish(_ value: Double, at time: TimeInterval) -> Bool {
        guard value != lastValue, value >= 1 || lastTime == nil || time - lastTime! >= 0.2 else { return false }
        lastTime = time
        lastValue = value
        return true
    }
}
