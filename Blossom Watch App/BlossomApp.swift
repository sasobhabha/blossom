import SwiftUI

@main
struct Blossom_WatchApp: App {
    // Create the view model here
    @StateObject private var viewModel = WatchBlossomViewModel()
    
    var body: some Scene {
        WindowGroup {
            // Inject it into the environment
            WatchContentView()
                .environmentObject(viewModel)
        }
    }
}
