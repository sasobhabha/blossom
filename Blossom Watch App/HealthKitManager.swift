//
//  HealthKitManager.swift
//  Blossom
//
//  Created by Shashwath Manjunath on 1/19/26.
//

import Foundation
import HealthKit
import Combine

/// Snapshot of every HealthKit metric the watch feeds into the stress calculation.
struct HealthMetrics {
    var heartRate: Double?                 // bpm (latest sample)
    var averageHeartRate: Double?          // bpm (mean over the last 24 h - the stable baseline)
    var restingHeartRate: Double?          // bpm (latest sample)
    var heartRateVariabilitySDNN: Double?  // ms (latest SDNN sample)
    var respiratoryRate: Double?           // breaths/min (latest sample)
    var oxygenSaturation: Double?          // percent, e.g. 97 (latest sample; monitored, not scored)
    var activeEnergyBurned: Double?        // kcal over the last 24 h
    var stepCount: Double?                 // steps over the last 24 h
    var distanceWalkingRunning: Double?    // meters over the last 24 h
    var sleepHours: Double?                // hours asleep over the last 24 h
}

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var heartRateObserverQuery: HKObserverQuery?
    private var anchor: HKQueryAnchor?
    private var sessionHeartRates: [Double] = []
    
    @Published var isAuthorized: Bool = false
    @Published var metrics: HealthMetrics = HealthMetrics()
    @Published var lastUpdateTime: Date = Date()
    
    private static let day: TimeInterval = 24 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60
    
    /// Safe, stable baseline: the user's own recent average heart rate first,
    /// then HealthKit's resting estimate, then their session average.
    var stableBaselineHeartRate: Double? {
        if let average = metrics.averageHeartRate { return average }
        if let resting = metrics.restingHeartRate { return resting }
        guard !sessionHeartRates.isEmpty else { return nil }
        return sessionHeartRates.reduce(0, +) / Double(sessionHeartRates.count)
    }
    
    /// Every type the watch reads. Keep in sync with NSHealthShareUsageDescription.
    private var readTypes: Set<HKObjectType> {
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .oxygenSaturation,
            .activeEnergyBurned,
            .stepCount,
            .distanceWalkingRunning
        ]
        
        var types: Set<HKObjectType> = []
        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        return types
    }
    
    init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            return
        }
        
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        
        let status = healthStore.authorizationStatus(for: heartRateType)
        DispatchQueue.main.async {
            self.isAuthorized = (status == .sharingAuthorized)
        }
    }
    
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            return
        }
        
        // One prompt for the full set of metrics used by the stress score.
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                if success {
                    print("HealthKit authorized")
                } else {
                    print("HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    // MARK: - Monitoring
    
    /// Starts continuous heart-rate tracking, pulls a full snapshot of every
    /// metric, and turns on background delivery so readings stay fresh while
    /// the app is off-screen.
    func startMonitoring() {
        startHeartRateQuery()
        enableBackgroundDelivery()
        fetchAllMetrics()
    }
    
    /// Lets HealthKit wake the app in the background when new heart rate
    /// samples arrive, so the stress score (and calming alerts) keep working
    /// without the app being open.
    func enableBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { _, error in
            if let error = error {
                print("Background delivery error: \(error.localizedDescription)")
            }
        }
        
        let observer = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, _ in
            // Background wakeup: refresh every metric; the view model
            // re-evaluates stress from the published snapshot and may alert.
            self?.fetchAllMetrics()
            completionHandler()
        }
        healthStore.execute(observer)
        heartRateObserverQuery = observer
    }
    
    func startHeartRateQuery() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        
        // Use HKAnchoredObjectQuery to receive continuous heart rate updates
        let anchoredQuery = HKAnchoredObjectQuery(type: heartRateType,
                                                  predicate: nil,
                                                  anchor: anchor,
                                                  limit: HKObjectQueryNoLimit,
                                                  resultsHandler: { [weak self] (_, samplesOrNil, deletedObjectsOrNil, newAnchor, errorOrNil) in
            guard let self = self else { return }
            if let error = errorOrNil {
                print("Anchored query initial results error: \(error.localizedDescription)")
                return
            }

            self.anchor = newAnchor

            if let samples = samplesOrNil as? [HKQuantitySample] {
                self.processHeartRateSamples(samples)
            }
        })

        anchoredQuery.updateHandler = { [weak self] (_, samplesOrNil, deletedObjectsOrNil, newAnchor, errorOrNil) in
            guard let self = self else { return }
            if let error = errorOrNil {
                print("Anchored query update error: \(error.localizedDescription)")
                return
            }

            self.anchor = newAnchor

            if let samples = samplesOrNil as? [HKQuantitySample] {
                self.processHeartRateSamples(samples)
            }
        }
        
        healthStore.execute(anchoredQuery)
        heartRateQuery = anchoredQuery
        
        // Initial fetch as backup
        fetchLatestHeartRate()
    }
    
    private func processHeartRateSamples(_ samples: [HKQuantitySample]) {
        guard let latestSample = samples.sorted(by: { $0.startDate > $1.startDate }).first else {
            return
        }
        
        let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let heartRate = latestSample.quantity.doubleValue(for: heartRateUnit)
        update(\.heartRate, with: heartRate)
    }
    
    /// Refreshes every metric the stress score depends on.
    func fetchAllMetrics() {
        let beatsPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        
        // Heart rate: recent, so the stress reading stays live. The 1 h window
        // keeps the reading alive even if the watch was briefly not worn.
        fetchLatestQuantity(.heartRate, unit: beatsPerMinute, within: 60 * 60) { [weak self] value in
            self?.update(\.heartRate, with: value)
        }
        // The user's own average heart rate over the last 24 h - the stable,
        // personal baseline stress is measured against.
        fetchAverageQuantity(.heartRate, unit: beatsPerMinute, within: Self.day) { [weak self] value in
            self?.update(\.averageHeartRate, with: value)
        }
        // HRV and resting heart rate are sparse (mostly recorded overnight).
        fetchLatestQuantity(.restingHeartRate, unit: beatsPerMinute, within: Self.week) { [weak self] value in
            self?.update(\.restingHeartRate, with: value)
        }
        fetchLatestQuantity(.heartRateVariabilitySDNN, unit: HKUnit.second(), within: Self.week) { [weak self] value in
            // SDNN is stored in seconds; expose milliseconds.
            self?.update(\.heartRateVariabilitySDNN, with: value.map { $0 * 1000 })
        }
        fetchLatestQuantity(.respiratoryRate, unit: beatsPerMinute, within: Self.day) { [weak self] value in
            self?.update(\.respiratoryRate, with: value)
        }
        fetchLatestQuantity(.oxygenSaturation, unit: HKUnit.percent(), within: Self.day) { [weak self] value in
            // HealthKit reports oxygen saturation as a fraction (0.97); normalise to percent.
            self?.update(\.oxygenSaturation, with: value.map { $0 <= 1.0 ? $0 * 100 : $0 })
        }
        
        // Daily activity totals.
        fetchCumulativeQuantity(.activeEnergyBurned, unit: HKUnit.kilocalorie(), within: Self.day) { [weak self] value in
            self?.update(\.activeEnergyBurned, with: value)
        }
        fetchCumulativeQuantity(.stepCount, unit: HKUnit.count(), within: Self.day) { [weak self] value in
            self?.update(\.stepCount, with: value)
        }
        fetchCumulativeQuantity(.distanceWalkingRunning, unit: HKUnit.meter(), within: Self.day) { [weak self] value in
            self?.update(\.distanceWalkingRunning, with: value)
        }
        
        // Sleep from the last 24 hours.
        fetchSleepHours(within: Self.day) { [weak self] value in
            self?.update(\.sleepHours, with: value)
        }
    }
    
    private func update(_ keyPath: WritableKeyPath<HealthMetrics, Double?>, with value: Double?) {
        DispatchQueue.main.async {
            if keyPath == \HealthMetrics.heartRate, let value = value {
                self.sessionHeartRates.append(value)
                if self.sessionHeartRates.count > 2880 {
                    self.sessionHeartRates.removeFirst(self.sessionHeartRates.count - 2880)
                }
            }
            self.metrics[keyPath: keyPath] = value
            self.lastUpdateTime = Date()
        }
    }
    
    private func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier,
                                     unit: HKUnit,
                                     within interval: TimeInterval,
                                     completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-interval),
                                                    end: nil,
                                                    options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type,
                                  predicate: predicate,
                                  limit: 1,
                                  sortDescriptors: [sortDescriptor]) { _, samples, _ in
            let quantity = (samples?.first as? HKQuantitySample)?.quantity
            completion(quantity?.doubleValue(for: unit))
        }
        
        healthStore.execute(query)
    }
    
    private func fetchCumulativeQuantity(_ identifier: HKQuantityTypeIdentifier,
                                         unit: HKUnit,
                                         within interval: TimeInterval,
                                         completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-interval),
                                                    end: nil,
                                                    options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, statistics, _ in
            completion(statistics?.sumQuantity()?.doubleValue(for: unit))
        }
        
        healthStore.execute(query)
    }
    
    private func fetchAverageQuantity(_ identifier: HKQuantityTypeIdentifier,
                                      unit: HKUnit,
                                      within interval: TimeInterval,
                                      completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-interval),
                                                    end: nil,
                                                    options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: predicate,
                                      options: .discreteAverage) { _, statistics, _ in
            completion(statistics?.averageQuantity()?.doubleValue(for: unit))
        }
        
        healthStore.execute(query)
    }
    
    private func fetchSleepHours(within interval: TimeInterval, completion: @escaping (Double?) -> Void) {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-interval),
                                                    end: nil,
                                                    options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sleepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sortDescriptor]) { _, samples, _ in
            guard let sleepSamples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }
            
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]
            
            let asleepSamples = sleepSamples.filter { asleepValues.contains($0.value) }
            // No sleep recorded (watch not worn) is "no data", not "0 hours":
            // reporting 0 here would push the sleep term to maximum stress.
            guard !asleepSamples.isEmpty else {
                completion(nil)
                return
            }
            
            let asleepSeconds = asleepSamples
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            
            completion(asleepSeconds / 3600)
        }
        
        healthStore.execute(query)
    }
    
    func fetchLatestHeartRate() {
        fetchLatestQuantity(.heartRate,
                            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                            within: 60 * 60) { [weak self] value in
            self?.update(\.heartRate, with: value)
        }
    }
    
    func stopHeartRateQuery() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        if let observer = heartRateObserverQuery {
            healthStore.stop(observer)
            heartRateObserverQuery = nil
        }
    }
}
