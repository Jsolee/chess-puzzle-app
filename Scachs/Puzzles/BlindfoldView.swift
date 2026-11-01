import SwiftUI
import AVFoundation
import MediaPlayer

/// Words for a position and a move, in the language of the app. Small positions only: nobody holds thirty pieces in their head.
enum Blindfold {
    static let maxPieces = 8

    private static func name(_ kind: PieceKind) -> String {
        switch kind {
        case .king: String(localized: "rei")
        case .queen: String(localized: "dama")
        case .rook: String(localized: "torre")
        case .bishop: String(localized: "alfil")
        case .knight: String(localized: "cavall")
        case .pawn: String(localized: "peó")
        }
    }

    private static let order: [PieceKind] = [.king, .queen, .rook, .bishop, .knight, .pawn]

    private static func list(_ position: Position, _ side: Side) -> String {
        let pieces = (0..<64).compactMap { s in position.piece(at: s).flatMap { $0.side == side ? (s, $0.kind) : nil } }
        return order.flatMap { kind in
            pieces.filter { $0.1 == kind }.sorted { $0.0 < $1.0 }.map { "\(name(kind)) \(squareName($0.0))" }
        }.joined(separator: ", ")
    }

    private static func squareName(_ s: Int) -> String {
        "\(["a", "b", "c", "d", "e", "f", "g", "h"][s % 8])\(s / 8 + 1)"
    }

    static func describe(_ position: Position) -> String {
        let white = list(position, .white), black = list(position, .black)
        let turn = position.side == .white ? String(localized: "Juguen les blanques.") : String(localized: "Juguen les negres.")
        return String(localized: "Blanques: \(white). Negres: \(black). \(turn)")
    }

    static func say(_ move: Move, on position: Position) -> String {
        let after = position.applying(move)
        let kind = position.piece(at: move.from)?.kind ?? .pawn
        let base = "\(name(kind)) \(squareName(move.to))"
        return after.isCheckmate ? String(localized: "\(base), mat.") : "\(base)."
    }
}

@MainActor @Observable final class BlindfoldSession: NSObject, AVSpeechSynthesizerDelegate {
    enum Phase { case listening, thinking, answered, over }
    static let length = 5

    private(set) var phase: Phase = .listening
    private(set) var index = 0
    private(set) var puzzle: Puzzle?
    private(set) var position: Position?
    let board = BoardModel()
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var used: Set<Int> = []
    @ObservationIgnored private var targets: [Any] = []

    override init() {
        super.init()
        speech.delegate = self
    }

    func begin() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        // A click on the earbuds moves things on, so the phone can stay in a pocket.
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.nextTrackCommand] {
            command.isEnabled = true
            targets.append(command.addTarget { [weak self] _ in
                Task { @MainActor in self?.advance() }
                return .success
            })
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: String(localized: "A cegues"), MPMediaItemPropertyArtist: "Scachs"]
        nextPuzzle()
    }

    func end() {
        speech.stopSpeaking(at: .immediate)
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.nextTrackCommand] { command.removeTarget(nil) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func advance() {
        switch phase {
        case .listening, .thinking: answer()
        case .answered: nextPuzzle()
        case .over: break
        }
    }

    func repeatPosition() {
        guard let position else { return }
        phase = .listening
        speak(Blindfold.describe(position) + " " + mateText)
    }

    private var mateText: String {
        guard let puzzle else { return "" }
        return puzzle.themes.contains("mateIn1") ? String(localized: "Mat en 1.") : String(localized: "Mat en 2.")
    }

    private func nextPuzzle() {
        guard index < Self.length, let p = pick() else { phase = .over; speak(String(localized: "Fins aquí.")); return }
        index += 1
        puzzle = p
        let setup = p.start.move(uci: p.line[0].uci) ?? p.line[0]
        let start = p.start.applying(setup)
        position = start
        board.interactive = false
        board.orientation = p.solverSide
        board.set(start, animated: false)
        phase = .listening
        speak(Blindfold.describe(start) + " " + mateText)
    }

    private func pick() -> Puzzle? {
        let store = PuzzleStore.shared
        let themes: Set<String> = index % 2 == 0 ? ["mateIn1"] : ["mateIn2"]
        let found = store.find(target: Int(Progress.shared.rating) - 300, anyOf: themes) { [used] i in
            used.contains(i) || store.puzzle(at: i).start.pieceCount > Blindfold.maxPieces
        }
        if let found { used.insert(found.index) }
        return found
    }

    private func answer() {
        guard let puzzle, var position else { return }
        phase = .answered
        var words: [String] = []
        for (i, m) in puzzle.line.dropFirst().enumerated() {
            guard let move = position.move(uci: m.uci) else { break }
            if i % 2 == 0 { words.append(Blindfold.say(move, on: position)) }
            board.play(move, quiet: true)
            position = position.applying(move)
        }
        speak(words.joined(separator: " "))
    }

    private func speak(_ text: String) {
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        speech.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.phase == .listening { self.phase = .thinking } }
    }
}

/// Calculating with nothing to look at, for a walk or a train. Mostly pleasure: the evidence that it raises a rating is thin.
struct BlindfoldView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = BlindfoldSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityLabel("Tanca").padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 10) {
                Text("A cegues").font(Theme.display(52)).foregroundStyle(Theme.tin)
                Text(explanation).font(Theme.text(17)).foregroundStyle(Theme.quiet).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
            if session.phase == .answered || session.phase == .over {
                BoardView(session.board).transition(.opacity)
            } else {
                Spacer()
                Text(verbatim: "\(session.index)").font(Theme.display(120)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity)
                    .accessibilityLabel("Posició \(session.index) de \(BlindfoldSession.length)")
                Spacer()
            }
            Spacer(minLength: 16)
            controls.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(Theme.field.ignoresSafeArea())
        .animation(.easeOut(duration: 0.25), value: session.phase)
        .task { session.begin() }
        .onDisappear { session.end() }
    }

    private var explanation: LocalizedStringKey {
        switch session.phase {
        case .listening: "Escolta la posició."
        case .thinking: "Calcula. Quan ho tinguis, prem els auriculars o el botó."
        case .answered: "Aquí la tens, per si la vols veure."
        case .over: "Això és tot per avui."
        }
    }

    @ViewBuilder private var controls: some View {
        switch session.phase {
        case .over:
            wide("Fet") { dismiss() }
        case .answered:
            wide("Següent") { session.advance() }
        case .listening, .thinking:
            VStack(spacing: 8) {
                wide("Solució") { session.advance() }
                Button("Repeteix") { session.repeatPosition() }.font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
            }
        }
    }

    private func wide(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
        }
    }
}
