//
//  ETFWidget.swift
//  ETFWidget
//

import Charts
import SwiftUI
import WidgetKit

// MARK: - Shared data

/// Mirror of `WidgetSnapshot` in the app (Shared/AppGroup.swift).
/// Keep both in sync — the app encodes, the widget decodes.
struct WidgetSnapshot: Codable, Hashable {
    struct Point: Codable, Hashable {
        let year: Int
        let value: Double
    }

    var finalValue: Double
    var totalContributions: Double
    var years: Int
    var monthlyContribution: Double
    var currencyCode: String
    var points: [Point]
    var nextMilestone: Double?
    var nextMilestoneYear: Int?
    var goalTarget: Double?
    var goalProgress: Double?
    var updatedAt: Date

    var gains: Double { finalValue - totalContributions }

    static let placeholder = WidgetSnapshot(
        finalValue: 19_186,
        totalContributions: 13_000,
        years: 10,
        monthlyContribution: 100,
        currencyCode: Locale.current.currency?.identifier ?? "EUR",
        points: (0...10).map { Point(year: $0, value: 1_000 + Double($0) * 1_200 * pow(1.035, Double($0))) },
        nextMilestone: 10_000,
        nextMilestoneYear: Calendar.current.component(.year, from: .now) + 6,
        goalTarget: 100_000,
        goalProgress: 0.32,
        updatedAt: .now
    )
}

private enum SharedStore {
    static let defaults = UserDefaults(suiteName: "group.app.etf-calculator.com") ?? .standard

    static var snapshot: WidgetSnapshot? {
        guard let data = defaults.data(forKey: "widgetSnapshot") else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static var isPremium: Bool { defaults.bool(forKey: "isPremium") }
}

// MARK: - Timeline

struct PlanEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPremium: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PlanEntry {
        PlanEntry(date: .now, snapshot: .placeholder, isPremium: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
        // The widget gallery shows the real design, even without Premium.
        let snapshot = SharedStore.snapshot ?? .placeholder
        completion(PlanEntry(date: .now, snapshot: snapshot, isPremium: context.isPreview || SharedStore.isPremium))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
        let entry = PlanEntry(date: .now, snapshot: SharedStore.snapshot ?? .placeholder, isPremium: SharedStore.isPremium)
        // The app reloads timelines whenever the plan changes; refresh daily otherwise.
        let next = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

private let emerald = LinearGradient(
    colors: [Color(red: 0.04, green: 0.49, blue: 0.35), Color(red: 0.02, green: 0.36, blue: 0.33), Color(red: 0.04, green: 0.30, blue: 0.44)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private extension WidgetSnapshot {
    func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }
}

struct ETFWidgetEntryView: View {
    let entry: PlanEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.isPremium {
            switch family {
            case .accessoryCircular: CircularView(snapshot: entry.snapshot)
            case .accessoryRectangular: RectangularView(snapshot: entry.snapshot)
            case .accessoryInline: InlineView(snapshot: entry.snapshot)
            case .systemMedium: MediumView(snapshot: entry.snapshot)
            default: SmallView(snapshot: entry.snapshot)
            }
        } else {
            LockedView(family: family)
        }
    }
}

private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("^[\(snapshot.years) Year](inflect: true)", systemImage: "calendar")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(snapshot.money(snapshot.finalValue))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("+\(snapshot.money(snapshot.gains))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 4)
            Sparkline(points: snapshot.points)
        }
        .foregroundStyle(.white)
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Final Value", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(snapshot.money(snapshot.finalValue))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(snapshot.money(snapshot.monthlyContribution))/mo · ^[\(snapshot.years) year](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 4)
                if let milestone = snapshot.nextMilestone, let year = snapshot.nextMilestoneYear {
                    Label {
                        Text("\(snapshot.money(milestone)) in \(String(year))")
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            Sparkline(points: snapshot.points)
        }
        .foregroundStyle(.white)
    }
}

private struct Sparkline: View {
    let points: [WidgetSnapshot.Point]

    var body: some View {
        Chart(points, id: \.year) { point in
            AreaMark(x: .value("Year", point.year), y: .value("Value", point.value))
                .foregroundStyle(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Year", point.year), y: .value("Value", point.value))
                .foregroundStyle(.white)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

private struct CircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if let progress = snapshot.goalProgress {
            Gauge(value: min(max(progress, 0), 1)) {
                Image(systemName: "flag.checkered")
            } currentValueLabel: {
                Text(min(max(progress, 0), 1), format: .percent.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3.weight(.semibold))
            }
        }
    }
}

private struct RectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("ETF Plan", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Text(snapshot.money(snapshot.finalValue))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let milestone = snapshot.nextMilestone, let year = snapshot.nextMilestoneYear {
                Text("\(snapshot.money(milestone)) in \(String(year))")
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text("^[\(snapshot.years) Year](inflect: true)")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Label("\(snapshot.money(snapshot.finalValue)) in \(snapshot.years) yrs", systemImage: "chart.line.uptrend.xyaxis")
    }
}

private struct LockedView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock.fill")
            }
        case .accessoryRectangular, .accessoryInline:
            Label("Widgets require Premium", systemImage: "lock.fill")
                .font(.caption)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Spacer()
                Text("Widgets are a Premium feature")
                    .font(.subheadline.weight(.semibold))
                Text("Open the app to unlock.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget

struct ETFWidget: Widget {
    let kind = "ETFWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ETFWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    emerald
                }
        }
        .configurationDisplayName("ETF Plan")
        .description("Your final value, growth curve and next milestone at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    ETFWidget()
} timeline: {
    PlanEntry(date: .now, snapshot: .placeholder, isPremium: true)
}

#Preview(as: .systemMedium) {
    ETFWidget()
} timeline: {
    PlanEntry(date: .now, snapshot: .placeholder, isPremium: true)
}
