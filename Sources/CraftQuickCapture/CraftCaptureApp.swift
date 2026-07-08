import SwiftUI

@main
struct CraftQuickCaptureApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (⌘, or menu bar → Préférences…)
        Settings {
            SettingsView(service: appDelegate.craftService)
        }
    }
}
