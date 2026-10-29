import Foundation

public struct Browser: Codable, Equatable, Sendable {
    /// Bundle identifier, e.g. "com.google.Chrome".
    public var app: String
    /// Chrome profile *directory* name ("Default", "Profile 1"), not the display name.
    public var profile: String?

    public init(app: String, profile: String? = nil) {
        self.app = app
        self.profile = profile
    }
}

public struct Rule: Codable, Equatable, Sendable {
    public var name: String?
    /// Unchecked rules stay in the list but are ignored when routing.
    public var enabled: Bool
    /// Patterns like "gitlab.com" or "gitlab.com/my-group". The link must match one of them.
    public var match: [String]
    /// Key into `Config.browsers`.
    public var browser: String

    public init(name: String? = nil, enabled: Bool = true, match: [String], browser: String) {
        self.name = name
        self.enabled = enabled
        self.match = match
        self.browser = browser
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        // Configs written before checkboxes existed have no "enabled" key.
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        match = try container.decode([String].self, forKey: .match)
        browser = try container.decode(String.self, forKey: .browser)
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var browsers: [String: Browser]
    public var `default`: String
    public var rules: [Rule]

    public init(browsers: [String: Browser], default: String, rules: [Rule]) {
        self.browsers = browsers
        self.default = `default`
        self.rules = rules
    }

    public static func decode(_ data: Data) throws -> Config {
        let config = try JSONDecoder().decode(Config.self, from: data)
        try config.validate()
        return config
    }

    public struct ValidationError: Error, CustomStringConvertible {
        public let description: String
    }

    func validate() throws {
        guard browsers[`default`] != nil else {
            throw ValidationError(description: "default browser '\(`default`)' is not defined in \"browsers\"")
        }
        for rule in rules where browsers[rule.browser] == nil {
            throw ValidationError(description: "rule '\(rule.name ?? rule.match.joined(separator: ","))' uses unknown browser '\(rule.browser)'")
        }
    }

    /// Mirrors the user's Velja setup; written to disk on first launch.
    public static let starter = Config(
        browsers: [
            "personal": Browser(app: "com.google.Chrome", profile: "Default"),
            "work": Browser(app: "com.google.Chrome", profile: "Profile 1"),
        ],
        default: "personal",
        rules: [
            Rule(name: "Meet", match: ["google.com"], browser: "work"),
            Rule(name: "Gitlab", match: ["gitlab.com"], browser: "work"),
            Rule(name: "Jira", match: ["atlassian.net"], browser: "work"),
        ]
    )

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
