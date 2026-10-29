import AppKit
import Observation
import RouterCore
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    var draft: EditableConfig
    var notice: String?
    @ObservationIgnored private let store: ConfigStore

    init(store: ConfigStore) {
        self.store = store
        draft = EditableConfig(.starter)
        reload()
    }

    /// Picks up hand edits to config.json. Only replaces the draft when the file actually differs,
    /// so reopening the window doesn't rewrite the file (or clobber a broken one).
    func reload() {
        do {
            let loaded = try store.load()
            if loaded != draft.config {
                draft = EditableConfig(loaded)
            }
            notice = nil
        } catch {
            notice = "config.json couldn't be read, so defaults are shown. Your next change here will overwrite it.\n\(error)"
        }
    }

    func save() {
        do {
            try store.save(draft.config)
        } catch {
            notice = "Couldn't save config.json: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(store: ConfigStore) {
        model = SettingsModel(store: store)
    }

    func show() {
        if let window {
            model.reload()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "LinkRouter"
        window.setContentSize(NSSize(width: 780, height: 540))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
