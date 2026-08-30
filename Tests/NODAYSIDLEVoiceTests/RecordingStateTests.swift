import Foundation
import Testing
@testable import NODAYSIDLEVoice

@Test func recordingStateMapsToCompactCapsulePresentation() {
    #expect(RecordingState.idle.capsulePresentation == .ready)
    #expect(RecordingState.arming.capsulePresentation == .arming)
    #expect(RecordingState.recording(startedAt: .distantPast).capsulePresentation == .recording)
    #expect(RecordingState.transcribing.capsulePresentation == .processing)
    #expect(RecordingState.refining.capsulePresentation == .processing)
    #expect(RecordingState.inserting.capsulePresentation == .processing)
    #expect(RecordingState.completed.capsulePresentation == .success)
    #expect(RecordingState.failed(.microphoneDenied).capsulePresentation == .error)
}

@Test func capsuleLabelsStayGenericWithoutWorkflowCopy() {
    #expect(RecordingState.idle.label == "Idle")
    #expect(RecordingState.arming.label == "Preparing")
    #expect(RecordingState.recording(startedAt: .distantPast).label == "Recording")
    #expect(RecordingState.transcribing.label == "Processing")
    #expect(RecordingState.refining.label == "Processing")
    #expect(RecordingState.inserting.label == "Processing")
}

@Test func onlyCapturedOrCompletedStatesOfferRecovery() {
    #expect(!RecordingState.idle.hasRecoverableResult)
    #expect(RecordingState.recording(startedAt: .distantPast).hasRecoverableResult)
    #expect(RecordingState.transcribing.hasRecoverableResult)
    #expect(RecordingState.completed.hasRecoverableResult)
    #expect(RecordingState.failed(.providerUnavailable).hasRecoverableResult)
    #expect(!RecordingState.failed(.microphoneDenied).hasRecoverableResult)
}

@Test func capsuleLayoutStaysTinyUntilHoverLiveWordsOrRecoverableError() {
    #expect(CapsuleLayout(state: .idle, isHovering: false, showsLiveWords: false).width == 144)
    #expect(!CapsuleLayout(state: .recording(startedAt: .distantPast), isHovering: false, showsLiveWords: false).showsControls)
    #expect(CapsuleLayout(state: .recording(startedAt: .distantPast), isHovering: true, showsLiveWords: false).width == 268)
    #expect(CapsuleLayout(state: .recording(startedAt: .distantPast), isHovering: true, showsLiveWords: false).showsControls)
    #expect(CapsuleLayout(state: .recording(startedAt: .distantPast), isHovering: false, showsLiveWords: true).width == 260)
    #expect(CapsuleLayout(state: .failed(.providerUnavailable), isHovering: false, showsLiveWords: false).width == 280)
    #expect(CapsuleLayout(state: .failed(.providerUnavailable), isHovering: false, showsLiveWords: false).showsRecovery)
    #expect(CapsuleLayout(state: .failed(.microphoneDenied), isHovering: false, showsLiveWords: false).showsRecovery)
}

@Test func outputLanguageResolvesCapsuleChipCodesForSTT() {
    #expect(OutputLanguage.resolve("Automatic") == .automatic)
    #expect(OutputLanguage.resolve("EN").whisperCode == "en")
    #expect(OutputLanguage.resolve("Italian").deepgramCode == "it")
    #expect(OutputLanguage.resolve("SL").whisperCode == "sl")
    #expect(OutputLanguage.resolve("auto").whisperCode == nil)
    #expect(OutputLanguage.resolve("Automatic").deepgramCode == "multi")
    #expect(OutputLanguage.allCases.map(\.chipLabel) == ["Automatic", "EN", "IT", "SL"])
}

@Test func runtimeErrorsMapToActionableRecoveryStates() {
    #expect(AppCoordinator.failure(for: AudioCaptureError.microphoneDenied, capturedAudio: false) == .microphoneDenied)
    #expect(AppCoordinator.failure(for: LocalModelError.notInstalled, capturedAudio: true) == .modelUnavailable)
    #expect(AppCoordinator.failure(for: ProviderError.rateLimited, capturedAudio: true) == .rateLimited)
    #expect(AppCoordinator.failure(for: URLError(.notConnectedToInternet), capturedAudio: true) == .offline)
    #expect(AppCoordinator.failure(for: InsertionError.accessibilityDenied, capturedAudio: false) == .accessibilityDenied)
}
