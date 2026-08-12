import AppKit
import Foundation

/// Profile routing for the sandboxed App Store build.
///
/// The App Sandbox silently drops `NSWorkspace.OpenConfiguration.arguments`:
/// the browser launches with no arguments at all, and `openApplication` still
/// reports success, so the failure is undetectable from the return value.
/// (Verified by spike, 2026-08-11.)
///
/// The only sanctioned way for a sandboxed app to pass command-line arguments
/// to another binary is `NSUserUnixTask`, which executes a script the **user**
/// has placed in `~/Library/Application Scripts/<bundle-id>/`. The app cannot
/// install that script itself — that restriction is the entire point of the
/// directory — so `SettingsView` walks the user through it.
enum ProfileRoutingHelper {

    static let scriptName = "open.sh"

    /// Exact contents the user must place at `scriptsDirectory/open.sh`.
    /// Kept deliberately trivial: it execs whatever it is handed, so the app
    /// stays in control of which browser and which flags are used, and the
    /// script never needs updating when browser support changes.
    static let scriptSource = """
    #!/bin/bash
    # OpenElsewhere profile-routing helper.
    #
    # The Mac App Store build is sandboxed and cannot pass command-line
    # arguments to a browser. This script does it on the app's behalf.
    # Argument 1 is the browser executable; the rest are its arguments.
    exec "$@"
    """

    /// `~/Library/Application Scripts/com.openelsewhere.app/`. Readable and
    /// executable by the sandboxed app, writable only by the user.
    static var scriptsDirectory: URL? {
        try? FileManager.default.url(for: .applicationScriptsDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: false)
    }

    static var scriptURL: URL? {
        scriptsDirectory?.appendingPathComponent(scriptName)
    }

    /// True once the user has installed the script and made it executable.
    /// A non-executable file counts as not installed, because
    /// `NSUserUnixTask` would fail on it anyway.
    static var isInstalled: Bool {
        guard let scriptURL else { return false }
        return FileManager.default.isExecutableFile(atPath: scriptURL.path)
    }

    /// Run the browser with arguments, outside the sandbox.
    /// Returns `false` if the script is missing or execution failed, so the
    /// caller degrades to opening the URL without profile selection.
    static func launch(executable: URL, arguments: [String]) async -> Bool {
        guard let scriptURL, isInstalled else { return false }

        do {
            let task = try NSUserUnixTask(url: scriptURL)
            try await task.execute(withArguments: [executable.path] + arguments)
            return true
        } catch {
            print("OpenElsewhere: profile helper script failed — \(error.localizedDescription)")
            return false
        }
    }
}
