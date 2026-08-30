import AppKit
import SwiftUI

struct CapsuleLayout: Equatable {
    let width: CGFloat
    let showsControls: Bool
    let showsRecovery: Bool

    init(state: RecordingState, isHovering: Bool) {
        showsRecovery = state.capsulePresentation == .error
        showsControls = isHovering && !showsRecovery
        width = showsRecovery ? 280 : (isHovering ? 236 : 144)
    }
}

struct RecordingHUDView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let layout = CapsuleLayout(state: model.recordingState, isHovering: isHovering)
        Group {
            if let failure {
                recoveryContent(failure)
            } else {
                standardContent(showsControls: layout.showsControls)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: layout.width, height: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(stateColor.opacity(0.65), lineWidth: 1) }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
        .contentShape(Capsule())
        .onHover { hovering in
            if reduceMotion { isHovering = hovering }
            else { withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        }
        .onChange(of: layout.width, initial: true) { _, width in model.resizeHUD(to: width) }
        .contextMenu { capsuleMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("NODAYSIDLE Voice: \(model.recordingState.label)")
        .accessibilityValue(model.statusMessage)
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private func standardContent(showsControls: Bool) -> some View {
        HStack(spacing: 9) {
            if showsControls { modeMenu }
            stateContent
                .frame(maxWidth: .infinity)
            if showsControls {
                Button(action: model.toggleRecording) {
                    Image(systemName: recording ? "stop.fill" : "mic.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(recording ? VoiceStyle.coral : .primary)
                .help(recording ? "Finish dictation" : "Start dictation")
                .accessibilityLabel(recording ? "Finish dictation" : "Start dictation")

                Button(action: model.openControlCenter) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Open Control Center")
                .accessibilityLabel("Open Control Center")
            }
        }
    }

    @ViewBuilder private var stateContent: some View {
        switch model.recordingState {
        case .idle:
            Label("Ready", systemImage: "mic.fill")
                .font(.caption.weight(.semibold))
        case .arming:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Arming").font(.caption.weight(.semibold))
            }
        case .recording:
            waveform
        case .transcribing:
            processingLabel("Transcribing")
        case .refining:
            processingLabel("Polishing")
        case .inserting:
            processingLabel("Inserting")
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VoiceStyle.success)
        case .failed:
            EmptyView()
        }
    }

    private func processingLabel(_ title: String) -> some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text(title).font(.caption.weight(.semibold))
        }
    }

    private var waveform: some View {
        let levels = Array(repeating: Float(0.08), count: max(0, 13 - model.audioLevels.count))
            + Array(model.audioLevels.suffix(13))
        return HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(index == 6 ? VoiceStyle.coral : stateColor.opacity(0.78))
                    .frame(width: 3, height: 5 + CGFloat(levels[index]) * 23)
            }
        }
        .frame(minWidth: 76, minHeight: 30)
        .accessibilityHidden(true)
    }

    private var modeMenu: some View {
        Menu {
            ForEach(model.modes, id: \.id) { mode in
                Button {
                    model.selectedMode = mode
                } label: {
                    Label(mode.name, systemImage: mode.symbol)
                }
            }
        } label: {
            Image(systemName: model.selectedMode.symbol)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Mode: \(model.selectedMode.name)")
        .accessibilityLabel("Mode: \(model.selectedMode.name)")
    }

    private func recoveryContent(_ failure: DictationFailure) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(VoiceStyle.coral)
            Text(failure.message)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            recoveryButton(for: failure)
            if failure.hasProviderFallback { fallbackMenu }
            Button(action: model.cancelRecording) {
                Image(systemName: "xmark").frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss error")
        }
    }

    @ViewBuilder private func recoveryButton(for failure: DictationFailure) -> some View {
        switch failure {
        case .microphoneDenied:
            Button("Settings") { model.openPermissionSettings(.microphone) }
                .controlSize(.small)
        case .accessibilityDenied:
            Button("Settings") { model.openPermissionSettings(.accessibility) }
                .controlSize(.small)
        case .modelUnavailable:
            Button("Models") { model.openSettings(.models) }
                .controlSize(.small)
        case .offline, .rateLimited, .providerUnavailable, .transcriptionFailed, .insertionFailed:
            Button("Retry", action: model.retry)
                .controlSize(.small)
        }
    }

    private var fallbackMenu: some View {
        Menu {
            Button("Retry locally") { model.useFallback(.localWhisper) }
            Button("Use OpenRouter") { model.useFallback(.openRouter) }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose retry engine")
        .accessibilityLabel("Choose retry engine")
    }

    @ViewBuilder private var capsuleMenu: some View {
        Button("Control Center", action: model.openControlCenter)
        Button("History", action: model.openHistory)
        Button("Settings") { model.openSettings() }
        Divider()
        Button("Cancel dictation", action: model.cancelRecording)
            .disabled(model.recordingState == .idle)
        Button("Quit NODAYSIDLE Voice") { NSApplication.shared.terminate(nil) }
    }

    private var recording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }

    private var failure: DictationFailure? {
        if case .failed(let failure) = model.recordingState { return failure }
        return nil
    }

    private var stateColor: Color {
        switch model.recordingState.capsulePresentation {
        case .ready: .secondary
        case .arming, .processing: VoiceStyle.warning
        case .recording, .error: VoiceStyle.coral
        case .success: VoiceStyle.success
        }
    }
}

private extension DictationFailure {
    var hasProviderFallback: Bool {
        switch self {
        case .modelUnavailable, .offline, .rateLimited, .providerUnavailable, .transcriptionFailed: true
        case .microphoneDenied, .accessibilityDenied, .insertionFailed: false
        }
    }
}
