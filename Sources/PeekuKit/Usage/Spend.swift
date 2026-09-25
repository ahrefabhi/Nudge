import Foundation

/// What a model's tokens cost, in dollars per million. Anthropic's list prices, bundled so
/// working out spend needs no network request.
public struct ModelPrice: Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double

    /// Cache writes cost 1.25× input for the 5-minute cache and 2× for the 1-hour one.
    init(input: Double, output: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        cacheWrite5m = input * 1.25
        cacheWrite1h = input * 2
    }

    /// Dollars for these tokens. Fast mode bills twice the standard rate.
    public func cost(_ tokens: TokenCounts, fast: Bool = false) -> Double {
        let dollars = Double(tokens.input) * input + Double(tokens.output) * output + Double(tokens.cacheRead) * cacheRead
            + Double(tokens.cacheWrite5m) * cacheWrite5m + Double(tokens.cacheWrite1h) * cacheWrite1h
        return dollars / 1_000_000 * (fast ? 2 : 1)
    }
}

public enum ModelPrices {
    /// Keyed by the model id without a date or `[1m]` suffix. A model missing here still counts
    /// its tokens; its cost just isn't known.
    static let claude: [String: ModelPrice] = [
        "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5": ModelPrice(input: 10, output: 50, cacheRead: 1),
        "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.2),
        "claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-8": ModelPrice(input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-7": ModelPrice(input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-6": ModelPrice(input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-5": ModelPrice(input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-1": ModelPrice(input: 15, output: 75, cacheRead: 1.5),
        "claude-opus-4": ModelPrice(input: 15, output: 75, cacheRead: 1.5),
        "claude-sonnet-5": ModelPrice(input: 2, output: 10, cacheRead: 0.2),
        "claude-sonnet-4-6": ModelPrice(input: 3, output: 15, cacheRead: 0.3),
        "claude-sonnet-4-5": ModelPrice(input: 3, output: 15, cacheRead: 0.3),
        "claude-sonnet-4": ModelPrice(input: 3, output: 15, cacheRead: 0.3),
        "claude-haiku-4-5": ModelPrice(input: 1, output: 5, cacheRead: 0.1),
    ]

    public static func price(for model: String) -> ModelPrice? { claude[normalize(model)] }

    /// Models that hold 200K tokens unless Claude Code asks for their 1M window with `[1m]`.
    static let smallWindow: Set<String> = ["claude-haiku-4-5", "claude-sonnet-4", "claude-sonnet-4-5", "claude-opus-4", "claude-opus-4-1", "claude-opus-4-5"]

    /// How many tokens a Claude model's context holds; newer models hold 1M.
    public static func contextWindow(for model: String) -> Int {
        !model.contains("[1m]") && smallWindow.contains(normalize(model)) ? 200_000 : 1_000_000
    }

    /// `claude-opus-5-5[1m]` and `claude-haiku-4-5-20251001` to their priced ids, `gpt-5.5-2026-01-01` to `gpt-5.5`.
    public static func normalize(_ model: String) -> String {
        var id = model
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        if let slash = id.lastIndex(of: "/") { id = String(id[id.index(after: slash)...]) }
        if let date = id.range(of: #"-\d{8}$|-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) { id.removeSubrange(date) }
        return id
    }
}

public struct TokenCounts: Sendable, Equatable {
    /// Input that wasn't read from or written to the cache.
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    /// Every token the model processed, cache reads included, which are most of them.
    public var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }
    public var isEmpty: Bool { total == 0 }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead,
                    cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m, cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h)
    }

    public static func - (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input - b.input, output: a.output - b.output, cacheRead: a.cacheRead - b.cacheRead,
                    cacheWrite5m: a.cacheWrite5m - b.cacheWrite5m, cacheWrite1h: a.cacheWrite1h - b.cacheWrite1h)
    }
}

/// Tokens and dollars for one model, or a sum of them.
public struct Spend: Sendable, Equatable {
    public var tokens = TokenCounts()
    /// Dollars for the requests Peeku knows a price for.
    public var cost: Double = 0
    public var requests = 0
    /// Requests whose model has no price, so `cost` leaves them out.
    public var unpriced = 0

    public init(tokens: TokenCounts = TokenCounts(), cost: Double = 0, requests: Int = 0, unpriced: Int = 0) {
        self.tokens = tokens
        self.cost = cost
        self.requests = requests
        self.unpriced = unpriced
    }

