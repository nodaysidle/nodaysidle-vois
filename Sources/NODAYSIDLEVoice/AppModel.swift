import AppKit
import Foundation
import Observation
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case hotkeys = "Hotkeys"
    case providers = "Providers"
    case models = "Local Models"
    case modes = "Modes"
    case vocabulary = "Vocabulary"
    case history = "History"
    case privacy = "Privacy"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .hotkeys: "keyboard"
        case .providers: "cloud"
        case .models: "internaldrive"
        case .modes: "slider.horizontal.3"
        case .vocabulary: "character.book.closed"
        case .history: "clock.arrow.circlepath"
        case .privacy: "hand.raised"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark = "Dark"
    case light = "Light"
    case system = "System"
    var id: String { rawValue }
}

private enum PreferenceKey {
    static let appearance = "appearance"
    static let engine = "transcriptionEngine"
    static let insertion = "insertionBehavior"
    static let mode = "selectedModeID"
    static let localModel = "selectedLocalModelID"
    static let openRouterModel = "openRouterSTTModel"
    static let refinementEnabled = "refinementEnabled"
    static let refinementModel = "refinementModel"
    static let historyEnabled = "historyEnabled"
    static let retentionDays = "retentionDays"
    static let hudEnabled = "hudEnabled"
    static let keepHUDVisible = "keepHUDVisibleWhenIdle"
    static let soundsEnabled = "soundsEnabled"
    static let pushToTalk = "pushToTalkHotkey"
    static let toggle = "toggleHotkey"
}

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var hudVisibilityHandler: ((Bool) -> Void)?
    @ObservationIgnored var hudWidthHandler: ((CGFloat) -> Void)?
    @ObservationIgnored var controlCenterHandler: (() -> Void)?
    @ObservationIgnored var settingsHandler: ((SettingsPage) -> Void)?
    @ObservationIgnored var previewHandler: ((Bool) -> Void)?
    @ObservationIgnored var recordAction: (() -> Void)?
    @ObservationIgnored var cancelAction: (() -> Void)?
    @ObservationIgnored var retryAction: (() -> Void)?
    @ObservationIgnored var fallbackAction: ((TranscriptionEngine) -> Void)?
    @ObservationIgnored var confirmPreviewAction: (() -> Void)?
    @ObservationIgnored var dismissPreviewAction: (() -> Void)?
    @ObservationIgnored var downloadModelAction: ((LocalModel) -> Void)?
    @ObservationIgnored var removeModelAction: ((LocalModel) -> Void)?
    @ObservationIgnored var importFileAction: (() -> Void)?
    @ObservationIgnored var refreshAction: (() -> Void)?
    @ObservationIgnored var updateHotkeysAction: ((HotkeyDescriptor, HotkeyDescriptor) -> Void)?
    @ObservationIgnored var permissionSettingsAction: ((SystemPermission) -> Void)?
    @ObservationIgnored var requestPermissionAction: ((SystemPermission) -> Void)?
    @ObservationIgnored var refreshOpenRouterCatalogAction: (() -> Void)?
    @ObservationIgnored var chooseVocabularyAction: (() -> Void)?
    @ObservationIgnored var importVocabularyAction: (() -> Void)?
    @ObservationIgnored var saveModeAction: ((DictationMode) -> Void)?
    @ObservationIgnored var setOutputLanguageAction: ((OutputLanguage) -> Void)?
    @ObservationIgnored var assignApplicationRuleAction: ((DictationMode) -> Void)?
    @ObservationIgnored var searchHistoryAction: ((String) -> Void)?
    @ObservationIgnored var historyTextAction: ((UUID) -> String?)?
    @ObservationIgnored var editHistoryAction: ((UUID, String) -> Void)?
    @ObservationIgnored var favoriteHistoryAction: ((UUID, Bool) -> Void)?
    @ObservationIgnored var deleteHistoryAction: ((UUID) -> Void)?
    @ObservationIgnored var clearHistoryAction: (() -> Void)?
    @ObservationIgnored var copyHistoryAction: ((UUID) -> Void)?
    @ObservationIgnored var repasteHistoryAction: ((UUID) -> Void)?
    @ObservationIgnored var rememberTargetAction: (() -> Void)?
    @ObservationIgnored var prepareEngineAction: (() -> Void)?

    var recordingState: RecordingState = .idle
    /// Engine for the in-flight job; used for Deepgram-only live capsule words.
    var activeTranscriptionEngine: TranscriptionEngine?
    var selectedMode: DictationMode {
        didSet { defaults.set(selectedMode.id, forKey: PreferenceKey.mode) }
    }
    var selectedEngine: TranscriptionEngine {
        didSet {
            defaults.set(selectedEngine.rawValue, forKey: PreferenceKey.engine)
            prepareEngineAction?()
        }
    }
    var insertionBehavior: InsertionBehavior {
        didSet { defaults.set(insertionBehavior.rawValue, forKey: PreferenceKey.insertion) }
    }
    var selectedLocalModelID: String {
        didSet {
            defaults.set(selectedLocalModelID, forKey: PreferenceKey.localModel)
            prepareEngineAction?()
        }
    }
    var openRouterSTTModel: String {
        didSet { defaults.set(openRouterSTTModel, forKey: PreferenceKey.openRouterModel) }
    }
    var refinementEnabled: Bool {
        didSet { defaults.set(refinementEnabled, forKey: PreferenceKey.refinementEnabled) }
    }
    var refinementModel: String {
        didSet { defaults.set(refinementModel, forKey: PreferenceKey.refinementModel) }
    }
    var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: PreferenceKey.historyEnabled) }
    }
    var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: PreferenceKey.retentionDays) }
    }
    var hudEnabled: Bool {
        didSet {
            defaults.set(hudEnabled, forKey: PreferenceKey.hudEnabled)
            if !hudEnabled { setHUDVisible(false) }
        }
    }
    var keepHUDVisibleWhenIdle: Bool {
        didSet { defaults.set(keepHUDVisibleWhenIdle, forKey: PreferenceKey.keepHUDVisible) }
    }
    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: PreferenceKey.soundsEnabled) }
    }
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: PreferenceKey.appearance) }
    }

    var modes = DictationMode.defaults
    let localModels = LocalModel.catalog
    var installedModelIDs: Set<String> = []
    var activeModelID: String?
    var modelDownloadProgress: [String: Double] = [:]
    var history: [HistorySummary] = []
    var historySearch = ""
    var showHUD = false
    var audioLevels: [Float] = []
    /// Live interim words from Deepgram only. Never inserted/pasted.
    var interimTranscript = ""
    var statusMessage = "Ready"
    var lastCompletedText: String?
    var previewText: String?
    private(set) var pushToTalkHotkey: HotkeyDescriptor
    private(set) var toggleHotkey: HotkeyDescriptor
    var hotkeyStatus = "Global shortcuts are ready."
    var microphonePermission: PermissionState = .notDetermined
    var accessibilityPermission: PermissionState = .denied
    var deepgramKeySaved = false
    var openRouterKeySaved = false
    var openRouterSTTModels: [OpenRouterCatalogModel] = []
    var openRouterCatalogStatus = "Refresh after saving a key to discover compatible models."
    var vocabularyPreview: VocabularyImportPreview?
    var vocabularyConflictChoices: [String: String] = [:]
    var vocabularyStatus = "No migration selected."
    var selectedSettingsPage = SettingsPage.general

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let modeID = defaults.string(forKey: PreferenceKey.mode) ?? DictationMode.defaults[0].id
        selectedMode = DictationMode.defaults.first { $0.id == modeID } ?? DictationMode.defaults[0]
        selectedEngine = TranscriptionEngine(rawValue: defaults.string(forKey: PreferenceKey.engine) ?? "") ?? .localWhisper
        insertionBehavior = InsertionBehavior(rawValue: defaults.string(forKey: PreferenceKey.insertion) ?? "") ?? .autoPaste
        selectedLocalModelID = defaults.string(forKey: PreferenceKey.localModel) ?? "base"
        openRouterSTTModel = defaults.string(forKey: PreferenceKey.openRouterModel) ?? "openai/whisper-large-v3"
        refinementEnabled = defaults.object(forKey: PreferenceKey.refinementEnabled) as? Bool ?? false
        refinementModel = defaults.string(forKey: PreferenceKey.refinementModel) ?? ""
        historyEnabled = defaults.object(forKey: PreferenceKey.historyEnabled) as? Bool ?? true
        let savedRetention = defaults.object(forKey: PreferenceKey.retentionDays) as? Int ?? 30
        retentionDays = [0, 7, 30, 90, 365].contains(savedRetention) ? savedRetention : 30
        hudEnabled = defaults.object(forKey: PreferenceKey.hudEnabled) as? Bool ?? true
        keepHUDVisibleWhenIdle = defaults.object(forKey: PreferenceKey.keepHUDVisible) as? Bool ?? true
        soundsEnabled = defaults.object(forKey: PreferenceKey.soundsEnabled) as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: PreferenceKey.appearance) ?? "") ?? .dark
        pushToTalkHotkey = Self.savedHotkey(PreferenceKey.pushToTalk, defaults: defaults) ?? .pushToTalk
        toggleHotkey = Self.savedHotkey(PreferenceKey.toggle, defaults: defaults) ?? .toggle
    }

    func toggleRecording() { recordAction?() }
    func cancelRecording() { cancelAction?() }
    func retry() { retryAction?() }
    func useFallback(_ engine: TranscriptionEngine) { fallbackAction?(engine) }
    func confirmPreview() { confirmPreviewAction?() }
    func dismissPreview() { dismissPreviewAction?() }
    func importAudioFile() { importFileAction?() }
    func refresh() { refreshAction?() }
    func updateHotkeys(pushToTalk: HotkeyDescriptor, toggle: HotkeyDescriptor) {
        updateHotkeysAction?(pushToTalk, toggle)
    }
    func openPermissionSettings(_ permission: SystemPermission) { permissionSettingsAction?(permission) }
    func requestPermission(_ permission: SystemPermission) { requestPermissionAction?(permission) }
    func refreshOpenRouterCatalog() { refreshOpenRouterCatalogAction?() }
    func download(_ model: LocalModel) { downloadModelAction?(model) }
    func remove(_ model: LocalModel) { removeModelAction?(model) }
    func chooseVocabularyFile() { chooseVocabularyAction?() }
    func importVocabulary() { importVocabularyAction?() }
    func saveMode(_ mode: DictationMode) { saveModeAction?(mode) }
    func assignApplicationRule(_ mode: DictationMode) { assignApplicationRuleAction?(mode) }
    func searchHistory(_ query: String) { searchHistoryAction?(query) }
    func historyText(for id: UUID) -> String? { historyTextAction?(id) }
    func editHistory(_ id: UUID, text: String) { editHistoryAction?(id, text) }
    func setHistoryFavorite(_ id: UUID, _ favorite: Bool) { favoriteHistoryAction?(id, favorite) }
    func deleteHistory(_ id: UUID) { deleteHistoryAction?(id) }
    func clearHistory() { clearHistoryAction?() }
    func copyHistory(_ id: UUID) { copyHistoryAction?(id) }
    func repasteHistory(_ id: UUID) { repasteHistoryAction?(id) }

    func applyRegisteredHotkeys(pushToTalk: HotkeyDescriptor, toggle: HotkeyDescriptor) {
        pushToTalkHotkey = pushToTalk
        toggleHotkey = toggle
        saveHotkey(pushToTalk, key: PreferenceKey.pushToTalk)
        saveHotkey(toggle, key: PreferenceKey.toggle)
    }

    func restoreSelectedMode() {
        let id = defaults.string(forKey: PreferenceKey.mode) ?? selectedMode.id
        selectedMode = modes.first { $0.id == id } ?? modes.first ?? DictationMode.defaults[0]
    }

    var outputLanguage: OutputLanguage {
        OutputLanguage.resolve(selectedMode.outputLanguage)
    }

    func setOutputLanguage(_ language: OutputLanguage) {
        if let setOutputLanguageAction {
            setOutputLanguageAction(language)
            return
        }
        applyOutputLanguage(language)
    }

    func applyOutputLanguage(_ language: OutputLanguage) {
        let mode = selectedMode
        selectedMode = DictationMode(
            id: mode.id,
            name: mode.name,
            symbol: mode.symbol,
            instruction: mode.instruction,
            outputLanguage: language.rawValue,
            engine: mode.engine,
            refinementModel: mode.refinementModel,
            insertion: mode.insertion
        )
        if let index = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[index] = selectedMode
        }
    }

    func setHUDVisible(_ visible: Bool) {
        showHUD = visible
        hudVisibilityHandler?(visible)
    }

    func resizeHUD(to width: CGFloat) { hudWidthHandler?(width) }

    func appendAudioLevel(_ level: Float) {
        if audioLevels.count == 13 { audioLevels.removeFirst() }
        audioLevels.append(min(max(level, 0), 1))
    }

    func clearInterimTranscript() { interimTranscript = "" }

    func openControlCenter() {
        rememberTargetAction?()
        controlCenterHandler?()
    }
    func openHistory() { openSettings(.history) }

    func openSettings(_ page: SettingsPage = .general) {
        rememberTargetAction?()
        selectedSettingsPage = page
        settingsHandler?(page)
    }

    private static func savedHotkey(_ key: String, defaults: UserDefaults) -> HotkeyDescriptor? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyDescriptor.self, from: data)
    }

    private func saveHotkey(_ descriptor: HotkeyDescriptor, key: String) {
        if let data = try? JSONEncoder().encode(descriptor) { defaults.set(data, forKey: key) }
    }
}
