import Foundation

/// Removes every trace Ebbrim leaves on a Mac, except the app bundle itself
/// (the caller trashes it). Never touches Claude's or Codex's own data or logins.
enum Uninstaller {
    struct Report { var done: [String] = []; var problems: [String] = [] }

    /// Where `install.sh` keeps its git checkout when run from the one-line installer.
    static let defaultSourceCheckout = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ebbrim")

    static func cleanup(settings: URL = StatusLineInstaller.settingsURL,
                        support: URL = StatusLineSource.folder,
                        sourceCheckout: URL = defaultSourceCheckout,
                        defaultsDomain: String = Bundle.main.bundleIdentifier ?? "com.denys.ebbrim",
                        preferencesDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences"),
                        unregisterLoginItem: () throws -> Bool) -> Report {
        var r = Report()
        let fm = FileManager.default

        if StatusLineInstaller.isInstalled(settings: settings) {
            do {
                try StatusLineInstaller.uninstall(settings: settings,
                                                  backup: support.appendingPathComponent("statusline-previous.json"))
                r.done.append("Restored your previous Claude Code statusLine")
            } catch {
                r.problems.append("Could not restore ~/.claude/settings.json: \(error.localizedDescription)")
            }
        }
        do { if try unregisterLoginItem() { r.done.append("Removed the login item") } }
        catch { r.problems.append("Could not remove the login item: \(error.localizedDescription)") }

        for (url, what) in [(support, "Removed Ebbrim's data folder"), (sourceCheckout, "Removed the downloaded source")]
        where fm.fileExists(atPath: url.path) {
            do { try fm.removeItem(at: url); r.done.append(what) }
            catch { r.problems.append("Could not remove \(url.path): \(error.localizedDescription)") }
        }
        UserDefaults.standard.removePersistentDomain(forName: defaultsDomain)
        // cfprefsd writes an empty plist for the removed domain a moment later;
        // let it flush first, then delete the file it leaves behind.
        CFPreferencesAppSynchronize(defaultsDomain as CFString)
        try? fm.removeItem(at: preferencesDir.appendingPathComponent("\(defaultsDomain).plist"))
        r.done.append("Cleared Ebbrim's preferences")
        return r
    }
}
