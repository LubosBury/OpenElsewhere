import Foundation
import SwiftUI

/// Resolved destination — which browser and (optionally) which profile.
struct RoutingDestination {
    let browserBundleID: String
    let profileDirectoryName: String?
}

class RoutingEngine: ObservableObject {
    static let shared = RoutingEngine()

    @Published var rules: [RoutingRule] {
        didSet { saveRules() }
    }

    @Published var defaultBrowserBundleID: String {
        didSet { UserDefaults.standard.set(defaultBrowserBundleID, forKey: "defaultBrowserBundleID") }
    }

    @Published var defaultProfileDirectoryName: String? {
        didSet {
            UserDefaults.standard.set(defaultProfileDirectoryName, forKey: "defaultProfileDirectoryName")
        }
    }

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        self.defaultBrowserBundleID = UserDefaults.standard.string(forKey: "defaultBrowserBundleID") ?? "com.apple.Safari"
        self.defaultProfileDirectoryName = UserDefaults.standard.string(forKey: "defaultProfileDirectoryName")

        if let data = UserDefaults.standard.data(forKey: "routingRules"),
           let decoded = try? JSONDecoder().decode([RoutingRule].self, from: data) {
            self.rules = decoded
        } else {
            self.rules = []
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
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "routingRules")
        }
    }
}
