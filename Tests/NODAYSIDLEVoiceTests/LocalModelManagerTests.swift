import Foundation
import Testing
@testable import NODAYSIDLEVoice

@Test func localModelDownloadValidatesThenAtomicallyPromotesOneDirectory() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "NODAYSIDLEVoiceModels-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try #require(LocalModel.catalog.first { $0.id == "base" })
    let manager = LocalModelManager(
        root: root,
        downloader: { _, staging, progress in
            let folder = staging.appending(path: "model", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("complete".utf8).write(to: folder.appending(path: "marker"))
            progress(1)
            return folder
        },
        validator: { folder, _ in
            guard FileManager.default.fileExists(atPath: folder.appending(path: "marker").path) else {
                throw LocalModelError.invalidModelDirectory
            }
        }
    )

    let installed = try await manager.download(model)

    #expect(installed.modelID == "base")
    #expect(FileManager.default.fileExists(atPath: installed.folderURL.appending(path: "marker").path))
    #expect(try await manager.installedModels().map(\.modelID) == ["base"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staging-") })
}

@Test func localModelDownloadRejectsPathsOutsideItsStagingDirectory() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "NODAYSIDLEVoiceModels-\(UUID().uuidString)", directoryHint: .isDirectory)
    let outside = root.deletingLastPathComponent().appending(path: "outside-model-\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let model = try #require(LocalModel.catalog.first)
    let manager = LocalModelManager(
        root: root,
        downloader: { _, _, _ in outside },
        validator: { _, _ in }
    )

    await #expect(throws: LocalModelError.downloadEscapedStagingDirectory) {
        _ = try await manager.download(model)
    }
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: model.id).path))
}

@Test func localWhisperRefusesTranscriptionUntilOneVerifiedModelIsLoaded() async {
    let engine = LocalWhisperEngine()
    let audio = URL(filePath: "/tmp/not-read-without-a-model.wav")

    await #expect(throws: LocalModelError.notInstalled) {
        _ = try await engine.transcribe(audio)
    }
    #expect(await engine.activeModelID == nil)
}
