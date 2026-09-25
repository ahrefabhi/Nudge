import CoreServices
import Darwin
import Foundation
import PeekuHookSchema

// Claude Code and Codex run this for every registered hook event. It only records what happened:
// it never prints, never decides anything for the agent, and always exits 0 quickly.
// Claude Code also runs it as its status line, to pass along subscription usage (see `runStatusLine`).

let maximumInput = 8 * 1024 * 1024

func argument(after flag: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func text(_ value: Any?, _ limit: Int) -> String? {
    guard let string = value as? String, !string.isEmpty else { return nil }
    return String(string.prefix(limit))
}

func toolInput(_ raw: Any?) -> HookRecord.ToolInput? {
    guard let input = raw as? [String: Any] else { return nil }
    var result = HookRecord.ToolInput()
    result.filePath = text(input["file_path"], 4096) ?? text(input["path"], 4096) ?? text(input["notebook_path"], 4096)
    result.pattern = text(input["pattern"], 512)
    result.query = text(input["query"], 512)
    result.description = text(input["description"], 512)
    result.command = text(input["command"], 512)
    if let questions = input["questions"] as? [[String: Any]] {
        result.questions = questions.prefix(8).compactMap { item in
            guard let question = text(item["question"], 1024) else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).prefix(16).compactMap { text($0["label"], 256) }
            return HookRecord.Question(question: question, header: text(item["header"], 128),
                                       options: options, multiSelect: item["multiSelect"] as? Bool == true)
        }
    }
    return result
}

func record(event: String, payload: [String: Any]) -> HookRecord? {
    guard let session = text(payload["session_id"], 256) else { return nil }
    var record = HookRecord(id: UUID().uuidString.lowercased(), event: event,
                            observedAt: Int64(Date().timeIntervalSince1970 * 1000), sessionID: session)
    record.agentID = text(payload["agent_id"], 256)
    record.toolUseID = text(payload["tool_use_id"], 256)
    record.cwd = text(payload["cwd"], 4096)

    switch event {
    case "UserPromptSubmit":
        record.prompt = text(payload["prompt"], 360)
    case "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "PermissionDenied":
        record.toolName = text(payload["tool_name"], 256)
        record.toolInput = toolInput(payload["tool_input"])
        record.error = text(payload["error"], 1024)
    case "Notification":
        record.message = text(payload["message"], 512)
        record.notificationType = text(payload["notification_type"], 128)
    case "Stop":
        record.lastAssistantMessage = text(payload["last_assistant_message"], 1024)
    case "StopFailure":
        record.error = text(payload["error"], 1024)
    case "CwdChanged":
        record.cwd = text(payload["new_cwd"], 4096) ?? record.cwd
    default:
        break
    }
    record.branch = record.cwd.flatMap(GitBranch.current(in:)).flatMap { text($0, 256) }

    if let agent = argument(after: "--agent"), agent == "claude" || agent == "codex" {
        record.agent = agent
        if agent == "codex" { record.agentPID = ancestor(namedLike: "codex") }
    }

    let environment = ProcessInfo.processInfo.environment
    let app = hostApp()
    let bundleID = text(environment["__CFBundleIdentifier"], 256)
    record.host = HookRecord.HostHint(
        bundleID: bundleID,
        termProgram: text(environment["TERM_PROGRAM"], 128),
        itermSessionID: text(environment["ITERM_SESSION_ID"], 128),
        parentPID: getppid(),
        appBundleID: app.flatMap { text($0.bundleID, 256) },
        appName: text(app?.name ?? bundleID.flatMap(appName(bundleID:)), 128),
        appPID: app?.pid
    )
    return record
}

// MARK: Process ancestry

func processName(_ pid: pid_t) -> String? {
    var buffer = [UInt8](repeating: 0, count: 256)
    let length = Int(proc_name(pid, &buffer, UInt32(buffer.count)))
    return length > 0 ? String(decoding: buffer.prefix(length), as: UTF8.self) : nil
}

func parent(of pid: pid_t) -> pid_t? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return pid_t(info.pbi_ppid)
}

