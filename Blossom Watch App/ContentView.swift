import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var viewModel: WatchBlossomViewModel
    @State private var isAnimating = false
    @State private var showControls = false
    
    var body: some View {
        ZStack {
            // Outer petals
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .stroke(viewModel.lotusColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .offset(offsetForPetal(index: index, radius: 50))
                    .scaleEffect(CGFloat(viewModel.lotusScale))
            }
            
            // Middle petals
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .stroke(viewModel.lotusColor.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 50, height: 50)
                    .offset(offsetForPetal(index: index, radius: 35, offset: 15))
                    .scaleEffect(CGFloat(viewModel.lotusScale))
            }
            
            // Inner circle
            Circle()
                .fill(viewModel.lotusColor.opacity(0.7))
                .frame(width: 25, height: 25)
                .scaleEffect(CGFloat(viewModel.lotusScale))
            
            // Center dot
            Circle()
                .fill(Color.yellow.opacity(0.9))
                .frame(width: 10, height: 10)
                .scaleEffect(CGFloat(viewModel.lotusScale))
        }
        .scaleEffect(isAnimating && viewModel.stressLevel == "Calm" ? 1.05 : 1.0)
        .animation(
            isAnimating && viewModel.stressLevel == "Calm" ?
            Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true) :
                .default,
            value: isAnimating
        )
        .onAppear {
            viewModel.startMonitoring()
            if viewModel.stressLevel == "Calm" {
                isAnimating = true
            }
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .onChange(of: viewModel.stressLevel) { newValue in
            isAnimating = newValue == "Calm"
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
    
    private var stressLevelColor: Color {
        switch viewModel.stressLevel {
        case "High Stress": return .red
        case "Moderate Stress": return .yellow
        case "Normal": return .green
        default: return .blue
        }
    }
    
    private var timeSinceUpdate: String {
        let interval = Date().timeIntervalSince(viewModel.lastUpdated)
        if interval < 10 {
            return "Now"
        } else if interval < 60 {
            return "\(Int(interval))s"
        } else {
            return "\(Int(interval/60))m"
        }
    }
    
    private func offsetForPetal(index: Int, radius: CGFloat, offset: CGFloat = 0) -> CGSize {
        let angle = CGFloat(index) * (2 * .pi / CGFloat(index < 8 ? 8 : 6))
        return CGSize(
            width: cos(angle) * (radius + offset),
            height: sin(angle) * (radius + offset)
        )
    }
}
