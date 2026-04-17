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
                ForEach(routingEngine.rules) { rule in
                    HStack(spacing: 6) {
                        appIcon(for: rule.sourceAppBundleID)
                        Text(appName(for: rule.sourceAppBundleID))
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        appIcon(for: rule.targetBrowserBundleID)
                        Text(labelForDestination(rule))
                            .lineLimit(1)
                    }
                    .font(.caption)
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

    private func appIcon(for bundleID: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app")
                    .frame(width: 16, height: 16)
            }
        }
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
