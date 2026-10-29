import AppKit
import RouterCore
import os

let log = Logger(subsystem: "com.anzedragar.LinkRouter", category: "routing")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private var statusItem: NSStatusItem?
    private lazy var settings = SettingsWindowController(store: store)
    private var receivedLinks = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.ensureExists()
        statusItem = makeStatusItem()
        NSApp.mainMenu = makeMainMenu()
        // Links that launched the app arrive before this point. Show settings only when the user
        // opened LinkRouter directly, not when a click or a login launch started it.
        if !receivedLinks && !launchedAsLoginItem() {
            settings.show()
        }
    }

    /// Opening LinkRouter again from Finder/Spotlight while it's running shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings.show()
        return false
    }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication)
        else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// macOS calls this for every link while we're the default browser, on cold launch and when running.
    func application(_ application: NSApplication, open urls: [URL]) {
        // Read modifiers at click time, before any async work.
        receivedLinks = true
        let pickManually = NSEvent.modifierFlags.contains(.option)
        let config = loadConfigOrFallback()

        for url in urls where url.scheme == "http" || url.scheme == "https" {
            if pickManually {
                showPicker(for: url, config: config)
            } else {
                let (browser, rule) = Router(config: config).route(url)
                log.notice("\(url.absoluteString, privacy: .public) → \(browser.profile ?? browser.app, privacy: .public) [\(rule?.name ?? "default", privacy: .public)]")
                open(url, in: browser)
            }
        }
    }

    // MARK: - Routing helpers

    /// A broken config must never swallow a link: fall back to the starter config and say so.
    private func loadConfigOrFallback() -> Config {
        do {
            return try store.load()
        } catch {
            log.error("Config error: \(String(describing: error), privacy: .public)")
            showAlert("LinkRouter config is invalid", "Using built-in defaults until it's fixed.\n\n\(error)")
            return .starter
        }
    }

    private func open(_ url: URL, in browser: Browser) {
        Task {
            do {
                try await BrowserLauncher.open(url, in: browser)
            } catch {
                log.error("Launch failed: \(String(describing: error), privacy: .public)")
                showAlert("Couldn't open link", "\(url.absoluteString)\n\n\(error)")
            }
        }
    }

    /// ⌥-click: choose the browser for this one link, ignoring the rules.
    private func showPicker(for url: URL, config: Config) {
        let menu = NSMenu()
        menu.addItem(withTitle: url.host() ?? url.absoluteString, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        for key in config.browsers.keys.sorted() {
            let item = ClosureMenuItem(title: key.capitalized) { [weak self] in
                self?.open(url, in: config.browsers[key]!)
            }
            menu.addItem(item)
        }
        NSApp.activate()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Menu bar

    /// Never visible (we're a menu-bar-only app), but ⌘C/⌘V/⌘X/⌘A/⌘Z in text fields are
    /// key equivalents of these menu items. Without them, those shortcuts do nothing.
    private func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for submenu in [NSMenu(title: "LinkRouter"), edit, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "LinkRouter")

        let menu = NSMenu()
        let settingsItem = ClosureMenuItem(title: "Settings…") { [weak self] in
            self?.settings.show()
        }
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(ClosureMenuItem(title: "Reveal Config in Finder") { [store] in
            NSWorkspace.shared.activateFileViewerSelecting([store.url])
        })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LinkRouter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}

/// NSMenuItem that runs a closure, avoiding a selector per menu entry.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
