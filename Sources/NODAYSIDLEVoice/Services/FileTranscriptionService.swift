import Foundation

enum FileTranscriptionError: Error, Equatable {
    case deepgramIsLiveOnly
    case unsupportedFormat
    case fileTooLarge
    case unreadableFile
}

extension FileTranscriptionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .deepgramIsLiveOnly: "Choose Local Whisper or OpenRouter to transcribe a file."
        case .unsupportedFormat: "Choose WAV, MP3, FLAC, M4A, OGG, WebM, or AAC audio."
        case .fileTooLarge: "The selected audio file exceeds this engine's request limit."
        case .unreadableFile: "The selected audio file could not be read."
        }
    }
}

struct FileTranscriptionInput: Equatable, Sendable {
    let url: URL
    let format: String
    let byteCount: Int
}

enum FileTranscriptionService {
    private static let localMaximumBytes = 1_024 * 1_024 * 1_024

    static func preflight(_ url: URL, engine: TranscriptionEngine) throws -> FileTranscriptionInput {
        guard engine != .deepgram else { throw FileTranscriptionError.deepgramIsLiveOnly }
        let format = url.pathExtension.lowercased()
        guard OpenRouterSTTEngine.supportedFormats.contains(format) else {
            throw FileTranscriptionError.unsupportedFormat
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isReadableKey])
        guard values.isRegularFile == true, values.isReadable == true, let size = values.fileSize else {
            throw FileTranscriptionError.unreadableFile
        }
        let maximum = engine == .openRouter ? OpenRouterSTTEngine.maximumAudioBytes : localMaximumBytes
        guard size <= maximum else { throw FileTranscriptionError.fileTooLarge }
        return FileTranscriptionInput(url: url, format: format, byteCount: size)
    }
}
