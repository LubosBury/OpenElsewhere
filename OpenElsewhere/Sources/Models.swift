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
}
