import AppKit
import Foundation

/// Opens URLs in specific browsers, optionally targeting a named profile.
///
/// macOS has no single correct way to hand a URL to a running browser with a
/// specific profile. Different browsers need different strategies:
///
/// - **Chrome / Brave / Edge / Vivaldi / Opera**: implement a binary-level
///   singleton protocol. Starting a second instance with `--profile-directory=X`
///   is detected by the existing instance (via a file lock in the user-data-dir),
///   the command line is forwarded over IPC, and the existing browser opens the
///   URL in the target profile.
///
/// - **Arc / Dia** (The Browser Company): strictly single-instance. When they
///   receive a URL through LaunchServices they open it in a detached popup
///   ("Little Arc") rather than a tab. A single AppleScript event asking for a
///   new tab in the front window is the only way to get the expected behaviour.
///   Under the App Store build this relies on the
///   `com.apple.security.temporary-exception.apple-events` entitlement.
///
/// - **Firefox**: handles multi-launch gracefully via its own remote protocol.
///
/// - **Safari / unknown**: defer to LaunchServices. No profile CLI.
///
/// `@MainActor` because `NSAppleScript` must run on the main thread, and every
/// caller (the `AppDelegate` Apple Event handler) is already main-isolated.
@MainActor
enum BrowserLauncher {

    /// UserDefaults key set to `true` when macOS blocks an automation event
    /// with `errAEEventNotPermitted` (-1743). `SettingsView` observes this
    /// key to show a one-click remediation banner.
    ///
    /// `nonisolated` because `SettingsView` reads it from a stored-property
    /// initializer (`@AppStorage(BrowserLauncher.automationDeniedDefaultsKey)`),
    /// which is not main-actor isolated.
    nonisolated static let automationDeniedDefaultsKey = "automationPermissionDenied"

    /// AppleScript error code returned when the user has denied (or not yet
    /// granted) automation permission in Privacy settings.
    private static let errAEEventNotPermitted = -1743

    /// Scripting targets for the single-instance browsers we route through
    /// AppleScript. Hardcoding these defends against a malicious app that
    /// registers a conflicting bundle ID with a hostile `CFBundleName`: the
    /// name is never read from disk, only sourced from this trusted map.
    /// This list must stay in sync with the `temporary-exception.apple-events`
    /// array in `OpenElsewhere-AppStore.entitlements`.
    /// `nonisolated` so the setup-prompt copy, which is not main-actor bound,
    /// can read it. It is an immutable table of `Sendable` values.
    nonisolated private static let knownScriptingNames: [String: String] = [
        "company.thebrowser.Browser": "Arc",
        "company.thebrowser.dia": "Dia",
        "com.thebrowser.dia": "Dia"
    ]

    /// Display names of the scripted browsers actually installed, deduplicated
    /// and sorted. Automation permission only ever matters for these, so the
    /// UI asks about it only when one is present — and can name the ones the
    /// user actually has instead of guessing.
    nonisolated static var installedScriptedBrowserNames: [String] {
        let names = knownScriptingNames.compactMap { bundleID, name in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil ? name : nil
        }
        return Array(Set(names)).sorted()
    }

    static func open(_ url: URL,
                     inBrowser bundleID: String,
                     profileDirectory: String? = nil) async {
        guard let browserAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSWorkspace.shared.open(url)
            return
        }

        let caps = BrowserCapabilities.forBundleID(bundleID)

