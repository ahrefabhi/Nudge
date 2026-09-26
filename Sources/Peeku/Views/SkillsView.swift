import AppKit
import PeekuKit
import SwiftUI

/// The Skills utility, opened from the manager's footer dock: the plugins and skills Claude Code
/// and Codex load, globally or per project, and what their marketplaces offer.
struct SkillsView: View {
    @Environment(\.palette) private var palette
    /// Nil in snapshots, which have nothing to list.
    let manager: SkillManager?

    /// Past this many matches Discover asks for a search instead of drawing them all.
    private static let discoverLimit = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let manager {
                controls(manager)
                if let notice = manager.notice { noticeBar(notice, manager) }
                switch manager.section {
                case .installed: InstalledList(manager: manager)
                case .discover: DiscoverList(manager: manager, limit: Self.discoverLimit)
                }
            } else {
                Spacer()
            }
        }
        .task { manager?.refreshIfStale() }
    }

    private func controls(_ manager: SkillManager) -> some View {
        @Bindable var manager = manager
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                sectionButton("Installed", count: visible(manager.installed, manager).count, .installed, manager)
                sectionButton("Discover", count: nil, .discover, manager)
                Spacer()
                agentChip(nil, "All", manager)
                agentChip(.claude, "Claude", manager)
                agentChip(.codex, "Codex", manager)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.label(0.45))
                TextField("Search", text: $manager.query,
                          prompt: Text(manager.section == .installed ? "Search installed" : "Search \(manager.catalog.count.formatted()) plugins"))
                    .textFieldStyle(.plain)
                    .font(.peeku(12))
                if !manager.query.isEmpty {
                    Button { manager.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(palette.label(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(palette.fill(0.06)))
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
    }

    private func sectionButton(_ title: String, count: Int?, _ section: SkillManager.Section, _ manager: SkillManager) -> some View {
        Button {
            manager.section = section
            manager.expanded = nil
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if let count { Text("\(count)").foregroundStyle(palette.label(0.45)) }
            }
        }
        .buttonStyle(ChipStyle(selected: manager.section == section))
        .accessibilityAddTraits(manager.section == section ? .isSelected : [])
    }

    private func agentChip(_ agent: Agent?, _ title: String, _ manager: SkillManager) -> some View {
        Button { manager.agentFilter = agent } label: {
            HStack(spacing: 4) {
                if let agent { AgentMark(agent: agent, size: 9) }
                Text(title)
            }
        }
        .buttonStyle(ChipStyle(selected: manager.agentFilter == agent))
        .accessibilityAddTraits(manager.agentFilter == agent ? .isSelected : [])
    }

    private func noticeBar(_ notice: String, _ manager: SkillManager) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent(.finished))
            Text(notice).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { manager.dismissNotice() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(palette.label(0.45))
                .accessibilityLabel("Dismiss")
        }
        .font(.peeku(11.5))
        .foregroundStyle(palette.label(0.8))
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.accent(.finished).opacity(0.12)))
        .padding(.horizontal, 16).padding(.bottom, 4)
    }
}

/// Items matching the agent filter and the search.
@MainActor
private func visible(_ items: [InstalledSkill], _ manager: SkillManager) -> [InstalledSkill] {
    items.filter { item in
        (manager.agentFilter == nil || item.agent == manager.agentFilter)
            && matches(manager.query, [item.name, item.summary, item.pluginID] + item.skills)
    }
}

private func matches(_ query: String, _ fields: [String?]) -> Bool {
    let words = query.lowercased().split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return true }
    let text = fields.compactMap { $0?.lowercased() }.joined(separator: " ")
    return words.allSatisfy { text.contains($0) }
}

// MARK: Installed

private struct InstalledList: View {
    @Environment(\.palette) private var palette
    let manager: SkillManager

    var body: some View {
        let items = visible(manager.installed, manager)
        let groups = Dictionary(grouping: items, by: \.scope)
        let scopes = [SkillScope.global] + manager.projects.map(SkillScope.project)
        SnapshotSafeScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                AddSkillBar(manager: manager)
                if items.isEmpty {
                    emptyState.padding(.top, 30)
                }
                ForEach(scopes.filter { groups[$0] != nil }, id: \.self) { scope in
                    ScopeLabel(scope: scope).padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    ForEach(groups[scope] ?? []) { InstalledRow(item: $0, manager: manager) }
                }
            }
            .padding(EdgeInsets(top: 2, leading: 8, bottom: 10, trailing: 8))
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 6) {
            if manager.loading && manager.loadedAt == nil {
                Spinner(size: 14)
                Text("Reading your plugins and skills…")
            } else if manager.agents.isEmpty && manager.loadedAt != nil && manager.installed.isEmpty {
                Text("Install Claude Code or Codex to manage their skills here.")
            } else {
                Text(manager.query.isEmpty ? "Nothing installed yet" : "Nothing matches “\(manager.query)”")
                    .font(.peeku(13, .semibold)).foregroundStyle(palette.primary)
                if manager.query.isEmpty {
                    Button("Browse Plugins") { manager.section = .discover }
                        .buttonStyle(PrimaryPillStyle(fontSize: 12))
                        .padding(.top, 6)
                }
            }
        }
        .font(.peeku(12))
        .foregroundStyle(palette.label(0.55))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// "GLOBAL", or "PROJECT · name" with the folder in a tooltip.
