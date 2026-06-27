import Foundation
import CoreHaptics
import OSLog
import SoccerShared

/// Core Haptics で蹴り/得点の振動を鳴らす薄いラッパ。
@MainActor
final class HapticsPlayer {
    private let log = Logger(subsystem: "com.yabetatuki.soccerstriker.kick", category: "Haptics")
    private var engine: CHHapticEngine?

    func start() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.resetHandler = { [weak self] in try? self?.engine?.start() }
            e.stoppedHandler = { _ in }
            try e.start()
            engine = e
        } catch {
            log.error("haptics init failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func restart() {
        if engine == nil { start() } else { try? engine?.start() }
    }

    func stop() {
        engine?.stop()
        engine = nil
    }

    /// 蹴った瞬間の軽いパルス。強さは power に比例。
    func playKick(power: Float) {
        playTransient(intensity: max(0.3, power), sharpness: 0.6)
    }

    /// Mac からの GoalEvent に応じた演出。
    func play(goal: GoalEvent) {
        switch goal.outcome {
        case .goal:
            playTransient(intensity: 1.0, sharpness: 0.5)
        case .conceded:
            playTransient(intensity: 0.7, sharpness: 0.2)
        case .save, .miss, .touch:
            playTransient(intensity: goal.intensity, sharpness: 0.7)
        }
    }

    private func playTransient(intensity: Float, sharpness: Float) {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            log.error("haptics play failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
