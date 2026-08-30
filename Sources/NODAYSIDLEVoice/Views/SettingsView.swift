import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $model.selectedSettingsPage) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            detail
        }
        .frame(width: 980, height: 680)
        .preferredColorScheme(model.appearance.colorScheme)
        .onAppear(perform: model.refresh)
    }

    @ViewBuilder private var detail: some View {
        if model.selectedSettingsPage == .history {
            HistorySettingsView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.selectedSettingsPage.rawValue)
                        .font(.largeTitle.weight(.semibold))
                    page
                }
                .padding(28)
                .frame(maxWidth: 740, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch model.selectedSettingsPage {
        case .general: GeneralSettingsView()
        case .hotkeys: HotkeySettingsView()
        case .providers: ProviderSettingsView()
        case .models: LocalModelSettingsView()
        case .modes: ModeSettingsView()
        case .vocabulary: VocabularySettingsView()
        case .history: EmptyView()
        case .privacy: PrivacySettingsView()
        }
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("After dictation", selection: $model.insertionBehavior) {
                        ForEach(InsertionBehavior.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Show the floating capsule", isOn: $model.hudEnabled)
                    Toggle("Keep the capsule visible while idle", isOn: $model.keepHUDVisibleWhenIdle)
                        .disabled(!model.hudEnabled)
                    Toggle("Play start, finish, and error sounds", isOn: $model.soundsEnabled)
                }
            }
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Keep local transcript history", isOn: $model.historyEnabled)
                    Picker("Delete history after", selection: $model.retentionDays) {
                        Text("Never").tag(0)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    .disabled(!model.historyEnabled)
                }
            }
        }
    }
}

private struct HotkeySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HotkeyRow(title: "Push to talk", descriptor: model.pushToTalkHotkey) { descriptor in
                    model.updateHotkeys(pushToTalk: descriptor, toggle: model.toggleHotkey)
                }
                Divider()
                HotkeyRow(title: "Start / stop", descriptor: model.toggleHotkey) { descriptor in
                    model.updateHotkeys(pushToTalk: model.pushToTalkHotkey, toggle: descriptor)
                }
                Text(model.hotkeyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Escape cancels only while a dictation or retry is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HotkeyRow: View {
    let title: String
    let descriptor: HotkeyDescriptor
    let onChange: (HotkeyDescriptor) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(title == "Push to talk" ? "Hold while speaking, then release." : "Press once to start and once to finish.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HotkeyRecorder(descriptor: descriptor, onChange: onChange)
                .frame(width: 150, height: 30)
                .accessibilityLabel("\(title) shortcut")
        }
    }
}

private struct HotkeyRecorder: NSViewRepresentable {
    let descriptor: HotkeyDescriptor
    let onChange: (HotkeyDescriptor) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        let button = HotkeyRecorderButton()
        button.onCapture = onChange
        button.setDescriptor(descriptor)
        return button
    }

    func updateNSView(_ button: HotkeyRecorderButton, context: Context) {
        button.onCapture = onChange
        if button.window?.firstResponder !== button { button.setDescriptor(descriptor) }
    }
}

private final class HotkeyRecorderButton: NSButton {
    var onCapture: ((HotkeyDescriptor) -> Void)?
    private var descriptor = HotkeyDescriptor.pushToTalk

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginCapture)
        focusRingType = .default
    }

    required init?(coder: NSCoder) { nil }

    func setDescriptor(_ descriptor: HotkeyDescriptor) {
        self.descriptor = descriptor
        title = descriptor.displayName
    }

    @objc private func beginCapture() {
        window?.makeFirstResponder(self)
        title = "Press shortcut…"
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = HotkeyDescriptor.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            title = "Add a modifier"
            return
        }
        let captured = HotkeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        setDescriptor(captured)
        onCapture?(captured)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        title = descriptor.displayName
        return super.resignFirstResponder()
    }
}

