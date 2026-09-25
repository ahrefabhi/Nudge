import PeekuKit
import SwiftUI

/// An agent's spend over the chosen period from its session logs: what it cost, how many
/// tokens and replies, and a bar per hour (today) or day, split by model. Hovering a bar shows it.
struct SpendSummary: View {
    @Environment(\.palette) private var palette
    let report: SpendReport
    let period: SpendReport.Period
    @State private var hovered: SpendReport.Bucket?
    @AppStorage(SpendFormat.showCostKey) private var showCost = true

    /// The top two models of the month get a color each, the rest share one. Ranked over the
    /// month, not the period, so a model keeps its color when the period changes.
    private var shaded: [String] { Array(report.models.prefix(2)) }
    /// Dollars when anything in the month has a price and costs aren't hidden, tokens otherwise.
    private var priced: Bool { showCost && report.window.isPriced }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            stats
            VStack(alignment: .leading, spacing: 5) {
                Text(caption)
                    .font(.peeku(11))
                    .foregroundStyle(palette.label(hovered == nil ? 0.45 : 0.75))
                    .lineLimit(1)
                SpendChart(buckets: report.buckets(period), shaded: shaded, priced: priced, hovered: $hovered)
                    .frame(height: 64)
                    .accessibilityLabel(period == .today ? "Spend per hour today" : "Spend per day for the last \(period.title)")
                legend
            }
        }
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
        .onChange(of: period) { hovered = nil }
    }

    private var stats: some View {
        let total = report.total(period)
        return HStack(alignment: .top, spacing: 0) {
            if priced { stat("Cost", SpendFormat.dollars(total.cost)) }
            stat("Tokens", SpendFormat.tokens(total.tokens.total))
            stat("Replies", total.requests.formatted())
            stat("Top model", report.models(period).first.map(SpendReport.displayName) ?? "—", figure: false)
        }
    }

    private func stat(_ title: String, _ value: String, figure: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.peeku(10.5))
                .foregroundStyle(palette.label(0.45))
            Text(value)
                .font(figure ? .peekuMono(14) : .peeku(14, .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// What the chart covers, or the hovered bar: "Tue, 23 Sep · $42.10 · 11M tokens", "2 PM · …".
    private var caption: String {
        guard let bucket = hovered else {
            let range = switch period {
            case .today: "Today by hour"
            case .week: "Last 7 days"
            case .month: "Last 30 days"
            }
            if !showCost { return range }
            return priced ? "\(range), at API prices" : "\(range) · Peeku has no prices for these models"
        }
        let total = bucket.total
        var parts = [period == .today ? bucket.date.formatted(.dateTime.hour())
                                      : bucket.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))]
        if total.requests == 0 { return parts[0] + " · no use" }
        if showCost && total.isPriced { parts.append(SpendFormat.dollars(total.cost)) }
        parts.append("\(SpendFormat.tokens(total.tokens.total)) tokens")
        return parts.joined(separator: " · ")
    }

    private var legend: some View {
        let hasOther = report.models.count > shaded.count
        return HStack(spacing: 12) {
            ForEach(Array(shaded.enumerated()), id: \.element) { index, model in
                key(SpendReport.displayName(model), SpendColors.series(index, palette))
            }
            if hasOther { key("Other", SpendColors.other(palette)) }
        }
        .font(.peeku(10.5))
        .foregroundStyle(palette.label(0.55))
    }

    private func key(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }
}

/// One bar per hour or day, stacked by model, the most used at the bottom, with a 2pt gap between parts.
private struct SpendChart: View {
    @Environment(\.palette) private var palette
    let buckets: [SpendReport.Bucket]
    let shaded: [String]
    let priced: Bool
    @Binding var hovered: SpendReport.Bucket?

    /// A week's seven bars would otherwise be slabs.
    static let widestBar: CGFloat = 22