    /// Whether any of it has a price, so a cost is worth showing.
    public var isPriced: Bool { unpriced < requests }

    public static func + (a: Spend, b: Spend) -> Spend {
        Spend(tokens: a.tokens + b.tokens, cost: a.cost + b.cost, requests: a.requests + b.requests, unpriced: a.unpriced + b.unpriced)
    }

    public static func - (a: Spend, b: Spend) -> Spend {
        Spend(tokens: a.tokens - b.tokens, cost: a.cost - b.cost, requests: a.requests - b.requests, unpriced: a.unpriced - b.unpriced)
    }

    public static func += (a: inout Spend, b: Spend) { a = a + b }
    public static func -= (a: inout Spend, b: Spend) { a = a - b }
}

/// One session's model, what it has cost, and how full its context is.
public struct SessionSpend: Sendable, Equatable {
    /// The model of its latest reply.
    public var model: String
    /// Every reply in the session, its subagents' included.
    public var spend: Spend
    /// Tokens the latest reply read: the conversation so far.
    public var context: Int
    public var contextWindow: Int

    public init(model: String, spend: Spend, context: Int, contextWindow: Int) {
        self.model = model
        self.spend = spend
        self.context = context
        self.contextWindow = contextWindow
    }

    /// 0 to 1.
    public var contextFraction: Double { contextWindow > 0 ? min(1, Double(context) / Double(contextWindow)) : 0 }
}

/// One agent's spend over the last `days` days, worked out from its session logs.
public struct SpendReport: Sendable, Equatable {
    /// A day or an hour of use.
    public struct Bucket: Sendable, Equatable, Identifiable {
        /// Its start: local midnight, or the top of the hour.
        public var date: Date
        public var models: [String: Spend]
        public var id: Date { date }
        public var total: Spend { models.values.reduce(Spend(), +) }
    }

    public var agent: Agent
    /// Oldest first, one per day, today last, days without use included.
    public var days: [Bucket]
    /// Today's 24 hours, midnight first, the hours still to come empty.
    public var hours: [Bucket]
    /// Keyed by session id, for sessions written to in the window.
    public var sessions: [String: SessionSpend]

    public init(agent: Agent, days: [Bucket], hours: [Bucket] = [], sessions: [String: SessionSpend] = [:]) {
        self.agent = agent
        self.days = days
        self.hours = hours
        self.sessions = sessions
    }

    /// What the Usage tab shows: today by hour, or the last 7 or 30 days by day.
    public enum Period: String, Sendable, CaseIterable {
        case today, week, month

        public var title: String {
            switch self {
            case .today: "Today"
            case .week: "7 days"
            case .month: "30 days"
            }
        }
    }

    /// The period's bars, oldest first.
    public func buckets(_ period: Period) -> [Bucket] {
        switch period {
        case .today: hours
        case .week: Array(days.suffix(7))
        case .month: days
        }
    }

    public func total(_ period: Period) -> Spend {
        // Today's hours add up to today, even before the first hour has any.
        period == .today ? today : buckets(period).reduce(Spend()) { $0 + $1.total }
    }

    /// `claude-opus-5-5` as "Opus 5.5", `gpt-6-luna` as "GPT-6 Luna".
    public static func displayName(_ model: String) -> String {
        var parts = ModelPrices.normalize(model).split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if parts.first == "gpt", parts.count > 1 {
            parts[0] = "GPT-" + parts.remove(at: 1)
        }
        var words: [String] = []
        for part in parts {
            if part.allSatisfy(\.isNumber), let last = words.last, last.last?.isNumber == true {
                words[words.count - 1] = last + "." + part
            } else if part.first?.isNumber == true || part.hasPrefix("GPT") {
                words.append(part)
            } else {
                words.append(part.prefix(1).uppercased() + part.dropFirst())
            }
        }
        return words.joined(separator: " ")
    }

    public var today: Spend { days.last?.total ?? Spend() }
    public var window: Spend { days.reduce(Spend()) { $0 + $1.total } }
    public var isEmpty: Bool { window.requests == 0 }

    /// The window's models, most expensive first, then by tokens, for models without a price.
    public var models: [String] { models(.month) }

    /// The period's models, ranked the same way.
    public func models(_ period: Period) -> [String] {
        var totals: [String: Spend] = [:]
        for bucket in period == .today ? Array(days.suffix(1)) : buckets(period) {
            for (model, spend) in bucket.models { totals[model, default: Spend()] += spend }
        }
        return totals.sorted { a, b in
            if a.value.cost != b.value.cost { return a.value.cost > b.value.cost }
            if a.value.tokens.total != b.value.tokens.total { return a.value.tokens.total > b.value.tokens.total }
            return a.key < b.key
        }.map(\.key)
    }
}

