import Foundation

struct RoutedTranscription: Equatable, Sendable {
    let text: String
    let cost: Double?
}

enum TranscriptionRouterError: Error, Equatable {
    case noStreamingJob
    case deepgramDoesNotAcceptFiles
}

extension TranscriptionRouterError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noStreamingJob: "The live transcription session ended before final text arrived."
        case .deepgramDoesNotAcceptFiles: "Deepgram is available only for live microphone dictation."
        }
    }
}

actor TranscriptionRouter {
    private let localModels: LocalModelManager
    private let localEngine: LocalWhisperEngine
    private let deepgram: DeepgramEngine
    private let openRouter: OpenRouterSTTEngine
    private let keychain: KeychainStore
    private var deepgramTask: Task<String, Error>?

    init(
        localModels: LocalModelManager = LocalModelManager(),
        localEngine: LocalWhisperEngine = LocalWhisperEngine(),
        deepgram: DeepgramEngine = DeepgramEngine(),
        openRouter: OpenRouterSTTEngine = OpenRouterSTTEngine(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.localModels = localModels
        self.localEngine = localEngine
        self.deepgram = deepgram
        self.openRouter = openRouter
        self.keychain = keychain
    }

    func beginStreamingIfNeeded(engine: TranscriptionEngine, frames: AsyncStream<Data>) throws {
        guard engine == .deepgram else { return }
        guard let credential = try keychain.load(account: "deepgram"), !credential.isEmpty else {
            throw ProviderError.missingCredential
        }
        deepgramTask?.cancel()
        deepgramTask = Task { [deepgram] in
            try await deepgram.transcribe(frames: frames, credential: credential)
        }
    }

    func finish(
        recording: AudioRecording,
        engine: TranscriptionEngine,
        localModelID: String,
        openRouterModel: String
    ) async throws -> RoutedTranscription {
        switch engine {
        case .localWhisper:
            let installed = try await localModels.installedModel(id: localModelID)
            try await localEngine.load(installed)
            return RoutedTranscription(text: try await localEngine.transcribe(recording.url), cost: nil)
        case .deepgram:
            guard let task = deepgramTask else { throw TranscriptionRouterError.noStreamingJob }
            deepgramTask = nil
            return RoutedTranscription(text: try await task.value, cost: nil)
        case .openRouter:
            guard let credential = try keychain.load(account: "openrouter"), !credential.isEmpty else {
                throw ProviderError.missingCredential
            }
            let audio = try Data(contentsOf: recording.url, options: .mappedIfSafe)
            let result = try await openRouter.transcribe(
                audio: audio,
                format: recording.format,
                model: openRouterModel,
                credential: credential
            )
            return RoutedTranscription(text: result.text, cost: result.cost)
        }
    }

    func transcribeFile(
        _ input: FileTranscriptionInput,
        engine: TranscriptionEngine,
        localModelID: String,
        openRouterModel: String
    ) async throws -> RoutedTranscription {
        switch engine {
        case .deepgram:
            throw TranscriptionRouterError.deepgramDoesNotAcceptFiles
        case .localWhisper:
            let installed = try await localModels.installedModel(id: localModelID)
            try await localEngine.load(installed)
            return RoutedTranscription(text: try await localEngine.transcribe(input.url), cost: nil)
        case .openRouter:
            guard let credential = try keychain.load(account: "openrouter"), !credential.isEmpty else {
                throw ProviderError.missingCredential
            }
            let result = try await openRouter.transcribe(
                audio: try Data(contentsOf: input.url, options: .mappedIfSafe),
                format: input.format,
                model: openRouterModel,
                credential: credential
            )
            return RoutedTranscription(text: result.text, cost: result.cost)
        }
    }

    func cancel() async {
        deepgramTask?.cancel()
        deepgramTask = nil
        await deepgram.cancel()
    }

    func unloadLocalModel() async {
        await localEngine.unload()
    }
}