        switch caps.family {
        case .chromium where isStrictSingleInstance(bundleID: bundleID, appURL: browserAppURL):
            // Arc, Dia — a second instance is refused outright, so AppleScript
            // is the only route to tab behaviour. Fall back to a plain open,
            // which yields the popup but at least delivers the URL.
            if launchViaAppleScript(url: url, bundleID: bundleID) { return }
            await openURL(url, inAppAt: browserAppURL)

        case .chromium:
            let profileArgs = chromiumProfileArgs(profileDirectory)
            if !profileArgs.isEmpty,
               await launchWithProfile(appURL: browserAppURL,
                                       arguments: profileArgs + [url.absoluteString]) {
                return
            }
            await openURL(url, inAppAt: browserAppURL)

        case .firefox:
            let profileArgs = firefoxProfileArgs(profileDirectory)
            if !profileArgs.isEmpty,
               await launchWithProfile(appURL: browserAppURL,
                                       arguments: profileArgs + ["--new-tab", url.absoluteString]) {
                return
            }
            await openURL(url, inAppAt: browserAppURL)

        case .safari, .unknown:
            await openURL(url, inAppAt: browserAppURL)
        }
    }

    // MARK: - Detection

    /// Browsers we know enforce a single-instance policy at the binary level.
    /// Detected either via `LSMultipleInstancesProhibited` in Info.plist or
    /// via an explicit allow-list for apps that do the check in their own
    /// startup code (like Arc).
    private static func isStrictSingleInstance(bundleID: String, appURL: URL) -> Bool {
        if knownScriptingNames[bundleID] != nil { return true }

        if let bundle = Bundle(url: appURL),
           let prohibit = bundle.object(forInfoDictionaryKey: "LSMultipleInstancesProhibited") as? Bool,
           prohibit {
            return true
        }
        return false
    }

    // MARK: - Profile arg helpers

    private static func chromiumProfileArgs(_ profile: String?) -> [String] {
        guard let profile, !profile.isEmpty else { return [] }
        return ["--profile-directory=\(profile)"]
    }

    private static func firefoxProfileArgs(_ profile: String?) -> [String] {
        guard let profile, !profile.isEmpty else { return [] }
        return ["-P", profile]
    }

    // MARK: - AppleScript helpers

    /// Strip ASCII control characters (C0 + DEL) from a string before
    /// embedding it in an AppleScript literal. Foundation will percent-encode
    /// control chars in a normal `URL`, but we filter defensively in case a
    /// malformed URL reaches us or a future code path passes untrusted text.
    /// After filtering, we escape the two AppleScript string-literal
    /// metacharacters: backslash and double-quote.
    private static func sanitizeForAppleScriptLiteral(_ value: String) -> String {
        let filtered = String(value.unicodeScalars.filter { scalar in
            let v = scalar.value
            return v >= 0x20 && v != 0x7F
        })
        return filtered
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Launch strategies

    /// Deliver a URL together with profile-selection arguments.
    ///
    /// Chromium and Firefox treat a second launch carrying arguments as
    /// "forward these to the running instance over IPC", which is how profile
    /// targeting works. Two routes reach that:
    ///
    /// - **Unsandboxed (Developer ID):** `NSWorkspace.openApplication` with
    ///   `createsNewApplicationInstance`.
    /// - **Sandboxed (App Store):** the sandbox silently drops
    ///   `configuration.arguments` — the browser launches with nothing, and
    ///   `openApplication` *still* reports success, so its return value cannot
    ///   be trusted. We never take that route when sandboxed, and go through
    ///   the user-installed helper script instead.
    ///
    /// Returns `false` when no profile-capable route is available, so the
    /// caller can degrade to a plain open.
    private static func launchWithProfile(appURL: URL, arguments: [String]) async -> Bool {
        guard Capabilities.canPassLaunchArguments else {
            guard let executable = Bundle(url: appURL)?.executableURL else { return false }
            return await ProfileRoutingHelper.launch(executable: executable, arguments: arguments)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.arguments = arguments

        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return true
        } catch {
            print("OpenElsewhere: openApplication(\(appURL.lastPathComponent)) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Hand the URL to LaunchServices for the given app. This is the universal
    /// fallback: no profile targeting, but it always delivers the URL, and it
    /// works identically sandboxed and unsandboxed.
    private static func openURL(_ url: URL, inAppAt appURL: URL) async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        do {
            _ = try await NSWorkspace.shared.open([url],
                                                  withApplicationAt: appURL,
                                                  configuration: configuration)
        } catch {
            print("OpenElsewhere: open(\(url.absoluteString)) in \(appURL.lastPathComponent) failed: \(error.localizedDescription)")
            NSWorkspace.shared.open(url)
        }
    }

    /// For strictly single-instance Chromium browsers (Arc, Dia), send the
    /// URL directly to the front window via AppleScript. Returns `true` on
    /// success; the caller falls back to a plain open on `false`.
    private static func launchViaAppleScript(url: URL, bundleID: String) -> Bool {
        // Only run if the target app is actually running — otherwise the
        // AppleEvent would force-launch it with no window, and `front window`
        // would fail. Let the caller's fallback cold-start it instead.
        let isRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated }
        guard isRunning else { return false }

        // `scriptingName` is sourced from our trusted allow-list, never from
        // an on-disk bundle's `CFBundleName`. A malicious app that registers
        // a conflicting bundle ID cannot poison the AppleScript target.
        guard let scriptingName = knownScriptingNames[bundleID] else { return false }

        let escapedURL = sanitizeForAppleScriptLiteral(url.absoluteString)

        let source = """
        tell application "\(scriptingName)"
            activate
            if (count of windows) is 0 then
                make new window
            end if
            tell front window
                make new tab with properties {URL:"\(escapedURL)"}
            end tell
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return false }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)

        if let info = errorInfo {
            let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
            print("OpenElsewhere: AppleScript for \(scriptingName) failed (\(code)): \(info)")

            // If the user has denied automation permission, set a flag that
            // SettingsView surfaces as a remediation banner. Users otherwise
            // silently get the "Little Arc" popup with no explanation.
            if code == errAEEventNotPermitted {
                UserDefaults.standard.set(true, forKey: automationDeniedDefaultsKey)
            }
            return false
        }

        // Clear any stale permission-denied flag on a successful run, so the
        // banner disappears after the user grants permission.
        if UserDefaults.standard.bool(forKey: automationDeniedDefaultsKey) {
            UserDefaults.standard.set(false, forKey: automationDeniedDefaultsKey)
        }
        return true
    }
}
