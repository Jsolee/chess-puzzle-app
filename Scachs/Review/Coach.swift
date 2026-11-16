import Foundation

// Rule-based coach. Every clause comes from one detector over the engine lines and the board, and
// carries that detector's arrows and squares. When nothing fires it shows the line and stays neutral,
// because wrong coach text destroys trust faster than no text.

enum CoachDetector: String, Codable, Sendable {
    case forced, book, mateDelivered, mateAllowed, mateMissed, mateKept
    case materialLost, materialMissed, materialWon
    case fork, pin, skewer, discovered, hanging, trapped, backRank, promotion
    case threatIgnored, threatPrevented, evalChange
    case sacrifice, onlyMove, turnaround
    case recapture, betterMove, verdict, line
}

/// Green for a stronger option, red for a threat or a problem, orange for the main idea, blue for the opponent's plans.
enum CoachRole: String, Codable, Sendable {
    case best, threat, idea, opponent

    var arrowRole: ArrowRole {
        switch self {
        case .best: return .best
        case .threat: return .threat
        case .idea: return .idea
        case .opponent: return .opponent
        }
    }

    var markRole: MarkRole {
        switch self {
        case .best: return .good
        case .threat: return .bad
        case .idea: return .hint
        case .opponent: return .target
        }
    }
}

struct CoachArrow: Hashable, Codable, Sendable {
    var from: Square
    var to: Square
    var role: CoachRole
    var board: BoardArrow { BoardArrow(from: from, to: to, role: role.arrowRole) }
}

struct CoachMark: Hashable, Codable, Sendable {
    var square: Square
    var role: CoachRole
    var board: BoardMark { BoardMark(square: square, role: role.markRole) }
}

struct CoachClause: Hashable, Codable, Sendable {
    var detector: CoachDetector
    var text: String
    var arrows: [CoachArrow] = []
    var marks: [CoachMark] = []
}

enum CoachShow: String, Codable, Sendable {
    case checkmate, lostPiece, fork, idea

    var title: String {
        switch self {
        case .checkmate: return String(localized: "Mostra el mat")
        case .lostPiece: return String(localized: "Mostra la peça perduda")
        case .fork: return String(localized: "Mostra la forquilla")
        case .idea: return String(localized: "Mostra la idea")
        }
    }
}

struct CoachNote: Hashable, Codable, Sendable {
    var clauses: [CoachClause]
    /// The Show button: which label it wears and the line it plays.
    var show: CoachShow?
    var line: [Move] = []
    /// Whether `line` starts after the played move, or before it.
    var lineStartsAfterMove = false

    var text: String { clauses.map(\.text).joined(separator: " ") }
    var arrows: [BoardArrow] { clauses.flatMap(\.arrows).map(\.board) }
    var marks: [BoardMark] { clauses.flatMap(\.marks).map(\.board) }
}

/// What the opponent would do if the mover passed, from a null-move search on the position before the move.
struct ThreatLine: Hashable, Codable, Sendable {
    var line: [Move]
    /// From the threatening side's point of view.
    var score: Score
}

enum Coach {
    static func note(facts f: MoveFacts, classification c: Classification, threat: ThreatLine? = nil, opening: Openings.Entry? = nil) -> CoachNote {
        var words = Words(seed: "\(f.before.epd)|\(f.move.uci)")
        switch c.moveClass {
        case .forced:
            return CoachNote(clauses: [CoachClause(detector: .forced, text: words.forced())])
        case .book:
            return CoachNote(clauses: [CoachClause(detector: .book, text: words.book(opening.map { OpeningNames.local($0.name) }))])
        case .inaccuracy, .mistake, .miss, .blunder:
            return badMove(f, c, threat, &words)
        case .brilliant, .great, .best, .excellent, .good:
            return goodMove(f, c, threat, &words)
        }
    }

    // MARK: Ladders

