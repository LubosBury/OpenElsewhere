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
        // Info.plist flag.
        let known: Set<String> = [
            "company.thebrowser.Browser",   // Arc
            "company.thebrowser.dia",       // Dia
            "com.thebrowser.dia",           // Dia (alternate bundle ID)
        ]
        if known.contains(bundleID) { return true }

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
    /// Calls `fallback` if scripting fails (Arc not running, no windows, user
    /// denied automation permission, etc.).
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

        // Resolve bundle ID → app name for the AppleScript `tell application`
        // target. Arc's scripting target is "Arc", Dia is "Dia".
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let appName = (Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? (Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) else {
            fallback()
            return
        }

        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedAppName = appName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // If there are no windows, create one first so `front window` exists.
        let source = """
        tell application "\(escapedAppName)"
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
        let result = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil || result.descriptorType == 0 {
            if let info = errorInfo {
                print("OpenElsewhere: AppleScript for \(appName) failed: \(info)")
            }
            fallback()
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

        do {
            try process.run()
        } catch {
            print("OpenElsewhere: /usr/bin/open failed: \(error.localizedDescription)")
            NSWorkspace.shared.open(url)
        }
    }
}
