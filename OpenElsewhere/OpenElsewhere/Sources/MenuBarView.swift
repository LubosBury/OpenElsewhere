import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var routingEngine: RoutingEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Route links through OpenElsewhere", isOn: $routingEngine.isEnabled)

            Divider()

            if routingEngine.rules.isEmpty {
                Text("No rules configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // In `.menuBarExtraStyle(.menu)` each top-level view becomes a
                // separate NSMenuItem, so an HStack of icons/text ends up
                // stacked vertically. Fold each rule into a single `Text`
                // (with inline `Image` interpolation) so NSMenu renders it as
                // one menu item on a single line.
                ForEach(routingEngine.rules) { rule in
                    ruleText(for: rule)
                }
            }

            Divider()

            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit OpenElsewhere") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(4)
    }

    private func ruleText(for rule: RoutingRule) -> Text {
        iconText(for: rule.sourceAppBundleID)
            + Text("  \(appName(for: rule.sourceAppBundleID))   →   ")
            + iconText(for: rule.targetBrowserBundleID)
            + Text("  \(labelForDestination(rule))")
    }

    private func iconText(for bundleID: String) -> Text {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return Text(Image(nsImage: icon))
        }
        return Text(Image(systemName: "app"))
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func labelForDestination(_ rule: RoutingRule) -> String {
        let browserName = appName(for: rule.targetBrowserBundleID)
        if let profile = rule.profileDirectoryName,
           let match = ProfileDiscovery.profiles(forBrowser: rule.targetBrowserBundleID)
            .first(where: { $0.directoryName == profile }) {
            return "\(browserName) · \(match.displayName)"
        }
        return browserName
    }
}
