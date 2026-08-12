import AppKit
import Foundation

/// A browser and, optionally, one of its profiles — collapsed into a single
/// choice.
///
/// The old UI showed a browser picker and then, conditionally, a profile
/// picker beside it; the row changed width as the conditional picker appeared
/// and disappeared. One list of combined entries removes both the conditional
/// control and the jitter, and reads the way the destination is spoken:
/// "Arc · Work".
struct Destination: Identifiable, Hashable {
    let browserBundleID: String
    let profileDirectoryName: String?
    let browserName: String
    let profileName: String?

    var id: String { "\(browserBundleID)#\(profileDirectoryName ?? "")" }

    var label: String {
        guard let profileName else { return browserName }
        return "\(browserName) · \(profileName)"
    }

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum DestinationList {
    /// Every browser contributes a bare entry (its default profile); browsers
    /// with discovered profiles contribute one more entry each.
    static func build(browsers: [AppInfo],
                      profiles: (String) -> [BrowserProfile]) -> [Destination] {
        browsers.flatMap { browser -> [Destination] in
            let bare = Destination(browserBundleID: browser.bundleID,
                                   profileDirectoryName: nil,
                                   browserName: browser.name,
                                   profileName: nil)
            let withProfiles = profiles(browser.bundleID).map { profile in
                Destination(browserBundleID: browser.bundleID,
                            profileDirectoryName: profile.directoryName,
                            browserName: browser.name,
                            profileName: profile.displayName)
            }
            return [bare] + withProfiles
        }
    }

    /// Resolve a stored (browser, profile) pair back to a list entry.
    ///
    /// A profile can disappear — the user deletes it in Chrome, or the rule
    /// was made on another Mac — so fall back to the bare browser entry, then
    /// to the first entry, rather than showing an empty chip.
    static func match(_ list: [Destination],
                      browserBundleID: String,
                      profileDirectoryName: String?) -> Destination? {
        list.first { $0.browserBundleID == browserBundleID
                  && $0.profileDirectoryName == profileDirectoryName }
        ?? list.first { $0.browserBundleID == browserBundleID && $0.profileDirectoryName == nil }
        ?? list.first
    }

    /// Display label for a stored pair without needing the full list — used by
    /// the menu-bar panel and the empty-state copy.
    static func label(browserBundleID: String,
                      profileDirectoryName: String?) -> String {
        let browserName = appName(for: browserBundleID)
        guard let profileDirectoryName,
              let match = ProfileDiscovery.profiles(forBrowser: browserBundleID)
                  .first(where: { $0.directoryName == profileDirectoryName })
        else { return browserName }
        return "\(browserName) · \(match.displayName)"
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }
        return AppInfo.displayName(at: url)
    }

    static func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