private struct ScopeLabel: View {
    let scope: SkillScope
    @Environment(\.palette) private var palette

    var body: some View {
        switch scope {
        case .global: SectionLabel(title: "GLOBAL")
        case .project(let path):
            HStack(spacing: 6) {
                SectionLabel(title: "PROJECT")
                Text(scope.title).font(.peeku(10.5, .semibold)).foregroundStyle(palette.label(0.6))
                Text(abbreviate(path)).font(.peeku(10.5)).foregroundStyle(palette.label(0.3))
                    .lineLimit(1).truncationMode(.head)
            }
            .help(path)
        }
    }
}

private struct InstalledRow: View {
    @Environment(\.palette) private var palette
    let item: InstalledSkill
    let manager: SkillManager
    @State private var hovering = false
    /// The trash button was clicked once and now asks again, since the notch can't show a dialog.
    @State private var confirmingRemove = false

    private var expanded: Bool { manager.expanded == item.id }
    private var other: Agent { item.agent == .claude ? .codex : .claude }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                AgentMark(agent: item.agent, size: 12).frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.name)
                            .font(.peeku(13, .semibold))
                            .foregroundStyle(item.enabled == false ? palette.label(0.5) : palette.primary)
                            .lineLimit(1)
                        Tag(text: item.isPlugin ? "Plugin" : "Skill")
                        if item.enabled == false { Tag(text: "Off") }
                    }
                    if let summary = item.summary {
                        Text(summary)
                            .font(.peeku(11.5))
                            .foregroundStyle(palette.label(0.55))
                            .lineLimit(expanded ? 6 : 1)
                            .fixedSize(horizontal: false, vertical: expanded)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            if expanded { details.padding(.leading, 26) }
            if let failure = manager.failures[item.id] { FailureText(text: failure).padding(.leading, 26) }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.fill(hovering || expanded ? 0.055 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { manager.expanded = expanded ? nil : item.id }
        .onHover { inside in
            hovering = inside
            if !inside { confirmingRemove = false }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: confirmingRemove)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(item.agent.productName) \(item.isPlugin ? "plugin" : "skill")")
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 6) {
            if let label = manager.working[item.id] {
                Spinner()
                Text(label).font(.peeku(11)).foregroundStyle(palette.label(0.5))
            } else {
                if confirmingRemove {
                    Button(item.isPlugin ? "Uninstall" : "Move to Trash") { manager.remove(item) }
                        .buttonStyle(DeleteStyle())
                        .fixedSize()
                } else if hovering || expanded {
                    IconButton(symbol: "trash", help: item.isPlugin ? "Uninstall" : "Move to Trash") { confirmingRemove = true }
                }
                if let enabled = item.enabled, item.agent == .claude {
                    SettingsSwitch(isOn: enabled) { manager.setEnabled(item, $0) }
                        .accessibilityLabel("\(item.name) enabled")
                        .help(enabled ? "Turn off without uninstalling" : "Turn on")
                }
            }
        }
        .padding(.top, 1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !item.skills.isEmpty {
                DetailLine(label: "Skills", value: item.skills.joined(separator: ", "))
            }
            if let id = item.pluginID { DetailLine(label: "ID", value: id + (item.version.map { " · \($0)" } ?? "")) }
            if let location = item.location { DetailLine(label: "Folder", value: abbreviate(location.path)) }
            HStack(spacing: 6) {
                if let location = item.location {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([location]) }
                        .buttonStyle(ChipStyle(selected: false))
                }
                if case .skill = item.kind, !manager.hasCopy(of: item, for: other) {
                    Button { manager.copy(item, to: other) } label: {
                        HStack(spacing: 4) {
                            AgentMark(agent: other, size: 9)
                            Text("Also for \(other.name)")
                        }
                    }
                    .buttonStyle(ChipStyle(selected: false))
                    .help("Copy this skill so \(other.productName) loads it too")
                }
            }
            .padding(.top, 2)
        }
    }
}