    private static func badMove(_ f: MoveFacts, _ c: Classification, _ threat: ThreatLine?, _ w: inout Words) -> CoachNote {
        let afterBoard = f.after
        var clauses: [CoachClause] = []
        var show: CoachShow?
        var line: [Move] = []
        var fromAfter = false
        var namedBest = false

        let reply = f.refutation.first.flatMap { afterBoard.isLegal($0) ? $0 : nil }
        let bestMove = f.bestMove.flatMap { f.before.isLegal($0) ? $0 : nil }
        // Material only counts if it lasts: a line cut mid-exchange can show a piece that's won back two moves later.
        func lasting(_ line: [Move], horizon: Int) -> MaterialOutcome {
            let near = f.outcome(of: line, horizon: horizon), far = f.outcome(of: line, horizon: line.count)
            return abs(far.net) < abs(near.net) ? far : near
        }
        let lost = lasting([f.move] + f.refutation, horizon: Thresholds.coachLineHorizon + 1)
        let bestOutcome = lasting(f.bestLine, horizon: Thresholds.coachLineHorizon)
        let worseThanBest = bestOutcome.net - lost.net

        func addLost() -> Bool {
            guard lost.net < 0, worseThanBest >= 1, let reply else { return false }
            // Being retaken after a capture of your own is a trade, whatever the line goes on to lose.
            let isRetake = reply.to == f.move.to && f.before.captured(by: f.move) != nil
            if !isRetake, let found = findMotif(on: afterBoard, line: f.refutation) {
                clauses.append(motifClause(found, voice: .opponent, &w))
                if case .fork = found.motif { show = .fork }
            }
            let target = afterBoard.captured(by: reply)?.square ?? reply.to
            clauses.append(CoachClause(detector: .materialLost,
                                       text: w.materialLost(phrase: w.material(lost, losing: true), san: afterBoard.san(reply)),
                                       arrows: [CoachArrow(from: reply.from, to: reply.to, role: .threat)],
                                       marks: [CoachMark(square: target, role: .threat)]))
            show = show ?? .lostPiece
            line = f.refutation
            fromAfter = true
            return true
        }

        func addMissed() -> Bool {
            guard bestOutcome.net >= 1, worseThanBest >= 1, let bestMove else { return false }
            if let found = findMotif(on: f.before, line: f.bestLine) {
                clauses.append(motifClause(found, voice: .missed, &w))
                if case .fork = found.motif { show = .fork }
            }
            let target = f.before.captured(by: bestMove)?.square ?? bestMove.to
            clauses.append(CoachClause(detector: .materialMissed,
                                       text: w.materialMissed(phrase: w.material(bestOutcome, losing: false), san: f.before.san(bestMove)),
                                       arrows: [CoachArrow(from: bestMove.from, to: bestMove.to, role: .best)],
                                       marks: [CoachMark(square: target, role: .best)]))
            show = show ?? .idea
            line = f.bestLine
            namedBest = true
            return true
        }

        if f.played.isMated, !f.best.isMated, let reply {
            clauses.append(CoachClause(detector: .mateAllowed,
                                       text: w.mateAllowed(moves: mateDistance(f.played), san: afterBoard.san(reply)),
                                       arrows: [CoachArrow(from: reply.from, to: reply.to, role: .threat)],
                                       marks: afterBoard.king(of: f.mover).map { [CoachMark(square: $0, role: .threat)] } ?? []))
            if let k = backRankMate(on: afterBoard, line: f.refutation) { clauses.append(backRankClause(k, voice: .opponent, &w)) }
            show = .checkmate
            line = f.refutation
            fromAfter = true
        } else if f.best.isMating, !f.played.isMating, let bestMove {
            clauses.append(CoachClause(detector: .mateMissed,
                                       text: w.mateMissed(moves: mateDistance(f.best), san: f.before.san(bestMove)),
                                       arrows: [CoachArrow(from: bestMove.from, to: bestMove.to, role: .best)]))
            if let k = backRankMate(on: f.before, line: f.bestLine) { clauses.append(backRankClause(k, voice: .missed, &w)) }
            show = .checkmate
            line = f.bestLine
            namedBest = true
        } else if c.moveClass == .miss ? (addMissed() || addLost()) : (addLost() || addMissed()) {
            // Clauses added by the helper that fired.
        } else if let threat, let reply, threat.line.first == reply, let board = f.before.nullMoved, isRealThreat(threat, on: board) {
            clauses.append(CoachClause(detector: .threatIgnored,
                                       text: w.threatIgnored(san: board.san(reply), mate: threat.score.isMating),
                                       arrows: [CoachArrow(from: reply.from, to: reply.to, role: .opponent)]))
            show = .idea
            line = f.refutation
            fromAfter = true
        } else if let change = w.evalChange(from: ExpectedPoints.zone(f.epBest), to: ExpectedPoints.zone(f.epPlayed)) {
            clauses.append(CoachClause(detector: .evalChange, text: change))
        }

        if clauses.isEmpty || clauses.allSatisfy({ $0.detector == .evalChange }) {
            clauses.insert(CoachClause(detector: .verdict, text: w.verdict(c.moveClass, isTop: f.isTopMove)), at: 0)
        }
        if !namedBest, let bestMove {
            clauses.append(CoachClause(detector: .betterMove, text: w.betterMove(san: f.before.san(bestMove)),
                                       arrows: [CoachArrow(from: bestMove.from, to: bestMove.to, role: .best)]))
        }
        if show == nil {
            show = .idea
            line = f.bestLine.isEmpty ? f.refutation : f.bestLine
            fromAfter = f.bestLine.isEmpty
            if !line.isEmpty, clauses.count < 3 {
                let start = fromAfter ? afterBoard : f.before
                clauses.append(CoachClause(detector: .line, text: w.line(sanLine(from: start, line))))
            }
        }
        return CoachNote(clauses: clauses, show: show, line: line, lineStartsAfterMove: fromAfter)
    }

