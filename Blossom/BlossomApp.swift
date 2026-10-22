import SwiftUI
import HealthKit

@main
struct BlossomApp: App {
    @StateObject private var healthKitManager = HealthKitManager()
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .onAppear {
                    healthKitManager.requestAuthorization()
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        healthKitManager.requestAuthorization()
                    }
                }
        }
    }
}

// MARK: - AppDelegate for HealthKit watch permission forwarding
#if os(iOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        let healthStore = HKHealthStore()
        healthStore.handleAuthorizationForExtension { success, error in
            if success {
                print("HealthKit authorization forwarded from watch")
            }
        }
    }
}
#endif
