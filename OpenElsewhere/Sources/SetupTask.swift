import AppKit
import Foundation

/// The one-time setup work the app can ask for, and the single place that
/// decides what is still outstanding.
///
/// Two surfaces render this: the setup strip at the top of Settings, which
/// shows **one** item at a time, and first-run onboarding, which walks the
/// list. They share these conditions so a step skipped in onboarding is
/// exactly the item still waiting in Settings.
enum SetupTask: String, Identifiable, CaseIterable {
    case defaultBrowser
    case automation
    case profileHelper
    /// Onboarding only — there is nothing to remediate once Settings is open,
    /// because the Rules tab is already the thing being asked for.
    case firstRule

    var id: String { rawValue }
}

/// Snapshot of everything the queue is derived from.
struct SetupConditions {
    var isHandlingLinks: Bool
    var automationPermissionDenied: Bool
    var profileHelperInstalled: Bool
    var hasRules: Bool
}

extension SetupTask {

    // MARK: Queues

    /// Outstanding items for the Settings strip, in priority order. The strip
    /// renders `.first`; the count drives the "n more after this" hint.
    static func settingsQueue(_ c: SetupConditions) -> [SetupTask] {
        var queue: [SetupTask] = []
        if !c.isHandlingLinks { queue.append(.defaultBrowser) }
        if c.automationPermissionDenied { queue.append(.automation) }
        if Capabilities.usesScriptBasedProfileRouting && !c.profileHelperInstalled {
            queue.append(.profileHelper)
        }
        return queue
    }

    /// Steps for first-run onboarding.
    ///
    /// Automation is offered here even though no denial has been recorded yet:
    /// macOS has no API to ask whether an automation grant exists without
    /// sending an event, so onboarding guides proactively while the Settings
    /// strip only ever remediates an observed denial. Profile-helper setup is
    /// deliberately absent — it is optional, and it is the one item that reads
    /// as a chore on first launch.
    static func onboardingSteps(_ c: SetupConditions) -> [SetupTask] {
        var steps: [SetupTask] = []
        if !c.isHandlingLinks { steps.append(.defaultBrowser) }
        steps.append(.automation)
        if !c.hasRules { steps.append(.firstRule) }
        return steps
    }

    // MARK: Presentation

    var tone: OETone {
        self == .automation ? .warn : .accent
    }

    var symbol: String {
        switch self {
        case .defaultBrowser: "bolt.horizontal.circle.fill"
        case .automation: "lock.shield.fill"
        case .profileHelper: "person.2.badge.gearshape"
        case .firstRule: "arrow.triangle.branch"
        }
    }

    // MARK: Settings strip copy

    var stripTitle: String {
        switch self {
        case .defaultBrowser: "OpenElsewhere isn't handling links yet"
        case .automation: "Let it control Arc and Dia"
        case .profileHelper: "Route to a specific profile"
        case .firstRule: "Send your first link somewhere"
        }
    }

    var stripBody: String {
        switch self {
        case .defaultBrowser:
            // The sandboxed build cannot claim the handler itself, so the copy
            // has to explain why it is asking rather than doing.
            Capabilities.canSetDefaultBrowser
                ? "Set it as your default link handler so other apps send URLs through it."
                : "macOS won't let a sandboxed app claim this itself — pick OpenElsewhere under \"Default web browser\"."
        case .automation:
            "Without automation permission, links open a new popup window instead of a tab in the window you already have."
        case .profileHelper:
            "Optional. Profile routing needs a small helper script you install once — the sandbox blocks the app from doing it."
        case .firstRule:
            "Pick one app to route differently. You can change it any time."
        }
    }

    /// The App Store build's button never sets the default — it opens System
    /// Settings. Only the Developer ID build gets to promise otherwise.
    var stripCTA: String {
        switch self {
        case .defaultBrowser:
            Capabilities.canSetDefaultBrowser ? "Make it Default" : "Open System Settings"
        case .automation: "Open Privacy Settings"
        case .profileHelper: "Show me how"
        case .firstRule: "Add a rule"
        }
    }

    // MARK: Onboarding copy

    var onboardingTitle: String {
        switch self {
        case .defaultBrowser: "Make it your link handler"
        case .automation: "Allow control of your browsers"
        case .profileHelper: "Route to a specific profile"
        case .firstRule: "Send your first link somewhere"
        }
    }

    var onboardingBody: String {
        switch self {
        case .defaultBrowser:
            "Other apps need to send URLs here first. macOS asks you to confirm in System Settings."
        case .automation:
            "So a link becomes a tab in the window you already have, not another popup."
        case .profileHelper:
            "Profile routing needs a small helper script you install once."
        case .firstRule:
            "Pick one app to route differently. You can change it any time."
        }
    }

    var onboardingCTA: String { stripCTA }
}

// MARK: - System Settings deep links

enum SystemSettings {
    /// Privacy & Security → Automation. Falls back to the Privacy pane root if
    /// a future macOS renames the anchor.
    static func openAutomation() {
        let anchored = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        let root = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let url = anchored ?? root {
            NSWorkspace.shared.open(url)
        }
    }

    /// Desktop & Dock, which is where "Default web browser" lives.
    static func openDefaultBrowser() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
