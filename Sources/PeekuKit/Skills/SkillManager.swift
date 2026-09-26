import Foundation
import Observation

/// Everything the Skills utility knows: what Claude Code and Codex have installed, what their
/// marketplaces offer, and the projects a plugin or skill can go in. Plugins install and uninstall
/// through the agents' own CLIs, never through a shell; standalone skills are folders Peeku copies
/// and moves to the Trash itself.
@MainActor
@Observable
public final class SkillManager {
    /// How long a listing counts as fresh when the view opens again.
    public static let staleAfter: TimeInterval = 120

    public private(set) var installed: [InstalledSkill] = []
    public private(set) var catalog: [CatalogPlugin] = []
    public private(set) var marketplaces: [Marketplace] = []
    /// Project folders the agents have run in, newest list first by name.
    public private(set) var projects: [String] = []
    /// The agents whose CLI Peeku found.
    public private(set) var agents: Set<Agent> = []
    public private(set) var loading = false
    public private(set) var loadedAt: Date?
    /// What's happening to an item right now, e.g. "Installing…", by item or catalog id.
    public private(set) var working: [String: String] = [:]
    /// The last thing that went wrong for an item, by item or catalog id.
    public private(set) var failures: [String: String] = [:]
    /// A short note after a change, e.g. that it applies to new sessions.
    public private(set) var notice: String?

    // MARK: View state
    // Kept here rather than in the view, so it survives the notch closing for a folder dialog.

    public enum Section: Sendable { case installed, discover }
    public var section: Section = .installed
    /// Nil shows both agents.
    public var agentFilter: Agent?
    public var query = ""
    /// The marketplace Discover shows, by id; nil shows all.
    public var marketplaceFilter: String?
    /// Discover's "Add Marketplace" field is open.
    public var addingMarketplace = false
    /// The row showing its details.
    public var expanded: String?
    /// The catalog plugin showing its install options, and where it would go.
    public var installing: String?
    public var installScope: SkillScope = .global
    /// Where "Add Skill Folder…" copies to.
    public var addAgent: Agent = .claude
    public var addScope: SkillScope = .global

    /// Asks the user for a folder. The notch floats above dialogs, so the app closes it first
    /// and reopens Skills afterwards.
    @ObservationIgnored public var chooseFolder: ((_ message: String, _ done: @escaping @MainActor (URL) -> Void) -> Void)?

    /// A change finished mid-listing, so list again once it's done.
    @ObservationIgnored private var reloadAfterLoading = false
    @ObservationIgnored private let paths: SkillPaths
    @ObservationIgnored private let locate: @Sendable (String) -> URL?

    public init(paths: SkillPaths = .default, locate: @escaping @Sendable (String) -> URL? = { AgentCLI.locate($0) }) {
        self.paths = paths
        self.locate = locate
    }

    public func refreshIfStale() {
        guard let loadedAt, Date().timeIntervalSince(loadedAt) < Self.staleAfter else { return refresh() }
    }

