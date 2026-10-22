//
//  WatchBlossomViewModel.swift
//  Blossom
//
//  Created by Shashwath Manjunath on 1/19/26.
//


import Foundation
import SwiftUI
import Combine
import HealthKit
import UserNotifications
import WidgetKit

class WatchBlossomViewModel: ObservableObject {
    private static let appGroupID = "group.com.educhange.Blossom"
    
    private let healthKitManager = HealthKitManager()
    private var cancellables = Set<AnyCancellable>()
    private var heartRateTimer: Timer?
    private var snapshotTimer: Timer?
    private var currentMetrics = HealthMetrics()
    private var lastPublishedLevel: String?
    private var highStressRun = 0
    private var lastAlertDate: Date?
    
    @Published var heartRate: Double = 75.0
    @Published var stressLevel: String = "Calm"
    @Published var stressScore: Double = 0.0
    @Published var lotusColor: Color = .blue
    @Published var lotusScale: Double = 1.0
    @Published var isRealData: Bool = false
    @Published var lastUpdated: Date = Date()
    
    init() {
        setupBindings()
        requestHealthKitAuthorization()
        requestNotificationAuthorization()
    }
    
    private func setupBindings() {
        healthKitManager.$metrics
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics in
                self?.update(with: metrics)
            }
            .store(in: &cancellables)
        
        healthKitManager.$isAuthorized
            .receive(on: RunLoop.main)
            .sink { [weak self] isAuthorized in
                self?.isRealData = isAuthorized
            }
            .store(in: &cancellables)
        
