import AppKit
import ServiceManagement

struct InstalledBrowser: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage
    var id: String { bundleID }
}

struct ChromiumProfile: Identifiable, Hashable {
    let directory: String
    let name: String
    var id: String { directory }
}

/// Everything that talks to macOS on behalf of the settings window.
@MainActor
enum SystemIntegration {
    private static let probeURL = URL(string: "https://example.com")!

    // MARK: Default browser

    static var isDefaultBrowser: Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm. Returns an error message on failure.
    static func makeDefaultBrowser() async -> String? {
        do {
            for scheme in ["http", "https"] {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Launch at login

    static var loginItemStatus: SMAppService.Status { SMAppService.mainApp.status }

    /// Returns an error message on failure.
    static func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Browsers and profiles

    static func installedBrowsers() -> [InstalledBrowser] {
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
            .compactMap { url -> InstalledBrowser? in
                guard let id = Bundle(url: url)?.bundleIdentifier,
                      id != Bundle.main.bundleIdentifier,
                      seen.insert(id).inserted
                else { return nil }
                let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                icon.size = NSSize(width: 16, height: 16)
                return InstalledBrowser(bundleID: id, name: url.deletingPathExtension().lastPathComponent, icon: icon)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Chromium browsers keep their profile list in "<support dir>/Local State".
    private static let chromiumSupportDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
    ]

    static func supportsProfiles(_ bundleID: String) -> Bool {
        chromiumSupportDirs[bundleID] != nil
    }

    /// Empty if the browser isn't Chromium-based or macOS privacy settings block the read;
    /// the UI then falls back to a plain text field.
    static func profiles(for bundleID: String) -> [ChromiumProfile] {
        guard let dir = chromiumSupportDirs[bundleID] else { return [] }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/\(dir)/Local State")
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any]
        else { return [] }
        return cache
            .map { directory, info in
                ChromiumProfile(directory: directory, name: (info as? [String: Any])?["name"] as? String ?? directory)
            }
            .sorted { $0.directory.localizedStandardCompare($1.directory) == .orderedAscending }
    }
}
