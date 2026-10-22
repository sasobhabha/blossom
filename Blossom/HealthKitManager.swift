//
//  HealthKitManager.swift
//  Blossom
//
//  Created by Shashwath Manjunath on 1/19/26.
//


import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKQuery?
    
    @Published var isAuthorized: Bool = false
    @Published var currentHeartRate: Double = 75.0
    @Published var lastUpdateTime: Date = Date()
    
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
        
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        
        let readTypes: Set<HKObjectType> = [heartRateType]
        
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
    
    func startHeartRateQuery() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        
        // Create observer query for background updates
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, _ in
            self?.fetchLatestHeartRate()
            completionHandler()
        }
        
        healthStore.execute(query)
        heartRateQuery = query
        
        // Initial fetch
        fetchLatestHeartRate()
    }
    
    func fetchLatestHeartRate() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            simulateHeartRate()
            return
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            if let sample = samples?.first as? HKQuantitySample {
                let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                let heartRate = sample.quantity.doubleValue(for: heartRateUnit)
                
                DispatchQueue.main.async {
                    self?.currentHeartRate = heartRate
                    self?.lastUpdateTime = Date()
                }
            } else {
                self?.simulateHeartRate()
            }
        }
        
        healthStore.execute(query)
    }
    
    private func simulateHeartRate() {
        // Fallback simulation when no real data
        let simulatedHR = Double.random(in: 60...120)
        DispatchQueue.main.async {
            self.currentHeartRate = simulatedHR
            self.lastUpdateTime = Date()
        }
    }
    
    func stopHeartRateQuery() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }
}