/// The nearest ancestor whose process name starts with `prefix` (e.g. "codex", or the npm
/// package's "codex-aarch64-apple-darwin"). Hooks may run under a shell, so look a few levels up.
func ancestor(namedLike prefix: String) -> Int32? {
    var pid = getppid()
    for _ in 0..<12 where pid > 1 {
        if processName(pid)?.hasPrefix(prefix) == true { return pid }
        guard let next = parent(of: pid) else { return nil }
        pid = next
    }
    return nil
}

func executablePath(_ pid: pid_t) -> String? {
    var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
    return length > 0 ? String(decoding: buffer.prefix(length), as: UTF8.self) : nil
}

/// The outermost app bundle an executable lives in: VS Code's helpers sit in
/// "Visual Studio Code.app/Contents/Frameworks/Code Helper.app/…", and belong to VS Code.
func outermostBundle(_ path: String) -> String? {
    guard let range = path.range(of: ".app/") else { return nil }
    return String(path[..<range.lowerBound]) + ".app"
}

/// The app the session runs in, whatever it is: the first ancestor inside an app bundle, then up
/// to that app's main process. Finds Warp, Ghostty, Cursor and the rest without knowing them.
/// Finds nothing under tmux, whose server's parent is launchd.
func hostApp() -> (bundleID: String?, name: String, pid: pid_t)? {
    var pid = getppid()
    var found: (bundle: String, pid: pid_t)?
    for _ in 0..<24 where pid > 1 {
        guard let path = executablePath(pid) else { break }
        if let current = found {
            guard path.hasPrefix(current.bundle + "/") else { break }
            found = (current.bundle, pid)
        } else if let bundle = outermostBundle(path) {
            found = (bundle, pid)
        }
        guard let next = parent(of: pid) else { break }
        pid = next
    }
    guard let found else { return nil }
    return (Bundle(path: found.bundle)?.bundleIdentifier, displayName(found.bundle), found.pid)
}

/// Names the app the environment points at, for when the ancestry has none (under tmux).
func appName(bundleID: String) -> String? {
    guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL],
          let url = urls.first else { return nil }
    return displayName(url.path)
}

/// Finder's name for an app, without the ".app" it keeps when the user shows all extensions.
func displayName(_ bundle: String) -> String {
    var name = FileManager.default.displayName(atPath: bundle)
    if name.hasSuffix(".app") { name.removeLast(4) }
    return name
}

func encode(_ record: HookRecord) -> Data? {
    let encoder = HookRecord.encoder()
    guard var data = try? encoder.encode(record) else { return nil }
    if data.count > HookRecord.maximumBytes {
        var trimmed = record
        trimmed.toolInput = nil
        trimmed.lastAssistantMessage = nil
        trimmed.truncated = true
        guard let smaller = try? encoder.encode(trimmed), smaller.count <= HookRecord.maximumBytes else { return nil }
        data = smaller
    }
    return data
}

/// Peeku drains the inbox within seconds while it runs. A backlog this large means Peeku was
/// deleted without removing its hooks (or hasn't run in ages), so stop filling the disk.
let maximumBacklog = 10_000

func inboxIsFull(_ inbox: URL) -> Bool {
    guard let directory = opendir(inbox.path) else { return false }
    defer { closedir(directory) }
    var count = 0
    while let entry = readdir(directory) {
        // Skip ".", ".." and in-flight ".tmp" files; only committed records count.
        let hidden = withUnsafeBytes(of: entry.pointee.d_name) { $0.first == UInt8(ascii: ".") }
        if hidden { continue }
        count += 1
        if count >= maximumBacklog { return true }
    }
    return false
}

/// Writes to a hidden temporary file, then renames it into place, so readers never see half a record.
func commit(_ data: Data, id: String, to inbox: URL) {
    let manager = FileManager.default
    try? manager.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    guard !inboxIsFull(inbox) else { return }
    let temporary = inbox.appending(path: ".\(id).tmp")
    let final = inbox.appending(path: "\(Int64(Date().timeIntervalSince1970 * 1000))-\(id).json")
    guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
    if rename(temporary.path, final.path) != 0 { unlink(temporary.path) }
}

