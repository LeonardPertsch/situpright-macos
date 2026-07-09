import SwiftUI

/// Entry point. This is a menu-bar-only utility, so there is no main window scene.
/// The `Settings` scene is empty and never shown; all UI lives in the popover that
/// `MenuBarController` presents from the status item.
@main
struct PostureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
