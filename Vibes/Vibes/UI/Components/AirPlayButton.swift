import SwiftUI
import AVKit

// MARK: - AirPlay Button

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = .white
        routePickerView.prioritizesVideoDevices = false

        // Make it more tappable
        routePickerView.activeTintColor = .systemBlue

        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // Update if needed
    }
}

// MARK: - Audio Output Info

struct AudioOutputInfo: View {
    @State private var currentOutput: String = "iPhone"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: outputIcon)
                .font(.caption)

            Text(currentOutput)
                .font(.caption)
        }
        .foregroundColor(.secondary)
        .onAppear {
            updateCurrentOutput()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            updateCurrentOutput()
        }
    }

    private var outputIcon: String {
        let route = AVAudioSession.sharedInstance().currentRoute

        for output in route.outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return "airpodspro"
            case .airPlay:
                return "airplayvideo"
            case .headphones:
                return "headphones"
            case .builtInSpeaker:
                return "iphone"
            case .carAudio:
                return "car"
            default:
                return "speaker.wave.2"
            }
        }

        return "speaker.wave.2"
    }

    private func updateCurrentOutput() {
        let route = AVAudioSession.sharedInstance().currentRoute

        if let output = route.outputs.first {
            currentOutput = output.portName
        }
    }
}
