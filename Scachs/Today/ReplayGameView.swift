import SwiftUI

/// Picks a reply the way a person of a rating might: usually a good move, more often a worse one the weaker they are.
/// Weighted over Stockfish's top lines, so it's an approximation of human play and not a model of it.
enum HumanishMove {
    static let lines = 4
    static let nodes = 30_000

    /// Softness of the choice in expected points: wide at club level, narrow near master.
    static func softness(rating: Int) -> Double {
        let t = min(max((Double(rating) - 800) / 1600, 0), 1)
        return 0.06 + (0.012 - 0.06) * t
    }

    static func choose(_ candidates: [EngineLine], rating: Int, roll: Double = Double.random(in: 0..<1)) -> Move? {
        let usable = candidates.filter { !$0.pv.isEmpty }
        guard let top = usable.first else { return nil }
        let best = ExpectedPoints.of(top.score, rating: rating)
        let weights = usable.map { exp((ExpectedPoints.of($0.score, rating: rating) - best) / softness(rating: rating)) }
        var left = roll * weights.reduce(0, +)
        for (line, weight) in zip(usable, weights) {
            left -= weight
            if left < 0 { return line.pv[0] }
        }
        return top.pv[0]
    }
}

@MainActor @Observable final class ReplayModel {
    enum Phase { case yourMove, thinking, won, lost, drawn }

    let board = BoardModel()
    let side: Side
    let opponentRating: Int
    let opponent: String
    private(set) var phase: Phase = .yourMove
    @ObservationIgnored private let start: Position
    @ObservationIgnored private var task: Task<Void, Never>?

    init(game: ImportedGame, replay: GameReplay, ply: Int) {
        side = replay.positions[min(ply, replay.positions.count - 1)].side
        start = replay.positions[min(ply, replay.positions.count - 1)]
        opponent = side == .white ? game.black : game.white
        opponentRating = (side == .white ? game.blackRating : game.whiteRating) ?? Int(Progress.shared.rating)
        board.orientation = side
        restart()
        AutoReview.shared.hold()
    }

    func close() {
        task?.cancel()
        AutoReview.shared.release()
    }

    func restart() {
        task?.cancel()
        board.set(start, animated: true)
        board.arrows = []; board.lastMove = nil
        board.interactive = true
        board.onMove = { [weak self] m in self?.played(m) }
        phase = .yourMove
    }

    private func played(_ m: Move) {
        board.play(m)
        board.interactive = false
        if finish() { return }
        phase = .thinking
        let fen = board.position.fen, rating = opponentRating
        task = Task { [weak self] in
            let lines = (try? await Engine.shared.analyse(startFEN: fen, moves: [], multiPV: HumanishMove.lines, nodes: HumanishMove.nodes, movetimeMs: 1500, searchMoves: nil, onUpdate: nil)) ?? []
            guard let self, !Task.isCancelled, let reply = HumanishMove.choose(lines, rating: rating) else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, self.board.position.isLegal(reply) else { return }
            self.board.play(reply)
            if !self.finish() {
                self.phase = .yourMove
                self.board.interactive = true
            }
        }
    }

    /// The board itself decides. Repetition and the fifty-move rule are left out: this is practice, and you can stop.
    private func finish() -> Bool {
        let p = board.position
        if p.isCheckmate {
            phase = p.side == side ? .lost : .won
            if phase == .won, let to = board.lastMove?.to { board.reflex(from: to) }
            return true
        }
        if p.isStalemate || p.hasInsufficientMaterial { phase = .drawn; return true }
        return false
    }
}

/// Back to the moment it went wrong, to play it out against someone of your opponent's level. Nobody's watching.
struct ReplayGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReplayModel

    init(game: ImportedGame, replay: GameReplay, ply: Int) {
        _model = State(initialValue: ReplayModel(game: game, replay: replay, ply: ply))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Tanca").padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.title(22)).foregroundStyle(Theme.tin).contentTransition(.opacity)
                    Text("Contra \(model.opponent), amb el seu nivell (\(model.opponentRating)).").font(Theme.text(15)).foregroundStyle(Theme.quiet).lineLimit(2)
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
                BoardView(model.board).boardFrame()
                Button { model.restart() } label: {
                    Text("Torna a començar des d'aquí").font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                }
                .padding(.horizontal, 20).padding(.top, 12)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fieldBackground()
        .animation(.easeOut(duration: 0.2), value: model.phase)
        .onDisappear { model.close() }
    }

    private var title: LocalizedStringKey {
        switch model.phase {
        case .yourMove: "Et toca"
        case .thinking: "Pensa"
        case .won: "L'has guanyada"
        case .lost: "Aquesta vegada no"
        case .drawn: "Taules"
        }
    }
}
