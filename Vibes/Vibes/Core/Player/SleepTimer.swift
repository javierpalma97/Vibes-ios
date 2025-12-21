import Foundation
import Combine

enum SleepTimerDuration: Int, CaseIterable, Identifiable {
    case off = 0
    case minutes5 = 5
    case minutes10 = 10
    case minutes15 = 15
    case minutes30 = 30
    case minutes45 = 45
    case hour1 = 60
    case hour2 = 120
    case endOfTrack = -1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .minutes5: return "5 minutes"
        case .minutes10: return "10 minutes"
        case .minutes15: return "15 minutes"
        case .minutes30: return "30 minutes"
        case .minutes45: return "45 minutes"
        case .hour1: return "1 hour"
        case .hour2: return "2 hours"
        case .endOfTrack: return "End of track"
        }
    }
}

@MainActor
class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published var isActive: Bool = false
    @Published var remainingTime: TimeInterval = 0
    @Published var selectedDuration: SleepTimerDuration = .off

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let playerManager = PlayerManager.shared

    private init() {
        setupEndOfTrackObserver()
    }

    private func setupEndOfTrackObserver() {
        // Observe when song ends to check if we should stop
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.selectedDuration == .endOfTrack && self.isActive {
                    self.stopTimer()
                    self.playerManager.pause()
                }
            }
            .store(in: &cancellables)
    }

    func startTimer(duration: SleepTimerDuration) {
        stopTimer()

        selectedDuration = duration

        guard duration != .off else {
            isActive = false
            return
        }

        if duration == .endOfTrack {
            isActive = true
            remainingTime = 0
            return
        }

        let seconds = TimeInterval(duration.rawValue * 60)
        remainingTime = seconds
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                self.remainingTime -= 1

                if self.remainingTime <= 0 {
                    self.stopTimer()
                    self.playerManager.pause()
                }
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingTime = 0
        selectedDuration = .off
    }

    func addTime(_ minutes: Int) {
        guard isActive && selectedDuration != .endOfTrack else { return }
        remainingTime += TimeInterval(minutes * 60)
    }

    var formattedRemainingTime: String {
        if selectedDuration == .endOfTrack {
            return "End of track"
        }

        let hours = Int(remainingTime) / 3600
        let minutes = (Int(remainingTime) % 3600) / 60
        let seconds = Int(remainingTime) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
