import AppKit
import Foundation

/// Represents a single browser profile (Chrome/Arc/Brave/Edge "Profile 1", Firefox profile, etc.)
struct BrowserProfile: Codable, Hashable, Identifiable {
    var id: String { "\(browserBundleID):\(directoryName)" }
    /// The browser this profile belongs to.
    let browserBundleID: String
    /// Internal directory name used in CLI flags (e.g. "Default", "Profile 1", or Firefox profile folder name).
    let directoryName: String
    /// Human-visible name ("Work", "Personal", etc.).
    let displayName: String
}

/// Browser engine families — determines how we discover profiles and launch with them.
enum BrowserFamily {
    case chromium          // Chrome, Arc, Brave, Edge, Vivaldi, Opera — use --profile-directory
    case firefox           // Firefox — use -P
    case safari            // Safari — no profile CLI support
    case unknown
}

struct BrowserCapabilities {
    let family: BrowserFamily
    /// Relative path under ~/Library/Application Support/ where the browser stores its user data.
    /// For Chromium browsers this contains `Local State`; for Firefox it contains `profiles.ini`.
    let userDataPath: String?

    static func forBundleID(_ bundleID: String) -> BrowserCapabilities {
        switch bundleID {
        case "com.google.Chrome":
            return .init(family: .chromium, userDataPath: "Google/Chrome")
        case "com.google.Chrome.canary":
            return .init(family: .chromium, userDataPath: "Google/Chrome Canary")
        case "company.thebrowser.Browser":   // Arc
            return .init(family: .chromium, userDataPath: "Arc/User Data")
        case "com.brave.Browser":
            return .init(family: .chromium, userDataPath: "BraveSoftware/Brave-Browser")
        case "com.microsoft.edgemac":
            return .init(family: .chromium, userDataPath: "Microsoft Edge")
        case "com.vivaldi.Vivaldi":
            return .init(family: .chromium, userDataPath: "Vivaldi")
        case "com.operasoftware.Opera":
            return .init(family: .chromium, userDataPath: "com.operasoftware.Opera")
        case "com.thebrowser.dia":           // Dia (by The Browser Company)
            return .init(family: .chromium, userDataPath: "Dia/User Data")
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly":
            return .init(family: .firefox, userDataPath: "Firefox")
        case "com.apple.Safari":
            return .init(family: .safari, userDataPath: nil)
        default:
            return .init(family: .unknown, userDataPath: nil)
        }
    }
}

/// Discovers browser profiles on disk for browsers that support them.
enum ProfileDiscovery {
    static func profiles(forBrowser bundleID: String) -> [BrowserProfile] {
        let caps = BrowserCapabilities.forBundleID(bundleID)
        switch caps.family {
        case .chromium:
            return chromiumProfiles(bundleID: bundleID, userDataPath: caps.userDataPath)
        case .firefox:
            return firefoxProfiles(bundleID: bundleID, userDataPath: caps.userDataPath)
        case .safari, .unknown:
            return []
        }
    }

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private static func chromiumProfiles(bundleID: String, userDataPath: String?) -> [BrowserProfile] {
        guard let userDataPath else { return [] }
        let localStateURL = appSupport
            .appendingPathComponent(userDataPath)
            .appendingPathComponent("Local State")

        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: [String: Any]] else {
            return []
        }

        var result: [BrowserProfile] = []
        for (directoryName, info) in infoCache {
            let displayName = (info["name"] as? String) ?? directoryName
            result.append(BrowserProfile(
                browserBundleID: bundleID,
                directoryName: directoryName,
                displayName: displayName
            ))
        }

        // Sort: "Default" first, then by display name
        return result.sorted { lhs, rhs in
            if lhs.directoryName == "Default" { return true }
            if rhs.directoryName == "Default" { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func firefoxProfiles(bundleID: String, userDataPath: String?) -> [BrowserProfile] {
        guard let userDataPath else { return [] }
        let iniURL = appSupport
            .appendingPathComponent(userDataPath)
            .appendingPathComponent("profiles.ini")

        guard let contents = try? String(contentsOf: iniURL, encoding: .utf8) else { return [] }

        var result: [BrowserProfile] = []
        var currentName: String?
        var currentPath: String?

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[Profile") {
                // Flush previous
                if let name = currentName, let path = currentPath {
                    result.append(BrowserProfile(
                        browserBundleID: bundleID,
                        directoryName: path,
                        displayName: name
                    ))
                }
                currentName = nil
                currentPath = nil
            } else if let eq = line.firstIndex(of: "=") {
                let key = String(line[..<eq])
                let value = String(line[line.index(after: eq)...])
                if key == "Name" { currentName = value }
                if key == "Path" { currentPath = value }
            }
        }
        // Flush last
        if let name = currentName, let path = currentPath {
            result.append(BrowserProfile(
                browserBundleID: bundleID,
                directoryName: path,
                displayName: name
            ))
        }

        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
