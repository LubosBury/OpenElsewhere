import Foundation
import ServiceManagement

/// Login-item registration via `SMAppService.mainApp`.
///
/// The truth lives in LaunchServices, not in `UserDefaults` — the user can
/// remove the login item from System Settings → General → Login Items without
/// the app running — so `isEnabled` reads `status` every time rather than
/// caching it.
@MainActor
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the status actually achieved, so a caller that optimistically
    /// flipped a switch can settle it back if the request failed.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // `.requiresApproval` means the item is registered but the user
                // has it switched off in System Settings; re-registering would
                // throw, and the honest answer is "not enabled".
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("OpenElsewhere: launch-at-login \(enabled ? "register" : "unregister") failed — \(error.localizedDescription)")
        }
        return isEnabled
    }
}
