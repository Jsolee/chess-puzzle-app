import AVFAudio
import Foundation

/// Every sound is struck live: a small bank of damped resonators, so enamel on enamel sounds like it.
/// ponytail: events pass through plain word-sized counters without a lock (atomic on arm64); use Synchronization.Atomic if two must change together.
final class ModalSynth: @unchecked Sendable {
    struct Mode { var f: Double; var decay: Double; var gain: Double }
    private struct Voice { var ph = 0.0, inc = 0.0, amp = 0.0, k = 0.0; var wait = 0 }
    private var voices = [Voice](repeating: Voice(), count: 48)
    private var queue = [[(Mode, Double)]](repeating: [], count: 32)
    private var writeIndex = 0, readIndex = 0
    let rate: Double
    init(rate: Double) { self.rate = rate }

    /// Called from the main thread.
    func strike(_ modes: [(Mode, Double)]) { queue[writeIndex & 31] = modes; writeIndex &+= 1 }

    func render(_ n: Int, _ out: UnsafeMutablePointer<Float>) {
        while readIndex != writeIndex {
            for (m, delay) in queue[readIndex & 31] {
                guard let free = voices.firstIndex(where: { $0.amp < 0.0004 && $0.wait == 0 }) else { break }
                voices[free] = Voice(ph: 0, inc: 2 * .pi * m.f / rate, amp: m.gain, k: exp(-1 / (m.decay * rate)), wait: Int(delay * rate))
            }
            readIndex &+= 1
        }
        for i in 0..<n {
            var s = 0.0
            for v in voices.indices where voices[v].amp >= 0.0004 {
                if voices[v].wait > 0 { voices[v].wait -= 1; continue }
                voices[v].ph += voices[v].inc
                s += sin(voices[v].ph) * voices[v].amp
                voices[v].amp *= voices[v].k
            }
            out[i] = Float(tanh(s * 0.9) * 0.8)
        }
    }
}

@MainActor enum Sound {
    private static let engine = AVAudioEngine()
    private static var synth: ModalSynth?
    static var enabled: Bool { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }

    static func start() {
        guard synth == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let rate = 44100.0
        let s = ModalSynth(rate: rate)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let node = AVAudioSourceNode(format: fmt) { _, _, frames, abl in
            let buf = UnsafeMutableAudioBufferListPointer(abl)
            s.render(Int(frames), buf[0].mData!.assumingMemoryBound(to: Float.self))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.8
        try? engine.start()
        synth = s
    }

    private static func strike(_ m: [(Double, Double, Double, Double)]) {
        guard enabled else { return }
        start()
        // A call, an alarm or a headphone change stops the engine, and nothing else restarts it.
        if !engine.isRunning { try? AVAudioSession.sharedInstance().setActive(true); try? engine.start() }
        guard engine.isRunning else { return }
        synth?.strike(m.map { (ModalSynth.Mode(f: $0.0, decay: $0.1, gain: $0.2), $0.3) })
    }

    private static func jitter() -> Double { Double.random(in: 0.97...1.03) }

    static func place() {
        let j = jitter()
        strike([(1860 * j, 0.016, 0.34, 0), (3120 * j, 0.012, 0.22, 0), (5240 * j, 0.008, 0.12, 0), (760 * j, 0.02, 0.12, 0)])
    }
    static func capture() {
        let j = jitter()
        strike([(1320 * j, 0.024, 0.36, 0), (2480 * j, 0.016, 0.24, 0), (4360 * j, 0.01, 0.12, 0), (540 * j, 0.03, 0.2, 0),
                (1720 * j, 0.018, 0.24, 0.03), (3060 * j, 0.012, 0.14, 0.03)])
    }
    static func check() {
        strike([(1568, 0.22, 0.14, 0), (3136, 0.14, 0.07, 0), (4704, 0.08, 0.035, 0), (1860, 0.016, 0.24, 0)])
    }
    static func wrong() { strike([(392, 0.05, 0.26, 0), (311, 0.07, 0.2, 0.05)]) }
    /// The solve: bells climbing with the wave. Each solve in a streak starts a step higher.
    static func reflex(step: Int = 0) {
        let scale = [0, 2, 4, 7, 9, 12, 14, 16]
        let base = 587.33 * pow(2, Double(min(step, 7) * 2) / 12)
        var m: [(Double, Double, Double, Double)] = []
        for (i, n) in scale.prefix(6).enumerated() {
            let f = base * pow(2, Double(n) / 12), t = Double(i) * 0.085
            m += [(f, 0.42, 0.1, t), (f * 2.76, 0.16, 0.035, t), (f * 5.4, 0.07, 0.015, t)]
        }
        strike(m)
    }
    static func tick() { strike([(2600, 0.006, 0.1, 0)]) }
}
