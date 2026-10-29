import Foundation

/// A UI-friendly view of `Config`. Items have stable IDs, and rules reference browsers by ID,
/// so renaming a browser in the settings window can't break the rules that point at it.
/// Names are only resolved back into `Config`'s string keys when saving.
public struct EditableConfig: Equatable, Sendable {
    public struct Target: Identifiable, Hashable, Sendable {
        public var id: UUID
        public var name: String
        public var app: String
        /// Chromium profile directory; empty means "don't pass a profile".
        public var profile: String

        public init(id: UUID = UUID(), name: String, app: String, profile: String = "") {
            self.id = id
            self.name = name
            self.app = app
            self.profile = profile
        }
    }

    public struct Matcher: Identifiable, Hashable, Sendable {
        public var id: UUID
        public var text: String

        public init(id: UUID = UUID(), text: String) {
            self.id = id
            self.text = text
        }
    }

    public struct RuleItem: Identifiable, Hashable, Sendable {
        public var id: UUID
        public var name: String
        public var enabled: Bool
        public var matchers: [Matcher]
        public var targetID: UUID

        public init(id: UUID = UUID(), name: String, enabled: Bool = true, matchers: [Matcher], targetID: UUID) {
            self.id = id
            self.name = name
            self.enabled = enabled
            self.matchers = matchers
            self.targetID = targetID
        }
    }

    public var targets: [Target]
    public var rules: [RuleItem]
    public var defaultTargetID: UUID

    public init(_ config: Config) {
        let targets = config.browsers
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { Target(name: $0.key, app: $0.value.app, profile: $0.value.profile ?? "") }
        let idByName = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0.id) })
        let fallback = idByName[config.default] ?? targets.first?.id ?? UUID()

        self.targets = targets
        self.defaultTargetID = fallback
        self.rules = config.rules.map { rule in
            RuleItem(
                name: rule.name ?? "",
                enabled: rule.enabled,
                matchers: rule.match.map { Matcher(text: $0) },
                targetID: idByName[rule.browser] ?? fallback
            )
        }
    }

    /// Converts back to the on-disk format. Always produces a valid config:
    /// blank names become "Untitled" and duplicates get a numeric suffix.
    public var config: Config {
        var browsers: [String: Browser] = [:]
        var keyByID: [UUID: String] = [:]
        for target in targets {
            let base = target.name.trimmed.isEmpty ? "Untitled" : target.name.trimmed
            var key = base
            var suffix = 2
            while browsers[key] != nil {
                key = "\(base) \(suffix)"
                suffix += 1
            }
            browsers[key] = Browser(app: target.app, profile: target.profile.trimmed.isEmpty ? nil : target.profile.trimmed)
            keyByID[target.id] = key
        }
        let defaultKey = keyByID[defaultTargetID] ?? browsers.keys.sorted().first ?? ""
        let rules = self.rules.map { item in
            Rule(
                name: item.name.trimmed.isEmpty ? nil : item.name.trimmed,
                enabled: item.enabled,
                match: item.matchers.map(\.text.trimmed).filter { !$0.isEmpty },
                browser: keyByID[item.targetID] ?? defaultKey
            )
        }
        return Config(browsers: browsers, default: defaultKey, rules: rules)
    }

    public func targetName(_ id: UUID) -> String {
        targets.first { $0.id == id }?.name ?? "—"
    }

    /// A blank rule pointing at the first non-default browser (usually "work").
    public func newRule() -> RuleItem {
        RuleItem(
            name: "",
            matchers: [Matcher(text: "")],
            targetID: targets.first { $0.id != defaultTargetID }?.id ?? defaultTargetID
        )
    }

    public mutating func upsert(_ rule: RuleItem) {
        var rule = rule
        rule.matchers.removeAll { $0.text.trimmed.isEmpty }
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    public mutating func deleteRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func addTarget() -> UUID {
        let target = Target(name: "New Browser", app: "com.google.Chrome")
        targets.append(target)
        return target.id
    }

    /// Rules that used the deleted browser fall back to the default one. The last browser can't be deleted.
    public mutating func deleteTarget(_ id: UUID) {
        guard targets.count > 1 else { return }
        targets.removeAll { $0.id == id }
        if defaultTargetID == id {
            defaultTargetID = targets[0].id
        }
        for index in rules.indices where rules[index].targetID == id {
            rules[index].targetID = defaultTargetID
        }
    }

    /// Lenient URL parsing for text fields: "gitlab.com/x" is treated as "https://gitlab.com/x".
    public static func parseURL(_ text: String) -> URL? {
        var text = text.trimmed
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    /// Which browser a link would open in, and which rule decided it (nil = default).
    public func route(_ text: String) -> (target: String, rule: String?)? {
        guard let url = Self.parseURL(text) else { return nil }
        let config = self.config
        let result = Router(config: config).route(url)
        return (result.rule?.browser ?? config.default, result.rule.map { $0.name ?? $0.match.joined(separator: ", ") })
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
