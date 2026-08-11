import AppKit

// Sandboxed spike. Answers two questions the App Store migration depends on:
//
//   1. Can a sandboxed process route a URL into a *specific* Chrome profile
//      while Chrome is already running? (NSWorkspace.openApplication with
//      createsNewApplicationInstance, relying on Chrome's singleton IPC.)
//   2. Can a sandboxed process drive Arc/Dia via AppleScript given only a
//      temporary-exception entitlement?
//
// Run the binary directly from Terminal so stdout is visible. The kernel
// still applies the sandbox, because it keys off the code signature.

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func testChromeProfile(profileDirectory: String, urlString: String) async -> Bool {
    let bundleID = "com.google.Chrome"
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        log("SKIP chrome: not installed")
        return false
    }

    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = true
    config.arguments = ["--profile-directory=\(profileDirectory)", urlString]

    do {
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        log("PASS chrome: openApplication returned pid \(app.processIdentifier)")
        log("      >>> NOW LOOK AT CHROME. Did \(urlString) open in profile '\(profileDirectory)'?")
        return true
    } catch {
        log("FAIL chrome: \(error)")
        return false
    }
}

/// The fallback path: hand a URL to a named app via LaunchServices, with no
/// command-line arguments involved. If this fails under sandbox, the App Store
/// build cannot route links at all.
func testPlainURLDelivery(urlString: String) async -> Bool {
    let bundleID = "com.google.Chrome"
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        log("SKIP plain: Chrome not installed")
        return false
    }
    guard let url = URL(string: urlString) else { return false }

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true

    do {
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        log("PASS plain: open(withApplicationAt:) returned")
        return true
    } catch {
        log("FAIL plain: \(error)")
        return false
    }
}

/// The sanctioned sandbox escape hatch: `NSUserUnixTask` runs a script the user
/// has manually placed in ~/Library/Application Scripts/<bundle-id>/. If this
/// works, profile routing is recoverable on the App Store build at the cost of
/// a one-time manual setup step. This is the mechanism Velja documents.
func testUserUnixTask(profileDirectory: String, urlString: String) async -> Bool {
    do {
        let scriptsDir = try FileManager.default.url(for: .applicationScriptsDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: false)
        let scriptURL = scriptsDir.appendingPathComponent("open.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            log("SKIP unixtask: no script at \(scriptURL.path)")
            return false
        }

        let task = try NSUserUnixTask(url: scriptURL)
        try await task.execute(withArguments: ["--profile-directory=\(profileDirectory)", urlString])
        log("PASS unixtask: script executed")
        return true
    } catch {
        log("FAIL unixtask: \(error)")
        return false
    }
}

func testArcAppleScript(urlString: String) -> Bool {
    let bundleID = "company.thebrowser.Browser"
    let running = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleID)
        .contains { !$0.isTerminated }
    guard running else {
        log("SKIP arc: not running (launch Arc and re-run to test this path)")
        return false
    }

    let source = """
    tell application "Arc"
        activate
        if (count of windows) is 0 then
            make new window
        end if
        tell front window
            make new tab with properties {URL:"\(urlString)"}
        end tell
    end tell
    """

    guard let script = NSAppleScript(source: source) else {
        log("FAIL arc: could not compile script")
        return false
    }

    var errorInfo: NSDictionary?
    _ = script.executeAndReturnError(&errorInfo)

    if let info = errorInfo {
        let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        log("FAIL arc (\(code)): \(info)")
        // -1743 means the user denied automation permission, which is a TCC
        // prompt result, not an entitlement failure. Re-run after approving.
        return false
    }
    log("PASS arc: tab created in front window")
    return true
}

let profile = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Default"
let url = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "https://example.com"

log("=== sandbox spike: profile='\(profile)' url='\(url)' ===")

let semaphore = DispatchSemaphore(value: 0)
Task {
    _ = await testChromeProfile(profileDirectory: profile, urlString: url)
    _ = await testPlainURLDelivery(urlString: url + "-plain")
    _ = await testUserUnixTask(profileDirectory: profile, urlString: url + "-unixtask")
    _ = testArcAppleScript(urlString: url)
    semaphore.signal()
}
semaphore.wait()
log("=== spike complete ===")
