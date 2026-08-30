import Foundation

struct VocabularyReplacement: Codable, Equatable, Sendable {
    let id: String
    let original: String
    let replacement: String

    enum CodingKeys: String, CodingKey {
        case id, original
        case replacement = "with"
    }
}

struct VocabularyConflict: Equatable, Sendable {
    let original: String
    let replacements: [String]
}

struct VocabularyImportPreview: Equatable, Sendable {
    let source: String
    let sourceVocabularyCount: Int
    let sourceReplacementCount: Int
    let uniqueVocabulary: [String]
    let replacements: [VocabularyReplacement]
    let duplicateVocabularyCount: Int
    let conflicts: [VocabularyConflict]
}

enum VocabularyImportError: Error, Equatable {
    case unsupportedSchema
    case emptyEntry
    case unresolvedConflicts
    case invalidConflictChoice
}

extension VocabularyImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "This vocabulary migration schema is not supported."
        case .emptyEntry: "The migration contains an empty vocabulary or replacement entry."
        case .unresolvedConflicts: "Resolve every replacement conflict before importing."
        case .invalidConflictChoice: "A conflict selection is not present in the source migration."
        }
    }
}

enum VocabularyImporter {
    private struct Migration: Decodable {
        let schemaVersion: Int
        let source: String
        let vocabulary: [String]
        let replacements: [VocabularyReplacement]
    }

    static func preview(_ data: Data) throws -> VocabularyImportPreview {
        let migration = try JSONDecoder().decode(Migration.self, from: data)
        guard migration.schemaVersion == 1 else { throw VocabularyImportError.unsupportedSchema }

        var seenVocabulary: Set<String> = []
        var vocabulary: [String] = []
        for term in migration.vocabulary {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw VocabularyImportError.emptyEntry }
            if seenVocabulary.insert(key(trimmed)).inserted { vocabulary.append(trimmed) }
        }

        var grouped: [String: [VocabularyReplacement]] = [:]
        for replacement in migration.replacements {
            let original = replacement.original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty, !replacement.replacement.isEmpty else {
                throw VocabularyImportError.emptyEntry
            }
            grouped[key(original), default: []].append(VocabularyReplacement(
                id: replacement.id,
                original: original,
                replacement: replacement.replacement
            ))
        }

        var replacements: [VocabularyReplacement] = []
        var conflicts: [VocabularyConflict] = []
        for group in grouped.values {
            let outputs = Array(Set(group.map(\.replacement))).sorted()
            if outputs.count > 1 {
                conflicts.append(VocabularyConflict(original: group[0].original, replacements: outputs))
            } else if let first = group.first {
                replacements.append(first)
            }
        }
        replacements.sort { key($0.original) < key($1.original) }
        conflicts.sort { key($0.original) < key($1.original) }

        return VocabularyImportPreview(
            source: migration.source,
            sourceVocabularyCount: migration.vocabulary.count,
            sourceReplacementCount: migration.replacements.count,
            uniqueVocabulary: vocabulary,
            replacements: replacements,
            duplicateVocabularyCount: migration.vocabulary.count - vocabulary.count,
            conflicts: conflicts
        )
    }

    static func apply(_ replacements: [VocabularyReplacement], to text: String) -> String {
        let usable = replacements.filter { !$0.original.isEmpty }
        guard !usable.isEmpty else { return text }
        let lookup = Dictionary(uniqueKeysWithValues: usable.map { (key($0.original), $0.replacement) })
        let alternatives = usable.map(\.original)
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        guard let expression = try? NSRegularExpression(pattern: alternatives, options: [.caseInsensitive]) else {
            return text
        }

        let result = NSMutableString(string: text)
        let range = NSRange(location: 0, length: result.length)
        for match in expression.matches(in: text, range: range).reversed() {
            let matched = result.substring(with: match.range)
            if let replacement = lookup[key(matched)] { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }

    static func resolving(
        _ preview: VocabularyImportPreview,
        choices: [String: String]
    ) throws -> VocabularyImportPreview {
        var resolved = preview.replacements
        var remaining: [VocabularyConflict] = []
        for conflict in preview.conflicts {
            guard let choice = choices[conflict.original] else {
                remaining.append(conflict)
                continue
            }
            guard conflict.replacements.contains(choice) else { throw VocabularyImportError.invalidConflictChoice }
            resolved.append(VocabularyReplacement(
                id: "resolved:\(conflict.original)",
                original: conflict.original,
                replacement: choice
            ))
        }
        return VocabularyImportPreview(
            source: preview.source,
            sourceVocabularyCount: preview.sourceVocabularyCount,
            sourceReplacementCount: preview.sourceReplacementCount,
            uniqueVocabulary: preview.uniqueVocabulary,
            replacements: resolved.sorted { key($0.original) < key($1.original) },
            duplicateVocabularyCount: preview.duplicateVocabularyCount,
            conflicts: remaining
        )
    }

    private static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