    private static func goodMove(_ f: MoveFacts, _ c: Classification, _ threat: ThreatLine?, _ w: inout Words) -> CoachNote {
        let afterBoard = f.after
        if afterBoard.isCheckmate {
            var clauses = [CoachClause(detector: .mateDelivered, text: w.mateDelivered())]
            if let k = backRankMate(on: f.before, line: [f.move]) { clauses.append(backRankClause(k, voice: .you, &w)) }
            return CoachNote(clauses: clauses)
        }

        let line = [f.move] + f.refutation
        var clauses: [CoachClause] = []
        var show: CoachShow?
        let moveArrow = CoachArrow(from: f.move.from, to: f.move.to, role: .idea)

        if c.moveClass == .brilliant, let s = c.sacrificed.first, let piece = afterBoard.piece(at: s) {
            clauses.append(CoachClause(detector: .sacrifice, text: w.sacrifice(piece.kind, on: s), arrows: [moveArrow],
                                       marks: c.sacrificed.map { CoachMark(square: $0, role: .idea) }))
            show = .idea
        }
        if let reason = c.greatReason {
            let detector: CoachDetector = reason == .onlyMove ? .onlyMove : .turnaround
            clauses.append(CoachClause(detector: detector, text: w.great(reason), arrows: clauses.isEmpty ? [moveArrow] : []))
            show = show ?? .idea
        }
        if f.played.isMating {
            clauses.append(CoachClause(detector: .mateKept, text: w.mateKept(moves: mateDistance(f.played)), arrows: [moveArrow]))
            if let k = backRankMate(on: f.before, line: line) { clauses.append(backRankClause(k, voice: .you, &w)) }
            show = .checkmate
        } else if f.isRecapture, let taken = f.before.captured(by: f.move) {
            clauses.append(CoachClause(detector: .recapture, text: w.recapture(w.def(taken.piece.kind), san: f.before.san(f.move)), arrows: [moveArrow]))
        } else if let found = findMotif(on: f.before, line: line) {
            clauses.append(motifClause(found, voice: .you, &w))
            if case .fork = found.motif { show = .fork }
            show = show ?? .idea
        }
        // Only a capture owns the gain. Later in a line it may just be a sacrifice the opponent chose to make.
        let won = f.outcome(of: line, horizon: Thresholds.shortLineHorizon)
        if !f.played.isMating, f.before.captured(by: f.move) != nil, won.net >= 1, !clauses.contains(where: { $0.detector == .sacrifice }) {
            clauses.append(CoachClause(detector: .materialWon, text: w.materialWon(w.material(won, losing: false)), arrows: [moveArrow]))
            show = show ?? .idea
        }
        if clauses.isEmpty, let threat, let first = threat.line.first, ExpectedPoints.zone(f.epPlayed) != .losing,
           !afterBoard.inCheck, let board = f.before.nullMoved, isRealThreat(threat, on: board), threatIsGone(first, after: afterBoard) {
            clauses.append(CoachClause(detector: .threatPrevented,
                                       text: w.threatPrevented(san: board.san(first), mate: threat.score.isMating),
                                       arrows: [CoachArrow(from: first.from, to: first.to, role: .opponent)]))
        }
        if clauses.isEmpty { clauses.append(CoachClause(detector: .verdict, text: w.verdict(c.moveClass, isTop: f.isTopMove))) }
        if c.moveClass == .good, let best = f.bestMove, f.before.isLegal(best), clauses.count < 3 {
            clauses.append(CoachClause(detector: .betterMove, text: w.betterMove(san: f.before.san(best)),
                                       arrows: [CoachArrow(from: best.from, to: best.to, role: .best)]))
        }
        return CoachNote(clauses: clauses, show: show, line: show == nil ? [] : line, lineStartsAfterMove: false)
    }

    /// The engine's continuation after the move, for a note with nothing more to say than its verdict.
    static func continuation(_ f: MoveFacts) -> CoachClause? {
        guard !f.refutation.isEmpty, !f.after.isCheckmate else { return nil }
        var words = Words(seed: "\(f.before.epd)|\(f.move.uci)|line")
        return CoachClause(detector: .line, text: words.line(sanLine(from: f.after, f.refutation)))
    }

    private static func mateDistance(_ score: Score) -> Int {
        if case .mate(let n) = score { return max(abs(n), 1) }
        return 1
    }

    private static func isRealThreat(_ threat: ThreatLine, on board: Position) -> Bool {
        threat.score.isMating
            || MaterialOutcome(from: board, line: threat.line, side: board.side, horizon: Thresholds.shortLineHorizon).net >= Thresholds.threatMinMaterial
    }

    /// The threatening move no longer exists after the played move, or no longer wins anything.
    private static func threatIsGone(_ threat: Move, after: Position) -> Bool {
        guard after.isLegal(threat) else { return true }
        return MaterialOutcome(from: after, line: [threat], side: after.side).net < Thresholds.threatMinMaterial
    }

    private static func sanLine(from start: Position, _ line: [Move], limit: Int = 6) -> String {
        var pos = start
        var out: [String] = []
        for m in line.prefix(limit) {
            guard pos.isLegal(m) else { break }
            out.append(pos.san(m))
            pos = pos.applying(m)
        }
        return out.joined(separator: " ")
    }

    // MARK: Motifs

    enum Motif {
        case fork(piece: Square, targets: [Square])
        case pin(attacker: Square, pinned: Square, rear: Square)
        case skewer(attacker: Square, front: Square, rear: Square)
        case discovered(moved: Square, slider: Square, target: Square)
        case hanging(victim: Square, taker: Square, why: HangingReason)
        case trapped(victim: Square)
        case promotion(square: Square)
    }

    enum HangingReason { case undefended, cheaperTaker, outnumbered }

    struct FoundMotif {
        var motif: Motif
        /// The board on which the motif's squares are read.
        var board: Position
        var san: String
    }

    /// The first tactic the line's opening move shows. Motifs that only promise material must see the
    /// line cash in, otherwise the geometry alone would make the coach claim things that never happen.
    static func findMotif(on pos: Position, line: [Move]) -> FoundMotif? {
        guard let first = line.first, pos.isLegal(first) else { return nil }
        let board = pos.applying(first)
        let san = pos.san(first)

        if let taken = pos.captured(by: first), taken.piece.kind != .pawn, !pos.isPieceSafe(at: taken.square),
           !isRetakenEvenly(pos: pos, board: board, first: first, taken: taken.piece, line: line) {
            let why: HangingReason
            if pos.directAttackers(of: taken.square, by: taken.piece.side).isEmpty {
                why = .undefended
            } else if (pos.piece(at: first.from)?.kind.pointValue ?? 100) < taken.piece.kind.pointValue {
                why = .cheaperTaker
            } else {
                why = .outnumbered
            }
            return FoundMotif(motif: .hanging(victim: taken.square, taker: first.from, why: why), board: pos, san: san)
        }
        if let m = fork(pos: pos, board: board, first: first, line: line) ?? discovered(pos: pos, board: board, first: first, line: line)
            ?? pinOrSkewer(pos: pos, board: board, first: first, line: line) ?? trapped(pos: pos, board: board, line: line) {
            return FoundMotif(motif: m, board: board, san: san)
        }
        var replay = pos
        for (i, m) in line.prefix(7).enumerated() {
            guard replay.isLegal(m) else { break }
            if i % 2 == 0, m.promotion != nil { return FoundMotif(motif: .promotion(square: m.to), board: board, san: san) }
            replay = replay.applying(m)
        }
        return nil
    }

