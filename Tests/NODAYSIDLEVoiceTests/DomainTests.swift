import Foundation
import Testing
@testable import NODAYSIDLEVoice

@Test func defaultModesAndLocalModelsRemainAvailable() {
    #expect(DictationMode.defaults.map(\.id) == ["raw", "message", "email", "notes", "code", "formal", "casual"])
    #expect(LocalModel.catalog.map(\.id).contains("large-v3-turbo"))
    #expect(TranscriptionEngine.localWhisper.isLocal)
    #expect(!TranscriptionEngine.deepgram.isLocal)
}

@MainActor
@Test func settingsNavigationDelegatesToTheNativeShell() {
    let suite = "NODAYSIDLEVoiceTests.Settings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    var rememberedTarget = false
    var openedPage: SettingsPage?
    model.rememberTargetAction = { rememberedTarget = true }
    model.settingsHandler = { openedPage = $0 }

    model.openSettings(.privacy)

    #expect(rememberedTarget)
    #expect(model.selectedSettingsPage == .privacy)
    #expect(openedPage == .privacy)
}
