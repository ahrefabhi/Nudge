import Foundation
import Testing
@testable import PeekuKit

@Suite struct SkillCatalogTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "peeku-skills-\(UUID().uuidString)")

    private var paths: SkillPaths {
        SkillPaths(home: root, claudeRoot: root.appending(path: ".claude"), claudeState: root.appending(path: ".claude.json"),
                   codexHome: root.appending(path: ".codex"), agentsHome: root.appending(path: ".agents"))
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func frontMatterReadsPlainQuotedAndFoldedValues() {
        let text = """
        ---
        name: caveman
        title: "Caveman"
        description: >
          Ultra-compressed communication mode.
          Cuts token usage.
        metadata:
          type: user
        ---
        # Body
        name: not this
        """
        let values = SkillCatalog.frontMatter(text)
        #expect(values["name"] == "caveman")
        #expect(values["title"] == "Caveman")
        #expect(values["description"] == "Ultra-compressed communication mode. Cuts token usage.")
        #expect(values["type"] == nil)
    }

    @Test func noFrontMatterIsEmpty() {
        #expect(SkillCatalog.frontMatter("# Just a heading\nname: x").isEmpty)
    }

    @Test func claudeListSplitsInstalledAndAvailable() throws {
        let json = """
        {"installed": [
          {"id": "caveman@caveman", "version": "af58", "scope": "user", "enabled": true, "installPath": "/nowhere/caveman"},
          {"id": "karpathy@k", "scope": "local", "enabled": false, "projectPath": "/work/app", "installPath": "/nowhere/k"}
        ], "available": [
          {"pluginId": "caveman@caveman", "name": "caveman", "description": "Talk less.\\nKeep meaning.", "marketplaceName": "caveman",
           "source": {"source": "github", "repo": "JuliusBrussee/caveman"}, "installCount": 900},
          {"pluginId": "api@official", "name": "api", "marketplaceName": "official",
           "source": {"source": "git-subdir", "url": "https://github.com/acme/plugins.git", "path": "plugins/api"}}
        ]}
        """
        let parsed = SkillCatalog.parseClaude(Data(json.utf8), paths: paths)
        #expect(parsed.installed.count == 2)
        #expect(parsed.installed[0].scope == .global)
        #expect(parsed.installed[0].name == "caveman")
        #expect(parsed.installed[0].summary == "Talk less. Keep meaning.")
        #expect(parsed.installed[0].kind == .plugin(id: "caveman@caveman", cliScope: "user"))
        #expect(parsed.installed[1].scope == .project("/work/app"))
        #expect(parsed.installed[1].enabled == false)
        #expect(parsed.available.map(\.origin) == ["github.com/JuliusBrussee/caveman", "github.com/acme/plugins/plugins/api"])
        #expect(parsed.available[0].installs == 900)
        #expect(parsed.available.allSatisfy { $0.agent == .claude && $0.supportsProjects })
    }

    @Test func bundledPluginsLinkToTheirMarketplaceFolder() {
        let marketplaces = SkillCatalog.parseClaudeMarketplaces(Data("""
        [{"name": "claude-plugins-official", "source": "github", "repo": "anthropics/claude-plugins-official"},
         {"name": "local", "source": "directory", "path": "/tmp/market"}]
        """.utf8))
        #expect(marketplaces.map(\.origin) == ["github.com/anthropics/claude-plugins-official", nil])
        #expect(marketplaces[0].originURL == URL(string: "https://github.com/anthropics/claude-plugins-official"))
        let json = """
        {"installed": [], "available": [
          {"pluginId": "code-review@claude-plugins-official", "name": "code-review", "marketplaceName": "claude-plugins-official", "source": "./plugins/code-review"},
          {"pluginId": "x@local", "name": "x", "marketplaceName": "local", "source": "./x"}
        ]}
        """
        let parsed = SkillCatalog.parseClaude(Data(json.utf8), paths: paths, marketplaces: marketplaces)
        #expect(parsed.available[0].origin == "github.com/anthropics/claude-plugins-official/plugins/code-review")
        #expect(parsed.available[0].originURL == URL(string: "https://github.com/anthropics/claude-plugins-official/tree/HEAD/plugins/code-review"))
        #expect(parsed.available[1].origin == nil)
        #expect(parsed.available[1].originURL == nil)
    }

    @Test func installedPluginsStillShowInTheirMarketplace() {
        let brag = InstalledSkill(agent: .claude, kind: .plugin(id: "brag@brag", cliScope: "user"), name: "brag", summary: "Launch videos", scope: .global)
        let karpathy = InstalledSkill(agent: .claude, kind: .plugin(id: "k@karpathy", cliScope: "local"), name: "k", scope: .project("/a"))
        let skill = InstalledSkill(agent: .claude, kind: .skill(folder: URL(filePath: "/s")), name: "s", scope: .global)
        var karpathyElsewhere = karpathy
        karpathyElsewhere.scope = .project("/b")
        let listed = CatalogPlugin(agent: .claude, pluginID: "k@karpathy", name: "k", marketplace: "karpathy")
        let entries = SkillCatalog.catalogEntries(for: [brag, karpathy, karpathyElsewhere, skill], besides: [listed],
                                                  marketplaces: [Marketplace(agent: .claude, name: "brag", origin: "github.com/latent-spaces/brag")])
        #expect(entries.map(\.pluginID) == ["brag@brag"])
        #expect(entries[0].marketplace == "brag")
        #expect(entries[0].summary == "Launch videos")
        #expect(entries[0].origin == "github.com/latent-spaces/brag")
    }

    @Test func originsBecomeWebPages() {
        #expect(SkillCatalog.webURL("github.com/obra/superpowers") == URL(string: "https://github.com/obra/superpowers"))
        #expect(SkillCatalog.webURL("gitlab.com/team/plugins") == URL(string: "https://gitlab.com/team/plugins"))
        #expect(SkillCatalog.webURL("npm: @acme/plugin") == URL(string: "https://www.npmjs.com/package/@acme/plugin"))
        #expect(SkillCatalog.webURL("/Users/me/market") == nil)
    }

    @Test func codexMarketplacesAreTheTableRows() {
        let text = "MARKETPLACE     ROOT\nopenai-curated  /Users/me/.codex/.tmp/plugins\nopenai-curated-remote\n"
        #expect(SkillCatalog.codexMarketplaces(text).map(\.name) == ["openai-curated", "openai-curated-remote"])
    }

    @Test func codexListDropsUnnamedAppsAndOnesItCantInstall() {
        let json = """
        {"installed": [{"pluginId": "slack@remote", "name": "slack", "marketplaceName": "remote", "version": "0.1.8", "enabled": true}],
         "available": [
          {"pluginId": "github@remote", "name": "github", "marketplaceName": "remote", "installPolicy": "AVAILABLE"},
          {"pluginId": "gmail@remote", "name": "gmail", "marketplaceName": "remote", "installPolicy": "NOT_AVAILABLE"},
          {"pluginId": "app-6a057d268ebc81919918d37eec718425@remote", "name": "app-6a057d268ebc81919918d37eec718425", "installPolicy": "AVAILABLE"}
         ]}
        """
        let manifest = SkillCatalog.CodexManifest(title: "GitHub", summary: "Triage PRs", category: "Coding", repository: "github.com/openai/plugins")
        let parsed = SkillCatalog.parseCodex(Data(json.utf8), manifests: ["github": manifest], paths: paths)
        #expect(parsed.installed.map(\.name) == ["slack"])
        #expect(parsed.installed[0].scope == .global)
        #expect(parsed.installed[0].enabled == nil)
        #expect(parsed.available.map(\.pluginID) == ["github@remote"])
        #expect(parsed.available[0].title == "GitHub")
        #expect(parsed.available[0].summary == "Triage PRs")
        #expect(!parsed.available[0].supportsProjects)
    }

    @Test func codexManifestPrefersItsInterface() {
        let json = """
        {"name": "github", "description": "Long", "author": {"name": "OpenAI"}, "repository": "https://github.com/openai/plugins",
         "interface": {"displayName": "GitHub", "shortDescription": "Short", "category": "Coding", "developerName": "OpenAI Inc"}}
        """
        let manifest = SkillCatalog.parseCodexManifest(Data(json.utf8))
        #expect(manifest?.title == "GitHub")
        #expect(manifest?.summary == "Short")
        #expect(manifest?.author == "OpenAI Inc")
        #expect(manifest?.repository == "github.com/openai/plugins")
    }

    @Test func marketplaceRootsAreTheAbsolutePaths() {
        let text = """
        MARKETPLACE     ROOT
        openai-curated  /Users/me/.codex/.tmp/plugins
        openai-curated-remote
        """
        #expect(SkillCatalog.codexMarketplaceRoots(text) == [URL(filePath: "/Users/me/.codex/.tmp/plugins", directoryHint: .isDirectory)])
    }

    @Test func skillFoldersNeedASkillFile() throws {
        let skills = root.appending(path: ".claude/skills")
        try write("---\nname: review\ndescription: Reviews code\n---\n", to: skills.appending(path: "review/SKILL.md"))
        try write("notes", to: skills.appending(path: "notes/README.md"))
        try write("# No front matter", to: skills.appending(path: "plain/SKILL.md"))
        let found = SkillCatalog.scanSkills(in: skills, agent: .claude, scope: .global)
        #expect(found.map(\.name) == ["plain", "review"])
        #expect(found[1].summary == "Reviews code")
        #expect(found[1].location?.lastPathComponent == "review")
        #expect(found[1].isPlugin == false)
    }

    @Test func eachAgentReadsItsOwnFolders() {
        #expect(paths.installFolder(.claude, .global) == root.appending(path: ".claude/skills"))
        #expect(paths.installFolder(.claude, .project("/work/app")) == URL(filePath: "/work/app/.claude/skills"))
        #expect(paths.installFolder(.codex, .global) == root.appending(path: ".agents/skills"))
        #expect(paths.skillFolders(.codex, .global).contains(root.appending(path: ".codex/skills")))
        #expect(paths.installFolder(.codex, .project("/work/app")) == URL(filePath: "/work/app/.agents/skills"))
    }

    @Test func projectsComeFromBothAgentsAndSkipHome() throws {
        let app = root.appending(path: "app"), api = root.appending(path: "api")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: api, withIntermediateDirectories: true)
        try write(#"{"projects": {"\#(root.path)": {}, "\#(app.path)": {}, "/gone/away": {}}}"#, to: paths.claudeState)
        try write("model = \"x\"\n[projects.\"\(api.path)\"]\ntrust_level = \"trusted\"\n", to: paths.codexHome.appending(path: "config.toml"))
        #expect(SkillManager.knownProjects(paths: paths, extra: []) == [api.standardizedFileURL.path, app.standardizedFileURL.path])
    }

    @Test func pluginIDsAndSourcesCantPassAsFlags() {
        #expect(SkillCatalog.isValidPluginID("caveman@caveman"))
        #expect(SkillCatalog.isValidPluginID("api-security_1.2@claude-plugins-official"))
        #expect(!SkillCatalog.isValidPluginID("--help"))
        #expect(!SkillCatalog.isValidPluginID("a b@c"))
        #expect(!SkillCatalog.isValidPluginID("a@b@c"))
        #expect(SkillCatalog.isValidMarketplaceSource("owner/repo"))
        #expect(SkillCatalog.isValidMarketplaceSource("https://github.com/o/r.git"))
        #expect(!SkillCatalog.isValidMarketplaceSource("-rf"))
        #expect(!SkillCatalog.isValidMarketplaceSource("owner/repo; rm"))
    }

    @Test func aFailedRunReportsItsLastError() {
        let result = AgentCLI.Result(status: 1, output: "Installing…\n", errors: "warning: slow\nError: Plugin \"x\" not found\n\n")
        #expect(SkillManager.message(result) == "Error: Plugin \"x\" not found")
        #expect(SkillManager.message(AgentCLI.Result(status: 3, output: "", errors: "")) == "It exited with code 3.")
    }
}
