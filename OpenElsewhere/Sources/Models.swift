import AppKit
import Foundation

struct RoutingRule: Codable, Identifiable, Equatable {
    var id: UUID
    var sourceAppBundleID: String
    var targetBrowserBundleID: String
    /// Optional: directory name of the profile to open in (for Chromium/Firefox).
    var profileDirectoryName: String?

    init(id: UUID = UUID(),
         sourceAppBundleID: String,
         targetBrowserBundleID: String,
         profileDirectoryName: String? = nil) {
        self.id = id
        self.sourceAppBundleID = sourceAppBundleID
        self.targetBrowserBundleID = targetBrowserBundleID
        self.profileDirectoryName = profileDirectoryName
    }
}

struct AppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage?

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleID == rhs.bundleID
    }

    /// Finder's display name for an app bundle, minus the extension.
    ///
    /// `FileManager.displayName` honours "Show all filename extensions", so
    /// for users who have that switched on it returns "Slack.app" — which
    /// then reads as "Links from Slack.app open in Arc.app". Nothing calls an
    /// app that, so drop the suffix while keeping the localized name.
    static func displayName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
