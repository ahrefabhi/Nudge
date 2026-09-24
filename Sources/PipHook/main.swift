import Darwin
import Foundation
import PipHookSchema

// Claude Code and Codex run this for every registered hook event. It only records what happened:
// it never prints, never decides anything for the agent, and always exits 0 quickly.

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

    if let agent = argument(after: "--agent"), agent == "claude" || agent == "codex" {
        record.agent = agent
        if agent == "codex" { record.agentPID = ancestor(namedLike: "codex") }
    }

    let environment = ProcessInfo.processInfo.environment
    record.host = HookRecord.HostHint(
        bundleID: text(environment["__CFBundleIdentifier"], 256),
        termProgram: text(environment["TERM_PROGRAM"], 128),
        itermSessionID: text(environment["ITERM_SESSION_ID"], 128),
        parentPID: getppid()
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

/// Pip drains the inbox within seconds while it runs. A backlog this large means Pip was
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

func run() {
    guard let input = try? FileHandle.standardInput.read(upToCount: maximumInput + 1), input.count <= maximumInput else { return }
    if let directory = argument(after: "--capture") { capture(input, to: directory) }
    guard let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let event = argument(after: "--event") ?? text(payload["hook_event_name"], 64),
          let record = record(event: event, payload: payload),
          let data = encode(record) else { return }
    let inbox = argument(after: "--inbox").map { URL(filePath: $0, directoryHint: .isDirectory) } ?? PipPaths.default.inbox
    commit(data, id: record.id, to: inbox)
}

run()
exit(0)
