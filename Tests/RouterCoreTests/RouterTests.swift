import Foundation
import Testing
@testable import RouterCore

private let work = Browser(app: "com.google.Chrome", profile: "Profile 1")
private let personal = Browser(app: "com.google.Chrome", profile: "Default")

private func route(_ string: String, config: Config = .starter) -> Browser {
    Router(config: config).route(URL(string: string)!).browser
}

@Test func unmatchedLinksGoToDefault() {
    #expect(route("https://www.youtube.com/watch?v=x") == personal)
    #expect(route("https://facebook.com") == personal)
}

@Test func starterRulesMirrorVelja() {
    #expect(route("https://gitlab.com/companyname/project/-/merge_requests/1") == work)
    #expect(route("https://meet.google.com/abc-defg-hij") == work)
    #expect(route("https://companyname.atlassian.net/browse/ABC-1") == work)
}

@Test func domainMatchesItselfAndSubdomainsOnly() {
    #expect(Router.matches(URL(string: "https://x.com")!, pattern: "x.com"))
    #expect(Router.matches(URL(string: "https://blog.x.com/post")!, pattern: "x.com"))
    #expect(!Router.matches(URL(string: "https://notx.com")!, pattern: "x.com"))
    #expect(!Router.matches(URL(string: "https://x.com")!, pattern: "blog.x.com"))
}

@Test func matchingIsCaseInsensitiveAndToleratesSchemesAndWildcards() {
    #expect(Router.matches(URL(string: "https://GitLab.COM/a")!, pattern: "gitlab.com"))
    #expect(Router.matches(URL(string: "https://gitlab.com/a")!, pattern: "https://gitlab.com"))
    #expect(Router.matches(URL(string: "https://a.b.example.com")!, pattern: "*.example.com"))
}

@Test func pathPrefixRespectsSegmentBoundaries() {
    let pattern = "gitlab.com/acme"
    #expect(Router.matches(URL(string: "https://gitlab.com/acme")!, pattern: pattern))
    #expect(Router.matches(URL(string: "https://gitlab.com/acme/repo")!, pattern: pattern))
    #expect(Router.matches(URL(string: "https://gitlab.com/ACME/repo")!, pattern: pattern))
    #expect(!Router.matches(URL(string: "https://gitlab.com/acmecorp")!, pattern: pattern))
    #expect(!Router.matches(URL(string: "https://gitlab.com/other")!, pattern: pattern))
}

@Test func firstMatchingRuleWins() {
    let config = Config(
        browsers: ["personal": personal, "work": work],
        default: "work",
        rules: [
            Rule(match: ["docs.google.com"], browser: "personal"),
            Rule(match: ["google.com"], browser: "work"),
        ]
    )
    #expect(route("https://docs.google.com/x", config: config) == personal)
    #expect(route("https://mail.google.com", config: config) == work)
}

@Test func redirectsAreUnwrappedBeforeMatching() {
    let safelink = "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgitlab.com%2Facme&data=x"
    #expect(route(safelink) == work)
    #expect(route("https://slack-redir.net/link?url=https%3A%2F%2Fgitlab.com%2Facme") == work)
    // Non-http payloads are ignored rather than followed.
    let js = Router.unwrapRedirect(URL(string: "https://slack-redir.net/link?url=javascript%3Aalert(1)")!)
    #expect(js.host() == "slack-redir.net")
}

@Test func invalidConfigIsRejected() throws {
    let badDefault = #"{"browsers":{"a":{"app":"x"}},"default":"b","rules":[]}"#
    #expect(throws: Config.ValidationError.self) { try Config.decode(Data(badDefault.utf8)) }
    let badRule = #"{"browsers":{"a":{"app":"x"}},"default":"a","rules":[{"match":["x.com"],"browser":"zzz"}]}"#
    #expect(throws: Config.ValidationError.self) { try Config.decode(Data(badRule.utf8)) }
}

@Test func starterConfigRoundTrips() throws {
    #expect(try Config.decode(Config.starter.encoded()) == .starter)
}
