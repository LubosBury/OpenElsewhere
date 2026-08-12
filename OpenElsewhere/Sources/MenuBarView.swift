import AppKit
import SwiftUI

/// The menu-bar panel.
///
/// Structurally what it always was — master switch, the rules, Settings, Quit
/// — but rendered as a glass panel rather than an `NSMenu`, which is what lets
/// each rule show its real app icon and read as the same sentence the Rules
/// tab uses. `.menuBarExtraStyle(.window)` is required for that, and it makes
/// this a popover: it dismisses on click-away rather than on any selection, so
/// the two actions that should close it do so explicitly.
struct MenuBarView: View {
    @EnvironmentObject var routingEngine: RoutingEngine
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    @State private var hoveredRow: String?

    private var t: OETheme { OETheme.resolve(scheme) }

    private var fallbackLabel: String {
        DestinationList.label(browserBundleID: routingEngine.defaultBrowserBundleID,
                              profileDirectoryName: routingEngine.defaultProfileDirectoryName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $routingEngine.isEnabled) {
                Text("Route links")
                    .font(.system(size: 13))
                    .foregroundStyle(t.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(OESwitchStyle(width: 36, height: 22, knob: 17, glows: false))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            divider

            if routingEngine.rules.isEmpty {
                Text("No rules — everything opens in \(fallbackLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(t.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            } else {
                ForEach(routingEngine.rules) { rule in
                    ruleRow(rule)
                }
            }

            divider

            actionRow("Settings…", shortcut: "⌘,") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
                dismissPanel()
            }
            .keyboardShortcut(",", modifiers: .command)

            actionRow("Quit OpenElsewhere", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(6)
        .frame(width: OE.Size.menuWidth)
        .background(
            RoundedRectangle(cornerRadius: OE.Radius.tile, style: .continuous)
                .fill(t.surfaceMenu)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: OE.Radius.tile, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OE.Radius.tile, style: .continuous)
                .strokeBorder(t.borderHairline, lineWidth: OE.hairline)
        )
        .tint(t.accent)
    }

    private var divider: some View {
        OEHairline(theme: t)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }

    private func ruleRow(_ rule: RoutingRule) -> some View {
        HStack(spacing: 8) {
            if let icon = DestinationList.appIcon(for: rule.sourceAppBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Text(DestinationList.appName(for: rule.sourceAppBundleID))
                .foregroundStyle(t.textPrimary)
            Text("→")
                .foregroundStyle(t.textTertiary)
            Text(DestinationList.label(browserBundleID: rule.targetBrowserBundleID,
                                       profileDirectoryName: rule.profileDirectoryName))
                .foregroundStyle(t.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(OEFont.menuRow)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: OE.Radius.menuRow, style: .continuous)
                .fill(hoveredRow == rule.id.uuidString ? t.surfaceControl : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hoveredRow = $0 ? rule.id.uuidString : nil }
    }

    private func actionRow(_ title: String,
                           shortcut: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(t.textPrimary)
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(OEFont.shortcut)
                    .foregroundStyle(t.textTertiary)
            }
            .font(OEFont.menuRow)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: OE.Radius.menuRow, style: .continuous)
                    .fill(hoveredRow == title ? t.surfaceControl : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredRow = $0 ? title : nil }
    }

    /// `.window`-style `MenuBarExtra` hosts its content in a private `NSPanel`
    /// that closes when it resigns key. Activating another window is usually
    /// enough, but ordering is not guaranteed, so close it by hand. Best
    /// effort: if the class name ever changes, the panel simply closes a
    /// moment later when focus moves instead.
    private func dismissPanel() {
        NSApp.windows
            .first { $0.className.contains("MenuBarExtraWindow") }?
            .close()
    }
}
