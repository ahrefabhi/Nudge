import Foundation
import Testing
@testable import PipKit

@Suite struct UsageAlertsTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func usage(_ windows: [(id: String, used: Double)], agent: Agent = .claude, resetsIn: TimeInterval = 3600) -> [AgentUsage] {
        let windows = windows.map { UsageWindow(id: $0.id, minutes: 300, usedPercent: $0.used, resetsAt: now.addingTimeInterval(resetsIn)) }
        return [AgentUsage(agent: agent, source: .connected, report: UsageReport(agent: agent, windows: windows, observedAt: now))]
    }

    func rules(_ scope: UsageAlertRule.Scope = .both, _ thresholds: Int...) -> [UsageAlertRule] {
        thresholds.map { UsageAlertRule(scope: scope, threshold: $0) }
    }

    @Test func alertsForEachWindowPastTheThreshold() {
        var alerts = UsageAlerts()
        let shown = alerts.update(usage([("five_hour", 92), ("seven_day", 40)]), rules: rules(.both, 90), now: now)
        #expect(shown.map(\.id) == ["usage:claude:five_hour"])
        #expect(shown[0].kind == .usage)
        #expect(shown[0].project == "5-hour limit")
        #expect(shown[0].task == "92% used")
        #expect(shown[0].hostName == "Claude Code")
    }

    @Test func noRulesMeansNoAlerts() {
        var alerts = UsageAlerts()
        #expect(alerts.update(usage([("five_hour", 100)]), rules: [], now: now).isEmpty)
    }

    @Test func aRuleOnlyCoversItsAgent() {
        var alerts = UsageAlerts()
        let both = usage([("five_hour", 95)]) + usage([("primary", 95)], agent: .codex)
        #expect(alerts.update(both, rules: rules(.codex, 90), now: now).map(\.agent) == [.codex])
        #expect(alerts.update(both, rules: rules(.claude, 90), now: now).map(\.agent) == [.claude])
    }

    @Test func keepsItsStartWhileTheNumberClimbs() {
        var alerts = UsageAlerts()
        let first = alerts.update(usage([("five_hour", 91)]), rules: rules(.both, 90), now: now)
        let later = alerts.update(usage([("five_hour", 97)]), rules: rules(.both, 90), now: now.addingTimeInterval(600))
        #expect(later[0].task == "97% used")
        #expect(later[0].attentionKey == first[0].attentionKey, "a climbing number is the same episode, not a new alert")
    }

    @Test func eachHigherThresholdAlertsAgain() {
        var alerts = UsageAlerts()
        let both = rules(.claude, 75, 90)
        let first = alerts.update(usage([("five_hour", 80)]), rules: both, now: now)
        #expect(first[0].quote?.contains("alert at 75%") == true)
        alerts.handle(first[0].id)
        #expect(alerts.update(usage([("five_hour", 85)]), rules: both, now: now).isEmpty)
        let reading = UsageReport(agent: .claude, windows: [UsageWindow(id: "five_hour", minutes: 300, usedPercent: 91, resetsAt: now.addingTimeInterval(3600))],
                                  observedAt: now.addingTimeInterval(900))
        let second = alerts.update([AgentUsage(agent: .claude, source: .connected, report: reading)], rules: both, now: now)
        #expect(second.count == 1)
        #expect(second[0].attentionKey != first[0].attentionKey, "crossing 90% is a new episode")
        alerts.handle(second[0].id)
        #expect(alerts.update(usage([("five_hour", 99)]), rules: both, now: now).isEmpty)
    }

    @Test func openedAlertStaysQuietUntilTheWindowDropsBack() {
        var alerts = UsageAlerts()
        _ = alerts.update(usage([("five_hour", 92)]), rules: rules(.both, 90), now: now)
        alerts.handle("usage:claude:five_hour")
        #expect(alerts.update(usage([("five_hour", 95)]), rules: rules(.both, 90), now: now).isEmpty)
        #expect(alerts.update([], rules: rules(.both, 90), now: now).isEmpty)
        #expect(alerts.handled["usage:claude:five_hour"] == 90, "a missing reading isn't a reset")
        _ = alerts.update(usage([("five_hour", 3)]), rules: rules(.both, 90), now: now)
        #expect(alerts.handled.isEmpty)
        #expect(alerts.update(usage([("five_hour", 91)]), rules: rules(.both, 90), now: now).count == 1, "the next window alerts again")
    }

    @Test func aWindowThatHasResetDoesNotAlert() {
        var alerts = UsageAlerts(handled: ["usage:codex:primary": 90])
        #expect(alerts.update(usage([("primary", 99)], agent: .codex, resetsIn: -60), rules: rules(.both, 90), now: now).isEmpty)
        #expect(alerts.handled.isEmpty, "a reset ends the episode")
    }

    @Test func rulesSortByAgentThenThreshold() {
        let sorted = UsageAlertRule.sorted(rules(.both, 90) + rules(.codex, 50) + rules(.claude, 95, 75))
        #expect(sorted.map { "\($0.scope.rawValue) \($0.threshold)" } == ["claude 75", "claude 95", "codex 50", "both 90"])
    }
}
