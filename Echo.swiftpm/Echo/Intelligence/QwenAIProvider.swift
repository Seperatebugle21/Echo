import Foundation
import Observation
import Metal
#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

@MainActor @Observable final class QwenModelStore {
    static let shared = QwenModelStore()
    static let modelID = "mlx-community/Qwen3-0.6B-4bit"
    static var compatible: Bool {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && !targetEnvironment(simulator)
        return MTLCreateSystemDefaultDevice() != nil && ProcessInfo.processInfo.physicalMemory >= 4_000_000_000
        #else
        return false
        #endif
    }
    private(set) var progress: Double = 0
    private(set) var downloading = false
    private(set) var installed = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    let directory: URL
    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Intelligence/Qwen3-0.6B-4bit")
        installed = FileManager.default.fileExists(atPath: directory.appendingPathComponent("complete.json").path)
    }
    var storageBytes: Int64 {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        } ?? 0
    }
    func download() {
        guard !downloading, Self.compatible else { error = AIError.localModel.localizedDescription; return }
        downloading = true; progress = 0; error = nil
        task = Task {
            defer { downloading = false; task = nil }
            let staging = directory.appendingPathExtension("download")
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                var excluded = staging; var values = URLResourceValues(); values.isExcludedFromBackup = true
                try excluded.setResourceValues(values)
                let capacity = try staging.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                guard capacity >= 1_500_000_000 else { throw AIError.storage }
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(from: URL(string: "https://huggingface.co/api/models/" + Self.modelID)!)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let revision = metadata["sha"] as? String, revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw AIError.response }
                // Fixed filenames and one immutable revision; no model code or remote scripts are executed.
                let files = ["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"]
                for (index, file) in files.enumerated() {
                    try Task.checkCancellation()
                    let url = URL(string: "https://huggingface.co/" + Self.modelID + "/resolve/" + revision + "/" + file)!
                    let observer = QwenDownloadProgress { fraction in
                        Task { @MainActor [weak self] in self?.progress = (Double(index) + fraction) / Double(files.count) }
                    }
                    let (temporary, response) = try await session.download(from: url, delegate: observer)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError.response }
                    let destination = staging.appendingPathComponent(file)
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    progress = Double(index + 1) / Double(files.count)
                }
                // A completed download is not advertised as loaded. Loading/inference still report real runtime errors.
                try JSONSerialization.data(withJSONObject: ["model": Self.modelID, "revision": revision]).write(to: staging.appendingPathComponent("complete.json"), options: .atomic)
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
                try FileManager.default.moveItem(at: staging, to: directory)
                installed = true
            } catch is CancellationError { try? FileManager.default.removeItem(at: staging) }
            catch { self.error = error.localizedDescription; try? FileManager.default.removeItem(at: staging) }
        }
    }
    func cancel() { task?.cancel() }
    func delete() throws {
        guard !downloading else { throw AIError.permission }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        installed = false; progress = 0
    }
}
private final class QwenDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    init(update: @escaping @Sendable (Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { update(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
}
@MainActor final class QwenAIProvider: AIProvider {
    let id = AIProviderID.qwen
    func respond(messages: [AIMessage], instructions: String, tools: [[String: Any]],
                 update: @escaping @MainActor (String) -> Void,
                 execute: @escaping @MainActor (AIToolCall) async throws -> String) async throws -> AIReply {
        guard QwenModelStore.compatible, QwenModelStore.shared.installed else { throw AIError.localModel }
        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        let directory = QwenModelStore.shared.directory
        let transcript = String(data: try JSONEncoder().encode(messages), encoding: .utf8) ?? ""
        // This small model is deliberately chat-only; no unvalidated text-to-action parser.
        let prompt = instructions + "\nYou have no app tools in this local model. Do not claim to perform actions.\nConversation data:\n" + transcript + "\n/no_think"
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let worker = Task {
                do {
                    // Directory loading never resolves a Hub model ID or downloads missing assets.
                    let container = try await LLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(directory: directory))
                    try Task.checkCancellation()
                    let output = try await container.perform { context in
                        let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
                        return try MLXLMCommon.generate(input: input, parameters: GenerateParameters(maxTokens: 1024, maxKVSize: 4096), context: context) { (tokens: [Int]) in
                            if Task.isCancelled { return .stop }
                            if tokens.count % 4 == 0 { continuation.yield(context.tokenizer.decode(tokens: tokens)) }
                            return tokens.count >= 1024 ? .stop : .more
                        }.output
                    }
                    continuation.yield(output)
                    try Task.checkCancellation()
                    continuation.finish()
                    // Container is request-owned and released here; closing Intelligence cancels the worker.
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
        var text = ""
        for try await snapshot in stream { try Task.checkCancellation(); text = snapshot; update(snapshot) }
        guard !text.isEmpty else { throw AIError.response }
        return AIReply(text: text)
        #else
        throw AIError.localModel
        #endif
    }
}