import SwiftUI

@main
struct OpenElsewhereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var routingEngine = RoutingEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(routingEngine)
        } label: {
            // Template-style menu bar icon: a simple compass glyph (SF Symbol
            // renders cleanly in the menu bar with the correct tint).
            Image(systemName: "location.north.line")
        }
        .menuBarExtraStyle(.menu)

        Window("OpenElsewhere", id: "settings") {
            SettingsView()
                .environmentObject(routingEngine)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}
