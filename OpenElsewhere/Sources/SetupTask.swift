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
                : "macOS won't let a sandboxed app claim this itself — in Desktop & Dock, pick OpenElsewhere under \"Default web browser\"."
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
    ///
    /// It names the destination pane rather than saying "System Settings":
    /// that app has thirty panes and "Default web browser" is buried near the
    /// bottom of a long one, so the generic label left people stranded.
    var stripCTA: String {
        switch self {
        case .defaultBrowser:
            Capabilities.canSetDefaultBrowser ? "Make it Default" : "Open Desktop & Dock"
        case .automation: "Open Privacy Settings"
        case .profileHelper: "Show me how"
        case .firstRule: "Add a rule"
        }
    }

    /// Shown once the CTA has handed the user off to System Settings. Neither
    /// pane opens scrolled to the row that matters, and the app cannot scroll
    /// it for them, so the follow-up spells out what to look for.
    var followUpInstruction: String? {
        switch self {
        case .defaultBrowser:
            Capabilities.canSetDefaultBrowser
                ? "Confirm the change when macOS asks."
                : "Scroll to the bottom of Desktop & Dock. Under \"Default web browser\", choose OpenElsewhere."
        case .automation:
            "Open Privacy & Security → Automation, find OpenElsewhere, and switch on the browsers you use."
        case .profileHelper, .firstRule:
            nil
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
            Capabilities.canSetDefaultBrowser
                ? "Other apps need to send URLs here first. One click, and macOS asks you to confirm."
                : "Other apps need to send URLs here first. A sandboxed app can't claim that itself, so macOS has you pick it by hand."
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

// MARK: - Default-handler check

enum DefaultBrowser {

    /// Whether macOS currently sends `https` links to OpenElsewhere.
    ///
    /// Deliberately never opens the resolved app bundle. The obvious
    /// implementation — resolve the handler URL, then read its
    /// `bundleIdentifier` — reads a bundle the App Sandbox may not be allowed
    /// to open: any copy outside `/Applications` (a build directory, a folder
    /// in the user's home) fails, `Bundle(url:)` returns nil, and the app
    /// concludes it is not the default *while being exactly that*. That is the
    /// "still asks me to set the default" report.
    ///
    /// Matching the handler URL against LaunchServices' own list of copies of
    /// our bundle ID answers the same question from the database alone, and
    /// has the useful side effect of recognising any installed copy — the one
    /// macOS registered is often not the one running.
    static var isHandlingLinks: Bool {
        guard let httpsURL = URL(string: "https://example.com"),
              let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL)
        else { return false }

        let handler = handlerURL.standardizedFileURL
        if handler == Bundle.main.bundleURL.standardizedFileURL { return true }

        guard let ownID = Bundle.main.bundleIdentifier else { return false }
        return NSWorkspace.shared
            .urlsForApplications(withBundleIdentifier: ownID)
            .contains { $0.standardizedFileURL == handler }
    }

    /// Claim the `http`/`https` handler. Only the Developer ID build can:
    /// Apple has not extended the runtime default-handler APIs to sandboxed
    /// apps, so the App Store build sends the user to System Settings instead.
    static func claim(completion: @escaping () -> Void) {
        guard Capabilities.canSetDefaultBrowser else {
            SystemSettings.openDefaultBrowser()
            completion()
            return
        }

        // LaunchServices' LSSetDefaultHandlerForURLScheme is deprecated since
        // macOS 12 and may silently no-op, so use the NSWorkspace API.
        let appURL = Bundle.main.bundleURL
        let group = DispatchGroup()
        for scheme in ["http", "https"] {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL,
                                                     toOpenURLsWithScheme: scheme) { error in
                if let error {
                    print("OpenElsewhere: setDefaultApplication(\(scheme)) failed: \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        group.notify(queue: .main, execute: completion)
    }
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
