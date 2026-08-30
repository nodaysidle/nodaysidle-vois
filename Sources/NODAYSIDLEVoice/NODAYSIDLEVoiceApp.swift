import SwiftUI

@main
struct NODAYSIDLEVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.model)
                .preferredColorScheme(appDelegate.model.appearance.colorScheme)
        }
    }
}