    private static func isRetakenEvenly(pos: Position, board: Position, first: Move, taken: Piece, line: [Move]) -> Bool {
        guard line.count > 1, line[1].to == first.to, board.isLegal(line[1]),
              let taker = pos.piece(at: first.from) else { return false }
        return taker.kind.pointValue >= taken.kind.pointValue
    }

    /// Whether the line's later moves by the same side take on one of the squares, or mate.
    private static func lineCashesIn(pos: Position, line: [Move], squares: Set<Square>) -> Bool {
        var replay = pos
        for (i, m) in line.prefix(5).enumerated() {
            guard replay.isLegal(m) else { return false }
            if i >= 2, i % 2 == 0, let taken = replay.captured(by: m), squares.contains(taken.square) { return true }
            replay = replay.applying(m)
            if replay.isCheckmate { return true }
        }
        return false
    }

    private static func fork(pos: Position, board: Position, first: Move, line: [Move]) -> Motif? {
        guard let moved = board.piece(at: first.to), moved.kind != .king, board.isPieceSafe(at: first.to) else { return nil }
        let targets = board.attackedSquares(from: first.to).filter { s in
            guard let p = board.piece(at: s), p.side != moved.side, p.kind != .pawn else { return false }
            return p.kind.pointValue > moved.kind.pointValue || !board.isPieceSafe(at: s)
        }
        guard targets.count >= 2, lineCashesIn(pos: pos, line: line, squares: Set(targets)) else { return nil }
        // The king, when attacked, leads the sentence.
        let ordered = targets.sorted { (board.piece(at: $0)?.kind.pointValue ?? 0) > (board.piece(at: $1)?.kind.pointValue ?? 0) }
        return .fork(piece: first.to, targets: Array(ordered.prefix(2)))
    }

    private static func pinOrSkewer(pos: Position, board: Position, first: Move, line: [Move]) -> Motif? {
        guard let moved = board.piece(at: first.to), board.isPieceSafe(at: first.to) else { return nil }
        for (df, dr) in moved.kind.lineSteps {
            guard let front = board.ray(from: first.to, df, dr).blocker, let frontPiece = board.piece(at: front), frontPiece.side != moved.side,
                  let rear = board.ray(from: front, df, dr).blocker, let rearPiece = board.piece(at: rear), rearPiece.side != moved.side else { continue }
            let frontValue = frontPiece.kind.pointValue, rearValue = rearPiece.kind.pointValue
            if frontPiece.kind != .pawn, rearValue > frontValue, lineCashesIn(pos: pos, line: line, squares: [front]) {
                return .pin(attacker: first.to, pinned: front, rear: rear)
            }
            if rearPiece.kind != .pawn, frontValue > rearValue, lineCashesIn(pos: pos, line: line, squares: [rear]) {
                return .skewer(attacker: first.to, front: front, rear: rear)
            }
        }
        return nil
    }

    private static func discovered(pos: Position, board: Position, first: Move, line: [Move]) -> Motif? {
        guard let moved = board.piece(at: first.to) else { return nil }
        for slider in board.squares(of: moved.side) where slider != first.to {
            guard let kind = board.piece(at: slider)?.kind, let step = lineStep(from: slider, to: first.from),
                  kind.lineSteps.contains(where: { $0 == step }),
                  pos.ray(from: slider, step.0, step.1).blocker == first.from,
                  let target = board.ray(from: slider, step.0, step.1).blocker, let piece = board.piece(at: target),
                  piece.side != moved.side, piece.kind != .pawn,
                  piece.kind.pointValue > kind.pointValue || !board.isPieceSafe(at: target) else { continue }
            // The moved piece can cash in as well, since the opponent can only answer one of the two.
            var squares: Set<Square> = [target]
            squares.formUnion(board.attackedSquares(from: first.to))
            if lineCashesIn(pos: pos, line: line, squares: squares) {
                return .discovered(moved: first.to, slider: slider, target: target)
            }
        }
        return nil
    }

    private static func trapped(pos: Position, board: Position, line: [Move]) -> Motif? {
        var replay = pos
        for (i, m) in line.prefix(5).enumerated() {
            guard replay.isLegal(m) else { return nil }
            if i >= 2, i % 2 == 0, let taken = replay.captured(by: m), taken.piece.kind != .pawn {
                let stayed = stride(from: 1, to: i, by: 2).allSatisfy { line[$0].from != taken.square }
                return stayed && board.piece(at: taken.square) == taken.piece && board.isTrapped(at: taken.square)
                    ? .trapped(victim: taken.square) : nil
            }
            replay = replay.applying(m)
        }
        return nil
    }

    /// The mated king's square when the line ends in a mate along its own back rank, shut in by its own pieces.
    static func backRankMate(on pos: Position, line: [Move]) -> Square? {
        var replay = pos
        for m in line {
            guard replay.isLegal(m) else { return nil }
            replay = replay.applying(m)
        }
        guard replay.isCheckmate, let k = replay.king(of: replay.side) else { return nil }
        let (back, forward) = replay.side == .white ? (0, 1) : (7, 6)
        guard k / 8 == back else { return nil }
        let onRank = replay.attackers(of: k, by: replay.side.opposite).contains { a in
            guard let kind = replay.piece(at: a)?.kind, kind == .rook || kind == .queen else { return false }
            return a / 8 == back
        }
        guard onRank else { return nil }
        let file = k % 8
        return (max(file - 1, 0)...min(file + 1, 7)).allSatisfy { replay.piece(at: forward * 8 + $0)?.side == replay.side } ? k : nil
    }

    // MARK: Motif clauses