    public func refresh() {
        guard !loading else { reloadAfterLoading = true; return }
        loading = true
        let paths = paths, locate = locate
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) { Self.load(paths: paths, locate: locate) }.value
            installed = snapshot.installed
            catalog = snapshot.catalog
            marketplaces = snapshot.marketplaces
            projects = snapshot.projects
            agents = snapshot.agents
            loadedAt = Date()
            loading = false
            if reloadAfterLoading {
                reloadAfterLoading = false
                refresh()
            }
        }
    }

    /// Fills the lists without reading anything, for snapshots.
    func seed(installed: [InstalledSkill], catalog: [CatalogPlugin], marketplaces: [Marketplace], projects: [String]) {
        self.installed = installed
        self.catalog = catalog
        self.marketplaces = marketplaces
        self.projects = projects
        agents = [.claude, .codex]
        loadedAt = .distantFuture
    }

    public func isInstalled(_ plugin: CatalogPlugin) -> Bool {
        installed.contains { $0.agent == plugin.agent && $0.pluginID == plugin.pluginID }
    }

    public func dismissNotice() { notice = nil }

    // MARK: Plugins

    public func install(_ plugin: CatalogPlugin, scope: SkillScope) {
        let scope = plugin.supportsProjects ? scope : .global
        let arguments = switch plugin.agent {
        case .claude: ["plugin", "install", plugin.pluginID, "--scope", scope == .global ? "user" : "project", "--yes"]
        case .codex: ["plugin", "add", plugin.pluginID]
        }
        run(plugin.agent, arguments, in: scope.projectPath, key: plugin.id, label: "Installing…", valid: SkillCatalog.isValidPluginID(plugin.pluginID),
            done: "Installed \(plugin.title). New \(plugin.agent.productName) sessions will load it.")
    }

    public func setEnabled(_ item: InstalledSkill, _ on: Bool) {
        guard item.agent == .claude, case .plugin(let id, let cliScope) = item.kind else { return }
        var arguments = ["plugin", on ? "enable" : "disable", id]
        if let cliScope { arguments += ["--scope", cliScope] }
        run(.claude, arguments, in: item.scope.projectPath, key: item.id, label: on ? "Enabling…" : "Disabling…",
            valid: SkillCatalog.isValidPluginID(id), done: nil)
    }

    public func addMarketplace(_ source: String, agent: Agent) {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // Both CLIs take the same words here.
        run(agent, ["plugin", "marketplace", "add", source], in: nil, key: "marketplace:\(agent.rawValue)", label: "Adding…",
            valid: SkillCatalog.isValidMarketplaceSource(source), done: "Added \(source). Its plugins are listed under Discover.")
    }

    // MARK: Removing

    /// Uninstalls a plugin, or moves a skill's folder to the Trash so it can be put back.
    public func remove(_ item: InstalledSkill) {
        switch item.kind {
        case .plugin(let id, let cliScope):
            let arguments = switch item.agent {
            case .claude: ["plugin", "uninstall", id] + (cliScope.map { ["--scope", $0] } ?? []) + ["--yes"]
            case .codex: ["plugin", "remove", id]
            }
            run(item.agent, arguments, in: item.scope.projectPath, key: item.id, label: "Removing…",
                valid: SkillCatalog.isValidPluginID(id), done: "Removed \(item.name).")
        case .skill(let folder):
            files(key: item.id, label: "Removing…", done: "Moved \(item.name) to the Trash.") {
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            }
        }
    }

    // MARK: Skill folders

    /// Copies a skill folder, or each skill folder inside `folder`, into an agent's skills.
    public func addSkills(from folder: URL, agent: Agent, scope: SkillScope) {
        let target = paths.installFolder(agent, scope)
        files(key: "add:\(agent.rawValue)", label: "Adding…", done: "Added to \(agent.productName). New sessions will load it.") {
            let manager = FileManager.default
            let sources = manager.fileExists(atPath: folder.appending(path: "SKILL.md").path)
                ? [folder]
                : ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                    .filter { manager.fileExists(atPath: $0.appending(path: "SKILL.md").path) }
            guard !sources.isEmpty else { throw SkillError("No SKILL.md in \(folder.lastPathComponent).") }
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            for source in sources { try Self.copy(source, into: target) }
        }
    }

    /// Copies a standalone skill so the other agent loads it too, in the same scope.
    public func copy(_ item: InstalledSkill, to agent: Agent) {
        guard case .skill(let folder) = item.kind else { return }
        let target = paths.installFolder(agent, item.scope)
        files(key: item.id, label: "Copying…", done: "Copied \(item.name) to \(agent.productName).") {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Self.copy(folder, into: target)
        }
    }

    /// Whether the other agent already has a skill with this folder name in the same scope.
    public func hasCopy(of item: InstalledSkill, for agent: Agent) -> Bool {
        guard case .skill(let folder) = item.kind else { return false }
        return paths.skillFolders(agent, item.scope).contains {
            FileManager.default.fileExists(atPath: $0.appending(path: folder.lastPathComponent).appending(path: "SKILL.md").path)
        }
    }

    public func pickSkillFolder(agent: Agent, scope: SkillScope) {
        chooseFolder?("Choose a skill folder (one with a SKILL.md) or a folder of skills.") { [weak self] url in
            self?.addSkills(from: url, agent: agent, scope: scope)
        }
    }

    /// Asks for a project folder and hands it back, remembering it for the pickers.
    public func pickProject(_ done: @escaping @MainActor (String) -> Void) {
        chooseFolder?("Choose a project folder.") { [weak self] url in
            let path = url.standardizedFileURL.path
            if let self, !self.projects.contains(path) { self.projects = (self.projects + [path]).sorted(by: Self.byName) }
            done(path)
        }
    }

    // MARK: Running

    private func run(_ agent: Agent, _ arguments: [String], in directory: String?, key: String, label: String, valid: Bool, done: String?) {
        guard valid else { failures[key] = "That name doesn't look right, so Peeku didn't run it."; return }
        guard let executable = locate(agent == .claude ? "claude" : "codex") else {
            failures[key] = "Couldn't find the \(agent == .claude ? "claude" : "codex") command."
            return
        }
        let folder = directory.map { URL(filePath: $0, directoryHint: .isDirectory) }
        perform(key: key, label: label, done: done) {
            guard let result = AgentCLI.execute(executable, arguments: arguments, in: folder, timeout: 300) else {
                throw SkillError("Couldn't start \(executable.lastPathComponent).")
            }
            guard result.succeeded else { throw SkillError(Self.message(result)) }
        }
    }

    private func files(key: String, label: String, done: String?, _ work: @escaping @Sendable () throws -> Void) {
        perform(key: key, label: label, done: done, work)
    }

    private func perform(key: String, label: String, done: String?, _ work: @escaping @Sendable () throws -> Void) {
        guard working[key] == nil else { return }
        working[key] = label
        failures[key] = nil
        notice = nil
        Task {
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                do { try work(); return nil } catch { return (error as? SkillError)?.message ?? error.localizedDescription }
            }.value
            working[key] = nil
            if let error { failures[key] = error } else if let done { notice = done }
            refresh()
        }
    }

    /// The most useful line of a failed CLI run: its last error, else its last output.
    nonisolated static func message(_ result: AgentCLI.Result) -> String {
        for text in [result.errors, result.output] {
            if let line = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).last(where: { !$0.isEmpty }) {
                return String(line.prefix(240))
            }
        }
        return "It exited with code \(result.status)."
    }

    nonisolated private static func copy(_ source: URL, into target: URL) throws {
        let destination = target.appending(path: source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw SkillError("\(source.lastPathComponent) is already there.")
        }
        try FileManager.default.copyItem(at: source.resolvingSymlinksInPath(), to: destination)
    }

    // MARK: Loading

    struct Snapshot: Sendable {
        var installed: [InstalledSkill]
        var catalog: [CatalogPlugin]
        var marketplaces: [Marketplace]
        var projects: [String]
        var agents: Set<Agent>
    }

    nonisolated static func load(paths: SkillPaths, locate: @Sendable (String) -> URL?) -> Snapshot {
        var installed: [InstalledSkill] = []
        var catalog: [CatalogPlugin] = []
        var marketplaces: [Marketplace] = []
        var agents: Set<Agent> = []

        if let claude = locate("claude") {
            agents.insert(.claude)
            let known = AgentCLI.execute(claude, arguments: ["plugin", "marketplace", "list", "--json"], timeout: 30)
                .map { SkillCatalog.parseClaudeMarketplaces(Data($0.output.utf8)) } ?? []
            marketplaces += known
            if let result = AgentCLI.execute(claude, arguments: ["plugin", "list", "--available", "--json"], timeout: 60), result.succeeded {
                let parsed = SkillCatalog.parseClaude(Data(result.output.utf8), paths: paths, marketplaces: known)
                installed += parsed.installed
                catalog += parsed.available.sorted { ($0.installs ?? 0, $1.name) > ($1.installs ?? 0, $0.name) }
                catalog += SkillCatalog.catalogEntries(for: parsed.installed, besides: catalog, marketplaces: known)
            }
        }
        if let codex = locate("codex") {
            agents.insert(.codex)
            let table = AgentCLI.execute(codex, arguments: ["plugin", "marketplace", "list"], timeout: 30)?.output ?? ""
            marketplaces += SkillCatalog.codexMarketplaces(table)
            let roots = SkillCatalog.codexMarketplaceRoots(table)
            let manifests = SkillCatalog.codexManifests(in: roots)
            if let result = AgentCLI.execute(codex, arguments: ["plugin", "list", "--available", "--json"], timeout: 60), result.succeeded {
                let parsed = SkillCatalog.parseCodex(Data(result.output.utf8), manifests: manifests, paths: paths)
                installed += parsed.installed
                // Described plugins first; the rest are connectors known only by name.
                catalog += parsed.available.sorted { ($0.summary == nil ? 1 : 0, $0.title.lowercased()) < ($1.summary == nil ? 1 : 0, $1.title.lowercased()) }
                catalog += SkillCatalog.catalogEntries(for: parsed.installed, besides: catalog, marketplaces: [], manifests: manifests)
            }
        }

        let projects = knownProjects(paths: paths, extra: installed.compactMap(\.scope.projectPath))
        for agent in Agent.allCases {
            for scope in [SkillScope.global] + projects.map(SkillScope.project) {
                var seen: Set<String> = []
                for folder in paths.skillFolders(agent, scope) {
                    for skill in SkillCatalog.scanSkills(in: folder, agent: agent, scope: scope) {
                        // A folder linked from two places is one skill.
                        guard let location = skill.location, seen.insert(location.resolvingSymlinksInPath().path).inserted else { continue }
                        installed.append(skill)
                    }
                }
            }
        }
        installed.sort { lhs, rhs in
            let left = (lhs.scope == .global ? 0 : 1, lhs.scope.title.lowercased(), lhs.isPlugin ? 0 : 1, lhs.name.lowercased())
            let right = (rhs.scope == .global ? 0 : 1, rhs.scope.title.lowercased(), rhs.isPlugin ? 0 : 1, rhs.name.lowercased())
            return left < right
        }
        // A marketplace can offer plugins without being listed, like Codex's built-in ones.
        for plugin in catalog where !marketplaces.contains(where: { $0.agent == plugin.agent && $0.name == plugin.marketplace }) {
            marketplaces.append(Marketplace(agent: plugin.agent, name: plugin.marketplace))
        }
        return Snapshot(installed: installed, catalog: catalog, marketplaces: marketplaces, projects: projects, agents: agents)
    }

    /// Folders Claude or Codex ran in that still exist, except the home folder, whose skills are the global ones.
    nonisolated static func knownProjects(paths: SkillPaths, extra: [String]) -> [String] {
        var found = extra
        if let data = try? Data(contentsOf: paths.claudeState) { found += SkillCatalog.claudeProjects(data) }
        if let config = try? String(contentsOf: paths.codexHome.appending(path: "config.toml"), encoding: .utf8) {
            found += SkillCatalog.codexProjects(config)
        }
        let home = paths.home.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        let existing = Set(found.map { URL(filePath: $0).standardizedFileURL.path }).filter {
            $0 != home && $0 != "/" && FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        return existing.sorted(by: byName)
    }

    nonisolated static func byName(_ lhs: String, _ rhs: String) -> Bool {
        let (left, right) = (URL(filePath: lhs).lastPathComponent.lowercased(), URL(filePath: rhs).lastPathComponent.lowercased())
        return left == right ? lhs < rhs : left < right
    }
}

struct SkillError: Error, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}
