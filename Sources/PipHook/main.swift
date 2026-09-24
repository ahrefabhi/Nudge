import Darwin
import Foundation
import PipHookSchema

// Claude Code runs this for every registered hook event. It only records what happened:
// it never prints, never decides anything for Claude, and always exits 0 quickly.

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

    let environment = ProcessInfo.processInfo.environment
    record.host = HookRecord.HostHint(
        bundleID: text(environment["__CFBundleIdentifier"], 256),
        termProgram: text(environment["TERM_PROGRAM"], 128),
        itermSessionID: text(environment["ITERM_SESSION_ID"], 128),
        parentPID: getppid()
    )
    return record
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

func run() {
    guard let input = try? FileHandle.standardInput.read(upToCount: maximumInput + 1), input.count <= maximumInput,
          let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let event = argument(after: "--event") ?? text(payload["hook_event_name"], 64),
          let record = record(event: event, payload: payload),
          let data = encode(record) else { return }
    let inbox = argument(after: "--inbox").map { URL(filePath: $0, directoryHint: .isDirectory) } ?? PipPaths.default.inbox
    commit(data, id: record.id, to: inbox)
}

run()
exit(0)
