import Foundation

/// Picks a session's window by title, for apps Nudge has no tab-level support for. Terminals and
/// editors usually title windows with the folder or the running program's own title.
public enum WindowMatch {
    /// 2 when the title has Claude's name for the session, 1 when it has the project folder, 0 otherwise.
    public static func score(_ title: String, for observed: ObservedSession) -> Int {
        if let name = observed.title, name.count >= 3, title.localizedCaseInsensitiveContains(name) { return 2 }
        if let folder = folder(observed), title.localizedCaseInsensitiveContains(folder) { return 1 }
        return 0
    }

    /// The best-matching title's index; ties go to the first, which is the frontmost.
    public static func best(_ titles: [String], for observed: ObservedSession) -> Int? {
        var best: (index: Int, score: Int)?
        for (index, title) in titles.enumerated() {
            let score = score(title, for: observed)
            if score > (best?.score ?? 0) { best = (index, score) }
        }
        return best?.index
    }

    /// Too short a folder name ("a", "go") would match unrelated windows.
    private static func folder(_ observed: ObservedSession) -> String? {
        let name = URL(filePath: observed.cwd).lastPathComponent
        return name.count >= 3 && name != "/" ? name : nil
    }
}
