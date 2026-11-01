import Foundation

/// A move of yours worth finding again. It copies the position and the answer, so it outlives the game and its review.
struct MistakeCard: Codable, Identifiable, Hashable {
    var id: String
    var gameID: String
    var fen: String
    var side: Side
    /// The opponent's move that led here, shown on the board for context.
    var lastMove: String?
    var bestUCI: String
    var playedSAN: String
    var opponent: String
    var gameDate: Date
    var note: String?
    /// Lichess theme tag, for the idea a first hint gives.
    var motif: String?
    var box = 0
    var due: Date

    static let perGame = 3
    static let perDay = 3
    /// Below this the game was already gone, and finding the best move there teaches little.
    static let minExpectedPoints = 0.35

    /// The worst few of your errors with one clearly better answer. A position with several fine moves makes an unfair question.
    static func cards(from review: GameReview, game: ImportedGame, now: Date = Date()) -> [MistakeCard] {
        guard let side = game.mySide, var board = Position(fen: review.startFEN) else { return [] }
        let rating = side == .white ? game.whiteRating : game.blackRating
        let opponent = side == .white ? game.black : game.white
        var found: [(lost: Double, card: MistakeCard)] = []
        var previous: String?
        for m in review.moves {
            guard let played = board.move(uci: m.uci) else { break }
            if m.side == side, let c = m.moveClass, [.mistake, .miss, .blunder].contains(c), let best = m.bestMove,
               let gap = m.secondBestGap, gap >= Thresholds.onlyMoveGap, let before = m.evalBefore,
               ExpectedPoints.of(side == .white ? before : before.flipped, rating: rating) >= minExpectedPoints {
                found.append((m.epLost, MistakeCard(
                    id: "\(game.id)#\(m.ply)", gameID: game.id, fen: board.fen, side: side, lastMove: previous, bestUCI: best.uci,
                    playedSAN: m.san, opponent: opponent, gameDate: game.date, note: m.coach?.text,
                    motif: GameLibrary.motifTag(on: board, line: m.bestLine), due: now)))
            }
            previous = m.uci
            board = board.applying(played)
        }
        return found.sorted { $0.lost > $1.lost }.prefix(perGame).map(\.card)
    }
}
