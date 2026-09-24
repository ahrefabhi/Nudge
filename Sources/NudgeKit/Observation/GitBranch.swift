import Foundation

/// Reads the current branch straight from `.git/HEAD`, without running git. Handles worktrees.
public enum GitBranch {
    public static func current(in directory: String) -> String? {
        guard let gitDirectory = gitDirectory(from: URL(filePath: directory, directoryHint: .isDirectory)),
              let head = try? String(contentsOf: gitDirectory.appending(path: "HEAD"), encoding: .utf8)
        else { return nil }
        let value = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("ref: refs/heads/") { return String(value.dropFirst("ref: refs/heads/".count)) }
        // Detached HEAD: a short commit id.
        return value.count >= 7 ? String(value.prefix(7)) : nil
    }

    /// Walks up to the nearest `.git`, following a worktree's `gitdir:` file.
    static func gitDirectory(from start: URL) -> URL? {
        var directory = start.standardizedFileURL
        let manager = FileManager.default
        while true {
            let candidate = directory.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return candidate }
                guard let contents = try? String(contentsOf: candidate, encoding: .utf8),
                      let line = contents.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir: ") else { return nil }
                let path = String(line.dropFirst("gitdir: ".count)).trimmingCharacters(in: .whitespaces)
                return path.hasPrefix("/") ? URL(filePath: path, directoryHint: .isDirectory)
                    : directory.appending(path: path, directoryHint: .isDirectory).standardizedFileURL
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }
}
