import Foundation
import RouterCore

/// ~/.config/linkrouter/config.json, re-read on every link so edits apply immediately.
struct ConfigStore: Sendable {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/linkrouter/config.json")

    func load() throws -> Config {
        try Config.decode(Data(contentsOf: url))
    }

    func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.encoded().write(to: url, options: .atomic)
    }

    func ensureExists() {
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Config.starter.encoded().write(to: url)
        } catch {
            log.error("Couldn't write starter config: \(String(describing: error), privacy: .public)")
        }
    }
}
