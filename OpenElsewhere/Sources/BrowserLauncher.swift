import AppKit
import Foundation

/// Opens URLs in specific browsers, optionally targeting a named profile.
///
/// macOS has no single correct way to hand a URL to a running browser with a
/// specific profile. Different browsers need different strategies:
///
/// - **Chrome / Brave / Edge / Vivaldi / Opera**: implement a binary-level
///   singleton protocol. Running their executable a second time with
///   `--profile-directory=X` is detected by the existing instance (via a
///   file lock in the user-data-dir), the command line is forwarded over IPC,
///   and the existing browser opens the URL in the target profile. Launching
///   via `Process` is the right approach here.
///
/// - **Arc / Dia** (The Browser Company): strictly single-instance. Launching
///   the binary a second time — even with profile flags — triggers an
///   "<App> is already open. Only one instance can be opened at a time."
///   dialog. For these, we must go through `/usr/bin/open`, which uses
///   LaunchServices to deliver the URL to the existing instance via an
///   `AppleEvent`. `--args` is only honored on *first* launch in this mode,
///   so profile switching for already-running single-instance browsers is a
///   best-effort operation and may not take effect until next restart.
///
/// - **Firefox**: handles multi-launch gracefully via its own remote protocol.
///
/// - **Safari / unknown**: defer to LaunchServices (`open`). No profile CLI.
enum BrowserLauncher {

    /// UserDefaults key set to `true` when macOS blocks an automation-event
    /// with `errAEEventNotPermitted` (-1743). `SettingsView` observes this
    /// key to show a one-click remediation banner.
    static let automationDeniedDefaultsKey = "automationPermissionDenied"

    /// AppleScript error code returned when the user has denied (or not yet
    /// granted) automation permission in Privacy settings.
    private static let errAEEventNotPermitted = -1743

    /// Scripting targets for the single-instance browsers we route through
    /// AppleScript. Hardcoding these defends against a malicious app that
    /// registers a conflicting bundle ID with a hostile `CFBundleName`: the
    /// name is never read from disk, only sourced from this trusted map.
    private static let knownScriptingNames: [String: String] = [
        "company.thebrowser.Browser": "Arc",
        "company.thebrowser.dia": "Dia",
        "com.thebrowser.dia": "Dia"
    ]

    static func open(_ url: URL, inBrowser bundleID: String, profileDirectory: String? = nil) {
        guard let browserAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSWorkspace.shared.open(url)
            return
        }

        let caps = BrowserCapabilities.forBundleID(bundleID)
        let strictSingleInstance = Self.isStrictSingleInstance(bundleID: bundleID, appURL: browserAppURL)

