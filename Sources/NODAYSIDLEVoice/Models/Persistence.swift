import Foundation
import SwiftData

@Model
final class TranscriptRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var editedAt: Date?
    var sourceApplication: String
    var sourceBundleIdentifier: String?
    var modeID: String
    var modeName: String
    var engineRawValue: String
    var duration: TimeInterval
    var preview: String
    var isFavorite: Bool
    var cost: Double?
    @Attribute(.externalStorage) var text: String

    init(
        id: UUID = UUID(),
        createdAt: Date,
        sourceApplication: String,
        sourceBundleIdentifier: String?,
        modeID: String,
        modeName: String,
        engine: TranscriptionEngine,
        duration: TimeInterval,
        text: String,
        cost: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceApplication = sourceApplication
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.modeID = modeID
        self.modeName = modeName
        engineRawValue = engine.rawValue
        self.duration = duration
        preview = String(text.prefix(120))
        isFavorite = false
        self.text = text
        self.cost = cost
    }
}

@Model
final class ModeRecord {
    @Attribute(.unique) var stableID: String
    var name: String
    var symbol: String
    var instruction: String?
    var outputLanguage: String
    var engineRawValue: String
    var refinementModel: String?
    var insertionRawValue: String
    var isBuiltIn: Bool

    init(mode: DictationMode, isBuiltIn: Bool = false) {
        stableID = mode.id
        name = mode.name
        symbol = mode.symbol
        instruction = mode.instruction
        outputLanguage = mode.outputLanguage
        engineRawValue = mode.engine?.rawValue ?? ""
        refinementModel = mode.refinementModel
        insertionRawValue = mode.insertion?.rawValue ?? ""
        self.isBuiltIn = isBuiltIn
    }
}

@Model
final class VocabularyEntry {
    @Attribute(.unique) var stableKey: String
    var term: String
    var replacement: String?
    var createdAt: Date

    init(term: String, replacement: String? = nil, createdAt: Date = .now) {
        let folded = term.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        stableKey = "\(replacement == nil ? "hint" : "replacement"):\(folded)"
        self.term = term
        self.replacement = replacement
        self.createdAt = createdAt
    }
}

@MainActor
final class ModeStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func modes() throws -> [DictationMode] {
        try context.fetch(FetchDescriptor<ModeRecord>(sortBy: [SortDescriptor(\.name)]))
            .map {
                DictationMode(
                    id: $0.stableID,
                    name: $0.name,
                    symbol: $0.symbol,
                    instruction: $0.instruction,
                    outputLanguage: $0.outputLanguage,
                    engine: TranscriptionEngine(rawValue: $0.engineRawValue),
                    refinementModel: $0.refinementModel,
                    insertion: InsertionBehavior(rawValue: $0.insertionRawValue)
                )
            }
    }

    func save(_ mode: DictationMode) throws {
        let modeID = mode.id
        var descriptor = FetchDescriptor<ModeRecord>(predicate: #Predicate { $0.stableID == modeID })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            record.name = mode.name
            record.symbol = mode.symbol
            record.instruction = mode.instruction
            record.outputLanguage = mode.outputLanguage
            record.engineRawValue = mode.engine?.rawValue ?? ""
            record.refinementModel = mode.refinementModel
            record.insertionRawValue = mode.insertion?.rawValue ?? ""
        } else {
            context.insert(ModeRecord(mode: mode))
        }
        try context.save()
    }

    func setRule(bundleIdentifier: String, modeID: String) throws {
        var descriptor = FetchDescriptor<AppRule>(predicate: #Predicate { $0.bundleIdentifier == bundleIdentifier })
        descriptor.fetchLimit = 1
        if let rule = try context.fetch(descriptor).first { rule.modeID = modeID }
        else { context.insert(AppRule(bundleIdentifier: bundleIdentifier, modeID: modeID)) }
        try context.save()
    }

    func modeID(for bundleIdentifier: String?) throws -> String? {
        guard let bundleIdentifier else { return nil }
        var descriptor = FetchDescriptor<AppRule>(predicate: #Predicate { $0.bundleIdentifier == bundleIdentifier })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.modeID
    }
}

@Model
final class AppRule {
    @Attribute(.unique) var bundleIdentifier: String
    var modeID: String

    init(bundleIdentifier: String, modeID: String) {
        self.bundleIdentifier = bundleIdentifier
        self.modeID = modeID
    }
}

enum VoiceSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        TranscriptRecord.self,
        ModeRecord.self,
        VocabularyEntry.self,
        AppRule.self,
    ]
}

enum VoiceMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [VoiceSchemaV1.self]
    static let stages: [MigrationStage] = []
}

enum VoiceData {
    @MainActor
    static func makeContainer(inMemory: Bool = false, storageURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VoiceSchemaV1.self)
        let configuration: ModelConfiguration
        if let storageURL {
            configuration = ModelConfiguration(nil, schema: schema, url: storageURL)
        } else {
            configuration = ModelConfiguration(nil, schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, migrationPlan: VoiceMigrationPlan.self, configurations: [configuration])
    }