/// Adds up the tokens in an agent's session logs, reading each log once and then only what
/// was appended to it. Not thread safe: use it from one queue.
final class SpendScanner: @unchecked Sendable {
    /// One billed request found in a log.
    struct Entry {
        var date: Date
        var model: String
        var tokens: TokenCounts
        var fast = false
        /// When the log says, like Codex's `model_context_window`.
        var contextWindow: Int?
        /// Lines with the same key are the same request; the last one has the final counts.
        var key: String?
    }

    /// What a log parser needs to remember between lines of one file, like Codex's current model.
    struct FileContext {
        var model: String?
        var totals: TokenCounts?
    }

    private struct FileState {
        var size: UInt64
        var offset: UInt64
        var context = FileContext()
    }

    /// Which session a log belongs to, and whether it's the session's own conversation rather
    /// than a subagent's, whose context is its own.
    struct LogOwner: Equatable {
        var session: String
        var isMain: Bool
    }

    let agent: Agent
    let roots: [URL]
    let days: Int
    let calendar: Calendar
    private let price: (String) -> ModelPrice?
    private let parse: (Data, inout FileContext) -> Entry?
    private let owner: (_ log: URL, _ root: URL) -> LogOwner?

    private var files: [String: FileState] = [:]
    /// Keyed by the top of the hour.
    private var buckets: [Date: [String: Spend]] = [:]
    private var sessions: [String: SessionSpend] = [:]
    /// Each keyed request's hour, model, session and spend as counted, so a later line can replace it.
    private var counted: [String: (hour: Date, model: String, session: String?, spend: Spend)] = [:]

    init(agent: Agent, roots: [URL], days: Int = 30, calendar: Calendar = .current,
         price: @escaping (String) -> ModelPrice? = ModelPrices.price(for:),
         owner: @escaping (_ log: URL, _ root: URL) -> LogOwner? = { _, _ in nil },
         parse: @escaping (Data, inout FileContext) -> Entry?) {
        self.agent = agent
        self.roots = roots
        self.days = days
        self.calendar = calendar
        self.price = price
        self.owner = owner
        self.parse = parse
    }

    func scan(now: Date = Date()) -> SpendReport {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let logs = roots.flatMap { root in Self.logs(in: root, modifiedSince: start).map { ($0.url, $0.size, root) } }
            .map { (url: $0.0, size: $0.1, owner: owner($0.0, $0.2)) }
        // A log that got shorter was rewritten, and what was counted from it can't be taken back.
        if logs.contains(where: { log in files[log.url.path].map { log.size < $0.size } ?? false }) {
            files = [:]
            buckets = [:]
            sessions = [:]
            counted = [:]
        }
        for log in logs {
            var state = files[log.url.path] ?? FileState(size: 0, offset: 0)
            guard log.size != state.size else { continue }
            state.offset = read(log.url, owner: log.owner, from: state.offset, since: start, context: &state.context)
            state.size = log.size
            files[log.url.path] = state
        }
        buckets = buckets.filter { $0.key >= start }
        var byDay: [Date: [String: Spend]] = [:]
        for (hour, models) in buckets {
            let day = calendar.startOfDay(for: hour)
            for (model, spend) in models { byDay[day, default: [:]][model, default: Spend()] += spend }
        }
        let range = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let hours = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }
            .filter { calendar.isDate($0, inSameDayAs: today) }
        return SpendReport(agent: agent, days: range.map { SpendReport.Bucket(date: $0, models: byDay[$0] ?? [:]) },
                           hours: hours.map { SpendReport.Bucket(date: $0, models: buckets[$0] ?? [:]) }, sessions: sessions)
    }

    /// Counts the complete lines after `offset` and returns where the last one ended.
    private func read(_ url: URL, owner: LogOwner?, from offset: UInt64, since start: Date, context: inout FileContext) -> UInt64 {
        guard SafeFile.isOwnedRegularFile(url, maximumBytes: .max), let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return offset }
        var consumed = offset
        var lineStart = data.startIndex
        // A line still being written has no newline yet; it's read next time.
        while let newline = data[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = data[lineStart..<newline]
            consumed += UInt64(line.count + 1)
            lineStart = data.index(after: newline)
            if let entry = parse(Data(line), &context), entry.date >= start { add(entry, owner: owner) }
        }
        return consumed
    }

    private func add(_ entry: Entry, owner: LogOwner?) {
        let hour = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
        let model = ModelPrices.normalize(entry.model)
        let price = price(entry.model)
        let spend = Spend(tokens: entry.tokens, cost: price?.cost(entry.tokens, fast: entry.fast) ?? 0,
                          requests: 1, unpriced: price == nil ? 1 : 0)
        if let key = entry.key {
            if let previous = counted[key] {
                buckets[previous.hour, default: [:]][previous.model, default: Spend()] -= previous.spend
                if let session = previous.session { sessions[session]?.spend -= previous.spend }
            }
            counted[key] = (hour, model, owner?.session, spend)
        }
        buckets[hour, default: [:]][model, default: Spend()] += spend
        guard let owner else { return }
        let tokens = entry.tokens
        let context = tokens.input + tokens.cacheRead + tokens.cacheWrite5m + tokens.cacheWrite1h
        var session = sessions[owner.session]
            ?? SessionSpend(model: model, spend: Spend(), context: 0, contextWindow: ModelPrices.contextWindow(for: entry.model))
        session.spend += spend
        // Lines arrive in order, so the main conversation's latest reply says where it stands.
        if owner.isMain {
            session.model = model
            session.context = context
            session.contextWindow = entry.contextWindow ?? ModelPrices.contextWindow(for: entry.model)
        }
        sessions[owner.session] = session
    }

    /// Every `.jsonl` under `root` written to since `start`, with its size.
    static func logs(in root: URL, modifiedSince start: Date) -> [(url: URL, size: UInt64)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var result: [(URL, UInt64)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= start else { continue }
            result.append((url, UInt64(values.fileSize ?? 0)))
        }
        return result
    }
}

