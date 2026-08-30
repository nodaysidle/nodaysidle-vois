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

@Test func onlyCapturedOrCompletedStatesOfferRecovery() {
    #expect(!RecordingState.idle.hasRecoverableResult)
    #expect(RecordingState.recording(startedAt: .distantPast).hasRecoverableResult)
    #expect(RecordingState.transcribing.hasRecoverableResult)
    #expect(RecordingState.completed.hasRecoverableResult)
    #expect(RecordingState.failed(.providerUnavailable).hasRecoverableResult)
    #expect(!RecordingState.failed(.microphoneDenied).hasRecoverableResult)
}

@Test func capsuleLayoutStaysTinyUntilHoverOrRecoverableError() {
    #expect(CapsuleLayout(state: .idle, isHovering: false).width == 144)
    #expect(!CapsuleLayout(state: .recording(startedAt: .distantPast), isHovering: false).showsControls)
    #expect(CapsuleLayout(state: .recording(startedAt: .distantPast), isHovering: true).width == 236)
    #expect(CapsuleLayout(state: .recording(startedAt: .distantPast), isHovering: true).showsControls)
    #expect(CapsuleLayout(state: .failed(.providerUnavailable), isHovering: false).width == 280)
    #expect(CapsuleLayout(state: .failed(.providerUnavailable), isHovering: false).showsRecovery)
    #expect(CapsuleLayout(state: .failed(.microphoneDenied), isHovering: false).showsRecovery)
}

@Test func runtimeErrorsMapToActionableRecoveryStates() {
    #expect(AppCoordinator.failure(for: AudioCaptureError.microphoneDenied, capturedAudio: false) == .microphoneDenied)
    #expect(AppCoordinator.failure(for: LocalModelError.notInstalled, capturedAudio: true) == .modelUnavailable)
    #expect(AppCoordinator.failure(for: ProviderError.rateLimited, capturedAudio: true) == .rateLimited)
    #expect(AppCoordinator.failure(for: URLError(.notConnectedToInternet), capturedAudio: true) == .offline)
    #expect(AppCoordinator.failure(for: InsertionError.accessibilityDenied, capturedAudio: false) == .accessibilityDenied)
}