    @MainActor
    static func seedBuiltInModes(in container: ModelContainer) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ModeRecord>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        DictationMode.defaults.forEach { context.insert(ModeRecord(mode: $0, isBuiltIn: true)) }
        try context.save()
    }
}

struct HistorySummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let sourceApplication: String
    let modeName: String
    let preview: String
    let isFavorite: Bool
}

enum HistoryError: Error, Equatable {
    case notFound
    case emptyTranscript
}

extension HistoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound: "The transcript no longer exists."
        case .emptyTranscript: "A transcript cannot be empty."
        }
    }
}

@MainActor
final class HistoryStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    @discardableResult
    func add(
        text: String,
        sourceApplication: String,
        sourceBundleIdentifier: String?,
        modeID: String,
        modeName: String,
        engine: TranscriptionEngine,
        duration: TimeInterval,
        cost: Double? = nil,
        createdAt: Date = .now
    ) throws -> HistorySummary {
        guard !text.isEmpty else { throw HistoryError.emptyTranscript }
        let record = TranscriptRecord(
            createdAt: createdAt,
            sourceApplication: sourceApplication,
            sourceBundleIdentifier: sourceBundleIdentifier,
            modeID: modeID,
            modeName: modeName,
            engine: engine,
            duration: duration,
            text: text,
            cost: cost
        )
        context.insert(record)
        try context.save()
        return summary(record)
    }

    func summaries(search: String = "") throws -> [HistorySummary] {
        var descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // ponytail: keep recent UI reads bounded; paginate if a user needs more than 500 rows at once.
        descriptor.fetchLimit = 500
        let records = try context.fetch(descriptor)
        let filtered = search.isEmpty ? records : records.filter {
            $0.preview.localizedStandardContains(search)
                || $0.sourceApplication.localizedStandardContains(search)
                || $0.modeName.localizedStandardContains(search)
                || $0.text.localizedStandardContains(search)
        }
        return filtered.map(summary)
    }

    func text(for id: UUID) throws -> String {
        try record(id).text
    }

    func edit(_ id: UUID, text: String, now: Date = .now) throws {
        guard !text.isEmpty else { throw HistoryError.emptyTranscript }
        let record = try record(id)
        record.text = text
        record.preview = String(text.prefix(120))
        record.editedAt = now
        try context.save()
    }

    func setFavorite(_ id: UUID, _ isFavorite: Bool) throws {
        try record(id).isFavorite = isFavorite
        try context.save()
    }

    func delete(_ id: UUID) throws {
        context.delete(try record(id))
        try context.save()
    }

    func clear() throws {
        try context.delete(model: TranscriptRecord.self)
        try context.save()
    }

    func cleanup(retentionDays: Int, now: Date = .now) throws {
        guard retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let descriptor = FetchDescriptor<TranscriptRecord>(predicate: #Predicate { $0.createdAt < cutoff })
        for record in try context.fetch(descriptor) { context.delete(record) }
        try context.save()
    }

    private func record(_ id: UUID) throws -> TranscriptRecord {
        var descriptor = FetchDescriptor<TranscriptRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { throw HistoryError.notFound }
        return record
    }

    private func summary(_ record: TranscriptRecord) -> HistorySummary {
        HistorySummary(
            id: record.id,
            createdAt: record.createdAt,
            sourceApplication: record.sourceApplication,
            modeName: record.modeName,
            preview: record.preview,
            isFavorite: record.isFavorite
        )
    }
}

@MainActor
final class VocabularyStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func importPreview(_ preview: VocabularyImportPreview) throws -> (vocabulary: Int, replacements: Int) {
        guard preview.conflicts.isEmpty else { throw VocabularyImportError.unresolvedConflicts }
        var existing = Set(try context.fetch(FetchDescriptor<VocabularyEntry>()).map(\.stableKey))
        var vocabularyCount = 0
        var replacementCount = 0
        for term in preview.uniqueVocabulary {
            let entry = VocabularyEntry(term: term)
            if existing.insert(entry.stableKey).inserted {
                context.insert(entry)
                vocabularyCount += 1
            }
        }
        for replacement in preview.replacements {
            let entry = VocabularyEntry(term: replacement.original, replacement: replacement.replacement)
            if existing.insert(entry.stableKey).inserted {
                context.insert(entry)
                replacementCount += 1
            }
        }
        try context.save()
        return (vocabularyCount, replacementCount)
    }

    func replacements() throws -> [VocabularyReplacement] {
        try context.fetch(FetchDescriptor<VocabularyEntry>())
            .compactMap { entry in
                entry.replacement.map {
                    VocabularyReplacement(id: entry.stableKey, original: entry.term, replacement: $0)
                }
            }
    }

    /// Hint terms (no replacement) used to bias Whisper / Deepgram recognition.
    func hints(limit: Int = 100) throws -> [String] {
        try context.fetch(FetchDescriptor<VocabularyEntry>())
            .compactMap { entry -> String? in
                guard entry.replacement == nil else { return nil }
                let trimmed = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }
}
