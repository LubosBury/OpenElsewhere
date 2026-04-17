import AppKit
import Foundation

/// `NSApplicationDelegate` is itself `@MainActor`-isolated in modern SDKs; the
/// explicit annotation here makes the isolation of our own methods obvious to
/// the reader and lets us call `@MainActor`-isolated `RoutingEngine` members
/// directly. Apple Events registered via `NSAppleEventManager` are delivered
/// on the main run loop, so the contract holds at runtime.
@MainActor
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
        // NSAppleEventManager dispatches on the main thread; assert the
        // isolation so the `@MainActor`-isolated RoutingEngine singleton is
        // callable from this @objc entry point without an async hop.
        MainActor.assumeIsolated {
            dispatch(event: event)
        }
    }

    private func dispatch(event: NSAppleEventDescriptor) {
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
