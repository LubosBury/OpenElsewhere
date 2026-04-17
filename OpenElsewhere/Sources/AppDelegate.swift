import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleGetURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        let senderBundleID = resolveSenderBundleID(from: event)
        let engine = RoutingEngine.shared

        guard engine.isEnabled else {
            BrowserLauncher.open(url, inBrowser: engine.defaultBrowserBundleID)
            return
        }

        let destination = engine.destination(forSourceApp: senderBundleID)
        BrowserLauncher.open(url,
                             inBrowser: destination.browserBundleID,
                             profileDirectory: destination.profileDirectoryName)
    }

    private func resolveSenderBundleID(from event: NSAppleEventDescriptor) -> String {
        // Primary: extract sender PID from the Apple Event.
        if let senderPIDDesc = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) {
            let pid = senderPIDDesc.int32Value
            if pid > 0, let app = NSRunningApplication(processIdentifier: pid_t(pid)),
               let bundleID = app.bundleIdentifier {
                return bundleID
            }
        }

        // Fallback: frontmost application.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier {
            return bundleID
        }

        return "unknown"
    }
}
