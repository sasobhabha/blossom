//
//  StressWidget.swift
//  BlossomWidget
//
//  Watch home screen widget (Smart Stack + watch face complication).
//

import WidgetKit
import SwiftUI

struct StressEntry: TimelineEntry {
    let date: Date
    let snapshot: StressSnapshot
}

struct StressProvider: TimelineProvider {
    func placeholder(in context: Context) -> StressEntry {
        StressEntry(date: Date(), snapshot: .placeholder)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (StressEntry) -> Void) {
        completion(StressEntry(date: Date(), snapshot: StressSnapshot.load()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StressEntry>) -> Void) {
        let entry = StressEntry(date: Date(), snapshot: StressSnapshot.load())
        // The app pushes fresh data on every reading (and reloads us when the
        // level changes); this is the fallback refresh.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct StressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StressEntry
    
    private var snapshot: StressSnapshot { entry.snapshot }
    
    private var color: Color {
        switch snapshot.colorName {
        case "red": return .red
        case "yellow": return .yellow
        case "green": return .green
        default: return .blue
        }
    }
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            inlineView
        }
    }
    
    private var circularView: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(snapshot.score / 100, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(snapshot.score.rounded()))")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(color)
                Text("stress")
                    .font(.system(.caption2))
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }
    
    private var rectangularView: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Blossom")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(snapshot.shortLevel)
                    .font(.headline)
                    .foregroundColor(color)
                Text("\(Int(snapshot.heartRate.rounded())) bpm · \(snapshot.updatedAgo)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }
    
    private var inlineView: some View {
        Text("Blossom: \(snapshot.shortLevel) · \(Int(snapshot.heartRate.rounded())) bpm")
            .font(.caption)
    }
}

struct StressWidget: Widget {
    let kind = "BlossomStressWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StressProvider()) { entry in
            StressWidgetView(entry: entry)
        }
        .configurationDisplayName("Blossom Stress")
        .description("Live stress level from your Apple Watch readings.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