/// "Add a skill folder to [Claude] in [Global ▾]  Choose Folder…"
private struct AddSkillBar: View {
    @Environment(\.palette) private var palette
    let manager: SkillManager

    private var key: String { "add:\(manager.addAgent.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a skill folder").font(.peeku(12, .semibold)).foregroundStyle(palette.primary)
            Text("A folder with a SKILL.md, like one you wrote or cloned. Peeku copies it into the agent's skills folder, and new sessions load it.")
                .foregroundStyle(palette.label(0.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("For").foregroundStyle(palette.label(0.55))
                SettingsMenu(title: manager.addAgent.name) {
                    ForEach(Agent.allCases, id: \.self) { agent in
                        Button(agent.productName) { manager.addAgent = agent }
                    }
                }
                .fixedSize()
                Text("in").foregroundStyle(palette.label(0.55))
                ScopeMenu(manager: manager, scope: manager.addScope) { manager.addScope = $0 }
                Spacer(minLength: 4)
                if let label = manager.working[key] {
                    Spinner()
                    Text(label).foregroundStyle(palette.label(0.5))
                } else {
                    Button("Choose Folder…") { manager.pickSkillFolder(agent: manager.addAgent, scope: manager.addScope) }
                        .buttonStyle(RowOpenStyle())
                        .fixedSize()
                }
            }
            .padding(.top, 2)
            if let failure = manager.failures[key] { FailureText(text: failure) }
        }
        .font(.peeku(11.5))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill(0.04)))
        .padding(.top, 4)
    }
}

/// A pop-up of Global, each known project, and Choose Folder… for another one.
private struct ScopeMenu: View {
    let manager: SkillManager
    let scope: SkillScope
    let choose: (SkillScope) -> Void

    var body: some View {
        SettingsMenu(title: scope.title) {
            Button("Global") { choose(.global) }
            if !manager.projects.isEmpty {
                Divider()
                ForEach(manager.projects, id: \.self) { path in
                    Button("\(URL(filePath: path).lastPathComponent) — \(abbreviate(path))") { choose(.project(path)) }
                }
            }
            Divider()
            Button("Choose Folder…") { manager.pickProject { choose(.project($0)) } }
        }
        .fixedSize()
    }
}

// MARK: Discover

private struct DiscoverList: View {
    @Environment(\.palette) private var palette
    let manager: SkillManager
    let limit: Int

    private var emptyText: String {
        if !manager.query.isEmpty { return "Nothing matches “\(manager.query)”" }
        if let id = manager.marketplaceFilter, let name = manager.marketplaces.first(where: { $0.id == id })?.name {
            return "\(name) doesn't list any plugins yet."
        }
        return "No plugins yet. Add a marketplace to browse its plugins."
    }