    var body: some View {
        let value: (Spend) -> Double = { priced ? $0.cost : Double($0.tokens.total) }
        let tallest = buckets.map { value($0.total) }.max() ?? 0
        GeometryReader { proxy in
            let count = CGFloat(max(1, buckets.count))
            let width = min(Self.widestBar, max(1, (proxy.size.width - 2 * (count - 1)) / count))
            // Capped bars spread out to fill the width.
            let gap = count > 1 ? (proxy.size.width - width * count) / (count - 1) : 0
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(buckets) { bucket in
                    bar(bucket, value: value, scale: tallest > 0 ? proxy.size.height / tallest : 0)
                        .frame(width: width, height: proxy.size.height, alignment: .bottom)
                        .opacity(hovered == nil || hovered == bucket ? 1 : 0.45)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { hovered = bucket } else if hovered == bucket { hovered = nil }
                        }
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
        .accessibilityElement()
    }

    private func bar(_ bucket: SpendReport.Bucket, value: (Spend) -> Double, scale: CGFloat) -> some View {
        let parts = segments(bucket).map { (color: $0.color, height: CGFloat(value($0.spend)) * scale) }.filter { $0.height > 0 }
        return VStack(spacing: 2) {
            ForEach(Array(parts.enumerated().reversed()), id: \.offset) { _, part in
                // At least 2pt, so a light day still shows next to the busiest.
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(part.color)
                    .frame(height: max(2, part.height - 2))
            }
        }
    }

    /// Bottom to top: the top model, the second, then everything else.
    private func segments(_ bucket: SpendReport.Bucket) -> [(color: Color, spend: Spend)] {
        var result = shaded.enumerated().compactMap { index, model in
            bucket.models[model].map { (SpendColors.series(index, palette), $0) }
        }
        let other = bucket.models.filter { !shaded.contains($0.key) }.values.reduce(Spend(), +)
        if other.requests > 0 { result.append((SpendColors.other(palette), other)) }
        return result
    }
}

/// Blue and orange for the top two models, gray for the rest, stepped for each panel.
/// Checked for color blindness separation against black and white.
enum SpendColors {
    static func series(_ index: Int, _ palette: Palette) -> Color {
        switch (index, palette.isLight) {
        case (0, true): Color(hex: 0x2a78d6)
        case (0, false): Color(hex: 0x3987e5)
        case (_, true): Color(hex: 0xeb6834)
        case (_, false): Color(hex: 0xd95926)
        }
    }

    static func other(_ palette: Palette) -> Color { Color(hex: palette.isLight ? 0x8e8e93 : 0x6e6e73) }
}

enum SpendFormat {
    /// Settings' "Show costs": off hides every dollar figure, leaving tokens.
    static let showCostKey = "showSpendCost"

    /// "$42.73", or "$1,941" once cents stop mattering.
    static func dollars(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(amount >= 1000 ? 0 : 2)))
    }

    /// "940", "11.4K", "285M", "2.85B".
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        let (scaled, suffix): (Double, String) = switch value {
        case 1e9...: (value / 1e9, "B")
        case 1e6...: (value / 1e6, "M")
        case 1e3...: (value / 1e3, "K")
        default: (value, "")
        }
        guard !suffix.isEmpty else { return "\(count)" }
        let digits = scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2
        return scaled.formatted(.number.precision(.fractionLength(0...digits))) + suffix
    }
}

/// A session's branch, model, what it has cost and how full its context is, as one quiet line.
/// Only what's known shows; with nothing known it's empty.
struct SessionDetails: View {
    @Environment(\.palette) private var palette
    let session: PeekuSession
    let spend: SessionSpend?
    @AppStorage(SpendFormat.showCostKey) private var showCost = true

    static func isEmpty(_ session: PeekuSession, _ spend: SessionSpend?) -> Bool {
        session.branch == nil && spend == nil
    }

    var body: some View {
        HStack(spacing: 6) {
            if let branch = session.branch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 8.5, weight: .semibold))
                    Text(Self.shortened(branch)).truncationMode(.middle)
                }
                // The rest keeps its size, so only a branch too long for the row gets shorter.
                .layoutPriority(-1)
                .accessibilityLabel("Branch \(branch)")
            }
            if let spend {
                if session.branch != nil { dot }
                Text(SpendReport.displayName(spend.model)).fixedSize()
                if showCost && spend.spend.isPriced {
                    dot
                    Text(SpendFormat.dollars(spend.spend.cost)).fixedSize()
                        .accessibilityLabel("\(SpendFormat.dollars(spend.spend.cost)) so far at API prices")
                }
                if spend.context > 0 {
                    dot
                    ContextMeter(fraction: spend.contextFraction)
                }
            }
        }
        .font(.peeku(11))
        .foregroundStyle(palette.label(0.4))
        .lineLimit(1)
    }

    private var dot: some View { Text("·").foregroundStyle(palette.label(0.25)).fixedSize() }

    /// "feature/very-long-branch-name-here" as "feature/very-lo…-name-here": both ends say the most.
    static func shortened(_ branch: String, limit: Int = 28) -> String {
        guard branch.count > limit else { return branch }
        let head = (limit - 1) / 2 + (limit - 1) % 2
        return branch.prefix(head) + "…" + branch.suffix(limit - 1 - head)
    }
}

/// How much of the model's context the conversation fills: quiet until 70%, amber, then red
/// from 90%, when Claude Code is about to compact it.
private struct ContextMeter: View {
    @Environment(\.palette) private var palette
    let fraction: Double

    private var color: Color {
        switch fraction {
        case 0.9...: palette.accent(.error)
        case 0.7...: palette.accent(.permission)
        default: palette.label(0.45)
        }
    }

    var body: some View {
        let percent = Int((fraction * 100).rounded())
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(palette.fill(0.12))
                Capsule().fill(color).frame(width: max(2, 24 * fraction))
            }
            .frame(width: 24, height: 4)
            Text("\(percent)% context")
                .foregroundStyle(fraction >= 0.7 ? color : palette.label(0.4))
        }
        .fixedSize()
        .accessibilityElement()
        .accessibilityLabel("\(percent)% of context used")
    }
}