        healthKitManager.$lastUpdateTime
            .receive(on: RunLoop.main)
            .sink { [weak self] updateTime in
                self?.lastUpdated = updateTime
            }
            .store(in: &cancellables)
    }
    
    private func requestHealthKitAuthorization() {
        healthKitManager.requestAuthorization()
    }
    
    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startMonitoring() {
        healthKitManager.startMonitoring()
        
        // Live heart rate every 3 seconds
        heartRateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.healthKitManager.fetchLatestHeartRate()
        }
        
        // Full sweep of the other metrics every 30 seconds
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.healthKitManager.fetchAllMetrics()
        }
    }
    
    func stopMonitoring() {
        heartRateTimer?.invalidate()
        heartRateTimer = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        healthKitManager.stopHeartRateQuery()
    }
    
    // MARK: - Scoring
    
    private func update(with metrics: HealthMetrics) {
        currentMetrics = metrics
        
        if let latestHeartRate = metrics.heartRate {
            heartRate = latestHeartRate
        }
        
        // Keep the heart-rate term live between samples (and before the first
        // sample arrives) by falling back to the last value we displayed.
        var effective = metrics
        if effective.heartRate == nil {
            effective.heartRate = heartRate
        }
        
        // Personal, safe baseline: the user's own average heart rate first,
        // then HealthKit's resting estimate, then their session average.
        let baseline = healthKitManager.stableBaselineHeartRate ?? heartRate
        
        let score = Self.stressScore(for: effective, baseline: baseline)
        stressScore = score
        apply(score: score)
        publishSnapshot()
        reloadWidgetIfLevelChanged()
        considerCalmingAlert(for: score)
    }
    
    /// Combines every metric the watch records into one 0 (calm) - 100 (stressed)
    /// score. Every per-metric mapping below is anchored to measured values from
    /// published psychophysiology (no composite scale like this exists in the
    /// literature, so the weights are a design choice):
    /// - Heart rate vs. the user's own average: a validated psychosocial stressor
    ///   (group TSST) raised heart rate by 9 bpm [PMID 36935021], with TSST-type
    ///   stressors reliably raising HR at large effect sizes [PMID 8255414,
    ///   33534392, 32305745]. So +9 bpm = 50 ("Moderate") and +18 bpm = 100.
    /// - HRV (SDNN): stress lowers HRV/parasympathetic activity [PMID 29910218,
    ///   37290411]; healthy short-term SDNN averages 50 ms (range 32-93) and
    ///   24 h SDNN < 50 ms is classified unhealthy [PMID 29034226]. Anchors:
    ///   60 ms = 0, 40 ms = 50, <= 20 ms = 100.
    /// - Respiratory rate: respiration tracks arousal [PMID 39379154, 40234515];
    ///   clinical normal is 12-20 breaths/min and slow breathing (<10/min)
    ///   raises HRV [PMID 30245619, 38063977]. Anchors: 12/min = 0, 30/min = 100.
    /// - Sleep over 24 h: randomized sleep restriction (7.4 h -> 6.2 h) markedly
    ///   raised perceived stress [PMID 38342031]. Anchors: 7 h = 0, 3 h = 100.
    /// - Blood oxygen is monitored but not scored: there is no validated mapping
    ///   from SpO2 to psychological stress (it reflects oxygenation, not arousal).
    /// - Physical activity dampens the heart-rate term because HR must be
    ///   corrected for exertion to isolate mental stress [PMID 39562517].
    static func stressScore(for metrics: HealthMetrics, baseline: Double) -> Double {
        var weightedTotal = 0.0
        var totalWeight = 0.0
        
        func add(_ score: Double?, weight: Double) {
            guard let score = score else { return }
            weightedTotal += min(100, max(0, score)) * weight
            totalWeight += weight
        }
        
        let energyFactor = min(1.0, max(0, (metrics.activeEnergyBurned ?? 0) / 400))
        let stepFactor = min(1.0, max(0, (metrics.stepCount ?? 0) / 8000))
        let distanceFactor = min(1.0, max(0, (metrics.distanceWalkingRunning ?? 0) / 5000))
        let activity = (energyFactor + stepFactor + distanceFactor) / 3
        let activityDampening = 1.0 - 0.35 * activity
        
        // Heart rate vs. the user's own average: +9 bpm = 50 (Moderate),
        // +18 bpm = 100 (High). At or below baseline reads as calm.
        let heartRateScore = metrics.heartRate.map { value in
            (value - baseline) / 18 * 100
        }
        add(heartRateScore.map { $0 * activityDampening }, weight: 0.40)
        
        // HRV (SDNN, ms): 60 ms = calm, 40 ms = moderate, 20 ms or less = max.
        add(metrics.heartRateVariabilitySDNN.map { (60 - $0) / 40 * 100 }, weight: 0.30)
        
        // Respiratory rate: 12 breaths/min = calm, 30 = max (normal is 12-20).
        add(metrics.respiratoryRate.map { ($0 - 12) / 18 * 100 }, weight: 0.15)
        
        // Sleep in the last 24 h: 7 h+ = calm, 3 h or less = max.
        add(metrics.sleepHours.map { (7 - $0) / 4 * 100 }, weight: 0.15)
        
        guard totalWeight > 0 else { return 0 }
        return weightedTotal / totalWeight
    }
    
    /// Colours follow colour-emotion research: blue and green read as positive,
    /// low-arousal states, yellow and red as high-arousal states, with red
    /// signalling threat [PMID 28612080, 39806242, 25254380]. The green -> yellow
    /// -> red sequence is the universally read severity ramp.
    private func apply(score: Double) {
        switch score {
        case 70...:
            stressLevel = "High Stress"
            lotusColor = .red
            lotusScale = 0.8
        case 50..<70:
            stressLevel = "Moderate Stress"
            lotusColor = .yellow
            lotusScale = 0.9
        case 30..<50:
            stressLevel = "Normal"
            lotusColor = .green
            lotusScale = 1.0
        default:
            stressLevel = "Calm"
            lotusColor = .blue
            lotusScale = 1.1
        }
    }
    
    // MARK: - Widget
    
    private func publishSnapshot() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        defaults.set(stressLevel, forKey: "stress_level")
        defaults.set(stressScore, forKey: "stress_score")
        defaults.set(heartRate, forKey: "heart_rate")
        defaults.set(Self.colorName(for: stressLevel), forKey: "color_name")
        defaults.set(Date().timeIntervalSince1970, forKey: "updated_at")
    }
    
    private func reloadWidgetIfLevelChanged() {
        guard stressLevel != lastPublishedLevel else { return }
        lastPublishedLevel = stressLevel
        publishSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private static func colorName(for level: String) -> String {
        switch level {
        case "High Stress": return "red"
        case "Moderate Stress": return "yellow"
        case "Normal": return "green"
        default: return "blue"
        }
    }
    
    // MARK: - Calming alerts
    
    /// Fires a calm-down notification when stress stays at or above 70 for two
    /// consecutive readings, at most every 30 minutes, and only with real
    /// HealthKit data behind the score.
    private func considerCalmingAlert(for score: Double) {
        guard isRealData else { return }
        
        if score >= 70 {
            highStressRun += 1
        } else {
            highStressRun = 0
            return
        }
        guard highStressRun >= 2 else { return }
        if let lastAlertDate = lastAlertDate,
           Date().timeIntervalSince(lastAlertDate) < 30 * 60 {
            return
        }
        
        highStressRun = 0
        lastAlertDate = Date()
        
        let content = UNMutableNotificationContent()
        content.title = "Time to breathe"
        content.body = "Your readings suggest high stress. Try 2 minutes of slow breathing: 5 to 7 breaths per minute."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "stress.breathe.\(Date().timeIntervalSince1970)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Simulation
    
    func simulateStress() {
        let targetHR: Double = 110.0
        let steps = max(1, Int((targetHR - heartRate) / 3.0))
        
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) { [weak self] in
                guard let self = self else { return }
                let newHR = min(self.heartRate + 3.0, targetHR)
                var simulated = self.currentMetrics
                simulated.heartRate = newHR
                self.update(with: simulated)
            }
        }
    }
    
    func simulateCalm() {
        let targetHR: Double = 65.0
        let steps = max(1, Int((heartRate - targetHR) / 2.0))
        
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) { [weak self] in
                guard let self = self else { return }
                let newHR = max(self.heartRate - 2.0, targetHR)
                var simulated = self.currentMetrics
                simulated.heartRate = newHR
                self.update(with: simulated)
            }
        }
    }
    
    deinit {
        heartRateTimer?.invalidate()
        snapshotTimer?.invalidate()
        healthKitManager.stopHeartRateQuery()
    }
}