/// Development aid, off unless `--capture <dir>` is passed: saves the raw payload, a few
/// environment variables and the process ancestry, to learn what an agent actually sends.
func capture(_ input: Data, to directory: String) {
    var chain: [String] = []
    var pid = getppid()
    for _ in 0..<12 where pid > 1 {
        chain.append("\(pid) \(processName(pid) ?? "?")")
        guard let next = parent(of: pid) else { break }
        pid = next
    }
    let environment = ProcessInfo.processInfo.environment
    let keys = ["TERM_PROGRAM", "__CFBundleIdentifier", "ITERM_SESSION_ID", "TERM_SESSION_ID", "SHELL", "PWD"]
    let info: [String: Any] = [
        "arguments": CommandLine.arguments,
        "ancestry": chain,
        "environment": environment.filter { keys.contains($0.key) || $0.key.hasPrefix("CODEX_") && !$0.key.contains("TOKEN") && !$0.key.contains("KEY") },
        "payload": (try? JSONSerialization.jsonObject(with: input)) ?? String(decoding: input, as: UTF8.self),
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: "\(directory)/\(Int64(Date().timeIntervalSince1970 * 1000))-\(getpid()).json", contents: data)
}

// MARK: Status line

/// Claude Code runs `peeku-hook statusline` as its status line command. It saves the subscription
/// usage Claude passes in, then hands the same input to the user's own status line command (kept
/// base64-encoded after `--then`), so what they see doesn't change. It never prints anything itself.
func runStatusLine() {
    let input = (try? FileHandle.standardInput.read(upToCount: maximumInput)) ?? Data()
    markSeen(argument(after: "--usage").map { URL(filePath: $0).deletingLastPathComponent().appending(path: "claude-statusline-seen") }
             ?? PeekuPaths.default.claudeStatusLineSeen)
    if let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
       let limits = payload["rate_limits"] as? [String: Any] {
        let file = argument(after: "--usage").map { URL(filePath: $0) } ?? PeekuPaths.default.claudeUsage
        saveUsage(limits, to: file)
    }
    if let encoded = argument(after: "--then"), let data = Data(base64Encoded: encoded),
       let command = String(data: data, encoding: .utf8), !command.isEmpty {
        forward(input, to: command)
    }
}

/// The status line refreshes after every message. Unchanged numbers are rewritten at most once a
/// minute, which is enough for Peeku's "updated … ago".
func saveUsage(_ limits: [String: Any], to file: URL) {
    let manager = FileManager.default
    if let data = try? Data(contentsOf: file),
       let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       (saved["rateLimits"] as? NSDictionary)?.isEqual(to: limits) == true,
       let modified = (try? manager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
       Date().timeIntervalSince(modified) < 60 { return }

    let snapshot: [String: Any] = ["observedAt": Int64(Date().timeIntervalSince1970 * 1000), "rateLimits": limits]
    guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
    let directory = file.deletingLastPathComponent()
    try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let temporary = directory.appending(path: ".\(file.lastPathComponent).\(getpid()).tmp")
    guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
    if rename(temporary.path, file.path) != 0 { unlink(temporary.path) }
}

/// Lets Peeku tell "the status line never ran" from "Claude didn't include usage". Touched at most once a minute.
func markSeen(_ file: URL) {
    let manager = FileManager.default
    if let modified = (try? manager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
       Date().timeIntervalSince(modified) < 60 { return }
    try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    if manager.fileExists(atPath: file.path) {
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    } else {
        manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
}

/// Runs the user's own status line with the same input, its output going straight to Claude Code.
func forward(_ input: Data, to command: String) {
    signal(SIGPIPE, SIG_IGN)
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardInput = pipe
    guard (try? process.run()) != nil else { return }
    // Written from another thread, so a command that never reads its input can't block us.
    let writer = pipe.fileHandleForWriting
    Thread.detachNewThread {
        try? writer.write(contentsOf: input)
        try? writer.close()
    }
    process.waitUntilExit()
}

// MARK: Hooks

func run() {
    if CommandLine.arguments.dropFirst().first == "statusline" { return runStatusLine() }
    guard let input = try? FileHandle.standardInput.read(upToCount: maximumInput + 1), input.count <= maximumInput else { return }
    if let directory = argument(after: "--capture") { capture(input, to: directory) }
    guard let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let event = argument(after: "--event") ?? text(payload["hook_event_name"], 64),
          let record = record(event: event, payload: payload),
          let data = encode(record) else { return }
    let inbox = argument(after: "--inbox").map { URL(filePath: $0, directoryHint: .isDirectory) } ?? PeekuPaths.default.inbox
    commit(data, id: record.id, to: inbox)
}

run()
exit(0)
