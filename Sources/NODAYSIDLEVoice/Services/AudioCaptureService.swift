import AVFoundation
import Accelerate
import Foundation
import os

enum AudioCaptureError: Error, Equatable {
    case alreadyRecording
    case notRecording
    case microphoneDenied
    case invalidInputFormat
    case conversionFailed
    case recordingOutsideTemporaryStore
}

extension AudioCaptureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .alreadyRecording: "A recording is already active."
        case .notRecording: "No active recording was found."
        case .microphoneDenied: "Allow microphone access in System Settings."
        case .invalidInputFormat: "The microphone format is not supported."
        case .conversionFailed: "Audio conversion stopped; the recording was kept for recovery."
        case .recordingOutsideTemporaryStore: "The temporary recording path was rejected."
        }
    }
}

struct MeterThrottle {
    private let minimumInterval: TimeInterval
    private var lastPublishedAt: TimeInterval?

    init(maximumUpdatesPerSecond: Double) {
        precondition(maximumUpdatesPerSecond > 0)
        minimumInterval = 1 / maximumUpdatesPerSecond
    }

    mutating func shouldPublish(at time: TimeInterval) -> Bool {
        guard let lastPublishedAt else {
            self.lastPublishedAt = time
            return true
        }
        guard time - lastPublishedAt >= minimumInterval else { return false }
        self.lastPublishedAt = time
        return true
    }
}

struct AudioLevelHistory: Equatable {
    private let capacity: Int
    private(set) var values: [Float] = []

    init(capacity: Int = 13) {
        precondition(capacity > 0)
        self.capacity = capacity
        values.reserveCapacity(capacity)
    }

    mutating func append(_ value: Float) {
        if values.count == capacity { values.removeFirst() }
        values.append(min(max(value, 0), 1))
    }
}

actor TemporaryAudioStore {
    private let root: URL
    private let fileManager: FileManager

    init(
        root: URL = FileManager.default.temporaryDirectory
            .appending(path: "NODAYSIDLEVoice", directoryHint: .isDirectory),
        fileManager: FileManager = .default
    ) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
    }

    func makeRecordingURL() throws -> URL {
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = root.appending(path: "\(UUID().uuidString).wav")
        guard fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    func discard(_ url: URL) throws {
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else {
            throw AudioCaptureError.recordingOutsideTemporaryStore
        }
        if fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }

    func discardExpired(olderThan cutoff: Date) throws {
        guard fileManager.fileExists(atPath: root.path) else { return }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        for url in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) {
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true, let modified = values.contentModificationDate, modified < cutoff {
                try discard(url)
            }
        }
    }
}

struct AudioCaptureSession: Sendable {
    let frames: AsyncStream<Data>
}

struct AudioRecording: Equatable, Sendable {
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let channels: Int
    let format: String
}

private struct AudioSinkState {
    let converter: AVAudioConverter
    var file: AVAudioFile?
    let continuation: AsyncStream<Data>.Continuation
    var throttle = MeterThrottle(maximumUpdatesPerSecond: 20)
    var error: AudioCaptureError?
}

private final class SingleAudioBufferInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let supplied = OSAllocatedUnfairLock(initialState: false)

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        let shouldSupply = supplied.withLock { supplied in
            guard !supplied else { return false }
            supplied = true
            return true
        }
        if shouldSupply {
            status.pointee = .haveData
            return buffer
        }
        status.pointee = .noDataNow
        return nil
    }
}

func convertAudioBuffer(
    _ input: AVAudioPCMBuffer,
    with converter: AVAudioConverter
) throws -> AVAudioPCMBuffer {
    guard input.format == converter.inputFormat else {
        throw AudioCaptureError.invalidInputFormat
    }
    let ratio = converter.outputFormat.sampleRate / input.format.sampleRate
    let capacity = max(1, AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)))
    guard let output = AVAudioPCMBuffer(
        pcmFormat: converter.outputFormat,
        frameCapacity: capacity
    ) else {
        throw AudioCaptureError.conversionFailed
    }

    let inputSource = SingleAudioBufferInput(input)
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
        inputSource.next(inputStatus)
    }
    guard status != .error, conversionError == nil else {
        throw AudioCaptureError.conversionFailed
    }
    return output
}

