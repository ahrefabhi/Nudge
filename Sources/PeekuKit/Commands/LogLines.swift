import Foundation

/// Turns a command's raw output into plain lines: splits on newlines, keeps only what a
/// terminal would leave after a carriage return (progress bars), and drops color and cursor codes.
public struct LogLineSplitter: Sendable {
    /// Longer lines are cut, so one runaway line can't swallow the log.
    public static let maxLineLength = 4000

    private var pending = Data()

    public init() {}

    /// Complete lines in `data`; a trailing partial line waits for the next chunk.
    public mutating func feed(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Self.clean(pending[pending.startIndex..<newline]))
            pending = Data(pending[pending.index(after: newline)...])
        }
        if pending.count > Self.maxLineLength {
            lines.append(Self.clean(pending))
            pending = Data()
        }
        return lines
    }

    /// The unfinished last line, like a prompt waiting for an answer.
    public var partial: String { Self.clean(pending) }

    /// Whatever is left once the output ends.
    public mutating func finish() -> [String] {
        defer { pending = Data() }
        let rest = Self.clean(pending)
        return rest.isEmpty ? [] : [rest]
    }

    /// Whether an unfinished line reads like a question: "(Y/n)", "Port 3000 is taken. Use another?",
    /// "Password:" or a `›` menu marker. Progress bars end in "%" or "]" and don't count.
    public static func looksLikePrompt(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        if asksYesOrNo(text) { return true }
        return text.hasSuffix("?") || text.hasSuffix(":") || text.hasSuffix("›") || text.hasSuffix("❯")
    }

    /// "(Y/n)", "[y/N]", "(yes/no)": a prompt a Yes or No button can answer.
    public static func asksYesOrNo(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("y/n") || lower.contains("yes/no")
    }

    static func clean(_ bytes: Data) -> String {
        var text = String(decoding: bytes, as: UTF8.self)
        if text.contains("\u{1B}") { text = stripEscapes(text) }
        // "\r" rewrites the line in a terminal, so only the last version counts. A "\r\n" ending leaves an empty tail.
        if text.contains("\r") {
            text = text.split(separator: "\r", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        }
        if text.count > maxLineLength { text = String(text.prefix(maxLineLength)) + "…" }
        return text
    }

    /// Drops ANSI CSI sequences (`ESC [ … letter`), OSC sequences (`ESC ] … BEL`) and other two-byte escapes.
    static func stripEscapes(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\u{1B}" else {
                // Other control characters besides tab and CR would render as junk.
                if scalar.value >= 0x20 || scalar == "\t" || scalar == "\r" { result.append(scalar) }
                continue
            }
            switch scalars.next() {
            case "[":
                while let next = scalars.next(), !(0x40...0x7E).contains(next.value) {}
            case "]":
                while let next = scalars.next(), next != "\u{07}" {
                    if next == "\u{1B}" { _ = scalars.next(); break }
                }
            default:
                break
            }
        }
        return String(result)
    }
}
