import SwiftUI

// MARK: - Sleep Timer Button (for Player)

struct SleepTimerButton: View {
    @StateObject private var sleepTimer = SleepTimerManager.shared
    @State private var showTimerSheet = false

    var body: some View {
        Button(action: { showTimerSheet = true }) {
            VStack(spacing: 4) {
                Image(systemName: sleepTimer.isActive ? "moon.fill" : "moon")
                    .font(.title2)

                if sleepTimer.isActive {
                    Text(sleepTimer.shortRemainingTime)
                        .font(.caption2)
                }
            }
        }
        .sheet(isPresented: $showTimerSheet) {
            SleepTimerView()
        }
    }
}

// MARK: - Sleep Timer View

struct SleepTimerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var sleepTimer = SleepTimerManager.shared

    var body: some View {
        NavigationStack {
            List {
                if sleepTimer.isActive {
                    Section {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.purple)

                            VStack(alignment: .leading) {
                                Text("Temporizador activo")
                                    .font(.headline)

                                Text(sleepTimer.formattedRemainingTime)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Cancelar") {
                                sleepTimer.stopTimer()
                            }
                            .foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("Temporizador")) {
                    ForEach(SleepTimerDuration.allCases) { duration in
                        Button(action: {
                            sleepTimer.startTimer(duration: duration)
                            if duration != .off {
                                dismiss()
                            }
                        }) {
                            HStack {
                                Text(duration.displayName)
                                    .foregroundColor(.primary)

                                Spacer()

                                if sleepTimer.selectedDuration == duration {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Temporizador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Extension for short time display

extension SleepTimerManager {
    var shortRemainingTime: String {
        if selectedDuration == .endOfTrack {
            return "EoT"
        }

        let minutes = Int(remainingTime) / 60
        return "\(minutes)m"
    }
}
