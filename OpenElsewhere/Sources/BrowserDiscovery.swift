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
                // Note: NSWorkspace.icon(forFile:) returns a shared NSImage.
                // Do NOT mutate its `.size` — that would affect every other
                // caller holding the same cached instance. Let SwiftUI frame
                // the icon at the call site instead.
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                return AppInfo(bundleID: bundleID, name: name, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func installedApps() -> [AppInfo] {
        var appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications")
        ]

        // Under the App Sandbox `homeDirectoryForCurrentUser` resolves to the
        // app's container, so scanning it would enumerate nothing useful.
        if Capabilities.canEnumerateUserApplications {
            appDirs.append(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications")
            )
        }

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
                // See note above: do not mutate `.size` on a shared NSImage.
                let icon = NSWorkspace.shared.icon(forFile: fileURL.path)

                if apps[bundleID] == nil {
                    apps[bundleID] = AppInfo(bundleID: bundleID, name: name, icon: icon)
                }
            }
        }

        // Union with currently-running apps. This recovers most of what the
        // sandbox hides: an app the user is actually using is discoverable
        // wherever it lives, including ~/Applications and Setapp. It also
        // helps the unsandboxed build find apps in unusual locations.
        for running in NSWorkspace.shared.runningApplications {
            guard running.activationPolicy == .regular,
                  let bundleID = running.bundleIdentifier,
                  let bundleURL = running.bundleURL,
                  apps[bundleID] == nil else { continue }

            apps[bundleID] = AppInfo(
                bundleID: bundleID,
                name: FileManager.default.displayName(atPath: bundleURL.path),
                icon: NSWorkspace.shared.icon(forFile: bundleURL.path)
            )
        }

        return apps.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