    private static func motifClause(_ found: FoundMotif, voice: Words.Voice, _ w: inout Words) -> CoachClause {
        let role: CoachRole = voice == .opponent ? .threat : voice == .missed ? .best : .idea
        let b = found.board
        func kind(_ s: Square) -> PieceKind { b.piece(at: s)?.kind ?? .pawn }
        func arrow(_ from: Square, _ to: Square) -> CoachArrow { CoachArrow(from: from, to: to, role: role) }
        func mark(_ s: Square) -> CoachMark { CoachMark(square: s, role: role) }

        switch found.motif {
        case .fork(let piece, let targets):
            let text = w.fork(san: found.san, actor: w.def(kind(piece), on: piece), first: w.def(kind(targets[0]), on: targets[0]),
                              second: w.def(kind(targets[1]), on: targets[1]), voice: voice)
            return CoachClause(detector: .fork, text: text, arrows: targets.map { arrow(piece, $0) }, marks: targets.map(mark))
        case .pin(let attacker, let pinned, let rear):
            let text = w.pin(san: found.san, attacker: w.def(kind(attacker), on: attacker), pinned: w.def(kind(pinned), on: pinned),
                             rear: w.def(kind(rear)), voice: voice)
            return CoachClause(detector: .pin, text: text, arrows: [arrow(attacker, pinned)], marks: [mark(pinned), mark(rear)])
        case .skewer(let attacker, let front, let rear):
            let text = w.skewer(san: found.san, attacker: w.def(kind(attacker), on: attacker), front: w.def(kind(front)),
                                frontOf: w.gen(kind(front)), rear: w.def(kind(rear), on: rear), voice: voice)
            return CoachClause(detector: .skewer, text: text, arrows: [arrow(attacker, front)], marks: [mark(front), mark(rear)])
        case .discovered(let moved, let slider, let target):
            let text = w.discovered(san: found.san, moved: w.def(kind(moved)), slider: w.def(kind(slider), on: slider),
                                    sliderOf: w.gen(kind(slider)), target: w.def(kind(target), on: target),
                                    towards: w.dat(kind(target), on: target), voice: voice)
            return CoachClause(detector: .discovered, text: text, arrows: [arrow(slider, target)], marks: [mark(target)])
        case .hanging(let victim, let taker, let why):
            let text = w.hanging(san: found.san, victim: w.def(kind(victim), on: victim), taker: w.def(kind(taker)),
                                 takerOf: w.gen(kind(taker)), why: why, voice: voice)
            return CoachClause(detector: .hanging, text: text, arrows: [arrow(taker, victim)], marks: [mark(victim)])
        case .trapped(let victim):
            return CoachClause(detector: .trapped, text: w.trapped(w.def(kind(victim), on: victim), voice: voice), marks: [mark(victim)])
        case .promotion(let square):
            return CoachClause(detector: .promotion, text: w.promotion(square: squareName(square), voice: voice), marks: [mark(square)])
        }
    }

    private static func backRankClause(_ king: Square, voice: Words.Voice, _ w: inout Words) -> CoachClause {
        let role: CoachRole = voice == .opponent ? .threat : voice == .missed ? .best : .idea
        return CoachClause(detector: .backRank, text: w.backRank(voice: voice), marks: [CoachMark(square: king, role: role)])
    }
}

// MARK: - Words

