import CoreHaptics
import UIKit

/// Fired together with sound and motion. What the screen takes away, you have to add back in.
@MainActor enum Haptics {
    private static var engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let e = try? CHHapticEngine()
        e?.isAutoShutdownEnabled = true
        e?.resetHandler = { try? e?.start() }
        try? e?.start()
        return e
    }()
    static var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    static func tap(_ intensity: Float = 0.5, sharpness: Float = 0.6) { pattern([(0, intensity, sharpness)]) }
    static func lift() { tap(0.35, sharpness: 0.35) }
    static func step() { tap(0.18, sharpness: 0.9) }
    static func place() { pattern([(0, 0.62, 0.75), (0.028, 0.24, 0.3)]) }
    static func capture() { pattern([(0, 0.85, 0.55), (0.035, 0.42, 0.25), (0.07, 0.2, 0.2)]) }
    static func wrong() { pattern([(0, 0.5, 0.12), (0.09, 0.32, 0.1)]) }
    /// A roll that follows the wave across the board.
    static func reflex() {
        var beats: [(Double, Float, Float)] = []
        for t in stride(from: 0.0, to: 0.72, by: 0.06) {
            beats.append((t, Float(0.68 - t * 0.62), Float(0.62 + t * 0.35)))
        }
        pattern(beats)
    }

    private static func pattern(_ beats: [(Double, Float, Float)]) {
        guard enabled, let engine else { return }
        let events = beats.map { t, i, s in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: i), .init(parameterID: .hapticSharpness, value: s)
            ], relativeTime: t)
        }
        guard let p = try? CHHapticPattern(events: events, parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: p).start(atTime: CHHapticTimeImmediate)
    }
}