private struct ProviderSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            CredentialCard(
                title: "Deepgram",
                detail: "Nova-3 live microphone streaming",
                account: "deepgram",
                isSaved: model.deepgramKeySaved
            )
            CredentialCard(
                title: "OpenRouter",
                detail: "Buffered speech-to-text and optional refinement",
                account: "openrouter",
                isSaved: model.openRouterKeySaved
            )
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("OpenRouter models").font(.headline)
                        Spacer()
                        Button("Refresh compatible models", action: model.refreshOpenRouterCatalog)
                            .disabled(!model.openRouterKeySaved)
                    }
                    if !model.openRouterSTTModels.isEmpty {
                        Picker("Speech-to-text model", selection: $model.openRouterSTTModel) {
                            ForEach(model.openRouterSTTModels) { Text($0.name).tag($0.id) }
                        }
                    }
                    TextField("Speech-to-text model ID", text: $model.openRouterSTTModel)
                    Text(model.openRouterCatalogStatus).font(.caption).foregroundStyle(.secondary)
                    Toggle("Refine completed transcripts", isOn: $model.refinementEnabled)
                    TextField("Text model ID", text: $model.refinementModel)
                        .disabled(!model.refinementEnabled)
                    Text("Cloud audio or text leaves this Mac only for the active request. Credentials stay in Keychain and are never stored with history.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CredentialCard: View {
    @Environment(AppModel.self) private var model
    let title: String
    let detail: String
    let account: String
    let isSaved: Bool
    @State private var key = ""
    @State private var status = ""
    private let keychain = KeychainStore()

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(isSaved ? "Saved" : "Not configured", systemImage: isSaved ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSaved ? VoiceStyle.success : .secondary)
                }
                SecureField("API key", text: $key)
                    .textContentType(.password)
                HStack {
                    Button("Save to Keychain") { save() }.disabled(key.isEmpty)
                    Button("Remove", role: .destructive) { remove() }.disabled(!isSaved)
                    if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func save() {
        do {
            try keychain.save(key, account: account)
            key = ""
            status = "Saved securely."
            model.refresh()
        } catch { status = error.localizedDescription }
    }

    private func remove() {
        do {
            try keychain.delete(account: account)
            key = ""
            status = "Removed."
            model.refresh()
        } catch { status = error.localizedDescription }
    }
}

private struct LocalModelSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloads are explicit, validated, and stored in Application Support. One model can be resident at a time.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(model.localModels, id: \.id) { localModel in
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(localModel.name).font(.headline)
                                    if model.selectedLocalModelID == localModel.id {
                                        Text("SELECTED").font(.caption2.weight(.bold)).foregroundStyle(VoiceStyle.coral)
                                    }
                                    if model.activeModelID == localModel.id {
                                        Text("LOADED").font(.caption2.weight(.bold)).foregroundStyle(VoiceStyle.success)
                                    }
                                }
                                Text("\(localModel.detail) · \(localModel.size)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Source: argmaxinc/whisperkit-coreml")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.installedModelIDs.contains(localModel.id) {
                                Button("Use") { model.selectedLocalModelID = localModel.id }
                                    .disabled(model.selectedLocalModelID == localModel.id)
                                Button("Remove", role: .destructive) { model.remove(localModel) }
                            } else {
                                Button("Download") { model.download(localModel) }
                            }
                        }
                        if let progress = model.modelDownloadProgress[localModel.id] {
                            ProgressView(value: progress) { Text("Downloading and validating") }
                                .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                }
            }
        }
    }
}

private struct ModeSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedModeID = "raw"
    @State private var name = ""
    @State private var instruction = ""
    @State private var outputLanguage = "Automatic"
    @State private var engine = ""
    @State private var insertion = ""
    @State private var refinementModel = ""

    var body: some View {
        VStack(spacing: 14) {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode", selection: $selectedModeID) {
                        ForEach(model.modes, id: \.id) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                    }
                    if let selectedMode {
                        Text(selectedMode.instruction ?? "No refinement instruction; the raw transcript is preserved.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Use for an application…") { model.assignApplicationRule(selectedMode) }
                    }
                }
            }
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("New custom mode").font(.headline)
                    TextField("Name", text: $name)
                    TextField("Output language", text: $outputLanguage)
                    TextField("Instruction", text: $instruction, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Transcription engine", selection: $engine) {
                        Text("Use current engine").tag("")
                        ForEach(TranscriptionEngine.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Insertion", selection: $insertion) {
                        Text("Use General setting").tag("")
                        ForEach(InsertionBehavior.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    TextField("Optional OpenRouter refinement model", text: $refinementModel)
                    HStack {
                        Spacer()
                        Button("Save mode") { save() }
                            .buttonStyle(.borderedProminent)
                            .tint(VoiceStyle.coral)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .onAppear { selectedModeID = model.selectedMode.id }
    }

    private var selectedMode: DictationMode? { model.modes.first { $0.id == selectedModeID } }

    private func save() {
        let mode = DictationMode(
            id: "custom-\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: "slider.horizontal.3",
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            outputLanguage: outputLanguage.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Automatic",
            engine: TranscriptionEngine(rawValue: engine),
            refinementModel: refinementModel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            insertion: InsertionBehavior(rawValue: insertion)
        )
        model.saveMode(mode)
        selectedModeID = mode.id
        name = ""
        instruction = ""
        refinementModel = ""
    }
}

private struct VocabularySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Import vocabulary migration").font(.headline)
                            Text("Choose the private JSON file explicitly. It is read locally, never bundled, and never deleted.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose JSON…", action: model.chooseVocabularyFile)
                    }
                    Text(model.vocabularyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let preview = model.vocabularyPreview {
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Source vocabulary", value: String(preview.sourceVocabularyCount))
                        LabeledContent("Source replacements", value: String(preview.sourceReplacementCount))
                        LabeledContent("Duplicate vocabulary", value: String(preview.duplicateVocabularyCount))
                        LabeledContent("Conflicts to resolve", value: String(preview.conflicts.count))
                    }
                }
                if !preview.conflicts.isEmpty {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Resolve replacement conflicts").font(.headline)
                            ForEach(preview.conflicts, id: \.original) { conflict in
                                Picker(
                                    conflict.original,
                                    selection: Binding(
                                        get: { model.vocabularyConflictChoices[conflict.original] ?? "" },
                                        set: { model.vocabularyConflictChoices[conflict.original] = $0 }
                                    )
                                ) {
                                    Text("Choose…").tag("")
                                    ForEach(conflict.replacements, id: \.self) { Text($0).tag($0) }
                                }
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Import verified entries", action: model.importVocabulary)
                        .buttonStyle(.borderedProminent)
                        .tint(VoiceStyle.coral)
                        .disabled(!allConflictsResolved(preview))
                }
            }
        }
    }

    private func allConflictsResolved(_ preview: VocabularyImportPreview) -> Bool {
        preview.conflicts.allSatisfy { !$0.replacements.isEmpty && $0.replacements.contains(model.vocabularyConflictChoices[$0.original] ?? "") }
    }
}

