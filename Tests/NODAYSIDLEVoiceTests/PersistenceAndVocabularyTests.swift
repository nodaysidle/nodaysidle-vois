import Foundation
import Testing
@testable import NODAYSIDLEVoice

@Test func vocabularyMigrationPreviewsDuplicatesConflictsAndAppliesOnePassReplacements() throws {
    let data = Data(#"""
    {
      "schemaVersion": 1,
      "source": "local-test",
      "vocabulary": ["Codex", "codex", "SwiftData"],
      "replacements": [
        {"id":"1","original":"open router","with":"OpenRouter"},
        {"id":"2","original":"Open Router","with":"Open-Router"},
        {"id":"3","original":"swift data","with":"SwiftData"}
      ]
    }
    """#.utf8)

    let preview = try VocabularyImporter.preview(data)

    #expect(preview.sourceVocabularyCount == 3)
    #expect(preview.uniqueVocabulary == ["Codex", "SwiftData"])
    #expect(preview.duplicateVocabularyCount == 1)
    #expect(preview.conflicts.count == 1)
    let resolved = try VocabularyImporter.resolving(
        preview,
        choices: [preview.conflicts[0].original: "OpenRouter"]
    )
    #expect(resolved.conflicts.isEmpty)
    #expect(resolved.replacements.count == 2)
    #expect(VocabularyImporter.apply(
        [VocabularyReplacement(id: "3", original: "swift data", replacement: "SwiftData")],
        to: "SWIFT DATA keeps SwiftData exact"
    ) == "SwiftData keeps SwiftData exact")
}

@MainActor
@Test func builtInAndCustomModesResolvePerApplicationRules() throws {
    let container = try VoiceData.makeContainer(inMemory: true)
    try VoiceData.seedBuiltInModes(in: container)
    let store = ModeStore(container: container)
    let custom = DictationMode(
        id: "custom-test",
        name: "Standup",
        symbol: "person.3",
        instruction: "Return three concise bullets.",
        outputLanguage: "English",
        engine: .openRouter,
        refinementModel: "provider/text-model",
        insertion: .preview
    )

    try store.save(custom)
    try store.setRule(bundleIdentifier: "com.example.Editor", modeID: custom.id)

    #expect(try store.modes().contains(custom))
    #expect(try store.modeID(for: "com.example.Editor") == custom.id)
}

@Test func privateMigrationFileMatchesTheDocumentedCountsWithoutExposingItsContents() throws {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "UserData/superwhisper-dictionary.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return }

    let preview = try VocabularyImporter.preview(Data(contentsOf: url))
    #expect(preview.sourceVocabularyCount == 288)
    #expect(preview.sourceReplacementCount == 264)
}

@MainActor
@Test func privateMigrationBlocksPersistenceUntilDocumentedConflictsAreResolved() throws {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "UserData/superwhisper-dictionary.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let preview = try VocabularyImporter.preview(Data(contentsOf: url))
    #expect(preview.conflicts.count == 36)
    let store = VocabularyStore(container: try VoiceData.makeContainer(inMemory: true))

    #expect(throws: VocabularyImportError.unresolvedConflicts) {
        _ = try store.importPreview(preview)
    }
}

@MainActor
@Test func historyPersistsCompletedTextAndRetentionDeletesOnlyExpiredRows() throws {
    let container = try VoiceData.makeContainer(inMemory: true)
    let store = HistoryStore(container: container)
    let now = Date(timeIntervalSince1970: 2_000_000)
    let expired = try store.add(
        text: "old complete transcript",
        sourceApplication: "TextEdit",
        sourceBundleIdentifier: "com.apple.TextEdit",
        modeID: "raw",
        modeName: "Raw",
        engine: .localWhisper,
        duration: 2,
        createdAt: now.addingTimeInterval(-8 * 86_400)
    )
    let current = try store.add(
        text: "current complete transcript",
        sourceApplication: "Notes",
        sourceBundleIdentifier: "com.apple.Notes",
        modeID: "notes",
        modeName: "Notes",
        engine: .openRouter,
        duration: 3,
        createdAt: now
    )

    try store.setFavorite(current.id, true)
    try store.edit(current.id, text: "edited complete transcript", now: now)
    try store.cleanup(retentionDays: 7, now: now)

    let summaries = try store.summaries(search: "edited")
    #expect(summaries.map(\.id) == [current.id])
    #expect(summaries.first?.isFavorite == true)
    #expect(try store.text(for: current.id) == "edited complete transcript")
    #expect(throws: HistoryError.notFound) { try store.text(for: expired.id) }
}

@MainActor
@Test func completedHistorySurvivesAStoreReopen() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "NODAYSIDLEVoicePersistence-\(UUID().uuidString)", directoryHint: .isDirectory)
    let storeURL = directory.appending(path: "voice.store")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        let container = try VoiceData.makeContainer(storageURL: storeURL)
        _ = try HistoryStore(container: container).add(
            text: "persisted final transcript",
            sourceApplication: "TextEdit",
            sourceBundleIdentifier: "com.apple.TextEdit",
            modeID: "raw",
            modeName: "Raw",
            engine: .localWhisper,
            duration: 1
        )
    }

    let reopened = try VoiceData.makeContainer(storageURL: storeURL)
    let summaries = try HistoryStore(container: reopened).summaries()
    #expect(summaries.count == 1)
    #expect(try HistoryStore(container: reopened).text(for: summaries[0].id) == "persisted final transcript")
}