func makeAudioRecordingFile(at url: URL, format: AVAudioFormat) throws -> AVAudioFile {
    try AVAudioFile(
        forWriting: url,
        settings: format.settings,
        commonFormat: format.commonFormat,
        interleaved: format.isInterleaved
    )
}

private final class AudioSink: Sendable {
    private let state: OSAllocatedUnfairLock<AudioSinkState>

    init(
        converter: AVAudioConverter,
        file: AVAudioFile,
        continuation: AsyncStream<Data>.Continuation
    ) {
        state = OSAllocatedUnfairLock(initialState: AudioSinkState(
            converter: converter,
            file: file,
            continuation: continuation
        ))
    }

    func consume(
        _ input: AVAudioPCMBuffer,
        onLevel: @escaping @MainActor @Sendable (Float) -> Void
    ) {
        // The tap invokes this synchronously; the buffer never escapes the lock scope.
        state.withLockUnchecked { state in
            guard state.error == nil, let file = state.file else { return }
            do {
                let output = try convertAudioBuffer(input, with: state.converter)
                try file.write(from: output)

                if let samples = output.int16ChannelData?[0], output.frameLength > 0 {
                    let data = Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
                    if case .dropped = state.continuation.yield(data) {
                        throw AudioCaptureError.conversionFailed
                    }
                }
            } catch {
                state.error = .conversionFailed
                state.continuation.finish()
                return
            }

            guard state.throttle.shouldPublish(at: ProcessInfo.processInfo.systemUptime),
                  let channel = input.floatChannelData?[0], input.frameLength > 0 else { return }
            var meanSquare: Float = 0
            vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(input.frameLength))
            let normalized = min(sqrt(meanSquare) * 8, 1)
            Task { @MainActor in onLevel(normalized) }
        }
    }

    func finish() -> AudioCaptureError? {
        state.withLock { state in
            state.continuation.finish()
            state.file = nil
            return state.error
        }
    }
}

actor AudioCaptureService {
    typealias MicrophonePermission = @Sendable () async -> Bool

    private let engine = AVAudioEngine()
    private let store: TemporaryAudioStore
    private let microphonePermission: MicrophonePermission
    private var sink: AudioSink?
    private var recordingURL: URL?
    private var startedAt: Date?
    private(set) var recoverableRecording: AudioRecording?

    init(
        store: TemporaryAudioStore = TemporaryAudioStore(),
        microphonePermission: @escaping MicrophonePermission = AudioCaptureService.requestMicrophonePermission
    ) {
        self.store = store
        self.microphonePermission = microphonePermission
    }

    var isRecording: Bool { recordingURL != nil }

    func start(
        onLevel: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws -> AudioCaptureSession {
        guard recordingURL == nil else { throw AudioCaptureError.alreadyRecording }
        guard await microphonePermission() else { throw AudioCaptureError.microphoneDenied }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: 16_000,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.invalidInputFormat
        }

        let url = try await store.makeRecordingURL()
        do {
            let file = try makeAudioRecordingFile(at: url, format: outputFormat)
            let stream = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(64))
            let sink = AudioSink(converter: converter, file: file, continuation: stream.continuation)
            input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
                sink.consume(buffer, onLevel: onLevel)
            }
            engine.prepare()
            try engine.start()
            self.sink = sink
            recordingURL = url
            startedAt = .now
            recoverableRecording = nil
            return AudioCaptureSession(frames: stream.stream)
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            try? await store.discard(url)
            throw error
        }
    }

    func stop() async throws -> AudioRecording {
        guard let url = recordingURL, let startedAt, let sink else {
            throw AudioCaptureError.notRecording
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let sinkError = sink.finish()
        self.sink = nil
        recordingURL = nil
        self.startedAt = nil

        let recording = AudioRecording(
            url: url,
            duration: Date.now.timeIntervalSince(startedAt),
            sampleRate: 16_000,
            channels: 1,
            format: "wav"
        )
        if let sinkError {
            recoverableRecording = recording
            throw sinkError
        }
        return recording
    }

    func cancel() async throws {
        guard let url = recordingURL else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        _ = sink?.finish()
        sink = nil
        recordingURL = nil
        startedAt = nil
        recoverableRecording = nil
        try await store.discard(url)
    }

    func discard(_ recording: AudioRecording) async throws {
        if recoverableRecording?.url == recording.url { recoverableRecording = nil }
        try await store.discard(recording.url)
    }

    private static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}
