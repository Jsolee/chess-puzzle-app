import Foundation

/// A move tried on the analysis board, judged the way a game move is.
struct BranchVerdict: Sendable {
    var moveClass: MoveClass
    var note: CoachNote
    /// White's point of view.
    var evalAfter: Score
    var epLost: Double
}

enum BranchJudge {
    /// Search budget for each position of a branch: enough to tell a slip from search noise, short enough to wait for.
    static let nodes = 600_000
    static let movetimeMs = 1_500

    /// `trail` runs from as far back as is known to the position before `move`, with `moves` between its
    /// positions, so that an exchange under way is counted the way the review counts it. `before` and
    /// `after` are MultiPV searches of the positions either side of the move, side to move's view.
    static func judge(trail: [Position], moves: [Move], move: Move, rating: Int?,
                      before: [EngineLine], after: [EngineLine], previous: MoveFacts.Previous?) -> BranchVerdict? {
        guard let board = trail.last, moves.count == trail.count - 1, let top = before.first, board.isLegal(move) else { return nil }
        // Like with like: a move among the candidates keeps that score, unless the deeper look after it is kinder.
        var looks: [(score: Score, line: [Move])] = []
        if let candidate = before.first(where: { $0.pv.first == move }) { looks.append((candidate.score, Array(candidate.pv.dropFirst()))) }
        if let reply = after.first { looks.append((reply.score.flipped, reply.pv)) }
        guard let played = looks.max(by: { ExpectedPoints.of($0.score, rating: rating) < ExpectedPoints.of($1.score, rating: rating) }) else { return nil }

        var from = trail.count - 1
        while from > 0, trail[from - 1].captured(by: moves[from - 1]) != nil { from -= 1 }
        let facts = MoveFacts(before: board, move: move, rating: rating, best: top.score, bestMove: top.pv.first, bestLine: top.pv,
                              played: played.score, second: before.dropFirst().first?.score, refutation: played.line, previous: previous,
                              exchangeStart: from < trail.count - 1 ? trail[from] : nil, exchange: Array(moves[from...]))
        let c = Classifier.classify(facts)
        var note = Coach.note(facts: facts, classification: c)
        if note.clauses.allSatisfy({ $0.detector == .verdict }), let more = Coach.continuation(facts) { note.clauses.append(more) }
        return BranchVerdict(moveClass: c.moveClass, note: note,
                             evalAfter: played.score.flipped.whitePOV(sideToMove: board.side.opposite), epLost: c.epLost)
    }
}
