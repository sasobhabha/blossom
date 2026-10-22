import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @State private var showInstructions = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // App Icon/Logo
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .padding(.top, 40)
                
                // App Title
                Text("Blossom")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                
                Text("Breathing & Stress Relief")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
                
                // Status Card
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Image(systemName: healthKitManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(healthKitManager.isAuthorized ? .green : .orange)
                        Text("HealthKit Status")
                            .font(.headline)
                    }
                    
                    if healthKitManager.isAuthorized {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("✓ Ready for Apple Watch")
                                .foregroundColor(.green)
                            Text("Heart rate monitoring enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Permission Required")
                                .foregroundColor(.orange)
                            Text("Enable HealthKit for watch app to work")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Text("How to use:")
                        .font(.headline)
                    
                    InstructionRow(number: 1, text: "Open Blossom on Apple Watch")
                    InstructionRow(number: 2, text: "Wear watch snugly for accuracy")
                    InstructionRow(number: 3, text: "Follow lotus breathing animation")
                    InstructionRow(number: 4, text: "Watch changes color with stress level")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Authorization Button
                if !healthKitManager.isAuthorized {
                    Button(action: {
                        healthKitManager.requestAuthorization()
                    }) {
                        HStack {
                            Image(systemName: "heart.text.square.fill")
                            Text("Enable Health Access")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Footer
                VStack(spacing: 5) {
                    Text("Apple Watch app is ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if healthKitManager.isAuthorized {
                        Text("Open Blossom on your Apple Watch")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showInstructions.toggle() }) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showInstructions) {
                InstructionsView()
            }
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.green)
                .cornerRadius(11)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

struct InstructionsView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("About Blossom")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Blossom helps you manage stress through guided breathing exercises synchronized with your heart rate.")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How it works:")
                            .font(.headline)
                        
                        Text("• Monitors heart rate via Apple Watch")
                        Text("• Lotus flower changes color (red=stressed, blue=calm)")
                        Text("• Guides breathing with lotus bloom animation")
                        Text("• No data stored - privacy focused")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationBarTitle("Instructions", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {})
        }
    }
}
