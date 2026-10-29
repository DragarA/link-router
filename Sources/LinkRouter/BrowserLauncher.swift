import AppKit
import RouterCore

enum BrowserLauncher {
    struct AppNotFound: Error, CustomStringConvertible {
        let bundleID: String
        var description: String { "No app installed with bundle ID \(bundleID)" }
    }

    @MainActor
    static func open(_ url: URL, in browser: Browser) async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.app) else {
            throw AppNotFound(bundleID: browser.app)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let profile = browser.profile {
            // Chromium only takes a profile as a launch argument. A new instance is required:
            // asking an already-running Chrome to "open" would ignore the arguments. The new
            // process hands the URL to the running one (in the right profile) and exits.
            configuration.arguments = ["--profile-directory=\(profile)", url.absoluteString]
            configuration.createsNewApplicationInstance = true
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } else {
            try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
    }
}
