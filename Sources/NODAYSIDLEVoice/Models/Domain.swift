import Foundation

enum OutputLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case english = "EN"
    case italian = "IT"
    case slovenian = "SL"

    var id: String { rawValue }
    var chipLabel: String { rawValue }

    /// WhisperKit / OpenAI-style language code. `nil` means detect automatically.
    var whisperCode: String? {
        switch self {
        case .automatic: nil
        case .english: "en"
        case .italian: "it"
        case .slovenian: "sl"
        }
    }

    /// Deepgram `language` query value. `nil` omits the parameter (provider default).
    var deepgramCode: String? {
        switch self {
        case .automatic: nil
        case .english: "en"
        case .italian: "it"
        case .slovenian: "sl"
        }
    }

    static func resolve(_ stored: String) -> OutputLanguage {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = OutputLanguage(rawValue: trimmed) { return exact }
        switch trimmed.lowercased() {
        case "", "auto", "automatic", "detect": return .automatic
        case "en", "en-us", "en-gb", "english": return .english
        case "it", "it-it", "italian", "italiano": return .italian
        case "sl", "sl-si", "slovenian", "slovene", "slovenščina", "slovenscina": return .slovenian
        default: return .automatic
        }
    }
}

enum CapsulePresentation: Equatable, Sendable {
    case ready
    case arming
    case recording
    case processing
    case success
    case error
}

enum DictationFailure: Error, Equatable, Sendable {
    case microphoneDenied
    case accessibilityDenied
    case modelUnavailable
    case offline
    case rateLimited
    case providerUnavailable
    case transcriptionFailed
    case insertionFailed

    var message: String {
        switch self {
        case .microphoneDenied: "Microphone access is required."
        case .accessibilityDenied: "Accessibility access is required for auto-paste."
        case .modelUnavailable: "Download the selected local model before dictating."
        case .offline: "The network is offline. Your recording is ready to retry."
        case .rateLimited: "The provider rate limit was reached. Your recording is ready to retry."
        case .providerUnavailable: "The selected transcription engine is unavailable."
        case .transcriptionFailed: "Transcription failed. Your recording is available to retry."
        case .insertionFailed: "Text is ready, but could not be inserted."
        }
    }
}

enum RecordingState: Equatable, Sendable {
    case idle
    case arming
    case recording(startedAt: Date)
    case transcribing
    case refining
    case inserting
    case completed
    case failed(DictationFailure)

    /// Accessibility / status labels only — the capsule UI stays wordless.
    var label: String {
        switch self {
        case .idle: "Idle"
        case .arming: "Preparing"
        case .recording: "Recording"
        case .transcribing, .refining, .inserting: "Processing"
        case .completed: "Done"
        case .failed: "Needs attention"
        }
    }

    var capsulePresentation: CapsulePresentation {
        switch self {
        case .idle: .ready
        case .arming: .arming
        case .recording: .recording
        case .transcribing, .refining, .inserting: .processing
        case .completed: .success
        case .failed: .error
        }
    }

    var hasRecoverableResult: Bool {
        switch self {
        case .recording, .transcribing, .refining, .inserting, .completed:
            true
        case .failed(.modelUnavailable), .failed(.offline), .failed(.rateLimited),
             .failed(.providerUnavailable), .failed(.transcriptionFailed), .failed(.insertionFailed):
            true
        case .idle, .arming, .failed(.microphoneDenied), .failed(.accessibilityDenied):
            false
        }
    }
}

enum InsertionBehavior: String, CaseIterable, Identifiable {
    case autoPaste = "Auto-paste"
    case clipboard = "Copy only"
    case preview = "Preview first"
    var id: String { rawValue }
}

struct DictationMode: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let instruction: String?
    let outputLanguage: String
    let engine: TranscriptionEngine?
    let refinementModel: String?
    let insertion: InsertionBehavior?

    init(
        id: String,
        name: String,
        symbol: String,
        instruction: String?,
        outputLanguage: String = "Automatic",
        engine: TranscriptionEngine? = nil,
        refinementModel: String? = nil,
        insertion: InsertionBehavior? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.instruction = instruction
        self.outputLanguage = outputLanguage
        self.engine = engine
        self.refinementModel = refinementModel
        self.insertion = insertion
    }

    static let defaults: [Self] = [
        .init(id: "raw", name: "Raw", symbol: "waveform", instruction: nil),
        .init(id: "message", name: "Message", symbol: "message", instruction: "Natural, concise message."),
        .init(id: "email", name: "Email", symbol: "envelope", instruction: "Polished email with clear paragraphs."),
        .init(id: "notes", name: "Notes", symbol: "note.text", instruction: "Structured notes without changing meaning."),
        .init(id: "code", name: "Coding", symbol: "chevron.left.forwardslash.chevron.right", instruction: "Preserve technical names and code formatting."),
        .init(id: "formal", name: "Formal", symbol: "textformat", instruction: "Use precise, professional language without changing meaning."),
        .init(id: "casual", name: "Casual", symbol: "bubble.left.and.bubble.right", instruction: "Use relaxed, natural language without changing meaning."),
    ]
}

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case localWhisper = "Local Whisper"
    case deepgram = "Deepgram Nova-3"
    case openRouter = "OpenRouter STT"
    var id: String { rawValue }
    var isLocal: Bool { self == .localWhisper }
}

struct LocalModel: Identifiable, Hashable {
    let id: String
    let variant: String
    let name: String
    let size: String
    let detail: String

    static let catalog: [Self] = [
        .init(id: "tiny", variant: "tiny", name: "Whisper Tiny", size: "~75 MB", detail: "Fastest, lowest accuracy"),
        .init(id: "base", variant: "base", name: "Whisper Base", size: "~150 MB", detail: "Fast everyday dictation"),
        .init(id: "small", variant: "small", name: "Whisper Small", size: "~500 MB", detail: "Balanced speed and accuracy"),
        .init(id: "large-v3-turbo", variant: "large-v3-v20240930_626MB", name: "Whisper Large V3", size: "~626 MB", detail: "Best local quality"),
    ]
}

struct HistoryItem: Identifiable {
    let id = UUID()
    let createdAt: Date
    let sourceApplication: String
    let mode: String
    let text: String
}
