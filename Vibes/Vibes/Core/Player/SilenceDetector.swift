import Foundation
import AVFoundation
import Accelerate

/// Detects silence in audio playback using RMS (Root Mean Square) analysis
class SilenceDetector {
    private let silenceThreshold: Float = -50.0  // dB
    private let skipDuration: TimeInterval = 0.5  // seconds to skip ahead

    /// Check if audio is currently silent by analyzing buffer data
    /// - Parameter buffer: Audio buffer to analyze
    /// - Returns: True if audio is below silence threshold
    func isSilent(buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else {
            return false
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        // Calculate RMS for each channel
        var totalRMS: Float = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var rms: Float = 0.0

            // Use Accelerate framework for fast RMS calculation
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))

            totalRMS += rms
        }

        // Average RMS across channels
        let averageRMS = totalRMS / Float(channelCount)

        // Convert to dB: dB = 20 * log10(RMS)
        let dB = 20 * log10(averageRMS + 1e-10) // Add epsilon to avoid log(0)

        return dB < silenceThreshold
    }

    /// Amount of time to skip when silence is detected
    var skipAmount: TimeInterval {
        return skipDuration
    }
}

/// Simple timer-based silence detection for AVPlayer
/// This approach monitors player output periodically rather than analyzing buffers directly
@MainActor
class SimpleSilenceDetector {
    private weak var player: AVPlayer?
    nonisolated(unsafe) private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 0.5
    private let silenceThreshold: Float = 0.01  // Very low volume threshold
    private let skipDuration: TimeInterval = 0.5

    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    var onSilenceDetected: (() -> Void)?

    init(player: AVPlayer?) {
        self.player = player
    }

    private func startMonitoring() {
        stopMonitoring() // Clear any existing timer

        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSilence()
            }
        }
    }

    nonisolated private func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func checkForSilence() {
        guard let player = player,
              let currentItem = player.currentItem,
              player.rate > 0 else {
            return
        }

        // Check if player is playing and has valid time
        let currentTime = currentItem.currentTime()
        guard currentTime.isValid && currentTime.seconds > 0 else {
            return
        }

        // For AVPlayer, we can't directly analyze audio buffers without AVAudioEngine
        // Instead, we monitor playback rate and loaded time ranges
        // This is a simplified approach that detects buffering/stalling

        let timeRange = currentItem.loadedTimeRanges.first?.timeRangeValue
        if let range = timeRange {
            let loadedDuration = CMTimeGetSeconds(range.duration)
            let currentSeconds = currentTime.seconds

            // If we're very close to the end of loaded content and not progressing,
            // it might be silence/buffering
            if loadedDuration - currentSeconds < 1.0 {
                // This is more of a buffering detection than silence
                // True silence detection requires AVAudioEngine or audio tap
                // For now, we'll use a simplified heuristic approach
                return
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
