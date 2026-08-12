import Foundation

/// Outbound URLs and the version string shown in the About tab. Kept in one
/// place so the two build channels can differ in exactly one line each.
enum AppLinks {
    static let repository = URL(string: "https://github.com/LubosBury/OpenElsewhere")!
    static let releaseNotes = URL(string: "https://github.com/LubosBury/OpenElsewhere/releases")!
    static let privacy = URL(string: "https://github.com/LubosBury/OpenElsewhere/blob/main/PRIVACY.md")!
    static let support = URL(string: "https://github.com/LubosBury/OpenElsewhere/issues")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/bozka")!

    static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "OpenElsewhere \(short) (\(Capabilities.buildChannelName))"
    }
}
