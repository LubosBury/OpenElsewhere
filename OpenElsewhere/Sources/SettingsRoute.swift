import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, rules, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .rules: "Rules"
        case .about: "About"
        }
    }
}

/// One-shot navigation intents handed to the Settings window from outside it.
///
/// Onboarding's last step has to open Settings *on the Rules tab* with a fresh
/// rule already inserted. `openWindow` cannot carry that, and the window may
/// not be mounted when the request is made, so the intent is parked here and
/// consumed by `SettingsView` whenever it next appears.
@MainActor
final class SettingsRoute: ObservableObject {
    static let shared = SettingsRoute()

    @Published var requestedTab: SettingsTab?
    @Published var wantsNewRule = false

    private init() {}

    func requestNewRule() {
        requestedTab = .rules
        wantsNewRule = true
    }
}
