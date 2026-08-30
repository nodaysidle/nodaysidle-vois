import Foundation
import WhisperKit

enum LocalModelError: Error, Equatable {
    case alreadyInstalled
    case notInstalled
    case invalidModelDirectory
    case downloadEscapedStagingDirectory
    case invalidManifest
    case emptyTranscript
}

extension LocalModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .alreadyInstalled: "This model is already installed."
        case .notInstalled: "This model is not installed."
        case .invalidModelDirectory: "The downloaded model did not pass validation."
        case .downloadEscapedStagingDirectory: "The model downloader returned an unsafe path."
        case .invalidManifest: "The installed model manifest is invalid."
        case .emptyTranscript: "No speech was detected."
        }
    }
}

actor LocalWhisperEngine {
    private let inactivity: Duration
    private var pipeline: WhisperKit?
    private var activeModel: InstalledLocalModel?
    private var unloadTask: Task<Void, Never>?

    init(inactivity: Duration = .seconds(300)) {
        self.inactivity = inactivity
    }

    var activeModelID: String? { activeModel?.modelID }

    func load(_ model: InstalledLocalModel) async throws {
        guard FileManager.default.fileExists(atPath: model.folderURL.path),
              model.source == "argmaxinc/whisperkit-coreml" else {
            throw LocalModelError.invalidManifest
        }
        if activeModel?.modelID == model.modelID, pipeline != nil {
            scheduleUnload()
            return
        }
        unloadTask?.cancel()
        if let pipeline { await pipeline.unloadModels() }
        pipeline = nil
        activeModel = nil

        let config = WhisperKitConfig(
            downloadBase: model.baseURL,
            modelFolder: model.folderURL.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        pipeline = try await WhisperKit(config)
        activeModel = model
        scheduleUnload()
    }

    func transcribe(_ audioURL: URL) async throws -> String {
        guard let pipeline else { throw LocalModelError.notInstalled }
        unloadTask?.cancel()
        let results = try await pipeline.transcribe(
            audioPath: audioURL.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental)
        )
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleUnload()
        guard !text.isEmpty else { throw LocalModelError.emptyTranscript }
        return text
    }

    func unload() async {
        unloadTask?.cancel()
        unloadTask = nil
        if let pipeline { await pipeline.unloadModels() }
        pipeline = nil
        activeModel = nil
    }

    func handleMemoryPressure() async {
        await unload()
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        let inactivity = inactivity
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: inactivity)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }
}

struct InstalledLocalModel: Codable, Equatable, Sendable {
    let modelID: String
    let variant: String
    let source: String
    let baseURL: URL
    let folderRelativePath: String

    var folderURL: URL { baseURL.appending(path: folderRelativePath, directoryHint: .isDirectory) }
}

actor LocalModelManager {
    typealias ProgressHandler = @Sendable (Double) -> Void
    typealias Downloader = @Sendable (LocalModel, URL, @escaping ProgressHandler) async throws -> URL
    typealias Validator = @Sendable (URL, URL) async throws -> Void

    private let root: URL
    private let fileManager: FileManager
    private let downloader: Downloader
    private let validator: Validator

    init(
        root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "NODAYSIDLE Voice/Models", directoryHint: .isDirectory),
        fileManager: FileManager = .default,
        downloader: @escaping Downloader = LocalModelManager.whisperKitDownload,
        validator: @escaping Validator = LocalModelManager.whisperKitValidate
    ) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        self.downloader = downloader
        self.validator = validator
    }

    func download(
        _ model: LocalModel,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> InstalledLocalModel {
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let finalBase = root.appending(path: model.id, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: finalBase.path) else { throw LocalModelError.alreadyInstalled }
        let staging = root.appending(path: ".staging-\(model.id)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])

        do {
            let downloaded = try await downloader(model, staging, progress).standardizedFileURL
            guard Self.contains(downloaded, in: staging) else {
                throw LocalModelError.downloadEscapedStagingDirectory
            }
            try await validator(downloaded, staging)
            let relativePath = String(downloaded.path.dropFirst(staging.path.count + 1))
            let manifest = InstalledLocalModel(
                modelID: model.id,
                variant: model.variant,
                source: "argmaxinc/whisperkit-coreml",
                baseURL: finalBase,
                folderRelativePath: relativePath
            )
            let manifestURL = staging.appending(path: "manifest.json")
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
            try fileManager.moveItem(at: staging, to: finalBase)
            return manifest
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func installedModels() throws -> [InstalledLocalModel] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let manifestURL = url.appending(path: "manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(InstalledLocalModel.self, from: data),
                  manifest.baseURL.standardizedFileURL == url.standardizedFileURL,
                  Self.contains(manifest.folderURL, in: url) else { return nil }
            return manifest
        }.sorted { $0.modelID < $1.modelID }
    }

    func installedModel(id: String) throws -> InstalledLocalModel {
        guard let model = try installedModels().first(where: { $0.modelID == id }) else {
            throw LocalModelError.notInstalled
        }
        return model
    }

    func remove(id: String) throws {
        let model = try installedModel(id: id)
        guard model.baseURL.deletingLastPathComponent().standardizedFileURL == root else {
            throw LocalModelError.invalidManifest
        }
        try fileManager.removeItem(at: model.baseURL)
    }

    private static func whisperKitDownload(
        model: LocalModel,
        staging: URL,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: model.variant,
            downloadBase: staging,
            progressCallback: { progress($0.fractionCompleted) }
        )
    }

    private static func whisperKitValidate(folder: URL, base: URL) async throws {
        let config = WhisperKitConfig(
            downloadBase: base,
            modelFolder: folder.path,
            verbose: false,
            prewarm: true,
            load: false,
            download: false
        )
        let pipeline = try await WhisperKit(config)
        await pipeline.unloadModels()
    }

    nonisolated private static func contains(_ child: URL, in parent: URL) -> Bool {
        let childPath = child.resolvingSymlinksInPath().standardizedFileURL.path
        let parentPath = parent.resolvingSymlinksInPath().standardizedFileURL.path
        return childPath.hasPrefix(parentPath + "/")
    }
}
