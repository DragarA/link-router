import RouterCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsModel
    @State private var pane: Pane? = .rules

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        case rules = "Rules"
        case browsers = "Browsers"

        var id: Self { self }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .rules: "arrow.triangle.branch"
            case .browsers: "globe"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.rawValue, systemImage: pane.icon)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 170, max: 220)
        } detail: {
            Group {
                switch pane ?? .rules {
                case .general: GeneralPane(model: model)
                case .rules: RulesPane(model: model)
                case .browsers: BrowsersPane(model: model)
                }
            }
            .navigationTitle((pane ?? .rules).rawValue)
            .safeAreaInset(edge: .top) {
                if let notice = model.notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.15))
                }
            }
        }
        // Every edit is saved immediately; the router re-reads the file on each link.
        .onChange(of: model.draft) { model.save() }
        .frame(minWidth: 700, minHeight: 460)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var model: SettingsModel
    @State private var isDefaultBrowser = false
    @State private var loginStatus = SMAppService.Status.notRegistered
    @State private var errorMessage: String?
    @State private var testLink = ""

    var body: some View {
        Form {
            Section("System") {
                LabeledContent("Default browser") {
                    if isDefaultBrowser {
                        Label("LinkRouter is the default", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Set as Default Browser") {
                            Task {
                                errorMessage = await SystemIntegration.makeDefaultBrowser()
                                refresh()
                            }
                        }
                    }
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { enabled in
                        errorMessage = SystemIntegration.setLaunchAtLogin(enabled)
                        refresh()
                    }
                ))
                if loginStatus == .requiresApproval {
                    LabeledContent("Allow LinkRouter in System Settings → Login Items") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Picker("Open other links in", selection: $model.draft.defaultTargetID) {
                    ForEach(model.draft.targets) { Text($0.name).tag($0.id) }
                }
            } header: {
                Text("Fallback")
            } footer: {
                Text("Used when no rule matches.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField("Link", text: $testLink, prompt: Text("Paste a link, e.g. gitlab.com/companyname"))
                if let result = model.draft.route(testLink) {
                    Label {
                        Text("Opens in \(Text(result.target).bold())") + Text(result.rule.map { " · rule “\($0)”" } ?? " · no rule matched, using fallback")
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                    }
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Test a link")
            } footer: {
                Text("Shows which browser a link would open in, without opening it. Handy for checking your rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        // Picks up changes made in System Settings while the window was in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        isDefaultBrowser = SystemIntegration.isDefaultBrowser
        loginStatus = SystemIntegration.loginItemStatus
    }
}

// MARK: - Rules

private struct EditingRule: Identifiable {
    var rule: EditableConfig.RuleItem
    var isNew: Bool
    var id: UUID { rule.id }
}

private struct RulesPane: View {
    @Bindable var model: SettingsModel
    @State private var editing: EditingRule?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($model.draft.rules) { $rule in
                    HStack(spacing: 10) {
                        Toggle("Enabled", isOn: $rule.enabled).labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name.isEmpty ? "Untitled" : rule.name)
                            Text(rule.matchers.map(\.text).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(model.draft.targetName(rule.targetID)).foregroundStyle(.secondary)
                        Button("Edit") { editing = EditingRule(rule: rule, isNew: false) }
                    }
                    .padding(.vertical, 3)
                    .opacity(rule.enabled ? 1 : 0.55)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editing = EditingRule(rule: rule, isNew: false) }
                    .contextMenu {
                        Button("Edit…") { editing = EditingRule(rule: rule, isNew: false) }
                        Button("Delete", role: .destructive) { model.draft.deleteRule(rule.id) }
                    }
                }
                .onMove { model.draft.rules.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack {
                Button {
                    editing = EditingRule(rule: model.draft.newRule(), isNew: true)
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Rule")
                Text("Rules are checked top to bottom; the first match wins. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
        .sheet(item: $editing) { item in
            // The editor works on a copy: Cancel discards, Save writes back.
            RuleEditor(
                rule: item.rule,
                isNew: item.isNew,
                targets: model.draft.targets,
                onSave: { model.draft.upsert($0) },
                onDelete: { model.draft.deleteRule(item.rule.id) }
            )
        }
    }
}

private struct RuleEditor: View {
    @State var rule: EditableConfig.RuleItem
    let isNew: Bool
    let targets: [EditableConfig.Target]
    let onSave: (EditableConfig.RuleItem) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sampleLink = ""

    private var sampleURL: URL? { EditableConfig.parseURL(sampleLink) }
    private var hasMatchers: Bool { rule.matchers.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $rule.name, prompt: Text("Gitlab"))
                    Picker("Open in", selection: $rule.targetID) {
                        ForEach(targets) { Text($0.name).tag($0.id) }
                    }
                }

                Section {
                    ForEach($rule.matchers) { $matcher in
                        HStack {
                            TextField("Domain", text: $matcher.text, prompt: Text("gitlab.com"))
                                .labelsHidden()
                            if let sampleURL, !matcher.text.isEmpty {
                                let matches = Router.matches(sampleURL, pattern: matcher.text)
                                Image(systemName: matches ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(matches ? .green : .secondary)
                                    .help(matches ? "Matches the sample link" : "Doesn't match the sample link")
                            }
                            Button {
                                rule.matchers.removeAll { $0.id == matcher.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(rule.matchers.count == 1)
                        }
                    }
                    Button("Add Domain") { rule.matchers.append(.init(text: "")) }
                } header: {
                    Text("URL Matchers")
                } footer: {
                    Text("“x.com” matches x.com and blog.x.com. “blog.x.com” only matches blog.x.com. Add a path to narrow it down: “gitlab.com/companyname”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Try a link") {
                    TextField("Sample link", text: $sampleLink, prompt: Text("https://gitlab.com/companyname/repo"))
                    if let sampleURL {
                        if rule.matchers.contains(where: { !$0.text.isEmpty && Router.matches(sampleURL, pattern: $0.text) }) {
                            Label("This rule matches", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label("This rule doesn't match", systemImage: "xmark.circle").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button("Delete Rule", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasMatchers)
            }
            .padding(12)
        }
        .frame(width: 500, height: 560)
    }
}

// MARK: - Browsers

private struct BrowsersPane: View {
    @Bindable var model: SettingsModel
    @State private var installed: [InstalledBrowser] = []
    @State private var profiles: [String: [ChromiumProfile]] = [:]

    var body: some View {
        Form {
            ForEach($model.draft.targets) { $target in
                Section {
                    TextField("Name", text: $target.name)
                    Picker("App", selection: $target.app) {
                        ForEach(installed) { browser in
                            Label { Text(browser.name) } icon: { Image(nsImage: browser.icon) }
                                .tag(browser.bundleID)
                        }
                        if !installed.contains(where: { $0.bundleID == target.app }) {
                            Text(target.app).tag(target.app)
                        }
                    }
                    profileRow(for: $target)
                    HStack {
                        Spacer()
                        Button("Remove Browser", role: .destructive) { model.draft.deleteTarget(target.id) }
                            .disabled(model.draft.targets.count == 1)
                    }
                }
            }
            Section {
                Button("Add Browser") { model.draft.addTarget() }
            } footer: {
                Text("A Chrome profile's folder is shown in chrome://version → Profile Path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            installed = SystemIntegration.installedBrowsers()
            for browser in installed where SystemIntegration.supportsProfiles(browser.bundleID) {
                profiles[browser.bundleID] = SystemIntegration.profiles(for: browser.bundleID)
            }
        }
    }

    @ViewBuilder
    private func profileRow(for target: Binding<EditableConfig.Target>) -> some View {
        let app = target.wrappedValue.app
        let current = target.wrappedValue.profile
        if let list = profiles[app], !list.isEmpty {
            Picker("Profile", selection: target.profile) {
                Text("Last used").tag("")
                ForEach(list) { Text("\($0.name)  (\($0.directory))").tag($0.directory) }
                if !current.isEmpty, !list.contains(where: { $0.directory == current }) {
                    Text(current).tag(current)
                }
            }
        } else if SystemIntegration.supportsProfiles(app) {
            TextField("Profile folder", text: target.profile, prompt: Text("Profile 1"))
        }
    }
}
