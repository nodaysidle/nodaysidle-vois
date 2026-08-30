import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    private enum Trigger { case pushToTalk, toggle }
    private struct Job {
        var target: InsertionTarget?
        var mode: DictationMode
        var engine: TranscriptionEngine
        let insertion: InsertionBehavior
        let localModelID: String
        let openRouterModel: String
        let refinementEnabled: Bool
        let refinementModel: String
        let trigger: Trigger
    }

    private let model: AppModel
    private let container: ModelContainer
    private let audio = AudioCaptureService()
    private let localModels = LocalModelManager()
    private let localEngine = LocalWhisperEngine()
    private let router: TranscriptionRouter
    private let refinement = RefinementService()
    private let openRouterCatalog = OpenRouterModelCatalog()
    private let insertion = InsertionService()
    private let permissions = PermissionCoordinator()
    private let keychain = KeychainStore()
    private let historyStore: HistoryStore
    private let vocabularyStore: VocabularyStore
    private let modeStore: ModeStore
    private var hotkeys: HotkeyController!
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var activeJob: Job?
    private var currentRecording: AudioRecording?
    private var recordingTask: Task<Void, Never>?
    private var successTask: Task<Void, Never>?
    private var retentionTask: Task<Void, Never>?
    private var finishWhenArmed = false
    private var lastExternalTarget: InsertionTarget?

    init(model: AppModel, container: ModelContainer) {
        self.model = model
        self.container = container
        historyStore = HistoryStore(container: container)
        vocabularyStore = VocabularyStore(container: container)
        modeStore = ModeStore(container: container)
        router = TranscriptionRouter(localModels: localModels, localEngine: localEngine)
        hotkeys = HotkeyController { [weak self] action in self?.handle(action) }
        connectActions()
    }

    func start() {
        do {
            try VoiceData.seedBuiltInModes(in: container)
            model.modes = try modeStore.modes()
            model.restoreSelectedMode()
            try historyStore.cleanup(retentionDays: model.retentionDays)
            model.history = try historyStore.summaries()
            try registerHotkeys()
        } catch {
            model.statusMessage = error.localizedDescription
        }
        refreshSecurityState()
        Task {
            await refreshInstalledModels()
            preferDeepgramWhenKeyedIfNeeded()
            await warmLocalModelIfNeeded()
            let store = TemporaryAudioStore()
            try? await store.discardExpired(olderThan: .now.addingTimeInterval(-86_400))
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.router.unloadLocalModel()
                self.model.activeModelID = nil
            }
        }
        source.resume()
        memoryPressureSource = source
        retentionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(86_400))
                guard !Task.isCancelled, let self else { return }
                try? self.historyStore.cleanup(retentionDays: self.model.retentionDays)
                self.model.history = (try? self.historyStore.summaries()) ?? self.model.history
            }
        }
        if model.hudEnabled, model.keepHUDVisibleWhenIdle { model.setHUDVisible(true) }
    }

    private func connectActions() {
        model.recordAction = { [weak self] in self?.toggleRecording() }
        model.cancelAction = { [weak self] in self?.cancel() }
        model.retryAction = { [weak self] in self?.retry() }
        model.fallbackAction = { [weak self] in self?.retry(using: $0) }
        model.confirmPreviewAction = { [weak self] in self?.confirmPreview() }
        model.dismissPreviewAction = { [weak self] in self?.dismissPreview() }
        model.downloadModelAction = { [weak self] in self?.download($0) }
        model.removeModelAction = { [weak self] in self?.remove($0) }
        model.importFileAction = { [weak self] in self?.chooseAudioFile() }
        model.refreshAction = { [weak self] in self?.refresh() }
        model.updateHotkeysAction = { [weak self] pushToTalk, toggle in
            self?.updateHotkeys(pushToTalk: pushToTalk, toggle: toggle)
        }
        model.permissionSettingsAction = { [weak self] in self?.permissions.openSettings(for: $0) }
        model.requestPermissionAction = { [weak self] in self?.requestPermission($0) }
        model.refreshOpenRouterCatalogAction = { [weak self] in self?.refreshOpenRouterCatalog() }
        model.chooseVocabularyAction = { [weak self] in self?.chooseVocabularyFile() }
        model.importVocabularyAction = { [weak self] in self?.importVocabulary() }
        model.saveModeAction = { [weak self] in self?.saveMode($0) }
        model.setOutputLanguageAction = { [weak self] in self?.setOutputLanguage($0) }
        model.assignApplicationRuleAction = { [weak self] in self?.chooseApplication(for: $0) }
        model.searchHistoryAction = { [weak self] in self?.searchHistory($0) }
        model.historyTextAction = { [weak self] in try? self?.historyStore.text(for: $0) }
        model.editHistoryAction = { [weak self] id, text in self?.editHistory(id, text: text) }
        model.favoriteHistoryAction = { [weak self] id, favorite in self?.favoriteHistory(id, favorite: favorite) }
        model.deleteHistoryAction = { [weak self] in self?.deleteHistory($0) }
        model.clearHistoryAction = { [weak self] in self?.clearHistory() }
        model.copyHistoryAction = { [weak self] in self?.copyHistory($0) }
        model.repasteHistoryAction = { [weak self] in self?.repasteHistory($0) }
        model.rememberTargetAction = { [weak self] in self?.rememberExternalTarget() }
    }

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .pushToTalkPressed:
            if model.recordingState == .idle { begin(trigger: .pushToTalk) }
        case .pushToTalkReleased:
            guard activeJob?.trigger == .pushToTalk else { return }
            if model.recordingState == .arming { finishWhenArmed = true }
            else if case .recording = model.recordingState { finish() }
        case .togglePressed:
            toggleRecording()
        case .cancelPressed:
            cancel()
        }
    }

    private func toggleRecording() {
        switch model.recordingState {
        case .idle, .completed, .failed:
            begin(trigger: .toggle)
        case .arming:
            finishWhenArmed = true
        case .recording:
            finish()
        case .transcribing, .refining, .inserting:
            break
        }
    }

    private func begin(trigger: Trigger) {
        successTask?.cancel()
        currentRecording = nil
        model.lastCompletedText = nil
        model.previewText = nil
        model.clearInterimTranscript()
        model.audioLevels.removeAll(keepingCapacity: true)
        rememberExternalTarget()
        let target = lastExternalTarget
        var mode = model.selectedMode
        if let ruleID = try? modeStore.modeID(for: target?.bundleIdentifier),
           let ruleMode = model.modes.first(where: { $0.id == ruleID }) {
            mode = ruleMode
        }
        let engine = resolveEngine(for: mode)
        let job = Job(
            target: target,
            mode: mode,
            engine: engine,
            insertion: mode.insertion ?? model.insertionBehavior,
            localModelID: model.selectedLocalModelID,
            openRouterModel: model.openRouterSTTModel,
            refinementEnabled: model.refinementEnabled || !(mode.refinementModel ?? "").isEmpty,
            refinementModel: mode.refinementModel ?? model.refinementModel,
            trigger: trigger
        )
        activeJob = job
        model.activeTranscriptionEngine = job.engine
        try? hotkeys.registerCancel()
        finishWhenArmed = false
        model.recordingState = .arming
        model.statusMessage = "Preparing"
        if model.hudEnabled { model.setHUDVisible(true) }

        let request = transcriptionRequest(for: mode, engine: engine)
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await audio.start { [weak model] level in model?.appendAudioLevel(level) }
                try await router.beginStreamingIfNeeded(
                    engine: job.engine,
                    frames: session.frames,
                    request: request,
                    onInterim: { [weak self] text in
                        Task { @MainActor in
                            guard let self, case .recording = self.model.recordingState else { return }
                            self.model.interimTranscript = text
                        }
                    }
                )
                guard !Task.isCancelled else {
                    try? await audio.cancel()
                    return
                }
                model.recordingState = .recording(startedAt: .now)
                model.statusMessage = "Recording"
                playSound("Tink")
                if finishWhenArmed { finish() }
            } catch {
                try? await audio.cancel()
                fail(error, capturedAudio: false)
            }
        }
    }

    private func resolveEngine(for mode: DictationMode) -> TranscriptionEngine {
        if let modeEngine = mode.engine { return modeEngine }
        return model.selectedEngine
    }

    private func transcriptionRequest(for mode: DictationMode, engine: TranscriptionEngine? = nil) -> TranscriptionRequest {
        let language = OutputLanguage.resolve(mode.outputLanguage)
        let hints = (try? vocabularyStore.hints()) ?? []
        let resolvedEngine = engine ?? mode.engine ?? model.selectedEngine
        let code: String? = switch resolvedEngine {
        case .deepgram: language.deepgramCode
        case .localWhisper, .openRouter: language.whisperCode
        }
        return TranscriptionRequest(
            language: code,
            vocabularyHints: resolvedEngine == .openRouter ? [] : hints
        )
    }

    /// Prefer Deepgram when a key is already saved and the user is still on Local without an installed model.
    private func preferDeepgramWhenKeyedIfNeeded() {
        guard model.deepgramKeySaved else { return }
        guard model.selectedEngine == .localWhisper else { return }
        guard !model.installedModelIDs.contains(model.selectedLocalModelID) else { return }
        model.selectedEngine = .deepgram
    }

    private func warmLocalModelIfNeeded() async {
        let engine = model.selectedMode.engine ?? model.selectedEngine
        guard engine == .localWhisper else { return }
        guard model.installedModelIDs.contains(model.selectedLocalModelID) else { return }
        await router.warmLocalModel(id: model.selectedLocalModelID)
        model.activeModelID = await localEngine.activeModelID
    }

    private func finish() {
        guard let job = activeJob else { return }
        model.recordingState = .transcribing
        model.statusMessage = "Processing"
        model.clearInterimTranscript()
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let recording = try await audio.stop()
                currentRecording = recording
                let result = try await router.finish(
                    recording: recording,
                    engine: job.engine,
                    localModelID: job.localModelID,
                    openRouterModel: job.openRouterModel,
                    request: transcriptionRequest(for: job.mode, engine: job.engine)
                )
                try await finishText(result, recording: recording, job: job)
            } catch {
                if currentRecording == nil { currentRecording = await audio.recoverableRecording }
                fail(error, capturedAudio: currentRecording != nil)
            }
        }
    }

    private func finishText(_ routed: RoutedTranscription, recording: AudioRecording, job: Job) async throws {
        let text = try await processedText(routed.text, job: job)
        model.lastCompletedText = text
        if model.historyEnabled {
            _ = try historyStore.add(
                text: text,
                sourceApplication: job.target?.applicationName ?? "Unknown application",
                sourceBundleIdentifier: job.target?.bundleIdentifier,
                modeID: job.mode.id,
                modeName: job.mode.name,
                engine: job.engine,
                duration: recording.duration,
                cost: routed.cost
            )
            model.history = try historyStore.summaries()
        }
        try await audio.discard(recording)
        currentRecording = nil
        try await deliver(text, job: job)
    }

    private func processedText(_ rawText: String, job: Job) async throws -> String {
        var text = VocabularyImporter.apply(try vocabularyStore.replacements(), to: rawText)
        let languageInstruction = job.mode.outputLanguage == "Automatic"
            ? nil : "Write the result in \(job.mode.outputLanguage)."
        let instruction = [job.mode.instruction, languageInstruction].compactMap { $0 }.joined(separator: " ")
        if job.refinementEnabled, !instruction.isEmpty,
           !job.refinementModel.isEmpty,
           let credential = try keychain.load(account: "openrouter") {
            model.recordingState = .refining
            model.statusMessage = "Processing"
            text = await refinement.refine(
                text,
                instruction: instruction,
                model: job.refinementModel,
                credential: credential
            )
        }
        return text
    }

    private func deliver(_ text: String, job: Job) async throws {
        model.recordingState = .inserting
        let outcome = try await insertion.insert(text, behavior: job.insertion, target: job.target)
        switch outcome {
        case .previewRequired(let text):
            model.previewText = text
            model.recordingState = .completed
            model.statusMessage = "Review before inserting"
            model.previewHandler?(true)
        case .pasted:
            complete(message: "Inserted")
        case .copied:
            complete(message: "Copied")
        }
    }

    private func complete(message: String) {
        hotkeys.unregisterCancel()
        model.recordingState = .completed
        model.statusMessage = message
        playSound("Pop")
        activeJob = nil
        model.activeTranscriptionEngine = nil
        successTask?.cancel()
        successTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            model.recordingState = .idle
            model.statusMessage = "Ready"
            if !model.keepHUDVisibleWhenIdle { model.setHUDVisible(false) }
        }
    }

    private func fail(_ error: Error, capturedAudio: Bool) {
        model.recordingState = .failed(Self.failure(for: error, capturedAudio: capturedAudio))
        model.statusMessage = error.localizedDescription
        if model.hudEnabled { model.setHUDVisible(true) }
        playSound("Basso")
        refreshSecurityState()
    }

    nonisolated static func failure(for error: Error, capturedAudio: Bool) -> DictationFailure {
        if error as? AudioCaptureError == .microphoneDenied { return .microphoneDenied }
        if error as? InsertionError == .accessibilityDenied { return .accessibilityDenied }
        if error as? LocalModelError == .notInstalled { return .modelUnavailable }
        if error as? ProviderError == .rateLimited { return .rateLimited }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet { return .offline }
        if error is ProviderError || error is TranscriptionRouterError { return .providerUnavailable }
        if error is InsertionError { return .insertionFailed }
        return capturedAudio ? .transcriptionFailed : .providerUnavailable
    }

    private func retry() {
        guard let recording = currentRecording, var job = activeJob else {
            if let text = model.lastCompletedText, let job = activeJob {
                Task {
                    do { try await deliver(text, job: job) }
                    catch { fail(error, capturedAudio: false) }
                }
            }
            return
        }
        guard job.engine != .deepgram else {
            model.statusMessage = "Choose Local or OpenRouter to retry saved audio."
            return
        }
        job.engine = model.selectedEngine
        activeJob = job
        model.recordingState = .transcribing
        model.statusMessage = "Processing"
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await router.finish(
                    recording: recording,
                    engine: job.engine,
                    localModelID: model.selectedLocalModelID,
                    openRouterModel: model.openRouterSTTModel,
                    request: transcriptionRequest(for: job.mode, engine: job.engine)
                )
                try await finishText(result, recording: recording, job: job)
            } catch { fail(error, capturedAudio: true) }
        }
    }

    private func retry(using engine: TranscriptionEngine) {
        guard engine != .deepgram else { return }
        model.selectedEngine = engine
        if var job = activeJob { job.engine = engine; activeJob = job }
        retry()
    }

    private func cancel() {
        hotkeys.unregisterCancel()
        recordingTask?.cancel()
        successTask?.cancel()
        let saved = currentRecording
        currentRecording = nil
        activeJob = nil
        model.activeTranscriptionEngine = nil
        finishWhenArmed = false
        model.previewText = nil
        model.clearInterimTranscript()
        model.previewHandler?(false)
        model.recordingState = .idle
        model.statusMessage = "Cancelled"
        model.setHUDVisible(false)
        Task {
            await router.cancel()
            try? await audio.cancel()
            if let saved { try? await audio.discard(saved) }
        }
    }

    private func confirmPreview() {
        guard let text = model.previewText, let job = activeJob else { return }
        model.previewHandler?(false)
        Task {
            do {
                _ = try await insertion.insert(text, behavior: .autoPaste, target: job.target)
                model.previewText = nil
                complete(message: "Inserted")
            } catch { fail(error, capturedAudio: false) }
        }
    }

    private func dismissPreview() {
        model.previewText = nil
        model.previewHandler?(false)
        complete(message: "Saved to history")
    }

    private func download(_ localModel: LocalModel) {
        model.modelDownloadProgress[localModel.id] = 0
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await localModels.download(localModel) { [weak self] progress in
                    Task { @MainActor in self?.model.modelDownloadProgress[localModel.id] = progress }
                }
                model.modelDownloadProgress[localModel.id] = nil
                await refreshInstalledModels()
                await warmLocalModelIfNeeded()
                model.statusMessage = "\(localModel.name) verified"
            } catch {
                model.modelDownloadProgress[localModel.id] = nil
                model.statusMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ localModel: LocalModel) {
        Task { [weak self] in
            guard let self else { return }
            do {
                await router.unloadLocalModel()
                try await localModels.remove(id: localModel.id)
                await refreshInstalledModels()
            } catch { model.statusMessage = error.localizedDescription }
        }
    }

    private func chooseAudioFile() {
        guard (model.selectedMode.engine ?? model.selectedEngine) != .deepgram else {
            model.statusMessage = "Deepgram is live microphone only. Choose Local or OpenRouter for files."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        rememberExternalTarget()
        let target = lastExternalTarget
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.startFileTranscription(url, target: target)
        }
    }

    private func startFileTranscription(_ url: URL, target: InsertionTarget?) {
        try? hotkeys.registerCancel()
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in await self?.transcribeFile(url, target: target) }
    }

    private func transcribeFile(_ url: URL, target: InsertionTarget?) async {
        do {
            let job = Job(
                target: target,
                mode: model.selectedMode,
                engine: model.selectedMode.engine ?? model.selectedEngine,
                insertion: .preview,
                localModelID: model.selectedLocalModelID,
                openRouterModel: model.openRouterSTTModel,
                refinementEnabled: model.refinementEnabled || !(model.selectedMode.refinementModel ?? "").isEmpty,
                refinementModel: model.selectedMode.refinementModel ?? model.refinementModel,
                trigger: .toggle
            )
            activeJob = job
            model.activeTranscriptionEngine = job.engine
            let input = try FileTranscriptionService.preflight(url, engine: job.engine)
            model.recordingState = .transcribing
            model.setHUDVisible(true)
            let routed = try await router.transcribeFile(
                input,
                engine: job.engine,
                localModelID: model.selectedLocalModelID,
                openRouterModel: model.openRouterSTTModel,
                request: transcriptionRequest(for: job.mode, engine: job.engine)
            )
            let text = try await processedText(routed.text, job: job)
            model.lastCompletedText = text
            if model.historyEnabled {
                _ = try historyStore.add(
                    text: text,
                    sourceApplication: url.lastPathComponent,
                    sourceBundleIdentifier: nil,
                    modeID: model.selectedMode.id,
                    modeName: model.selectedMode.name,
                    engine: job.engine,
                    duration: 0,
                    cost: routed.cost
                )
                model.history = try historyStore.summaries()
            }
            model.previewText = text
            model.previewHandler?(true)
            model.recordingState = .completed
            model.statusMessage = "File transcribed"
        } catch { fail(error, capturedAudio: false) }
    }

    private func refresh() {
        do {
            model.history = try historyStore.summaries()
            model.modes = try modeStore.modes()
            if !model.modes.contains(model.selectedMode) { model.restoreSelectedMode() }
        } catch { model.statusMessage = error.localizedDescription }
        refreshSecurityState()
        Task {
            await refreshInstalledModels()
            preferDeepgramWhenKeyedIfNeeded()
            await warmLocalModelIfNeeded()
        }
    }

    private func refreshInstalledModels() async {
        let installed = (try? await localModels.installedModels()) ?? []
        model.installedModelIDs = Set(installed.map(\.modelID))
        model.activeModelID = await localEngine.activeModelID
    }

    private func setOutputLanguage(_ language: OutputLanguage) {
        model.applyOutputLanguage(language)
        do {
            try modeStore.save(model.selectedMode)
            model.modes = try modeStore.modes()
            if let updated = model.modes.first(where: { $0.id == model.selectedMode.id }) {
                model.selectedMode = updated
            }
        } catch {
            model.statusMessage = error.localizedDescription
        }
    }

    private func refreshSecurityState() {
        model.microphonePermission = permissions.state(for: .microphone)
        model.accessibilityPermission = permissions.state(for: .accessibility)
        model.deepgramKeySaved = ((try? keychain.load(account: "deepgram")) ?? nil) != nil
        model.openRouterKeySaved = ((try? keychain.load(account: "openrouter")) ?? nil) != nil
    }

    private func requestPermission(_ permission: SystemPermission) {
        switch permission {
        case .microphone:
            Task {
                _ = await permissions.requestMicrophone()
                refreshSecurityState()
            }
        case .accessibility:
            permissions.requestAccessibilityPrompt()
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                refreshSecurityState()
            }
        }
    }

    private func refreshOpenRouterCatalog() {
        model.openRouterCatalogStatus = "Loading compatible models…"
        Task {
            do {
                guard let credential = try keychain.load(account: "openrouter"), !credential.isEmpty else {
                    throw ProviderError.missingCredential
                }
                model.openRouterSTTModels = try await openRouterCatalog.models(credential: credential)
                model.openRouterCatalogStatus = model.openRouterSTTModels.isEmpty
                    ? "No transcription models are currently listed."
                    : "Compatible catalog refreshed."
            } catch {
                model.openRouterCatalogStatus = error.localizedDescription
            }
        }
    }

    private func chooseVocabularyFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let preview = try VocabularyImporter.preview(Data(contentsOf: url, options: .mappedIfSafe))
                self?.model.vocabularyPreview = preview
                self?.model.vocabularyConflictChoices = [:]
                self?.model.vocabularyStatus = "Review the source counts and resolve every conflict before import."
            } catch {
                self?.model.vocabularyStatus = error.localizedDescription
            }
        }
    }

    private func importVocabulary() {
        guard let preview = model.vocabularyPreview else { return }
        do {
            let resolved = try VocabularyImporter.resolving(preview, choices: model.vocabularyConflictChoices)
            guard resolved.conflicts.isEmpty else { throw VocabularyImportError.unresolvedConflicts }
            let inserted = try vocabularyStore.importPreview(resolved)
            model.vocabularyPreview = resolved
            model.vocabularyStatus = "Imported \(inserted.vocabulary) hints and \(inserted.replacements) replacements. The source file was retained."
        } catch {
            model.vocabularyStatus = error.localizedDescription
        }
    }

    private func saveMode(_ mode: DictationMode) {
        do {
            try modeStore.save(mode)
            model.modes = try modeStore.modes()
            model.selectedMode = model.modes.first { $0.id == mode.id } ?? mode
            model.statusMessage = "\(mode.name) saved"
        } catch {
            model.statusMessage = error.localizedDescription
        }
    }

    private func chooseApplication(for mode: DictationMode) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url,
                  let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else { return }
            do {
                try self?.modeStore.setRule(bundleIdentifier: bundleIdentifier, modeID: mode.id)
                self?.model.statusMessage = "\(mode.name) is now the default for \(url.deletingPathExtension().lastPathComponent)."
            } catch {
                self?.model.statusMessage = error.localizedDescription
            }
        }
    }

    private func searchHistory(_ query: String) {
        do {
            model.historySearch = query
            model.history = try historyStore.summaries(search: query)
        } catch { model.statusMessage = error.localizedDescription }
    }

    private func editHistory(_ id: UUID, text: String) {
        do {
            try historyStore.edit(id, text: text)
            searchHistory(model.historySearch)
        } catch { model.statusMessage = error.localizedDescription }
    }

    private func favoriteHistory(_ id: UUID, favorite: Bool) {
        do {
            try historyStore.setFavorite(id, favorite)
            searchHistory(model.historySearch)
        } catch { model.statusMessage = error.localizedDescription }
    }

    private func deleteHistory(_ id: UUID) {
        do {
            try historyStore.delete(id)
            searchHistory(model.historySearch)
        } catch { model.statusMessage = error.localizedDescription }
    }

    private func clearHistory() {
        do {
            try historyStore.clear()
            model.history = []
            model.statusMessage = "History cleared"
        } catch { model.statusMessage = error.localizedDescription }
    }

    private func copyHistory(_ id: UUID) {
        do {
            let text = try historyStore.text(for: id)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            model.statusMessage = "Transcript copied"
        } catch { model.statusMessage = error.localizedDescription }
    }

    private func repasteHistory(_ id: UUID) {
        guard let target = lastExternalTarget else {
            model.statusMessage = "Focus the destination app before opening History."
            return
        }
        Task {
            do {
                let text = try historyStore.text(for: id)
                _ = try await insertion.insert(text, behavior: .autoPaste, target: target)
                model.statusMessage = "Transcript inserted"
            } catch { fail(error, capturedAudio: false) }
        }
    }

    private func rememberExternalTarget() {
        guard let target = insertion.captureTarget(),
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalTarget = target
    }

    private func updateHotkeys(pushToTalk: HotkeyDescriptor, toggle: HotkeyDescriptor) {
        guard pushToTalk != toggle else {
            model.hotkeyStatus = "Push-to-talk and toggle shortcuts must be different."
            return
        }
        let oldPushToTalk = model.pushToTalkHotkey
        let oldToggle = model.toggleHotkey
        do {
            try hotkeys.register(pushToTalk: pushToTalk, toggle: toggle)
            if model.recordingState != .idle { try? hotkeys.registerCancel() }
            model.applyRegisteredHotkeys(pushToTalk: pushToTalk, toggle: toggle)
            model.hotkeyStatus = "\(pushToTalk.displayName) hold · \(toggle.displayName) toggle"
        } catch {
            try? hotkeys.register(pushToTalk: oldPushToTalk, toggle: oldToggle)
            if model.recordingState != .idle { try? hotkeys.registerCancel() }
            model.hotkeyStatus = "Shortcut unavailable; the previous shortcuts remain active."
        }
    }

    private func playSound(_ name: String) {
        guard model.soundsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func registerHotkeys() throws {
        guard model.pushToTalkHotkey != model.toggleHotkey else {
            model.hotkeyStatus = "Shortcuts must be different."
            throw HotkeyRegistrationError.conflict("duplicate shortcuts")
        }
        try hotkeys.register(pushToTalk: model.pushToTalkHotkey, toggle: model.toggleHotkey)
        model.applyRegisteredHotkeys(pushToTalk: model.pushToTalkHotkey, toggle: model.toggleHotkey)
        model.hotkeyStatus = "\(model.pushToTalkHotkey.displayName) hold · \(model.toggleHotkey.displayName) toggle"
    }
}
