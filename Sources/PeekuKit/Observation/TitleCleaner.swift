import Foundation

/// Turns a raw prompt into a short task line, e.g. "please fix the flaky login test in ci" → "Fix the flaky login test in ci".
public enum TitleCleaner {
    static let maximumWords = 8

    public static func title(from prompt: String?) -> String? {
        guard let prompt else { return nil }
        var text = prompt
            .replacing(/<\/?pasted_content[^>]*>/, with: "\n")
            .replacing(/```[\s\S]*?```/, with: " ")
            .replacing(/\[(Image|Pasted text) #\d+[^\]]*\]/, with: " ")
            .replacing(/https?:\/\/\S+/, with: " ")
            .replacing(/(?:\/[\w.-]+){3,}/) { match in String(match.output.split(separator: "/").last ?? "") }
        guard let line = text.split(whereSeparator: \.isNewline).map({ stripMarkdown(String($0)) }).first(where: { !$0.isEmpty })
        else { return nil }
        text = line
            .replacing(/^\/[\w:-]+\s*/, with: "")
            .replacing(/^(?:(?:please|pls|can you|could you|would you|help me(?: to)?|i (?:want|need)(?: you)? to)[\s,]+)+/.ignoresCase(), with: "")
        var sentence = text
        if let end = text.firstMatch(of: /[.!?]\s/) {
            let mark = text[end.range.lowerBound]
            sentence = String(text[..<end.range.lowerBound]) + (mark == "." ? "" : String(mark))
        }
        let words = sentence.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return nil }
        var short = words.prefix(maximumWords).joined(separator: " ")
        while let last = short.last, ".,:;".contains(last) { short.removeLast() }
        if words.count > maximumWords { short += "…" }
        return short.prefix(1).uppercased() + short.dropFirst()
    }

    /// Drops inline markdown: headers, bullets, emphasis, backticks and link targets.
    static func stripMarkdown(_ line: String) -> String {
        line
            .replacing(/\[([^\]]+)\]\([^)]+\)/) { String($0.output.1) }
            .replacing(/(\*\*|__)(.+?)\1/) { String($0.output.2) }
            .replacing(/^[\s#>*\-]+/, with: "")
            .replacing("`", with: "")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
