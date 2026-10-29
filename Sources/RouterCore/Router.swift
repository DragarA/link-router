import Foundation

public struct Router: Sendable {
    public let config: Config

    public init(config: Config) {
        self.config = config
    }

    /// Picks the browser for a link. First matching rule wins, otherwise the default.
    public func route(_ url: URL) -> (browser: Browser, rule: Rule?) {
        let url = Self.unwrapRedirect(url)
        for rule in config.rules where rule.enabled && rule.match.contains(where: { Self.matches(url, pattern: $0) }) {
            if let browser = config.browsers[rule.browser] {
                return (browser, rule)
            }
        }
        return (config.browsers[config.default]!, nil)
    }

    /// Velja-style domain matching: "x.com" matches x.com and any subdomain (blog.x.com).
    /// An optional path ("gitlab.com/my-group") additionally restricts by path prefix.
    public static func matches(_ url: URL, pattern rawPattern: String) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }

        var pattern = rawPattern.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where pattern.hasPrefix(scheme) {
            pattern.removeFirst(scheme.count)
        }
        let parts = pattern.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard let domainPart = parts.first else { return false }
        let domain = domainPart.hasPrefix("*.") ? String(domainPart.dropFirst(2)) : String(domainPart)

        // The "." check stops "notgitlab.com" from matching "gitlab.com".
        guard host == domain || host.hasSuffix("." + domain) else { return false }

        guard parts.count == 2 else { return true }
        let prefix = "/" + parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = url.path().lowercased()
        // Match on segment boundaries: "/acme" matches "/acme" and "/acme/x", not "/acmecorp".
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    /// Unwraps common tracking/safety redirects so the *real* destination gets routed.
    static func unwrapRedirect(_ url: URL) -> URL {
        guard let host = url.host()?.lowercased(),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return url }

        let param: String? = switch true {
        case host.hasSuffix("safelinks.protection.outlook.com"): "url"
        case host == "slack-redir.net": "url"
        case (host == "www.google.com" || host == "google.com") && url.path() == "/url": "q"
        default: nil
        }

        guard let param,
              let value = items.first(where: { $0.name == param })?.value,
              let target = URL(string: value),
              target.scheme == "http" || target.scheme == "https"
        else { return url }
        return target
    }
}
