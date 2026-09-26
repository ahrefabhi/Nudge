import Foundation

/// Where a skill or plugin applies: everywhere, or in one project folder.
public enum SkillScope: Hashable, Sendable {
    case global
    case project(String)

    public var projectPath: String? {
        if case .project(let path) = self { return path }
        return nil
    }

    /// "Global", or the project folder's name.
    public var title: String {
        switch self {
        case .global: "Global"
        case .project(let path): URL(filePath: path).lastPathComponent
        }
    }
}

/// A plugin or a standalone skill folder one of the agents loads.
public struct InstalledSkill: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Installed through the agent's own CLI. `cliScope` is Claude's "user", "project" or "local".
        case plugin(id: String, cliScope: String?)
        /// A folder with a SKILL.md, which Peeku manages as files.
        case skill(folder: URL)
    }

    public var agent: Agent
    public var kind: Kind
    public var name: String
    public var summary: String?
    public var scope: SkillScope
    /// Nil when the agent can't switch it off without removing it.
    public var enabled: Bool?
    public var version: String?
    /// The plugin's install folder or the skill's folder.
    public var location: URL?
    /// The skills a plugin brings.
    public var skills: [String]

    public init(agent: Agent, kind: Kind, name: String, summary: String? = nil, scope: SkillScope, enabled: Bool? = nil,
                version: String? = nil, location: URL? = nil, skills: [String] = []) {
        self.agent = agent
        self.kind = kind
        self.name = name
        self.summary = summary
        self.scope = scope
        self.enabled = enabled
        self.version = version
        self.location = location
        self.skills = skills
    }

    public var id: String {
        switch kind {
        case .plugin(let plugin, let cliScope): "\(agent.rawValue):plugin:\(plugin):\(cliScope ?? ""):\(scope.projectPath ?? "")"
        case .skill(let folder): "\(agent.rawValue):skill:\(folder.path)"
        }
    }

    public var isPlugin: Bool {
        if case .plugin = kind { return true }
        return false
    }

    public var pluginID: String? {
        if case .plugin(let id, _) = kind { return id }
        return nil
    }
}

/// A plugin a marketplace offers.
public struct CatalogPlugin: Identifiable, Hashable, Sendable {
    public var agent: Agent
    /// `name@marketplace`, what the CLIs install.
    public var pluginID: String
    public var name: String
    public var title: String
    public var summary: String?
    public var marketplace: String
    public var category: String?
    public var author: String?
    public var homepage: URL?
    /// Where its code comes from, e.g. "github.com/owner/repo", and that page's address.
    public var origin: String?
    public var originURL: URL?
    public var installs: Int?
    public var skills: [String]

    public init(agent: Agent, pluginID: String, name: String, title: String? = nil, summary: String? = nil, marketplace: String,
                category: String? = nil, author: String? = nil, homepage: URL? = nil, origin: String? = nil,
                originURL: URL? = nil, installs: Int? = nil, skills: [String] = []) {
        self.agent = agent
        self.pluginID = pluginID
        self.name = name
        self.title = title ?? name
        self.summary = summary
        self.marketplace = marketplace
        self.category = category
        self.author = author
        self.homepage = homepage
        self.origin = origin
        self.originURL = originURL ?? origin.flatMap(SkillCatalog.webURL)
        self.installs = installs
        self.skills = skills
    }

    public var id: String { "\(agent.rawValue):\(pluginID)" }

    /// Codex plugins install for the user only; Claude's can go in a project too.
    public var supportsProjects: Bool { agent == .claude }
}

/// A source of plugins one of the agents knows about.
public struct Marketplace: Identifiable, Hashable, Sendable {
    public var agent: Agent
    public var name: String
    /// "github.com/owner/repo", when it comes from somewhere Peeku can link to.
    public var origin: String?
    public var originURL: URL?

    public init(agent: Agent, name: String, origin: String? = nil) {
        self.agent = agent
        self.name = name
        self.origin = origin
        originURL = origin.flatMap(SkillCatalog.webURL)
    }

