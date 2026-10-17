import Foundation
import Observation
import Metal
#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLX
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
        installed = ["complete.json", "config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"].allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
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
        QwenAIProvider.shared.unload()
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
    static let shared = QwenAIProvider()
    let id = AIProviderID.qwen
    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private var loadedContainer: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?
    private var loadToken = UUID()
    #endif
    func prewarm() {
        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        guard loadedContainer == nil, loadingTask == nil, QwenModelStore.compatible,
              QwenModelStore.shared.installed else { return }
        let directory = QwenModelStore.shared.directory
        loadingTask = Task { try await LLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(directory: directory)) }
        #endif
    }
    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private func container(at directory: URL) async throws -> ModelContainer {
        if let loadedContainer { return loadedContainer }
        let token = loadToken
        let worker: Task<ModelContainer, Error>
        if let loadingTask { worker = loadingTask }
        else {
            worker = Task { try await LLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(directory: directory)) }
            loadingTask = worker
        }
        do {
            let container = try await worker.value
            guard token == loadToken else { throw CancellationError() }
            loadedContainer = container; loadingTask = nil
            try Task.checkCancellation()
            return container
        } catch {
            if token == loadToken { loadingTask = nil }
            throw error
        }
    }
    #endif
    func unload() {
        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        loadToken = UUID(); loadingTask?.cancel(); loadingTask = nil
        loadedContainer = nil; GPU.clearCache()
        #endif
    }
    func respond(messages: [AIMessage], instructions: String, tools: [[String: Any]],
                 update: @escaping @MainActor (String) -> Void,
                 execute: @escaping @MainActor (AIToolCall) async throws -> String) async throws -> AIReply {
        guard QwenModelStore.compatible, QwenModelStore.shared.installed else { throw AIError.localModel }
        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        let directory = QwenModelStore.shared.directory
        // Preserve actual system/user/assistant roles. A JSON transcript inside a
        // single user prompt made the small model answer the setup, not the user.
        let chat: [Chat.Message] = [.system("""
            You are Echo, a helpful assistant for music and everyday questions.
            Answer the latest user message directly in the user's language. Be concise and specific.
            Do not start with a generic greeting or a disclaimer about tools or data.
            You can discuss music and answer general questions. Only if asked to perform an app action,
            explain briefly that this local model cannot control Echo, and suggest the relevant Echo screen.
            Never claim to have changed playback or accessed data you were not given.
            Return only the answer, without reasoning, analysis, or think tags. /no_think
            """)] + messages.compactMap { message in
                switch message.role {
                case .user: return .user(message.text)
                case .assistant: return message.text.isEmpty ? nil : .assistant(AIResponseText.visible(message.text))
                case .tool: return nil
                }
            }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let worker = Task {
                do {
                    GPU.set(cacheLimit: 32 * 1024 * 1024)
                    defer { GPU.clearCache() }
                    // Directory loading never resolves a Hub model ID or downloads missing assets.
                    let container = try await self.container(at: directory)
                    try Task.checkCancellation()
                    let output = try await container.perform { context in
                        let input = try await context.processor.prepare(input: UserInput(chat: chat, additionalContext: ["enable_thinking": false]))
                        return try MLXLMCommon.generate(input: input, parameters: GenerateParameters(maxTokens: 512, maxKVSize: 4096), context: context) { (tokens: [Int]) in
                            if Task.isCancelled { return .stop }
                            if tokens.count == 1 || tokens.count % 4 == 0 { continuation.yield(context.tokenizer.decode(tokens: tokens)) }
                            return tokens.count >= 512 ? .stop : .more
                        }.output
                    }
                    continuation.yield(output)
                    try Task.checkCancellation()
                    continuation.finish()
                    // Keep model weights ready for the next turn; cancel/dismiss/background unload them.
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
