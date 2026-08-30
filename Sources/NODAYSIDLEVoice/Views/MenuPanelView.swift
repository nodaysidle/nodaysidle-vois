import SwiftUI

struct MenuPanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            header
            readiness

            Button(action: model.toggleRecording) {
                Label(recordButtonTitle, systemImage: recording ? "stop.fill" : "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(recording ? .secondary : VoiceStyle.coral)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint("The focused application remains the insertion target.")

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Mode").foregroundStyle(.secondary)
                            Picker("Mode", selection: $model.selectedMode) {
                                ForEach(model.modes, id: \.id) { mode in
                                    Label(mode.name, systemImage: mode.symbol).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Engine").foregroundStyle(.secondary)
                            Picker("Engine", selection: $model.selectedEngine) {
                                ForEach(TranscriptionEngine.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                    .font(.callout)
                    Text(privacyLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            recentHistory
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(width: 380, height: 520)
        .background(.regularMaterial)
        .onAppear(perform: model.refresh)
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NODAYSIDLE")
                    .font(.caption2.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(VoiceStyle.coral)
                Text("Voice")
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            Button(action: model.openControlCenter) {
                Image(systemName: "xmark").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close Control Center")
            .accessibilityLabel("Close Control Center")
        }
    }

    @ViewBuilder private var readiness: some View {
        if model.microphonePermission != .granted {
            SectionCard {
                HStack {
                    PermissionBadge(title: "Microphone", state: model.microphonePermission)
                    Spacer()
                    Button(model.microphonePermission == .notDetermined ? "Allow" : "Open Settings") {
                        if model.microphonePermission == .notDetermined { model.requestPermission(.microphone) }
                        else { model.openPermissionSettings(.microphone) }
                    }
                }
            }
        } else if model.insertionBehavior == .autoPaste, model.accessibilityPermission != .granted {
            SectionCard {
                HStack {
                    PermissionBadge(title: "Auto-paste", state: model.accessibilityPermission)
                    Spacer()
                    Button("Allow") { model.requestPermission(.accessibility) }
                }
            }
        } else {
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(model.statusMessage).font(.caption).lineLimit(2)
                Spacer()
                Text(model.recordingState.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var recentHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("History", action: model.openHistory).buttonStyle(.plain)
            }
            if model.history.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(.secondary)
                    Text("No dictations yet").font(.headline)
                    Text(model.historyEnabled ? "Completed transcripts stay locally on this Mac." : "History is disabled in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .accessibilityElement(children: .combine)
            } else {
                ForEach(model.history.prefix(3)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.isFavorite ? "star.fill" : "text.quote")
                            .foregroundStyle(item.isFavorite ? VoiceStyle.warning : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.preview).font(.callout).lineLimit(1)
                            Text("\(item.sourceApplication) · \(item.modeName)")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { model.copyHistory(item.id) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain)
                            .help("Copy transcript")
                            .accessibilityLabel("Copy transcript")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Transcribe File…", action: model.importAudioFile)
                .buttonStyle(.plain)
            Spacer()
            Button("Settings…") { model.openSettings() }
                .buttonStyle(.plain)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
        }
        .font(.caption)
    }

    private var recording: Bool {
        if case .recording = model.recordingState { return true }
        return false
    }

    private var recordButtonTitle: String {
        switch model.recordingState {
        case .idle, .completed, .failed: "Start dictation"
        case .arming, .recording: "Finish dictation"
        case .transcribing, .refining, .inserting: "Working…"
        }
    }

    private var privacyLine: String {
        let engine = model.selectedMode.engine ?? model.selectedEngine
        return engine.isLocal
            ? "Audio stays on this Mac."
            : "Audio is sent to \(engine.rawValue) only for this transcription."
    }

    private var statusColor: Color {
        switch model.recordingState.capsulePresentation {
        case .ready: .secondary
        case .arming, .processing: VoiceStyle.warning
        case .recording, .error: VoiceStyle.coral
        case .success: VoiceStyle.success
        }
    }
}

struct TranscriptPreviewView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review transcript").font(.title2.weight(.semibold))
                    Text("Nothing is inserted until you confirm.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.dismissPreview) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close without inserting")
            }
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(VoiceStyle.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(VoiceStyle.border) }
                .accessibilityLabel("Completed transcript")
            HStack {
                Button("Keep without inserting", action: model.dismissPreview)
                Spacer()
                Button("Insert at previous cursor") {
                    model.previewText = draft
                    model.confirmPreview()
                }
                .buttonStyle(.borderedProminent)
                .tint(VoiceStyle.coral)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540, height: 330)
        .background(.regularMaterial)
        .onAppear { draft = model.previewText ?? "" }
        .onChange(of: model.previewText) { _, text in draft = text ?? "" }
        .preferredColorScheme(model.appearance.colorScheme)
    }
}