    public var id: String { "\(agent.rawValue):\(name)" }
}

/// The folders skills live in, overridable for tests.
public struct SkillPaths: Sendable {
    public var home: URL
    public var claudeRoot: URL
    public var claudeState: URL
    public var codexHome: URL
    /// The shared `~/.agents` folder Codex and other agents read skills from.
    public var agentsHome: URL

    public init(home: URL, claudeRoot: URL, claudeState: URL, codexHome: URL, agentsHome: URL) {
        self.home = home
        self.claudeRoot = claudeRoot
        self.claudeState = claudeState
        self.codexHome = codexHome
        self.agentsHome = agentsHome
    }

    public static var `default`: SkillPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { !$0.isEmpty } ?? false
        // Claude keeps its project list in ~/.claude.json, or inside a custom config folder.
        let state = custom ? ClaudePaths.configRoot.appending(path: ".claude.json") : home.appending(path: ".claude.json")
        return SkillPaths(home: home, claudeRoot: ClaudePaths.configRoot, claudeState: state,
                          codexHome: CodexPaths.home, agentsHome: home.appending(path: ".agents", directoryHint: .isDirectory))
    }

    /// Every folder the agent reads standalone skills from, for listing.
    public func skillFolders(_ agent: Agent, _ scope: SkillScope) -> [URL] {
        switch (agent, scope) {
        case (.claude, .global): [claudeRoot.appending(path: "skills")]
        case (.claude, .project(let path)): [URL(filePath: path).appending(path: ".claude/skills")]
        case (.codex, .global): [agentsHome.appending(path: "skills"), codexHome.appending(path: "skills")]
        case (.codex, .project(let path)): [URL(filePath: path).appending(path: ".agents/skills"), URL(filePath: path).appending(path: ".codex/skills")]
        }
    }

    /// Where Peeku puts a skill it adds.
    public func installFolder(_ agent: Agent, _ scope: SkillScope) -> URL { skillFolders(agent, scope)[0] }
}

/// Reads what the agents' CLIs and skill folders say is installed and available. Pure parsing
/// lives here so it can be tested without the CLIs.
public enum SkillCatalog {
    // MARK: Claude

