import Foundation

/// Compile-time capability switches for the two distribution channels.
///
/// The App Store build runs inside the App Sandbox, which forbids several
/// things the Developer ID build can do. This enum is the **only** place
/// `#if APP_STORE` is allowed to appear — every feature site reads a boolean
/// instead, so the conditional compilation never spreads into behaviour code.
enum Capabilities {
    #if APP_STORE

    /// Apple has not extended runtime default-handler APIs to sandboxed apps,
    /// so `NSWorkspace.setDefaultApplication` cannot be used. The UI guides the
    /// user to System Settings instead.
    static let canSetDefaultBrowser = false

    /// Under the sandbox, `homeDirectoryForCurrentUser` resolves to the app's
    /// container, so `~/Applications` is not reachable.
    static let canEnumerateUserApplications = false

    /// App Review restricts donation links for individual developers; the App
    /// Store build offers a StoreKit tip jar instead.
    static let showsExternalDonationLink = false

    /// The App Sandbox silently drops
    /// `NSWorkspace.OpenConfiguration.arguments`: the target launches with no
    /// arguments at all, and `openApplication` still reports success.
    /// Verified by spike, 2026-08-11.
    static let canPassLaunchArguments = false

    /// Profile routing therefore goes through a user-installed helper script
    /// executed via `NSUserUnixTask`, which runs outside the sandbox.
    static let usesScriptBasedProfileRouting = true

    /// About-tab identity. Display strings only — no behaviour reads these.
    static let buildChannelName = "App Store"
    static let buildChannelDetail = "Sandboxed build · profile routing via helper script"

    #else

    static let canSetDefaultBrowser = true
    static let canEnumerateUserApplications = true
    static let showsExternalDonationLink = true
    static let canPassLaunchArguments = true
    static let usesScriptBasedProfileRouting = false

    static let buildChannelName = "Direct"
    static let buildChannelDetail = "Notarized build · profiles routed natively"

    #endif
}