    var body: some View {
        let matching = manager.catalog.filter { plugin in
            (manager.agentFilter == nil || plugin.agent == manager.agentFilter)
                && (manager.marketplaceFilter == nil || "\(plugin.agent.rawValue):\(plugin.marketplace)" == manager.marketplaceFilter)
                && matches(manager.query, [plugin.title, plugin.name, plugin.summary, plugin.marketplace, plugin.category, plugin.author] + plugin.skills)
        }
        VStack(spacing: 0) {
            if !manager.agents.isEmpty { MarketplaceToolbar(manager: manager).padding(.horizontal, 16).padding(.bottom, 2) }
            SnapshotSafeScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if matching.isEmpty {
                        VStack(spacing: 6) {
                            if manager.loading {
                                Spinner(size: 14)
                                Text("Reading the marketplaces…")
                            } else {
                                Text(emptyText)
                            }
                        }
                        .font(.peeku(12))
                        .foregroundStyle(palette.label(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                    ForEach(Agent.allCases, id: \.self) { agent in
                        let plugins = matching.filter { $0.agent == agent }
                        if !plugins.isEmpty {
                            HStack(spacing: 6) {
                                AgentMark(agent: agent, size: 10)
                                SectionLabel(title: "\(agent.productName.uppercased()) · \(plugins.count.formatted())")
                            }
                            .padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                            ForEach(plugins.prefix(limit)) { CatalogRow(plugin: $0, manager: manager) }
                            if plugins.count > limit {
                                Text("Showing \(limit) of \(plugins.count.formatted()). Search to find the rest.")
                                    .font(.peeku(11)).foregroundStyle(palette.label(0.4))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: 2, leading: 8, bottom: 10, trailing: 8))
            }
        }
    }
}

/// "From [All marketplaces ▾]  github.com/… ↗   + Add Marketplace", above Discover's list,
/// with the field to add one opening below it.
private struct MarketplaceToolbar: View {
    @Environment(\.palette) private var palette
    let manager: SkillManager

    private var selected: Marketplace? { manager.marketplaces.first { $0.id == manager.marketplaceFilter } }
    private var shown: [Marketplace] {
        manager.marketplaces.filter { manager.agentFilter == nil || $0.agent == manager.agentFilter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("From").foregroundStyle(palette.label(0.55))
                SettingsMenu(title: selected?.name ?? "All marketplaces") {
                    Button("All marketplaces") { manager.marketplaceFilter = nil }
                    ForEach(Agent.allCases, id: \.self) { agent in
                        let list = shown.filter { $0.agent == agent }
                        if !list.isEmpty {
                            Section(agent.productName) {
                                ForEach(list) { marketplace in
                                    Button(label(marketplace)) { manager.marketplaceFilter = marketplace.id }
                                }
                            }
                        }
                    }
                }
                .fixedSize()
                if let selected, let url = selected.originURL, let origin = selected.origin {
                    SourceLink(text: origin, url: url)
                }
                Spacer(minLength: 4)
                if let label = manager.agents.lazy.compactMap({ manager.working["marketplace:\($0.rawValue)"] }).first {
                    Spinner()
                    Text(label).foregroundStyle(palette.label(0.5))
                } else {
                    Button { manager.addingMarketplace.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: manager.addingMarketplace ? "xmark" : "plus").font(.system(size: 9, weight: .bold))
                            Text(manager.addingMarketplace ? "Cancel" : "Add Marketplace")
                        }
                    }
                    .buttonStyle(ChipStyle(selected: manager.addingMarketplace))
                    .fixedSize()
                }
            }
            if manager.addingMarketplace { MarketplaceBar(manager: manager) }
            ForEach(Array(manager.agents), id: \.self) { agent in
                if let failure = manager.failures["marketplace:\(agent.rawValue)"] { FailureText(text: failure) }
            }
        }
        .font(.peeku(11.5))
    }

    /// "brag — 1 plugin, 1 installed".
    private func label(_ marketplace: Marketplace) -> String {
        let plugins = manager.catalog.filter { $0.agent == marketplace.agent && $0.marketplace == marketplace.name }
        let installed = plugins.count(where: manager.isInstalled)
        var text = "\(marketplace.name) — \(plugins.count) plugin\(plugins.count == 1 ? "" : "s")"
        if installed > 0 { text += ", \(installed) installed" }
        return text
    }
}

/// "🔗 github.com/owner/repo", opening the page in the browser.
private struct SourceLink: View {
    let text: String
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 4) {
                Image(systemName: "link").font(.system(size: 9, weight: .semibold))
                Text(text).lineLimit(1).truncationMode(.middle)
            }
        }
        .buttonStyle(LinkTextStyle())
        .help(url.absoluteString)
        .accessibilityLabel("Open \(text)")
    }
}

private struct CatalogRow: View {
    @Environment(\.palette) private var palette
    let plugin: CatalogPlugin
    let manager: SkillManager
    @State private var hovering = false

    private var expanded: Bool { manager.expanded == plugin.id }
    private var choosing: Bool { manager.installing == plugin.id }

    var body: some View {
        let installed = manager.isInstalled(plugin)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                AgentMark(agent: plugin.agent, size: 12).frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(plugin.title).font(.peeku(13, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                        Text(meta).font(.peeku(11)).foregroundStyle(palette.label(0.4)).lineLimit(1)
                    }
                    Text(plugin.summary ?? "No description")
                        .font(.peeku(11.5))
                        .foregroundStyle(palette.label(plugin.summary == nil ? 0.35 : 0.55))
                        .lineLimit(expanded ? 8 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if let origin = plugin.origin, let url = plugin.originURL {
                            SourceLink(text: origin, url: url)
                        } else {
                            Text("From the \(plugin.marketplace) marketplace").font(.peeku(11.5)).foregroundStyle(palette.label(0.4))
                        }
                    }
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let label = manager.working[plugin.id] {
                        HStack(spacing: 6) {
                            Spinner()
                            Text(label).font(.peeku(11)).foregroundStyle(palette.label(0.5))
                        }
                    } else if installed {
                        Text("Installed").font(.peeku(11.5)).foregroundStyle(palette.accent(.finished))
                    } else if !choosing {
                        Button("Install") {
                            manager.installing = plugin.id
                            manager.installScope = .global
                        }
                        .buttonStyle(RowOpenStyle())
                    }
                }
                .fixedSize()
                .padding(.top, 1)
            }
            if expanded { details.padding(.leading, 26) }
            if choosing && !installed && manager.working[plugin.id] == nil { installOptions.padding(.leading, 26) }
            if let failure = manager.failures[plugin.id] { FailureText(text: failure).padding(.leading, 26) }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.fill(hovering || expanded || choosing ? 0.055 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { manager.expanded = expanded ? nil : plugin.id }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(plugin.title), \(plugin.agent.productName) plugin")
    }

