//
//  StressSnapshot.swift
//  BlossomWidget
//
//  Shared App Group snapshot written by the watch app and read by the widget.
//  This mirrors the keys written by WatchBlossomViewModel.publishSnapshot().
//

import Foundation

struct StressSnapshot {
    static let appGroupID = "group.com.educhange.Blossom"
    
    let level: String      // "Calm" | "Normal" | "Moderate Stress" | "High Stress"
    let score: Double      // 0 (calm) - 100 (stressed)
    let heartRate: Double  // bpm
    let colorName: String  // "blue" | "green" | "yellow" | "red"
    let updatedAt: Date
    
    static var placeholder: StressSnapshot {
        StressSnapshot(level: "Calm",
                       score: 12,
                       heartRate: 68,
                       colorName: "blue",
                       updatedAt: Date())
    }
    
    static func load() -> StressSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return placeholder
        }
        
        let timestamp = defaults.double(forKey: "updated_at")
        return StressSnapshot(
            level: defaults.string(forKey: "stress_level") ?? "Calm",
            score: defaults.double(forKey: "stress_score"),
            heartRate: defaults.double(forKey: "heart_rate"),
            colorName: defaults.string(forKey: "color_name") ?? "blue",
            updatedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .distantPast
        )
    }
    
    /// Compact label for tight widget layouts ("Moderate" for "Moderate Stress").
    var shortLevel: String {
        level == "Moderate Stress" ? "Moderate" : level
    }
    
    var updatedAgo: String {
        let interval = Date().timeIntervalSince(updatedAt)
        guard interval.isFinite, updatedAt != .distantPast else { return "no data yet" }
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        return "\(Int(interval / 3600)) h ago"
    }
}