/// All the copy. Each template has a few phrasings, chosen by a hash of the move so a review reads the
/// same every time. Swift's Hasher is seeded per process, so it must not be used here.
private struct Words {
    enum Voice { case opponent, you, missed }

    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        state = hash
    }

    private mutating func pick(_ variants: [String]) -> String {
        // xorshift, so each clause of a note gets its own draw.
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return variants[Int(state % UInt64(variants.count))]
    }

    // MARK: Pieces and squares

    func def(_ k: PieceKind) -> String {
        switch k {
        case .pawn: return String(localized: "el peó")
        case .knight: return String(localized: "el cavall")
        case .bishop: return String(localized: "l'alfil")
        case .rook: return String(localized: "la torre")
        case .queen: return String(localized: "la dama")
        case .king: return String(localized: "el rei")
        }
    }

    func gen(_ k: PieceKind) -> String {
        switch k {
        case .pawn: return String(localized: "del peó")
        case .knight: return String(localized: "del cavall")
        case .bishop: return String(localized: "de l'alfil")
        case .rook: return String(localized: "de la torre")
        case .queen: return String(localized: "de la dama")
        case .king: return String(localized: "del rei")
        }
    }

    /// For "cap a": "al cavall", "a la dama", "a l'alfil".
    func dat(_ k: PieceKind) -> String {
        switch k {
        case .pawn: return String(localized: "al peó")
        case .knight: return String(localized: "al cavall")
        case .bishop: return String(localized: "a l'alfil")
        case .rook: return String(localized: "a la torre")
        case .queen: return String(localized: "a la dama")
        case .king: return String(localized: "al rei")
        }
    }

    /// "de c4" but "d'e4": the letters a, e, f and h start with a vowel sound in Catalan.
    func of(_ s: Square) -> String {
        let name = squareName(s)
        return "aefh".contains(name.prefix(1)) ? String(localized: "d'\(name)") : String(localized: "de \(name)")
    }

    func def(_ k: PieceKind, on s: Square) -> String { k == .king ? def(k) : "\(def(k)) \(of(s))" }
    func dat(_ k: PieceKind, on s: Square) -> String { k == .king ? dat(k) : "\(dat(k)) \(of(s))" }

    private func cap(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    func material(_ o: MaterialOutcome, losing: Bool) -> String {
        let out = losing ? o.lost : o.won, back = losing ? o.won : o.lost
        func net(_ k: PieceKind) -> Int { (out[k] ?? 0) - (back[k] ?? 0) }
        let q = net(.queen), r = net(.rook), n = net(.knight), b = net(.bishop), p = net(.pawn)
        let minors = n + b
        if q == 1, r == 0, minors == 0 { return String(localized: "la dama") }
        if q == 0, r == 1, minors == -1 { return String(localized: "la qualitat") }
        if q == 0, r == 1, minors == 0 { return String(localized: "una torre") }
        if q == 0, r == 0, minors == 1 {
            if n == 1, b == 0 { return String(localized: "un cavall") }
            if b == 1, n == 0 { return String(localized: "un alfil") }
            return String(localized: "una peça")
        }
        if q == 0, r == 0, minors == 0, p > 0 {
            switch p {
            case 1: return String(localized: "un peó")
            case 2: return String(localized: "dos peons")
            case 3: return String(localized: "tres peons")
            default: return String(localized: "\(p) peons")
            }
        }
        return String(localized: "material")
    }

    // MARK: Plain facts

    mutating func forced() -> String {
        pick([String(localized: "Era l'única jugada legal."),
              String(localized: "No hi havia cap altra jugada possible."),
              String(localized: "Jugada obligada: no tenies cap alternativa.")])
    }

    mutating func book(_ name: String?) -> String {
        guard let name, !name.isEmpty else {
            return pick([String(localized: "Jugada de llibre."),
                         String(localized: "Encara ets dins la teoria."),
                         String(localized: "És una jugada coneguda de l'obertura.")])
        }
        return pick([String(localized: "Jugada de llibre: \(name)."),
                     String(localized: "Encara ets dins la teoria: \(name)."),
                     String(localized: "Obertura coneguda: \(name).")])
    }

    mutating func verdict(_ c: MoveClass, isTop: Bool) -> String {
        switch c {
        case .inaccuracy:
            return pick([String(localized: "Hi havia una opció més precisa."),
                         String(localized: "No és la més precisa: perds una mica de terreny."),
                         String(localized: "La posició empitjora una mica: hi havia alguna cosa millor.")])
        case .mistake:
            return pick([String(localized: "Aquesta jugada empitjora clarament la posició."),
                         String(localized: "Hi havia opcions molt millors."),
                         String(localized: "És una errada: la posició queda força pitjor.")])
        case .miss:
            return pick([String(localized: "Tenies una oportunitat clara i se t'ha escapat."),
                         String(localized: "La fallada del rival et donava una oportunitat que no has aprofitat."),
                         String(localized: "El rival havia fallat i no n'has tret profit.")])
        case .blunder:
            return pick([String(localized: "És una pífia: la posició empitjora molt."),
                         String(localized: "Aquesta jugada fa molt de mal a la posició."),
                         String(localized: "La valoració cau molt amb aquesta jugada.")])
        case .excellent:
            return pick([String(localized: "Gairebé tan bona com la millor."),
                         String(localized: "Perds molt poc respecte de la millor opció."),
                         String(localized: "Una jugada sòlida, molt a prop de la millor.")])
        case .good:
            return pick([String(localized: "Una jugada correcta, tot i que n'hi havia de millors."),
                         String(localized: "Serveix, encara que no és la més precisa."),
                         String(localized: "És acceptable, però hi havia una opció més forta.")])
        default:
            if !isTop {
                return pick([String(localized: "Tan bona com la primera opció del motor."),
                             String(localized: "El motor la valora igual que la seva primera opció."),
                             String(localized: "No perds res respecte de la millor opció.")])
            }
            return pick([String(localized: "És la millor jugada de la posició."),
                         String(localized: "El motor tria aquesta mateixa jugada."),
                         String(localized: "Cap altra jugada és millor que aquesta.")])
        }
    }

    mutating func betterMove(san: String) -> String {
        pick([String(localized: "Era millor \(san)."),
              String(localized: "La millor jugada era \(san)."),
              String(localized: "El motor preferia \(san).")])
    }

    mutating func line(_ moves: String) -> String {
        pick([String(localized: "La línia principal continua amb \(moves)."),
              String(localized: "El motor preveu \(moves)."),
              String(localized: "La seqüència més probable és \(moves).")])
    }

    // MARK: Mate

    mutating func mateDelivered() -> String {
        pick([String(localized: "Escac i mat."),
              String(localized: "És mat: la partida s'acaba aquí."),
              String(localized: "Mat. No hi ha res més a jugar.")])
    }

    mutating func mateAllowed(moves n: Int, san: String) -> String {
        if n == 1 {
            return pick([String(localized: "Aquesta jugada permet mat immediat amb \(san)."),
                         String(localized: "Després d'això, el rival fa mat amb \(san)."),
                         String(localized: "Amb això, \(san) és mat.")])
        }
        return pick([String(localized: "Aquesta jugada permet un mat en \(n), que comença amb \(san)."),
                     String(localized: "Ara el rival té mat en \(n) a partir de \(san)."),
                     String(localized: "Permets un mat forçat en \(n) jugades, començant per \(san).")])
    }

    mutating func mateMissed(moves n: Int, san: String) -> String {
        if n == 1 {
            return pick([String(localized: "Tenies mat immediat amb \(san)."),
                         String(localized: "\(san) era mat."),
                         String(localized: "Se t'ha escapat el mat amb \(san).")])
        }
        return pick([String(localized: "Tenies mat en \(n) començant per \(san)."),
                     String(localized: "Hi havia un mat forçat en \(n) a partir de \(san)."),
                     String(localized: "Se t'ha escapat un mat en \(n): la clau era \(san).")])
    }

    mutating func mateKept(moves n: Int) -> String {
        if n == 1 {
            return pick([String(localized: "La jugada següent és mat."),
                         String(localized: "Ja només queda fer mat."),
                         String(localized: "Fas mat a la jugada següent.")])
        }
        return pick([String(localized: "Tens mat forçat en \(n)."),
                     String(localized: "Mantens un mat forçat en \(n)."),
                     String(localized: "Amb aquesta jugada, el mat en \(n) és inevitable.")])
    }

    mutating func backRank(voice: Voice) -> String {
        if voice == .missed {
            return pick([String(localized: "Era un mat de passadís: el rei no podia sortir de l'última fila."),
                         String(localized: "El rei quedava tancat a l'última fila per les seves pròpies peces."),
                         String(localized: "Mat de passadís: les mateixes peces del rei li tancaven la sortida.")])
        }
        return pick([String(localized: "És un mat de passadís: el rei no pot sortir de l'última fila."),
                     String(localized: "El rei queda tancat a l'última fila per les seves pròpies peces."),
                     String(localized: "Mat de passadís: les mateixes peces del rei li tanquen la sortida.")])
    }

    // MARK: Material

    mutating func materialLost(phrase: String, san: String) -> String {
        pick([String(localized: "Perds \(phrase) després de \(san)."),
              String(localized: "Amb \(san), el rival et guanya \(phrase)."),
              String(localized: "Aquesta jugada et costa \(phrase): \(san).")])
    }

    mutating func materialMissed(phrase: String, san: String) -> String {
        pick([String(localized: "Podies guanyar \(phrase) amb \(san)."),
              String(localized: "Amb \(san) guanyaves \(phrase)."),
              String(localized: "Hi havia \(phrase) per guanyar amb \(san).")])
    }

    mutating func materialWon(_ phrase: String) -> String {
        pick([String(localized: "Guanyes \(phrase)."),
              String(localized: "Aquesta jugada guanya \(phrase)."),
              String(localized: "Et quedes amb \(phrase).")])
    }

    // MARK: Tactics

    mutating func fork(san: String, actor: String, first: String, second: String, voice: Voice) -> String {
        if voice == .missed {
            return pick([String(localized: "Amb \(san), \(actor) atacava alhora \(first) i \(second)."),
                         String(localized: "\(san) era una forquilla sobre \(first) i \(second)."),
                         String(localized: "Hi havia una forquilla amb \(san): atacava \(first) i \(second) alhora.")])
        }
        return pick([String(localized: "Amb \(san), \(actor) ataca alhora \(first) i \(second)."),
                     String(localized: "\(san) és una forquilla sobre \(first) i \(second)."),
                     String(localized: "\(san) fa una forquilla: ataca \(first) i \(second) alhora.")])
    }

    mutating func pin(san: String, attacker: String, pinned: String, rear: String, voice: Voice) -> String {
        if voice == .missed {
            return pick([String(localized: "Amb \(san), \(attacker) clavava \(pinned) contra \(rear)."),
                         String(localized: "\(san) creava una clavada: \(pinned) no es podia moure sense exposar \(rear)."),
                         String(localized: "\(san) clavava \(pinned) contra \(rear).")])
        }
        return pick([String(localized: "Amb \(san), \(attacker) clava \(pinned) contra \(rear)."),
                     String(localized: "\(san) crea una clavada: \(pinned) no es pot moure sense exposar \(rear)."),
                     String(localized: "\(san) clava \(pinned) contra \(rear).")])
    }

    mutating func skewer(san: String, attacker: String, front: String, frontOf: String, rear: String, voice: Voice) -> String {
        if voice == .missed {
            return pick([String(localized: "\(san) era una enfilada: \(front) havia d'apartar-se i quedava \(rear) a l'abast."),
                         String(localized: "Amb \(san), \(attacker) feia una enfilada sobre \(front) i \(rear)."),
                         String(localized: "\(san) feia una enfilada: darrere \(frontOf) hi havia \(rear).")])
        }
        return pick([String(localized: "\(san) és una enfilada: \(front) ha d'apartar-se i queda \(rear) a l'abast."),
                     String(localized: "Amb \(san), \(attacker) fa una enfilada sobre \(front) i \(rear)."),
                     String(localized: "\(san) fa una enfilada: darrere \(frontOf) hi ha \(rear).")])
    }

    mutating func discovered(san: String, moved: String, slider: String, sliderOf: String, target: String, towards: String, voice: Voice) -> String {
        if voice == .missed {
            return pick([String(localized: "En moure \(moved), \(slider) atacava \(target)."),
                         String(localized: "\(san) era un atac a la descoberta: \(slider) atacava \(target)."),
                         String(localized: "\(san) obria la línia \(sliderOf) cap \(towards).")])
        }
        return pick([String(localized: "En moure \(moved), \(slider) ataca \(target)."),
                     String(localized: "\(san) és un atac a la descoberta: \(slider) ataca \(target)."),
                     String(localized: "\(san) obre la línia \(sliderOf) cap \(towards).")])
    }

    mutating func recapture(_ piece: String, san: String) -> String {
        pick([String(localized: "Recaptures \(piece)."),
              String(localized: "Recuperes el material amb \(san)."),
              String(localized: "Respons a la captura amb \(san).")])
    }

    mutating func hanging(san: String, victim: String, taker: String, takerOf: String, why: Coach.HangingReason, voice: Voice) -> String {
        let v = cap(victim)
        switch (voice, why) {
        case (.opponent, .undefended):
            return pick([String(localized: "Amb \(san), el rival captura \(victim), que no té defensa."),
                         String(localized: "\(v) no té defensa: \(san)."),
                         String(localized: "\(san) captura \(victim), que està sense defensa.")])
        case (.opponent, .outnumbered):
            return pick([String(localized: "\(san) captura \(victim), que no té prou defensa."),
                         String(localized: "\(v) no té prou defensa: \(san)."),
                         String(localized: "Amb \(san), \(taker) captura \(victim), que no té prou defensa.")])
        case (.opponent, .cheaperTaker):
            return pick([String(localized: "\(san) captura \(victim) amb una peça de menys valor."),
                         String(localized: "\(v) està a l'abast \(takerOf): \(san)."),
                         String(localized: "Amb \(san), \(taker) captura \(victim).")])
        case (.you, .undefended):
            return pick([String(localized: "Captures \(victim), que no té defensa."),
                         String(localized: "Aprofites que \(victim) no té defensa."),
                         String(localized: "\(san) captura \(victim), que està sense defensa.")])
        case (.you, .outnumbered):
            return pick([String(localized: "Captures \(victim), que no té prou defensa."),
                         String(localized: "Aprofites que \(victim) no té prou defensa."),
                         String(localized: "\(san) captura \(victim), que no té prou defensa.")])
        case (.you, .cheaperTaker):
            return pick([String(localized: "Captures \(victim) amb una peça de menys valor."),
                         String(localized: "\(v) estava a l'abast \(takerOf), i ho aprofites."),
                         String(localized: "\(san) captura \(victim) amb una peça de menys valor.")])
        case (.missed, .undefended):
            return pick([String(localized: "Podies capturar \(victim), que no tenia defensa, amb \(san)."),
                         String(localized: "\(v) no tenia defensa: \(san)."),
                         String(localized: "\(san) capturava \(victim), que estava sense defensa.")])
        case (.missed, .outnumbered):
            return pick([String(localized: "Podies capturar \(victim), que no tenia prou defensa, amb \(san)."),
                         String(localized: "\(v) no tenia prou defensa: \(san)."),
                         String(localized: "\(san) capturava \(victim), que no tenia prou defensa.")])
        case (.missed, .cheaperTaker):
            return pick([String(localized: "\(san) capturava \(victim) amb una peça de menys valor."),
                         String(localized: "\(v) estava a l'abast \(takerOf): \(san)."),
                         String(localized: "Amb \(san), \(taker) capturava \(victim).")])
        }
    }

    mutating func trapped(_ victim: String, voice: Voice) -> String {
        let v = cap(victim)
        if voice == .missed {
            return pick([String(localized: "\(v) no tenia cap casella segura."),
                         String(localized: "\(v) no tenia escapatòria."),
                         String(localized: "Podies atrapar \(victim): no tenia cap casella segura.")])
        }
        return pick([String(localized: "\(v) no té cap casella segura."),
                     String(localized: "\(v) es queda sense escapatòria."),
                     String(localized: "\(v) no té escapatòria.")])
    }

    mutating func promotion(square: String, voice: Voice) -> String {
        if voice == .missed {
            return pick([String(localized: "En aquesta línia, el peó coronava a \(square)."),
                         String(localized: "El peó arribava a \(square) i coronava."),
                         String(localized: "Hi havia una coronació a \(square) en aquesta línia.")])
        }
        return pick([String(localized: "En aquesta línia, el peó corona a \(square)."),
                     String(localized: "El peó arriba a \(square) i corona."),
                     String(localized: "Hi ha una coronació a \(square) en aquesta línia.")])
    }

    // MARK: Threats and evals

    mutating func threatIgnored(san: String, mate: Bool) -> String {
        if mate {
            return pick([String(localized: "El rival amenaçava mat amb \(san), i no l'has aturat."),
                         String(localized: "Hi havia una amenaça de mat amb \(san) i no l'has atesa."),
                         String(localized: "No has atès l'amenaça de mat: \(san).")])
        }
        return pick([String(localized: "No has atès l'amenaça \(san)."),
                     String(localized: "L'amenaça era \(san), i no l'has aturada."),
                     String(localized: "Has deixat passar l'amenaça \(san).")])
    }

    mutating func threatPrevented(san: String, mate: Bool) -> String {
        if mate {
            return pick([String(localized: "Atures l'amenaça de mat amb \(san)."),
                         String(localized: "Així evites el mat amb \(san)."),
                         String(localized: "Neutralitzes l'amenaça de mat: \(san).")])
        }
        return pick([String(localized: "Atures l'amenaça \(san)."),
                     String(localized: "Així evites \(san)."),
                     String(localized: "Neutralitzes l'amenaça \(san).")])
    }

    mutating func evalChange(from: ExpectedPoints.Zone, to: ExpectedPoints.Zone) -> String? {
        guard from != to else { return nil }
        let origin: String, target: String
        switch from {
        case .winning: origin = String(localized: "de guanyadora")
        case .equal: origin = String(localized: "d'igualada")
        case .losing: origin = String(localized: "de perduda")
        }
        switch to {
        case .winning: target = String(localized: "a guanyadora")
        case .equal: target = String(localized: "a igualada")
        case .losing: target = String(localized: "a perduda")
        }
        return pick([String(localized: "La posició passa \(origin) \(target)."),
                     String(localized: "Amb aquesta jugada, la posició passa \(origin) \(target)."),
                     String(localized: "Aquí la posició passa \(origin) \(target).")])
    }

    // MARK: The good ones

    mutating func sacrifice(_ kind: PieceKind, on s: Square) -> String {
        let piece = def(kind, on: s)
        return pick([String(localized: "Sacrifiques \(piece) i la posició ho compensa."),
                     String(localized: "Ofereixes \(piece), i el rival no en treu cap profit."),
                     String(localized: "Un bon sacrifici: \(piece) queda a l'abast, però la valoració es manté.")])
    }

    mutating func great(_ reason: GreatReason) -> String {
        switch reason {
        case .onlyMove:
            return pick([String(localized: "Era l'única jugada bona."),
                         String(localized: "Totes les altres opcions eren clarament pitjors."),
                         String(localized: "Has trobat l'única jugada que mantenia la posició.")])
        case .losingToEqual:
            return pick([String(localized: "Estaves perdent i aquesta jugada et torna a la igualtat."),
                         String(localized: "Recuperes la igualtat en una posició que anava malament."),
                         String(localized: "Amb aquesta jugada surts d'una posició perduda.")])
        case .equalToWinning:
            return pick([String(localized: "Aprofites el moment i passes a una posició guanyadora."),
                         String(localized: "La partida estava igualada i ara tens una posició guanyadora."),
                         String(localized: "Amb aquesta jugada treus avantatge d'una posició igualada.")])
        }
    }
}