        switch caps.family {
        case .chromium where strictSingleInstance:
            // Arc, Dia — can't launch a second binary. Also: by default Arc
            // routes incoming URLs into "Little Arc" (a popup window) instead
            // of the main window. Using AppleScript to explicitly create a
            // tab in the front window bypasses that and gives us the
            // "open as a new tab in the existing window" behavior users
            // expect. If AppleScript fails (no windows open, scripting
            // disabled, etc.), fall back to `/usr/bin/open`.
            launchViaAppleScript(url: url,
                                 bundleID: bundleID,
                                 fallback: {
                                     launchViaOpen(url: url,
                                                   bundleID: bundleID,
                                                   profileArgs: chromiumProfileArgs(profileDirectory))
                                 })

        case .chromium:
            // Chrome, Brave, Edge, Vivaldi, Opera — binary IPC handles this.
            launchViaProcess(url: url,
                             appURL: browserAppURL,
                             processArgs: chromiumProfileArgs(profileDirectory) + [url.absoluteString],
                             fallbackBundleID: bundleID,
                             fallbackProfileArgs: chromiumProfileArgs(profileDirectory))

        case .firefox:
            var args = firefoxProfileArgs(profileDirectory)
            args.append(contentsOf: ["--new-tab", url.absoluteString])
            launchViaProcess(url: url,
                             appURL: browserAppURL,
                             processArgs: args,
                             fallbackBundleID: bundleID,
                             fallbackProfileArgs: firefoxProfileArgs(profileDirectory))

        case .safari, .unknown:
            launchViaOpen(url: url, bundleID: bundleID, profileArgs: [])
        }
    }

    // MARK: - Detection

    /// Browsers we know enforce a single-instance policy at the binary level.
    /// Detected either via `LSMultipleInstancesProhibited` in Info.plist or
    /// via an explicit allow-list for apps that do the check in their own
    /// startup code (like Arc).
    private static func isStrictSingleInstance(bundleID: String, appURL: URL) -> Bool {
        // Explicit allow-list — Arc and Dia both exit with a modal alert if a
        // second binary instance starts, even though they don't set the
        // Info.plist flag. This matches `knownScriptingNames` above.
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

    /// Run the browser's binary directly. Suitable for browsers whose binary
    /// implements the singleton-IPC pattern (Chrome, Brave, Edge, Vivaldi,
    /// Opera, Firefox). On failure, falls back to `/usr/bin/open`.
    private static func launchViaProcess(url: URL,
                                         appURL: URL,
                                         processArgs: [String],
                                         fallbackBundleID: String,
                                         fallbackProfileArgs: [String]) {
        guard let bundle = Bundle(url: appURL),
              let exec = bundle.executableURL else {
            launchViaOpen(url: url, bundleID: fallbackBundleID, profileArgs: fallbackProfileArgs)
            return
        }

        let process = Process()
        process.executableURL = exec
        process.arguments = processArgs
        // Detach stdio — we never want the browser's stdout/stderr to pipe
        // back into OpenElsewhere's file descriptors.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("OpenElsewhere: Process launch of \(exec.lastPathComponent) failed: \(error.localizedDescription)")
            launchViaOpen(url: url, bundleID: fallbackBundleID, profileArgs: fallbackProfileArgs)
        }
    }

    /// For strictly single-instance Chromium browsers (Arc, Dia), send the
    /// URL directly to the front window via AppleScript. This reuses the
    /// existing window (as a new tab) instead of triggering Arc's "Little
    /// Arc" popup behavior.
    ///
    /// Calls `fallback` if scripting fails (target not running, no windows
    /// open, user denied automation permission, etc.).
    private static func launchViaAppleScript(url: URL, bundleID: String, fallback: () -> Void) {
        // Only run if the target app is actually running — otherwise the
        // AppleEvent would force-launch it with no window, and `front window`
        // would fail. Let the fallback (`/usr/bin/open`) cold-start it instead.
        let isRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated }
        guard isRunning else {
            fallback()
            return
        }

        // `scriptingName` is sourced from our trusted allow-list, never from
        // an on-disk bundle's `CFBundleName`. A malicious app that registers
        // a conflicting bundle ID cannot poison the AppleScript target.
        guard let scriptingName = knownScriptingNames[bundleID] else {
            fallback()
            return
        }

        let escapedURL = sanitizeForAppleScriptLiteral(url.absoluteString)

        // `scriptingName` is an allow-listed literal (`Arc` / `Dia`), so no
        // escaping is needed. We still embed it via interpolation for
        // locality of reading.
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

        guard let script = NSAppleScript(source: source) else {
            fallback()
            return
        }

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
            fallback()
        } else {
            // Clear any stale permission-denied flag on a successful run,
            // so the banner disappears after the user grants permission.
            if UserDefaults.standard.bool(forKey: automationDeniedDefaultsKey) {
                UserDefaults.standard.set(false, forKey: automationDeniedDefaultsKey)
            }
        }
    }

    /// Delegate to `/usr/bin/open`, which routes through LaunchServices.
    /// `profileArgs` are appended after `--args` — they are honored only when
    /// the target app is not already running.
    private static func launchViaOpen(url: URL, bundleID: String, profileArgs: [String]) {
        let openURL = URL(fileURLWithPath: "/usr/bin/open")

        var args: [String] = ["-b", bundleID, url.absoluteString]
        if !profileArgs.isEmpty {
            args.append("--args")
            args.append(contentsOf: profileArgs)
        }

        let process = Process()
        process.executableURL = openURL
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("OpenElsewhere: /usr/bin/open failed: \(error.localizedDescription)")
            NSWorkspace.shared.open(url)
        }
    }
}
