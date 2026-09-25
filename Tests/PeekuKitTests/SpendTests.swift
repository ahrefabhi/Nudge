import Foundation
import Testing
@testable import PeekuKit

@Suite struct SpendTests {
    let root: URL
    let now = CodexUsageReader.timestamp("2026-09-25T12:00:00Z")!
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "peeku-spend-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// An assistant line as Claude Code writes it.
    static func claudeLine(id: String = "msg_1", request: String = "req_1", model: String = "claude-opus-5",
                           at timestamp: String = "2026-09-25T10:00:00.000Z", input: Int = 10, output: Int = 100,
                           read: Int = 1_000, write5m: Int = 0, write1h: Int = 0, speed: String = "standard") -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"\(request)","message":{"id":"\(id)","model":"\(model)",\
        "usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(read),\
        "cache_creation_input_tokens":\(write5m + write1h),\
        "cache_creation":{"ephemeral_5m_input_tokens":\(write5m),"ephemeral_1h_input_tokens":\(write1h)},"speed":"\(speed)"}}}
        """
    }

    func scanner(_ agent: Agent = .claude) -> SpendScanner {
        agent == .claude
            ? SpendScanner(agent: agent, roots: [root], calendar: calendar, parse: ClaudeSpendParser.parse)
            : SpendScanner(agent: agent, roots: [root], calendar: calendar, parse: CodexSpendParser.parse)
    }

    func write(_ lines: [String], to name: String = "session.jsonl") throws {
        try (lines.joined(separator: "\n") + "\n").write(to: root.appending(path: name), atomically: true, encoding: .utf8)
    }

    func append(_ line: String, to name: String = "session.jsonl") throws {
        let handle = try FileHandle(forWritingTo: root.appending(path: name))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
        try handle.close()
    }

    @Test func pricesEachKindOfToken() throws {
        let price = try #require(ModelPrices.price(for: "claude-opus-5"))
        let tokens = TokenCounts(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
        // $5 in, $25 out, $0.50 read, $6.25 5-minute write, $10 1-hour write.
        #expect(abs(price.cost(tokens) - 46.75) < 1e-9)
        #expect(abs(price.cost(tokens, fast: true) - 93.5) < 1e-9)
    }

    @Test func normalizesModelIds() {
        #expect(ModelPrices.normalize("claude-opus-5-5[1m]") == "claude-opus-5-5")
        #expect(ModelPrices.normalize("claude-haiku-4-5-20251001") == "claude-haiku-4-5")
        #expect(ModelPrices.normalize("anthropic/claude-sonnet-5") == "claude-sonnet-5")
        #expect(ModelPrices.normalize("gpt-5.5-2026-01-01") == "gpt-5.5")
        // Opus 5 and Opus 5.5 are priced differently.
        #expect(ModelPrices.price(for: "claude-opus-5") != ModelPrices.price(for: "claude-opus-5-5"))
    }

    @Test func namesModelsForTheTab() {
        #expect(SpendReport.displayName("claude-opus-5-5[1m]") == "Opus 5.5")
        #expect(SpendReport.displayName("claude-fable-5") == "Fable 5")
        #expect(SpendReport.displayName("claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(SpendReport.displayName("gpt-6-luna") == "GPT-6 Luna")
        #expect(SpendReport.displayName("gpt-5.5") == "GPT-5.5")
    }

    @Test func splitsCacheWritesByDuration() throws {
        var context = SpendScanner.FileContext()
        let entry = try #require(ClaudeSpendParser.parse(Data(Self.claudeLine(write5m: 3, write1h: 7).utf8), &context))
        #expect(entry.tokens == TokenCounts(input: 10, output: 100, cacheRead: 1_000, cacheWrite5m: 3, cacheWrite1h: 7))
        #expect(entry.key == "msg_1|req_1")
    }

    @Test func olderLogsCountEveryCacheWriteAsFiveMinute() throws {
        let line = #"{"type":"assistant","timestamp":"2026-09-25T10:00:00Z","message":{"id":"m","model":"claude-sonnet-4","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":40}}}"#
        var context = SpendScanner.FileContext()
        let entry = try #require(ClaudeSpendParser.parse(Data(line.utf8), &context))
        #expect(entry.tokens.cacheWrite5m == 40)
        #expect(entry.tokens.cacheWrite1h == 0)
    }

    @Test func skipsSyntheticAndEmptyReplies() {
        var context = SpendScanner.FileContext()
        let synthetic = Self.claudeLine(model: "<synthetic>")
        let empty = Self.claudeLine(input: 0, output: 0, read: 0)
        #expect(ClaudeSpendParser.parse(Data(synthetic.utf8), &context) == nil)
        #expect(ClaudeSpendParser.parse(Data(empty.utf8), &context) == nil)
    }

    /// Claude Code logs a reply once per content block; only the last line has its full output.
    @Test func countsARepeatedReplyOnceWithItsLastCounts() throws {
        try write([Self.claudeLine(output: 5), Self.claudeLine(output: 336)])
        let report = scanner().scan(now: now)
        #expect(report.today.requests == 1)
        #expect(report.today.tokens.output == 336)
    }

    @Test func aReplyCopiedIntoAResumedSessionCountsOnce() throws {
        try write([Self.claudeLine()], to: "a.jsonl")
        try write([Self.claudeLine()], to: "b.jsonl")
        #expect(scanner().scan(now: now).window.requests == 1)
    }

    @Test func bucketsByDayAndModel() throws {
        try write([
            Self.claudeLine(id: "1", model: "claude-opus-5", at: "2026-09-25T09:00:00Z"),
            Self.claudeLine(id: "2", model: "claude-fable-5-1", at: "2026-09-25T09:30:00Z"),
            Self.claudeLine(id: "3", model: "claude-fable-5-1", at: "2026-09-24T09:00:00Z", output: 10_000),
            // Outside the 30-day window.
            Self.claudeLine(id: "4", at: "2026-08-01T09:00:00Z"),
        ])
        let report = scanner().scan(now: now)
        #expect(report.days.count == 30)
        #expect(report.days.last?.date == calendar.startOfDay(for: now))
        #expect(report.today.requests == 2)
        #expect(report.window.requests == 3)
        #expect(report.days[28].models.keys.sorted() == ["claude-fable-5-1"])
        #expect(report.models.first == "claude-fable-5-1")
    }

    @Test func splitsTodayByHourAndAddsUpEachPeriod() throws {
        try write([
            Self.claudeLine(id: "1", at: "2026-09-25T09:05:00Z"),
            Self.claudeLine(id: "2", at: "2026-09-25T09:55:00Z"),
            Self.claudeLine(id: "3", model: "claude-fable-5-1", at: "2026-09-25T11:30:00Z", output: 1_000),
            Self.claudeLine(id: "4", at: "2026-09-21T10:00:00Z"),
            Self.claudeLine(id: "5", model: "claude-fable-5-1", at: "2026-09-10T10:00:00Z", output: 1_000),
        ])
        let report = scanner().scan(now: now)
        #expect(report.hours.count == 24)
        #expect(report.hours.first?.date == calendar.startOfDay(for: now))
        #expect(report.hours[9].total.requests == 2)
        #expect(report.hours[11].models.keys.sorted() == ["claude-fable-5-1"])
        #expect(report.buckets(.today).count == 24)
        #expect(report.buckets(.week).count == 7)
        #expect(report.buckets(.month).count == 30)
        #expect(report.total(.today).requests == 3)
        #expect(report.total(.week).requests == 4)
        #expect(report.total(.month).requests == 5)
        // Two Opus replies today outnumber the one Fable reply, but Fable's cost more.
        #expect(report.models(.today).first == "claude-fable-5-1")
        #expect(report.models(.week) == ["claude-fable-5-1", "claude-opus-5"])
    }

    @Test func fastModeCostsTwice() throws {
        try write([Self.claudeLine(id: "1"), Self.claudeLine(id: "2", speed: "fast")])
        let models = try #require(scanner().scan(now: now).days.last?.models["claude-opus-5"])
        let standard = ModelPrices.price(for: "claude-opus-5")!.cost(TokenCounts(input: 10, output: 100, cacheRead: 1_000))
        #expect(abs(models.cost - standard * 3) < 1e-12)
    }

    @Test func unknownModelsCountTokensButNotCost() throws {
        try write([Self.claudeLine(model: "claude-future-9")])
        let today = scanner().scan(now: now).today
        #expect(today.tokens.total == 1_110)
        #expect(today.cost == 0)
        #expect(!today.isPriced)
    }

    @Test func readsOnlyWhatWasAppended() throws {
        try write([Self.claudeLine(id: "1")])
        let scanner = scanner()
        #expect(scanner.scan(now: now).today.requests == 1)
        // A line still being written isn't counted until it ends.
        let handle = try FileHandle(forWritingTo: root.appending(path: "session.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(Self.claudeLine(id: "2").prefix(40).utf8))
        try handle.close()
        #expect(scanner.scan(now: now).today.requests == 1)
        try append(String(Self.claudeLine(id: "2").dropFirst(40)))
        #expect(scanner.scan(now: now).today.requests == 2)
    }

    @Test func startsOverWhenALogIsRewritten() throws {
        try write([Self.claudeLine(id: "1"), Self.claudeLine(id: "2")])
        let scanner = scanner()
        #expect(scanner.scan(now: now).today.requests == 2)
        try write([Self.claudeLine(id: "3")])
        #expect(scanner.scan(now: now).today.requests == 1)
    }

    // MARK: Sessions

    @Test func tracksEachSessionsModelCostAndContext() throws {
        let project = root.appending(path: "-Users-me-app", directoryHint: .isDirectory)
        let subagents = project.appending(path: "s1/subagents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try write([Self.claudeLine(id: "1", model: "claude-opus-5", read: 100_000),
                   Self.claudeLine(id: "2", model: "claude-opus-5-5", input: 5, read: 250_000, write1h: 45)], to: "-Users-me-app/s1.jsonl")
        // A subagent's reply costs the session but has its own context.
        try write([Self.claudeLine(id: "3", model: "claude-haiku-4-5", read: 900_000)], to: "-Users-me-app/s1/subagents/agent-a1.jsonl")
        let scanner = SpendScanner(agent: .claude, roots: [root], calendar: calendar, owner: SpendScanner.claudeOwner,
                                   parse: ClaudeSpendParser.parse)
        let session = try #require(scanner.scan(now: now).sessions["s1"])
        #expect(session.model == "claude-opus-5-5")
        #expect(session.spend.requests == 3)
        #expect(session.context == 250_050)
        #expect(session.contextWindow == 1_000_000)
        #expect(abs(session.contextFraction - 0.25005) < 1e-9)
        #expect([SpendReport(agent: .claude, days: [], sessions: ["s1": session])].session("s1") == session)
    }

    @Test func olderModelsHoldASmallerContext() {
        #expect(ModelPrices.contextWindow(for: "claude-haiku-4-5-20251001") == 200_000)
        #expect(ModelPrices.contextWindow(for: "claude-sonnet-4-5[1m]") == 1_000_000)
        #expect(ModelPrices.contextWindow(for: "claude-fable-5-1") == 1_000_000)
    }

    @Test func codexSessionsComeFromTheLogName() throws {
        let usage = #"{"input_tokens":64600,"cached_input_tokens":60000,"output_tokens":14}"#
        let event = #"{"timestamp":"2026-09-25T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(usage),"last_token_usage":\#(usage),"model_context_window":258400}}}"#
        let name = "rollout-2026-09-24T18-46-33-01a0d38f-8690-7c22-bb37-fd55e7e7e972.jsonl"
        try write([Self.codexContext("gpt-6-luna"), event], to: name)
        let scanner = SpendScanner(agent: .codex, roots: [root], calendar: calendar, owner: SpendScanner.codexOwner,
                                   parse: CodexSpendParser.parse)
        let session = try #require(scanner.scan(now: now).sessions["01a0d38f-8690-7c22-bb37-fd55e7e7e972"])
        #expect(session.model == "gpt-6-luna")
        #expect(session.context == 64_600)
        #expect(session.contextWindow == 258_400)
    }

    // MARK: Codex

    static func codexContext(_ model: String) -> String {
        #"{"timestamp":"2026-09-25T10:00:00Z","type":"turn_context","payload":{"model":"\#(model)"}}"#
    }

    static func codexTokens(at timestamp: String = "2026-09-25T10:00:01Z", last: String?, total: String) -> String {
        let last = last.map { #","last_token_usage":\#($0)"# } ?? ""
        return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(total)\#(last)}}}"#
    }

    @Test func codexKeepsCachedInputApartAndUsesTheTurnsModel() throws {
        let usage = #"{"input_tokens":13533,"cached_input_tokens":9984,"cache_write_input_tokens":0,"output_tokens":14}"#
        try write([Self.codexContext("gpt-6-luna"), Self.codexTokens(last: usage, total: usage)])
        let models = try #require(scanner(.codex).scan(now: now).days.last?.models)
        #expect(models["gpt-6-luna"]?.tokens == TokenCounts(input: 3549, output: 14, cacheRead: 9984))
    }

    @Test func codexTakesTheDifferenceOfRunningTotals() throws {
        try write([
            Self.codexContext("gpt-5.5"),
            Self.codexTokens(last: nil, total: #"{"input_tokens":100,"output_tokens":10}"#),
            Self.codexTokens(last: nil, total: #"{"input_tokens":250,"output_tokens":30}"#),
            // Repeated when only the rate limits changed.
            Self.codexTokens(last: nil, total: #"{"input_tokens":250,"output_tokens":30}"#),
        ])
        let today = scanner(.codex).scan(now: now).today
        #expect(today.requests == 2)
        #expect(today.tokens == TokenCounts(input: 250, output: 30))
    }
}