extension [SpendReport] {
    /// A running session's model, cost and context.
    public func session(_ id: String) -> SessionSpend? {
        lazy.compactMap { $0.sessions[id] }.first
    }
}

// MARK: Claude Code

public enum ClaudeSpendParser {
    /// An assistant line: `{"type":"assistant","timestamp","requestId","message":{"id","model","usage":{…}}}`.
    /// Claude Code writes one per content block of a reply, and only the last has the final output count.
    static func parse(_ line: Data, _ context: inout SpendScanner.FileContext) -> SpendScanner.Entry? {
        guard line.range(of: Data(#""type":"assistant""#.utf8)) != nil, line.range(of: Data(#""usage""#.utf8)) != nil,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "assistant",
              let date = (object["timestamp"] as? String).flatMap(CodexUsageReader.timestamp),
              let message = object["message"] as? [String: Any],
              let model = message["model"] as? String, !model.hasPrefix("<"),
              let usage = message["usage"] as? [String: Any] else { return nil }
        let cacheWrite = int(usage["cache_creation_input_tokens"])
        // Older Claude Code builds don't split cache writes by duration; those were all 5-minute.
        let split = usage["cache_creation"] as? [String: Any]
        let write1h = split.map { int($0["ephemeral_1h_input_tokens"]) } ?? 0
        let tokens = TokenCounts(input: int(usage["input_tokens"]), output: int(usage["output_tokens"]),
                                 cacheRead: int(usage["cache_read_input_tokens"]),
                                 cacheWrite5m: split.map { int($0["ephemeral_5m_input_tokens"]) } ?? cacheWrite,
                                 cacheWrite1h: write1h)
        guard !tokens.isEmpty else { return nil }
        let ids = [message["id"] as? String, object["requestId"] as? String].compactMap { $0 }
        return SpendScanner.Entry(date: date, model: model, tokens: tokens, fast: usage["speed"] as? String == "fast",
                                  key: ids.isEmpty ? nil : ids.joined(separator: "|"))
    }

    static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
}

// MARK: Codex

public enum CodexSpendParser {
    /// A `turn_context` line names the model for the `token_count` events after it, which carry
    /// the turn's tokens in `last_token_usage`, or only the session's running `total_token_usage`.
    static func parse(_ line: Data, _ context: inout SpendScanner.FileContext) -> SpendScanner.Entry? {
        let isContext = line.range(of: Data(#""turn_context""#.utf8)) != nil
        guard isContext || line.range(of: Data(#""token_count""#.utf8)) != nil,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return nil }
        if object["type"] as? String == "turn_context" {
            if let model = payload["model"] as? String { context.model = model }
            return nil
        }
        guard payload["type"] as? String == "token_count", let info = payload["info"] as? [String: Any],
              let date = (object["timestamp"] as? String).flatMap(CodexUsageReader.timestamp) else { return nil }
        let total = (info["total_token_usage"] as? [String: Any]).map(tokens)
        // Codex repeats the last event when only its rate limits changed.
        if let total, total == context.totals { return nil }
        let turn: TokenCounts
        if let last = info["last_token_usage"] as? [String: Any] {
            turn = tokens(last)
        } else if let total {
            turn = context.totals.map { total - $0 } ?? total
        } else {
            return nil
        }
        if let total { context.totals = total }
        guard !turn.isEmpty, turn.input >= 0, turn.output >= 0 else { return nil }
        return SpendScanner.Entry(date: date, model: context.model ?? "gpt-5", tokens: turn,
                                  contextWindow: (info["model_context_window"] as? NSNumber)?.intValue)
    }

    /// Codex counts cached input inside `input_tokens`; Peeku keeps them apart, like Claude's.
    static func tokens(_ usage: [String: Any]) -> TokenCounts {
        let input = ClaudeSpendParser.int(usage["input_tokens"])
        let cached = min(ClaudeSpendParser.int(usage["cached_input_tokens"]), input)
        let written = min(ClaudeSpendParser.int(usage["cache_write_input_tokens"]), input - cached)
        return TokenCounts(input: input - cached - written, output: ClaudeSpendParser.int(usage["output_tokens"]),
                           cacheRead: cached, cacheWrite5m: written)
    }
}

extension SpendScanner {
    static func claude(projects: URL = ClaudePaths.configRoot.appending(path: "projects", directoryHint: .isDirectory)) -> SpendScanner {
        SpendScanner(agent: .claude, roots: [projects], owner: claudeOwner, parse: ClaudeSpendParser.parse)
    }

    static func codex(home: URL = CodexPaths.home) -> SpendScanner {
        SpendScanner(agent: .codex, roots: [home.appending(path: "sessions", directoryHint: .isDirectory),
                                            home.appending(path: "archived_sessions", directoryHint: .isDirectory)],
                     owner: codexOwner, parse: CodexSpendParser.parse)
    }

    /// `<project>/<session>.jsonl` is the session; `<project>/<session>/subagents/agent-….jsonl` are its subagents.
    static func claudeOwner(_ log: URL, root: URL) -> LogOwner? {
        let parts = log.resolvingSymlinksInPath().pathComponents.dropFirst(root.resolvingSymlinksInPath().pathComponents.count)
        guard parts.count >= 2 else { return nil }
        let second = parts[parts.startIndex + 1]
        return parts.count == 2
            ? LogOwner(session: String(second.dropLast(".jsonl".count)), isMain: true)
            : LogOwner(session: second, isMain: false)
    }

    /// `rollout-2026-09-24T18-46-33-<session uuid>.jsonl`.
    static func codexOwner(_ log: URL, root: URL) -> LogOwner? {
        let name = log.deletingPathExtension().lastPathComponent
        guard name.count > 36 else { return nil }
        return LogOwner(session: String(name.suffix(36)), isMain: true)
    }
}

/// Works out each agent's spend every 20 seconds on a background queue, and when the Usage tab opens.
@MainActor
public final class SpendService {
    public var onChange: (([SpendReport]) -> Void)?
    public private(set) var reports: [SpendReport] = []

    private let scanners: [SpendScanner]
    private let codexInstalled: @Sendable () -> Bool
    private let io = DispatchQueue(label: "app.peeku.spend", qos: .utility)
    private var timer: Timer?
    private var scanning = false

    /// Only new lines are read, so often enough for a working session's cost and context to keep up.
    static let interval: TimeInterval = 20

    public init(codexInstalled: @escaping @Sendable () -> Bool = { CodexPaths.isInstalled }) {
        scanners = [.claude(), .codex()]
        self.codexInstalled = codexInstalled
    }

    public func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Only the bytes appended since the last scan are read, so this is cheap after the first.
    public func refresh() {
        guard !scanning else { return }
        scanning = true
        let (scanners, codexInstalled) = (scanners, codexInstalled)
        io.async { [weak self] in
            let next = scanners.filter { $0.agent == .claude || codexInstalled() }.map { $0.scan() }
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                guard next != self.reports else { return }
                self.reports = next
                self.onChange?(next)
            }
        }
    }
}
