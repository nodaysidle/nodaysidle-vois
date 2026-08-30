import AVFoundation
import Foundation
import Testing
@testable import NODAYSIDLEVoice

@Test func meterThrottleNeverPublishesFasterThanTwentyHertz() {
    var throttle = MeterThrottle(maximumUpdatesPerSecond: 20)

    let first = throttle.shouldPublish(at: 10)
    let tooSoon = throttle.shouldPublish(at: 10.049)
    let next = throttle.shouldPublish(at: 10.05)

    #expect(first)
    #expect(!tooSoon)
    #expect(next)
}

@Test func waveformHistoryIsBoundedAndClamped() {
    var history = AudioLevelHistory(capacity: 3)
    history.append(-1)
    history.append(0.25)
    history.append(2)
    history.append(0.5)

    #expect(history.values == [0.25, 1, 0.5])
}

@Test func temporaryAudioStoreCreatesPrivateFilesAndDeletesOnlyOwnedRecordings() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "NODAYSIDLEVoiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let outside = root.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).wav")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    let store = TemporaryAudioStore(root: root)
    let recording = try await store.makeRecordingURL()
    try Data([0, 1, 2]).write(to: recording)
    try Data([3]).write(to: outside)

    let attributes = try FileManager.default.attributesOfItem(atPath: recording.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    try await store.discard(recording)
    #expect(!FileManager.default.fileExists(atPath: recording.path))
    await #expect(throws: AudioCaptureError.recordingOutsideTemporaryStore) {
        try await store.discard(outside)
    }
    #expect(FileManager.default.fileExists(atPath: outside.path))
}

@Test func audioCaptureDoesNotArmHardwareWithoutMicrophonePermission() async {
    let service = AudioCaptureService(microphonePermission: { false })

    await #expect(throws: AudioCaptureError.microphoneDenied) {
        _ = try await service.start { _ in }
    }
    #expect(await !service.isRecording)
    await #expect(throws: AudioCaptureError.notRecording) {
        _ = try await service.stop()
    }
}

@Test func microphoneBuffersResampleToSixteenKilohertzWithoutAConverterException() throws {
    let inputFormat = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    ))
    let outputFormat = try #require(AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    ))
    let converter = try #require(AVAudioConverter(from: inputFormat, to: outputFormat))
    let input = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 1_024))
    input.frameLength = 1_024
    for channel in 0..<Int(inputFormat.channelCount) {
        let samples = try #require(input.floatChannelData?[channel])
        for frame in 0..<Int(input.frameLength) {
            samples[frame] = sin(Float(frame) * 0.04)
        }
    }

    let output = try convertAudioBuffer(input, with: converter)

    #expect(output.format.sampleRate == 16_000)
    #expect(output.format.channelCount == 1)
    #expect(output.frameLength > 0)
    #expect(output.frameLength <= output.frameCapacity)
}

@Test func waveWriterAcceptsTheInt16ProcessingBuffer() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "NODAYSIDLEVoice-(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    ))
    let file = try makeAudioRecordingFile(at: url, format: format)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
    buffer.frameLength = 160

    try file.write(from: buffer)

    #expect(file.processingFormat == format)
    #expect(file.length == 160)
}
