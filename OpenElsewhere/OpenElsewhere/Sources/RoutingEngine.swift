import Foundation
import SwiftUI

/// Resolved destination — which browser and (optionally) which profile.
struct RoutingDestination: Sendable {
    let browserBundleID: String
    let profileDirectoryName: String?
}

/// `@MainActor`-isolated so `@Published` reads/writes can't race. All callers
/// (SwiftUI views, the AppDelegate `@objc` handler) already run on the main
/// thread; the annotation just makes that contract explicit to the compiler.
@MainActor
class RoutingEngine: ObservableObject {
    static let shared = RoutingEngine()

    // UserDefaults keys — kept in one place so corruption-recovery and tests
    // can reference them symbolically.
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let defaultBrowserBundleID = "defaultBrowserBundleID"
        static let defaultProfileDirectoryName = "defaultProfileDirectoryName"
        static let routingRules = "routingRules"
        /// Prefix for corruption-recovery backups of bad routingRules blobs.
        static let routingRulesBackupPrefix = "routingRules.invalid."
    }

    @Published var rules: [RoutingRule] {
        didSet { saveRules() }
    }

    @Published var defaultBrowserBundleID: String {
        didSet { UserDefaults.standard.set(defaultBrowserBundleID, forKey: Keys.defaultBrowserBundleID) }
    }

    @Published var defaultProfileDirectoryName: String? {
        didSet {
            UserDefaults.standard.set(defaultProfileDirectoryName, forKey: Keys.defaultProfileDirectoryName)
        }
    }

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.defaultBrowserBundleID = defaults.string(forKey: Keys.defaultBrowserBundleID) ?? "com.apple.Safari"
        self.defaultProfileDirectoryName = defaults.string(forKey: Keys.defaultProfileDirectoryName)
        self.rules = Self.loadRules(from: defaults)
    }

    /// Load rules with corruption recovery. If decode fails we preserve the
    /// bad blob under a timestamped key so it can be inspected or restored,
    /// then start with an empty rule list. This prevents a schema/format bug
    /// from silently wiping a user's configuration with no trail.
    private static func loadRules(from defaults: UserDefaults) -> [RoutingRule] {
        guard let data = defaults.data(forKey: Keys.routingRules) else { return [] }
        do {
            return try JSONDecoder().decode([RoutingRule].self, from: data)
        } catch {
            let backupKey = Keys.routingRulesBackupPrefix + String(Int(Date().timeIntervalSince1970))
            defaults.set(data, forKey: backupKey)
            print("""
                  OpenElsewhere: failed to decode routingRules — \(error.localizedDescription). \
                  Corrupted blob preserved under UserDefaults key \(backupKey). Starting with an empty rule list.
                  """)
            return []
        }
    }

    func destination(forSourceApp bundleID: String) -> RoutingDestination {
        if let rule = rules.first(where: { $0.sourceAppBundleID == bundleID }) {
            return RoutingDestination(
                browserBundleID: rule.targetBrowserBundleID,
                profileDirectoryName: rule.profileDirectoryName
            )
        }
        return RoutingDestination(
            browserBundleID: defaultBrowserBundleID,
            profileDirectoryName: defaultProfileDirectoryName
        )
    }

    func addRule(sourceAppBundleID: String, targetBrowserBundleID: String, profileDirectoryName: String? = nil) {
        rules.removeAll { $0.sourceAppBundleID == sourceAppBundleID }
        rules.append(RoutingRule(
            sourceAppBundleID: sourceAppBundleID,
            targetBrowserBundleID: targetBrowserBundleID,
            profileDirectoryName: profileDirectoryName
        ))
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    private func saveRules() {
        do {
            let data = try JSONEncoder().encode(rules)
            UserDefaults.standard.set(data, forKey: Keys.routingRules)
        } catch {
            // Encoding our own Codable shouldn't fail, but if it does we'd
            // rather log than silently lose state.
            print("OpenElsewhere: failed to encode routingRules — \(error.localizedDescription)")
        }
    }
}
