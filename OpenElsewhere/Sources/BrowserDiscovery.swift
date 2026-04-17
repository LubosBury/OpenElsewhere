import AppKit
import Foundation

class BrowserDiscovery {
    static let shared = BrowserDiscovery()

    func installedBrowsers() -> [AppInfo] {
        guard let httpsURL = URL(string: "https://example.com") else { return [] }
        let browserURLs = NSWorkspace.shared.urlsForApplications(toOpen: httpsURL)
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""

        return browserURLs
            .compactMap { url -> AppInfo? in
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      bundleID.lowercased() != ownBundleID.lowercased() else { return nil }
                let name = FileManager.default.displayName(atPath: url.path)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)
                return AppInfo(bundleID: bundleID, name: name, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func installedApps() -> [AppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var apps: [String: AppInfo] = [:]

        for dir in appDirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: fileURL),
                      let bundleID = bundle.bundleIdentifier else { continue }

                let name = FileManager.default.displayName(atPath: fileURL.path)
                let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                icon.size = NSSize(width: 32, height: 32)

                if apps[bundleID] == nil {
                    apps[bundleID] = AppInfo(bundleID: bundleID, name: name, icon: icon)
                }
            }
        }

        return apps.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