    /// "marketplace · 12.3k installs".
    private var meta: String {
        var parts = [plugin.category ?? plugin.marketplace]
        if let installs = plugin.installs, installs > 0 {
            parts.append("\(SpendFormat.tokens(installs)) installs")
        }
        return parts.joined(separator: " · ")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !plugin.skills.isEmpty { DetailLine(label: "Skills", value: plugin.skills.joined(separator: ", ")) }
            if let author = plugin.author { DetailLine(label: "By", value: author) }
            DetailLine(label: "ID", value: plugin.pluginID)
            if let homepage = plugin.homepage {
                Button("Open Homepage") { NSWorkspace.shared.open(homepage) }
                    .buttonStyle(ChipStyle(selected: false))
                    .padding(.top, 2)
            }
        }
    }

    /// Where to install, what it can do, and a confirm, since plugins can run code.
    private var installOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Install for").foregroundStyle(palette.label(0.55))
                if plugin.supportsProjects {
                    ScopeMenu(manager: manager, scope: manager.installScope) { manager.installScope = $0 }
                } else {
                    Text("your user (Codex plugins are global)").foregroundStyle(palette.label(0.8))
                }
            }
            Text("Plugins can add hooks, commands and MCP servers that run on your Mac."
                 + (plugin.origin.map { " From \($0)." } ?? " From the \(plugin.marketplace) marketplace."))
                .foregroundStyle(palette.label(0.45))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Install") {
                    manager.install(plugin, scope: manager.installScope)
                    manager.installing = nil
                }
                .buttonStyle(PrimaryPillStyle(fontSize: 11.5, padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)))
                Button("Cancel") { manager.installing = nil }
                    .buttonStyle(ChipStyle(selected: false))
            }
        }
        .font(.peeku(11.5))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill(0.05)))
    }
}

/// "[Claude ▾] [owner/repo or Git URL] Add", opened from Discover's Add Marketplace.
private struct MarketplaceBar: View {
    @Environment(\.palette) private var palette
    let manager: SkillManager
    @State private var source = ""
    @State private var picked: Agent?
    @FocusState private var focused: Bool

    private var available: [Agent] { Agent.allCases.filter(manager.agents.contains) }
    /// The one picked here, else the agent filter's, else the first found.
    private var agent: Agent {
        if let picked, available.contains(picked) { return picked }
        if let filter = manager.agentFilter, available.contains(filter) { return filter }
        return available.first ?? .claude
    }
    private var trimmed: String { source.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { SkillCatalog.isValidMarketplaceSource(trimmed) }

    var body: some View {
        HStack(spacing: 6) {
            if available.count > 1 {
                SettingsMenu(title: agent.name) {
                    ForEach(available, id: \.self) { agent in
                        Button(agent.productName) { picked = agent }
                    }
                }
                .fixedSize()
            }
            // Filled and outlined like a field, brighter while typing into it.
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 10, weight: .medium)).foregroundStyle(palette.label(0.45))
                TextField("Marketplace", text: $source, prompt: Text("owner/repo or Git URL").foregroundStyle(palette.label(0.35)))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 7).fill(palette.fill(focused ? 0.1 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.label(focused ? 0.35 : 0.14), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            Button("Add", action: add)
                .buttonStyle(RowOpenStyle())
                .fixedSize()
                .disabled(!valid)
                .opacity(valid ? 1 : 0.4)
        }
        .font(.peeku(12))
        .onAppear { focused = true }
    }

    private func add() {
        guard valid else { return }
        manager.addMarketplace(trimmed, agent: agent)
        manager.addingMarketplace = false
    }
}

// MARK: Bits

private struct Tag: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.peeku(10))
            .foregroundStyle(palette.label(0.6))
            .padding(.vertical, 1).padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(palette.fill(0.08)))
    }
}

/// "Skills  caveman, compress".
private struct DetailLine: View {
    let label: String
    let value: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.peeku(11)).foregroundStyle(palette.label(0.4)).frame(width: 44, alignment: .leading)
            Text(value).font(.peeku(11.5)).foregroundStyle(palette.label(0.75))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FailureText: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.peeku(11))
            .foregroundStyle(palette.accent(.error))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "~/Documents/app" for a folder under the home folder.
private func abbreviate(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
