import Foundation

/// The on/off switches for Claude, Codex and Local servers. A fresh install has
/// everything off: the user connects each source in onboarding or Settings, so
/// nothing is read before they choose it.
enum SourceSwitches {
    static func isOn(_ key: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }
}
