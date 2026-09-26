import Foundation

/// Runs the agents' own command-line tools to ask them for things only they know, like Codex's
/// live rate limits or the Claude plan. Never through a shell, always with fixed arguments and a
/// time limit, and never with anything Peeku read from a session.
public enum AgentCLI {
    /// An app opened from Finder gets a bare PATH, so also look where installers put these tools.
    public static func locate(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin",
                        "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.claude/local"]
        // nvm keeps one bin folder per Node version; try the newest first.
        let nvm = "\(home)/.nvm/versions/node"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        directories += versions.map { "\(nvm)/\($0)/bin" }
        for directory in directories where !directory.isEmpty {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return URL(filePath: path) }
        }
        return nil
    }

    /// The tool's standard output, or nil if it failed, timed out or printed too much.
    static func output(of executable: URL, arguments: [String], timeout: TimeInterval) -> Data? {
        var result: Data?
        run(executable, arguments: arguments, timeout: timeout) { _, output in
            result = output.readToEnd(limit: 1024 * 1024)
            return true
        }
        return result
    }

    /// What a tool printed and how it exited, for commands whose errors the user should read.
    public struct Result: Sendable {
        public var status: Int32
        public var output: String
        public var errors: String
        public var succeeded: Bool { status == 0 }
    }

    /// Runs the tool to the end, collecting stdout and stderr separately. Nil if it couldn't start;
    /// a tool still running after `timeout` is stopped and reported as failed.
    static func execute(_ executable: URL, arguments: [String], in directory: URL? = nil, timeout: TimeInterval) -> Result? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.environment = environment(for: executable)
        let output = Pipe(), errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        guard (try? process.run()) != nil else { return nil }

        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Both pipes drain at once, so a tool that fills one while we wait on the other can't stall.
        nonisolated(unsafe) var errorData = Data()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: group) {
            errorData = errors.fileHandleForReading.readToEnd(limit: 256 * 1024) ?? Data()
        }
        let outputData = output.fileHandleForReading.readToEnd(limit: 16 * 1024 * 1024) ?? Data()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()
        return Result(status: process.terminationStatus,
                      output: String(decoding: outputData, as: UTF8.self),
                      errors: String(decoding: errorData, as: UTF8.self))
    }

    private static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // An npm install needs `node`, which sits next to it; Homebrew's may need the rest.
        environment["PATH"] = ([executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
                               + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// Starts the tool with stdin and stdout piped, hands them to `talk` on this thread, and
    /// stops the tool when `talk` returns or `timeout` passes, whichever comes first.
    @discardableResult
    static func run(_ executable: URL, arguments: [String], in directory: URL? = nil, timeout: TimeInterval,
                    talk: (_ input: FileHandle, _ output: FileHandle) -> Bool) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.environment = environment(for: executable)
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }

        // Closing our end of stdout unblocks a read that's waiting on a tool that hangs.
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let finished = talk(input.fileHandleForWriting, output.fileHandleForReading)
        watchdog.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        return finished
    }
}

extension FileHandle {
    /// Reads until end of file, giving up past `limit` bytes.
    func readToEnd(limit: Int) -> Data? {
        var data = Data()
        while true {
            let chunk = availableData
            if chunk.isEmpty { return data }
            data.append(chunk)
            if data.count > limit { return nil }
        }
    }

    /// Calls `line` with each line of output until it returns true or the output ends.
    func readLines(limit: Int, _ line: (Data) -> Bool) -> Bool {
        var buffer = Data()
        while true {
            let chunk = availableData
            if chunk.isEmpty { return false }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let text = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                if line(Data(text)) { return true }
            }
            if buffer.count > limit { return false }
        }
    }
}
