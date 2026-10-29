import Foundation
import Testing
@testable import RouterCore

@Test func disabledRulesAreSkipped() {
    var config = Config.starter
    config.rules = config.rules.map { var r = $0; r.enabled = r.name != "Gitlab"; return r }
    let result = Router(config: config).route(URL(string: "https://gitlab.com/acme")!)
    #expect(result.rule == nil)
    #expect(result.browser == config.browsers[config.default])
}

@Test func legacyConfigWithoutEnabledDecodesAsEnabled() throws {
    let json = #"{"browsers":{"a":{"app":"x"}},"default":"a","rules":[{"match":["x.com"],"browser":"a"}]}"#
    #expect(try Config.decode(Data(json.utf8)).rules[0].enabled)
}

@Test func editableConfigRoundTrips() {
    #expect(EditableConfig(.starter).config == .starter)
}

@Test func renamingTargetKeepsRuleReferences() {
    var draft = EditableConfig(.starter)
    let work = draft.targets.firstIndex { $0.name == "work" }!
    draft.targets[work].name = "Work"
    let config = draft.config
    #expect(config.browsers["Work"] != nil)
    #expect(config.rules.allSatisfy { $0.browser == "Work" })
}

@Test func duplicateAndBlankNamesStayValid() throws {
    var draft = EditableConfig(.starter)
    for i in draft.targets.indices { draft.targets[i].name = " " }
    let config = draft.config
    #expect(Set(config.browsers.keys) == ["Untitled", "Untitled 2"])
    #expect(try Config.decode(config.encoded()) == config)
}

@Test func deletingTargetReassignsRulesToDefault() {
    var draft = EditableConfig(.starter)
    let work = draft.targets.first { $0.name == "work" }!.id
    draft.deleteTarget(work)
    #expect(draft.targets.count == 1)
    #expect(draft.rules.allSatisfy { $0.targetID == draft.defaultTargetID })
    // The last remaining browser can't be deleted.
    draft.deleteTarget(draft.defaultTargetID)
    #expect(draft.targets.count == 1)
}

@Test func upsertDropsBlankMatchersAndAppendsNewRules() {
    var draft = EditableConfig(.starter)
    var rule = draft.newRule()
    rule.matchers = [.init(text: "sentry.io"), .init(text: "  ")]
    draft.upsert(rule)
    #expect(draft.rules.last?.matchers.map(\.text) == ["sentry.io"])
    rule.name = "Sentry"
    draft.upsert(rule)
    #expect(draft.rules.count == 4)
    #expect(draft.rules.last?.name == "Sentry")
}

@Test func routeExplainsDecision() {
    let draft = EditableConfig(.starter)
    let gitlab = draft.route("gitlab.com/companyname")
    #expect(gitlab?.target == "work")
    #expect(gitlab?.rule == "Gitlab")
    #expect(draft.route("https://youtube.com")?.rule == nil)
    #expect(draft.route("https://youtube.com")?.target == "personal")
    #expect(draft.route("") == nil)
}