private struct HistorySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var draft = ""
    @State private var showClearConfirmation = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("History").font(.largeTitle.weight(.semibold))
                Spacer()
                Toggle("Keep history", isOn: $model.historyEnabled).toggleStyle(.switch)
                Button("Clear…", role: .destructive) { showClearConfirmation = true }
                    .disabled(model.history.isEmpty)
            }
            TextField("Search transcripts", text: $model.historySearch)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.historySearch) { _, query in model.searchHistory(query) }

            if model.history.isEmpty {
                ContentUnavailableView(
                    "No matching transcripts",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(model.historyEnabled ? "Completed dictations will appear here." : "Turn on local history to save future transcripts.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(model.history, selection: $selection) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.sourceApplication).font(.headline).lineLimit(1)
                                Spacer()
                                if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(VoiceStyle.warning) }
                            }
                            Text(item.preview).lineLimit(2)
                            Text("\(item.modeName) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                    .frame(minWidth: 270, idealWidth: 310)

                    VStack(alignment: .leading, spacing: 12) {
                        if let selection, let item = model.history.first(where: { $0.id == selection }) {
                            TextEditor(text: $draft)
                                .font(.body)
                                .padding(8)
                                .background(VoiceStyle.card, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel("Transcript text")
                            HStack {
                                Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                                    model.setHistoryFavorite(item.id, !item.isFavorite)
                                }
                                Button("Copy") { model.copyHistory(item.id) }
                                Button("Re-paste") { model.repasteHistory(item.id) }
                                Spacer()
                                Button("Delete", role: .destructive) { model.deleteHistory(item.id); self.selection = nil }
                                Button("Save") { model.editHistory(item.id, text: draft) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            ContentUnavailableView("Select a transcript", systemImage: "text.quote")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.leading, 12)
                    .frame(minWidth: 360)
                }
            }
        }
        .padding(28)
        .onChange(of: selection) { _, id in draft = id.flatMap(model.historyText) ?? "" }
        .confirmationDialog("Clear all transcript history?", isPresented: $showClearConfirmation) {
            Button("Clear History", role: .destructive, action: model.clearHistory)
        } message: {
            Text("This deletes locally stored transcript text and cannot be undone.")
        }
    }
}

private struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    permissionRow("Microphone", permission: .microphone, state: model.microphonePermission)
                    Divider()
                    permissionRow("Accessibility for auto-paste", permission: .accessibility, state: model.accessibilityPermission)
                }
            }
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Provider keys are stored only in macOS Keychain.", systemImage: "key.fill")
                    Label("Local transcription stays offline after an explicit model download.", systemImage: "macbook")
                    Label("Cloud audio is sent only to the engine selected for the active request.", systemImage: "cloud")
                    Label("Temporary audio is deleted after success or discard; completed history stores no audio.", systemImage: "trash")
                    Label("No account, analytics, background daemon, or mandatory backend.", systemImage: "hand.raised.fill")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(_ title: String, permission: SystemPermission, state: PermissionState) -> some View {
        HStack {
            PermissionBadge(title: title, state: state)
            Spacer()
            if state == .notDetermined {
                Button("Allow") { model.requestPermission(permission) }
            } else if state != .granted {
                Button("Open System Settings") { model.openPermissionSettings(permission) }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