    /// `claude plugin marketplace list --json`.
    public static func parseClaudeMarketplaces(_ data: Data) -> [Marketplace] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            return Marketplace(agent: .claude, name: name, origin: origin(entry))
        }
    }

    /// `claude plugin list --available --json`. A plugin that ships inside its marketplace links to
    /// its folder in the marketplace's repository.
    public static func parseClaude(_ data: Data, paths: SkillPaths, marketplaces: [Marketplace] = []) -> (installed: [InstalledSkill], available: [CatalogPlugin]) {
        let origins = Dictionary(marketplaces.map { ($0.name, $0.origin) }, uniquingKeysWith: { first, _ in first })
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], []) }
        let available = (root["available"] as? [[String: Any]] ?? []).compactMap { entry -> CatalogPlugin? in
            guard let id = entry["pluginId"] as? String, let name = entry["name"] as? String else { return nil }
            let marketplace = entry["marketplaceName"] as? String ?? id.split(separator: "@").last.map(String.init) ?? ""
            return CatalogPlugin(agent: .claude, pluginID: id, name: name, summary: clean(entry["description"] as? String),
                                 marketplace: marketplace, author: (entry["author"] as? [String: Any])?["name"] as? String,
                                 homepage: (entry["homepage"] as? String).flatMap(URL.init(string:)),
                                 origin: origin(entry["source"]) ?? bundledOrigin(entry["source"], in: origins[marketplace] ?? nil),
                                 installs: entry["installCount"] as? Int)
        }
        let summaries = Dictionary(available.map { ($0.pluginID, $0.summary) }, uniquingKeysWith: { first, _ in first })
        let installed = (root["installed"] as? [[String: Any]] ?? []).compactMap { entry -> InstalledSkill? in
            guard let id = entry["id"] as? String else { return nil }
            let cliScope = entry["scope"] as? String ?? "user"
            let scope: SkillScope = if cliScope != "user", let project = entry["projectPath"] as? String { .project(project) } else { .global }
            let location = (entry["installPath"] as? String).map { URL(filePath: $0, directoryHint: .isDirectory) }
            let manifest = location.flatMap { manifestSummary($0.appending(path: ".claude-plugin/plugin.json")) }
            return InstalledSkill(agent: .claude, kind: .plugin(id: id, cliScope: cliScope),
                                  name: String(id.split(separator: "@").first ?? Substring(id)),
                                  summary: manifest ?? summaries[id] ?? nil, scope: scope,
                                  enabled: entry["enabled"] as? Bool, version: entry["version"] as? String,
                                  location: location, skills: location.map { skillNames(in: $0.appending(path: "skills")) } ?? [])
        }
        return (installed, available)
    }

    /// Catalog rows for installed plugins, which the CLIs leave out of their available lists, so
    /// each marketplace shows everything it offers. One row per plugin, however many scopes have it.
    public static func catalogEntries(for installed: [InstalledSkill], besides catalog: [CatalogPlugin], marketplaces: [Marketplace],
                                      manifests: [String: CodexManifest] = [:]) -> [CatalogPlugin] {
        var seen = Set(catalog.map(\.id))
        let origins = Dictionary(marketplaces.map { ($0.name, $0.origin) }, uniquingKeysWith: { first, _ in first })
        return installed.compactMap { item in
            guard let id = item.pluginID, seen.insert("\(item.agent.rawValue):\(id)").inserted else { return nil }
            let parts = id.split(separator: "@", maxSplits: 1).map(String.init)
            let name = parts[0], marketplace = parts.count > 1 ? parts[1] : ""
            let manifest = manifests[name]
            return CatalogPlugin(agent: item.agent, pluginID: id, name: name, title: item.name, summary: item.summary,
                                 marketplace: marketplace, category: manifest?.category, author: manifest?.author,
                                 homepage: manifest?.homepage, origin: manifest?.repository ?? origins[marketplace] ?? nil,
                                 skills: item.skills)
        }
    }

    // MARK: Codex

    /// What a Codex plugin's own manifest says about it.
    public struct CodexManifest: Sendable, Equatable {
        public var title: String?
        public var summary: String?
        public var category: String?
        public var author: String?
        public var homepage: URL?
        public var repository: String?
        public var skills: [String] = []
    }

    /// `codex plugin list --available --json`, with descriptions from the marketplaces' manifests
    /// where Peeku found them. Unnamed connector apps and ones the account can't install are left out.
    public static func parseCodex(_ data: Data, manifests: [String: CodexManifest], paths: SkillPaths) -> (installed: [InstalledSkill], available: [CatalogPlugin]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], []) }
        let installed = (root["installed"] as? [[String: Any]] ?? []).compactMap { entry -> InstalledSkill? in
            guard let id = entry["pluginId"] as? String, let name = entry["name"] as? String else { return nil }
            let marketplace = entry["marketplaceName"] as? String ?? ""
            let version = entry["version"] as? String
            var location: URL? = paths.codexHome.appending(path: "plugins/cache/\(marketplace)/\(name)", directoryHint: .isDirectory)
            if let version { location = location?.appending(path: version, directoryHint: .isDirectory) }
            let manifest = location.flatMap { codexManifest($0) } ?? manifests[name]
            return InstalledSkill(agent: .codex, kind: .plugin(id: id, cliScope: nil), name: manifest?.title ?? name,
                                  summary: manifest?.summary, scope: .global, version: version, location: location,
                                  skills: manifest?.skills ?? [])
        }
        let available = (root["available"] as? [[String: Any]] ?? []).compactMap { entry -> CatalogPlugin? in
            guard let id = entry["pluginId"] as? String, let name = entry["name"] as? String,
                  entry["installPolicy"] as? String != "NOT_AVAILABLE", !isUnnamedApp(name) else { return nil }
            let manifest = manifests[name]
            return CatalogPlugin(agent: .codex, pluginID: id, name: name, title: manifest?.title, summary: manifest?.summary,
                                 marketplace: entry["marketplaceName"] as? String ?? "", category: manifest?.category,
                                 author: manifest?.author, homepage: manifest?.homepage, origin: manifest?.repository,
                                 skills: manifest?.skills ?? [])
        }
        return (installed, available)
    }

    /// Connector apps listed only by their id, like "app-6a057d268ebc81919918d37eec718425".
    static func isUnnamedApp(_ name: String) -> Bool {
        name.hasPrefix("app-") && name.dropFirst(4).count >= 16 && name.dropFirst(4).allSatisfy(\.isHexDigit)
    }

    /// The marketplaces in `codex plugin marketplace list`, a table of names and local folders.
    public static func codexMarketplaces(_ text: String) -> [Marketplace] {
        text.split(separator: "\n").dropFirst().compactMap { line in
            line.split(whereSeparator: \.isWhitespace).first.map { Marketplace(agent: .codex, name: String($0)) }
        }
    }

    /// The local folders in `codex plugin marketplace list`, whose plugins carry manifests.
    public static func codexMarketplaceRoots(_ text: String) -> [URL] {
        text.split(separator: "\n").compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 2, let last = columns.last, last.hasPrefix("/") else { return nil }
            return URL(filePath: String(last), directoryHint: .isDirectory)
        }
    }

    /// Every plugin manifest under a Codex marketplace folder, by plugin name.
    static func codexManifests(in roots: [URL]) -> [String: CodexManifest] {
        var manifests: [String: CodexManifest] = [:]
        for root in roots {
            let plugins = root.appending(path: "plugins", directoryHint: .isDirectory)
            for folder in (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? [] {
                if let manifest = codexManifest(folder) { manifests[folder.lastPathComponent] = manifest }
            }
        }
        return manifests
    }

    static func codexManifest(_ folder: URL) -> CodexManifest? {
        guard let data = try? Data(contentsOf: folder.appending(path: ".codex-plugin/plugin.json")) else { return nil }
        return parseCodexManifest(data, skills: skillNames(in: folder.appending(path: "skills")))
    }

    public static func parseCodexManifest(_ data: Data, skills: [String] = []) -> CodexManifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let interface = json["interface"] as? [String: Any] ?? [:]
        return CodexManifest(title: interface["displayName"] as? String,
                             summary: clean(interface["shortDescription"] as? String ?? json["description"] as? String),
                             category: interface["category"] as? String,
                             author: interface["developerName"] as? String ?? (json["author"] as? [String: Any])?["name"] as? String,
                             homepage: (json["homepage"] as? String).flatMap(URL.init(string:)),
                             repository: (json["repository"] as? String).map(shortenURL), skills: skills)
    }

    // MARK: Skill folders

    /// Each folder under `folder` holding a SKILL.md.
    public static func scanSkills(in folder: URL, agent: Agent, scope: SkillScope) -> [InstalledSkill] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { entry in
            let file = entry.appending(path: "SKILL.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let front = frontMatter(text)
            return InstalledSkill(agent: agent, kind: .skill(folder: entry), name: front["name"] ?? entry.lastPathComponent,
                                  summary: clean(front["description"]), scope: scope, location: entry)
        }
    }

    /// The skills in a plugin's `skills` folder, by name.
    static func skillNames(in folder: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { FileManager.default.fileExists(atPath: $0.appending(path: "SKILL.md").path) }
            .map(\.lastPathComponent).sorted()
    }

    /// The `key: value` pairs between a SKILL.md's leading `---` lines. Folded (`>`) and literal
    /// (`|`) values join their indented lines with spaces.
    public static func frontMatter(_ text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var values: [String: String] = [:]
        var index = 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != "---" {
            let line = lines[index]
            index += 1
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if [">", "|", ">-", "|-", ">+", "|+"].contains(value) {
                var parts: [String] = []
                while index < lines.count, lines[index].hasPrefix(" ") || lines[index].hasPrefix("\t") || lines[index].isEmpty {
                    let part = lines[index].trimmingCharacters(in: .whitespaces)
                    if !part.isEmpty { parts.append(part) }
                    index += 1
                }
                value = parts.joined(separator: " ")
            } else if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }

    // MARK: Projects

    /// Folders Claude has run in, from `~/.claude.json`.
    public static func claudeProjects(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: Any] else { return [] }
        return Array(projects.keys)
    }

    /// Folders Codex trusts, from the `[projects."…"]` tables in its config.toml.
    public static func codexProjects(_ config: String) -> [String] {
        config.split(separator: "\n").compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[projects.\""), line.hasSuffix("\"]") else { return nil }
            return String(line.dropFirst("[projects.\"".count).dropLast(2))
        }
    }

    // MARK: Checks

    /// A plugin id the CLIs accept, like "caveman@caveman". Never starts with "-", so it can't read as a flag.
    public static func isValidPluginID(_ id: String) -> Bool {
        id.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9._\-]*(@[A-Za-z0-9][A-Za-z0-9._\-]*)?/) != nil
    }

    /// A marketplace source: "owner/repo", a Git URL or a local path.
    public static func isValidMarketplaceSource(_ source: String) -> Bool {
        !source.isEmpty && source.count <= 300 && !source.hasPrefix("-") && !source.contains(where: \.isWhitespace)
    }

    // MARK: Helpers

    private static func manifestSummary(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return clean(json["description"] as? String)
    }

    /// "github.com/owner/repo" for a plugin's source, or nil when it ships inside its marketplace.
    static func origin(_ source: Any?) -> String? {
        guard let source = source as? [String: Any] else { return nil }
        if let repo = source["repo"] as? String { return "github.com/\(repo)" }
        if let url = source["url"] as? String {
            let short = shortenURL(url)
            if let path = source["path"] as? String, !path.isEmpty { return "\(short)/\(path)" }
            return short
        }
        if let package = source["package"] as? String { return "npm: \(package)" }
        return nil
    }

    /// "github.com/owner/repo/plugins/name" for a plugin given as "./plugins/name" inside its marketplace.
    static func bundledOrigin(_ source: Any?, in marketplace: String?) -> String? {
        guard let marketplace, var path = source as? String else { return nil }
        if path.hasPrefix("./") { path.removeFirst(2) }
        return path.isEmpty ? marketplace : "\(marketplace)/\(path)"
    }

    /// The web page for an origin: a GitHub folder opens on the default branch.
    public static func webURL(_ origin: String) -> URL? {
        guard !origin.hasPrefix("npm: "), !origin.hasPrefix("/"), origin.contains(".") else {
            return origin.hasPrefix("npm: ") ? URL(string: "https://www.npmjs.com/package/\(origin.dropFirst(5))") : nil
        }
        let parts = origin.split(separator: "/")
        if parts.first == "github.com", parts.count > 3 {
            return URL(string: "https://github.com/\(parts[1])/\(parts[2])/tree/HEAD/" + parts.dropFirst(3).joined(separator: "/"))
        }
        return URL(string: "https://\(origin)")
    }

    static func shortenURL(_ url: String) -> String {
        var short = url
        for prefix in ["https://", "http://", "git@"] where short.hasPrefix(prefix) { short.removeFirst(prefix.count) }
        if short.hasSuffix(".git") { short.removeLast(4) }
        if short.hasSuffix("/") { short.removeLast() }
        return short.replacingOccurrences(of: "github.com:", with: "github.com/")
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
