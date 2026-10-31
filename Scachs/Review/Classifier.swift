import Foundation
import SwiftUI

// Our own model. The class names and the expected-points bands are the ones chess.com publishes,
// everything else here is calibration of ours, so nothing may claim to match their labels.

enum MoveClass: String, Codable, CaseIterable, Sendable {
    case brilliant, great, best, excellent, good, book, inaccuracy, mistake, miss, blunder, forced

    /// "!!", "!", "?!", "?" and "??" are set as text. The others name our own drawn icons.
    var glyph: String {
        switch self {
        case .brilliant: return "!!"
        case .great: return "!"
        case .best: return "star"
        case .excellent: return "thumb"
        case .good: return "check"
        case .book: return "book"
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .miss: return "x"
        case .blunder: return "??"
        case .forced: return "forced"
        }
    }

    var displayName: String {
        switch self {
        case .brilliant: return String(localized: "Brillant")
        case .great: return String(localized: "Genial")
        case .best: return String(localized: "La millor")
        case .excellent: return String(localized: "Excel·lent")
        case .good: return String(localized: "Bona")
        case .book: return String(localized: "Llibre")
        case .inaccuracy: return String(localized: "Imprecisió")
        case .mistake: return String(localized: "Errada")
        case .miss: return String(localized: "Oportunitat perduda")
        case .blunder: return String(localized: "Pífia")
        case .forced: return String(localized: "Forçada")
        }
    }

    /// From brand/tokens.json. It has no Forced entry, so Forced borrows Best's tone.
    var fillHex: UInt32 {
        switch self {
        case .brilliant: return 0x3FC8B0
        case .great: return 0x7AA7CF
        case .best, .excellent, .forced: return 0x7FBF5A
        case .good: return 0x9CC07F
        case .book: return 0xD8AD85
        case .inaccuracy: return 0xF2C94C
        case .mistake: return 0xF29D4E
        case .miss: return 0xEF7D6C
        case .blunder: return 0xE2483A
        }
    }

    var onHex: UInt32 { self == .blunder ? 0xF6F1E6 : 0x0B2C27 }
    var fill: Color { Color(hex: fillHex) }
    var on: Color { Color(hex: onHex) }

    /// Forced moves are shown on the move but stay out of the player's count table.
    var isCounted: Bool { self != .forced }
}

/// Every threshold of the review in one place. Only the bands are published by chess.com;
/// all the rest are starting calibrations of ours, to tune against hand-labelled positions.
/// Game results can't fit those, so when the curve was refit they were scaled to keep their worth in centipawns.
enum Thresholds {
    // Expected-points loss bands. Adjacent published bands share their endpoints and the source
    // does not say which side owns them. Our rule: a band owns its lower endpoint, so a loss of
    // exactly 0.20 is a Blunder and exactly 0.02 is Good. Only a loss of zero is Best.
    static let bandGood = 0.02
    static let bandInaccuracy = 0.05
    static let bandMistake = 0.10
    static let bandBlunder = 0.20

    // Winning, equal and losing cuts in expected points. They move in cp with rating through k.
    static let losingBelow = 0.43
    static let winningFrom = 0.57

    // Blunder gate: a Blunder must lose material or allow mate, or it is a Mistake.
    static let blunderMinMaterial = 2
    static let lineHorizonPlies = 10

    // Miss.
    static let missOpponentLoss = 0.05
    static let missMinLoss = 0.05
    static let missLostMateMinLoss = 0.02

    // Great.
    static let greatMinEPAfter = 0.50
    static let onlyMoveGap = 0.05
    static let onlyMoveGapNewPlayer = 0.035
    static let turnaroundMinGap = 0.035
    /// Still completely winning without this move, on the Stockfish scale of the review.
    static let alreadyWinningCp = 700

    // Brilliant.
    static let brilliantMaxLoss = 0.005
    static let brilliantMaxLossNewPlayer = 0.01
    static let sacrificeMinMaterial = 2
    static let sacrificeMinMaterialNewPlayer = 1
    static let sacrificeHorizonPlies = 6

    /// Below this rating Great and Brilliant are more generous, as the published rules ask.
    static let newPlayerRating = 1200

    // Which plies get the deep second pass.
    static let nearBandFraction = 0.15
    static let deepOpponentLoss = 0.025
    static let deepCandidateMaxEP = 0.70
    /// A quick look at a top move goes on to the full search only with a gap of at least this.
    static let probeEscalateGap = 0.025
    /// A deep eval replaces the shallow one in the accuracy only past this many win percent apart.
    static let deepOverridesWinPercent = 20.0

    /// How far along a line the coach attributes material to a move, in plies after that move.
    static let coachLineHorizon = 5
    /// A capture, the reply and the follow-up: as far as a gain or a threat is credited to one move.
    static let shortLineHorizon = 3
    /// What a null-move line must win in that span, in pawns, to count as a threat.
    static let threatMinMaterial = 2

    static let retryTolerance = 0.02
}

/// Winning chances from the mover's rating and the engine score: EP(cp) = 1 / (1 + exp(-k * cp)).
///
/// The function is unpublished, so this is our own curve. Lichess's k = 0.00368208 was fitted on
/// the Stockfish cp scale of June 2022. Stockfish 15.1 then redefined the scale so that +1.00 is a
/// 50% win chance: the same internal value now prints about 0.58 times the cp, which makes the
/// equivalent k about 0.0064 at master level. It falls with rating because weaker players convert
/// less often. The low anchor also satisfies the one rating sweep on record (a move from -4.25 to
/// mated in 5 labelled Blunder near 670, Mistake near 1670, Inaccuracy near 2670), which is thin
/// evidence, so treat every number here as a stand-in.
///
/// TODO: refit k per rating bucket with the shipped engine and node budget on positions sampled
/// from the CC0 Lichess database. Do not reuse embedded %eval across eras, that mixes scales.
enum ExpectedPoints {
    /// k at the median rating of each 200-point band, fitted on Lichess games by tools/calibration: see docs/CALIBRATION.md.
    static let kTable: [(rating: Int, k: Double)] = [
        (733, 0.00159),
        (927, 0.00183),
        (1113, 0.00195),
        (1309, 0.00207),
        (1505, 0.00214),
        (1697, 0.00238),
        (1889, 0.00259),
        (2077, 0.00296),
        (2267, 0.00361),
        (2489, 0.00389),
    ]
    /// Used when a game has no Elo headers and the player's own rating is unknown.
    static let defaultRating = 1500
    static let cpCeiling = 1000

    // Mate runs through the same curve, since evidence is against fixed mate-distance tables.
    // Each move further from mate is worth 100 cp less, down to the cp ceiling at mate in 15.
    static let mateInZeroCp = 2500
    static let mateStepCp = 100

    static func k(rating: Int?) -> Double {
        let r = rating ?? defaultRating
        guard let i = kTable.firstIndex(where: { r <= $0.rating }) else { return kTable[kTable.count - 1].k }
        guard i > 0 else { return kTable[0].k }
        let a = kTable[i - 1], b = kTable[i]
        return a.k + (b.k - a.k) * Double(r - a.rating) / Double(b.rating - a.rating)
    }

    /// The chances of the side the score is written for, so `.mate(0)` means that side is mated.
    static func of(_ score: Score, rating: Int?) -> Double {
        let cp: Int
        switch score {
        case .cp(let c): cp = min(max(c, -cpCeiling), cpCeiling)
        case .mate(0): return 0
        case .mate(let n): cp = n > 0 ? mateCp(n) : -mateCp(-n)
        }
        return 1 / (1 + exp(-k(rating: rating) * Double(cp)))
    }

    static func mateCp(_ moves: Int) -> Int { max(cpCeiling, mateInZeroCp - mateStepCp * moves) }

    enum Zone: Comparable { case losing, equal, winning }

    /// The winning, equal and losing cut-offs. In centipawns they move with rating, through k.
    static func zone(_ ep: Double) -> Zone {
        ep >= Thresholds.winningFrom ? .winning : ep < Thresholds.losingBelow ? .losing : .equal
    }

    static func loss(best: Score, played: Score, rating: Int?) -> Double {
        max(0, of(best, rating: rating) - of(played, rating: rating))
    }
}

extension Score {
    /// The same evaluation from the other side. Mated flips to mate in one, the nearest signed value.
    var flipped: Score {
        switch self {
        case .cp(let c): return .cp(-c)
        case .mate(0): return .mate(1)
        case .mate(let n): return .mate(-n)
        }
    }

    var isMating: Bool {
        if case .mate(let n) = self { return n > 0 }
        return false
    }

    var isMated: Bool {
        if case .mate(let n) = self { return n <= 0 }
        return false
    }

    /// Reads a side-to-move score from White's point of view.
    func whitePOV(sideToMove: Side) -> Score { sideToMove == .white ? self : flipped }
}

// MARK: - Board facts

extension PieceKind {
    /// Exchange value in pawns. The king outranks everything but never counts as material.
    var pointValue: Int {
        switch self {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 100
        }
    }
}

extension Position {
    func squares(of side: Side) -> [Square] {
        (0..<64).filter { piece(at: $0)?.side == side }
    }

    var pieceCount: Int { (0..<64).reduce(0) { $0 + (piece(at: $1) == nil ? 0 : 1) } }

    func materialBalance(for side: Side) -> Int {
        var balance = 0
        for s in 0..<64 {
            guard let p = piece(at: s), p.kind != .king else { continue }
            balance += p.side == side ? p.kind.pointValue : -p.kind.pointValue
        }
        return balance
    }

    /// The piece a move takes and where it stands, which differs from `to` for en passant.
    func captured(by m: Move) -> (piece: Piece, square: Square)? {
        if let p = piece(at: m.to) { return (p, m.to) }
        guard piece(at: m.from)?.kind == .pawn, m.from % 8 != m.to % 8 else { return nil }
        let s = m.to + (side == .white ? -8 : 8)
        return piece(at: s).map { ($0, s) }
    }

    /// The side to move passes. Nil when it is in check, which has no legal null move:
    /// the FEN would let the other side capture the king, so Position rejects it.
    var nullMoved: Position? {
        var fields = fen.split(separator: " ").map(String.init)
        guard fields.count == 6 else { return nil }
        fields[1] = side == .white ? "b" : "w"
        fields[3] = "-"
        return Position(fen: fields.joined(separator: " "))
    }

    /// Squares a piece strikes, whoever stands there, own pieces included.
    func attackedSquares(from s: Square) -> [Square] {
        guard let p = piece(at: s) else { return [] }
        let f = s % 8, r = s / 8
        var out: [Square] = []
        func step(_ df: Int, _ dr: Int) {
            let nf = f + df, nr = r + dr
            if (0..<8).contains(nf), (0..<8).contains(nr) { out.append(nr * 8 + nf) }
        }
        switch p.kind {
        case .pawn:
            let dr = p.side == .white ? 1 : -1
            step(-1, dr); step(1, dr)
        case .knight:
            for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)] { step(df, dr) }
        case .king:
            for (df, dr) in [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)] { step(df, dr) }
        case .bishop, .rook, .queen:
            for (df, dr) in p.kind.lineSteps { out += ray(from: s, df, dr).squares }
        }
        return out
    }

    /// Squares along a line up to and including the first piece.
    func ray(from s: Square, _ df: Int, _ dr: Int) -> (squares: [Square], blocker: Square?) {
        var f = s % 8 + df, r = s / 8 + dr
        var out: [Square] = []
        while (0..<8).contains(f), (0..<8).contains(r) {
            let t = r * 8 + f
            out.append(t)
            if piece(at: t) != nil { return (out, t) }
            f += df
            r += dr
        }
        return (out, nil)
    }

    /// Pinned to its own king, unless the capture of `target` stays on the pin line.
    private func isPinned(_ s: Square, capturing target: Square) -> Bool {
        guard let p = piece(at: s), p.kind != .king, let k = king(of: p.side),
              let (df, dr) = lineStep(from: k, to: s) else { return false }
        guard ray(from: k, df, dr).blocker == s, let behind = ray(from: s, df, dr).blocker,
              let slider = piece(at: behind), slider.side != p.side,
              slider.kind.lineSteps.contains(where: { $0 == (df, dr) }) else { return false }
        if let along = lineStep(from: k, to: target), along == (df, dr) { return false }
        return true
    }

    /// Who can really take or retake on a square: pinned pieces drop out, and if the taker's side is
    /// to move so does anything that leaves its king in check. An adjacent king always counts, as
    /// the safety rule weighs it even when it could not recapture.
    func directAttackers(of s: Square, by attacker: Side) -> [Square] {
        attackers(of: s, by: attacker).filter { a in
            guard let p = piece(at: a), p.kind != .king else { return true }
            if attacker == side, piece(at: s)?.side != attacker {
                let promotion: PieceKind? = p.kind == .pawn && (s / 8 == 0 || s / 8 == 7) ? .queen : nil
                return isLegal(Move(from: a, to: s, promotion: promotion))
            }
            return !isPinned(a, capturing: s)
        }
    }

    /// Direct attackers plus the batteries lined up behind them.
    private func allAttackers(of s: Square, by attacker: Side) -> [Square] {
        var out = directAttackers(of: s, by: attacker)
        for a in out {
            guard piece(at: a)?.kind != .king, piece(at: a)?.kind != .knight, let (df, dr) = lineStep(from: s, to: a) else { continue }
            var front = a
            while let next = ray(from: front, df, dr).blocker, let p = piece(at: next), p.side == attacker,
                  p.kind.lineSteps.contains(where: { $0 == (df, dr) }) {
                out.append(next)
                front = next
            }
        }
        return out
    }

    /// Whether a piece can stay where it stands.
    func isPieceSafe(at s: Square) -> Bool {
        guard let p = piece(at: s) else { return true }
        let direct = directAttackers(of: s, by: p.side.opposite)
        if direct.isEmpty { return true }
        let value = p.kind.pointValue
        let attackerValues = direct.compactMap { piece(at: $0)?.kind.pointValue }
        let cheapest = attackerValues.min() ?? 100
        if cheapest < value { return false }

        let attackers = allAttackers(of: s, by: p.side.opposite)
        let defenders = allAttackers(of: s, by: p.side)
        if attackers.count <= defenders.count { return true }

        let defenderValues = defenders.compactMap { piece(at: $0)?.kind.pointValue }
        if value < cheapest, defenderValues.contains(where: { $0 < cheapest }) { return true }
        return defenders.contains { piece(at: $0)?.kind == .pawn }
    }

    /// Pieces of a side that can be taken with profit. Pawns and the king never count, nor does
    /// anything worth no more than what the last move captured, since that is an even trade.
    func unsafePieces(of side: Side, captured: Piece? = nil) -> [Square] {
        let floor = captured?.kind.pointValue ?? 0
        return squares(of: side).filter { s in
            guard let p = piece(at: s), p.kind != .pawn, p.kind != .king, p.kind.pointValue > floor else { return false }
            // A rook attacked once by a knight after taking a knight is a favourable trade of two pieces.
            if p.kind == .rook, captured?.kind == .knight {
                let takers = allAttackers(of: s, by: side.opposite)
                if takers.count == 1, piece(at: takers[0])?.kind == .knight, !allAttackers(of: s, by: side).isEmpty { return false }
            }
            return !isPieceSafe(at: s)
        }
    }

    /// Attacked with no safe flight. It needs its own side on move, so a check on the other king hides it.
    func isTrapped(at s: Square) -> Bool {
        guard let p = piece(at: s), !isPieceSafe(at: s) else { return false }
        guard let board = p.side == side ? self : nullMoved else { return false }
        return board.legalMoves(from: s).allSatisfy { !board.applying($0).isPieceSafe(at: $0.to) }
    }

    func mateInOneExists() -> Bool {
        legalMoves().contains { applying($0).isCheckmate }
    }
}

extension PieceKind {
    fileprivate static let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    fileprivate static let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    /// Directions a slider moves along. Empty for the others.
    var lineSteps: [(Int, Int)] {
        switch self {
        case .rook: return Self.straight
        case .bishop: return Self.diagonal
        case .queen: return Self.straight + Self.diagonal
        default: return []
        }
    }
}

/// The unit step from one square to another if they share a line.
func lineStep(from a: Square, to b: Square) -> (Int, Int)? {
    guard a != b else { return nil }
    let df = b % 8 - a % 8, dr = b / 8 - a / 8
    guard df == 0 || dr == 0 || abs(df) == abs(dr) else { return nil }
    return (df.signum(), dr.signum())
}

/// What a line of moves does to the material of the pieces involved.
struct MaterialOutcome: Hashable {
    /// Change of `side`'s balance. Positive means it comes out ahead.
    var net = 0
    var lost: [PieceKind: Int] = [:]
    var won: [PieceKind: Int] = [:]

    /// Plays the line, running on past the horizon while captures continue. If it stops on a capture
    /// that would simply be retaken, the capturing piece is written off as well.
    init(from start: Position, line: [Move], side: Side, horizon: Int = Thresholds.lineHorizonPlies) {
        var pos = start
        var last: Move?
        for (i, m) in line.enumerated() {
            guard pos.isLegal(m) else { break }
            if i >= horizon, pos.captured(by: m) == nil { break }
            let taken = pos.captured(by: m)?.piece
            last = taken == nil ? nil : m
            pos = pos.applying(m)
        }
        net = pos.materialBalance(for: side) - start.materialBalance(for: side)
        for kind in PieceKind.allCases where kind != .king {
            let mine = count(kind, of: side, in: start) - count(kind, of: side, in: pos)
            let theirs = count(kind, of: side.opposite, in: start) - count(kind, of: side.opposite, in: pos)
            if mine > 0 { lost[kind] = mine }
            if theirs > 0 { won[kind] = theirs }
        }
        if let m = last, let taker = pos.piece(at: m.to), !pos.isPieceSafe(at: m.to) {
            if taker.side == side {
                net -= taker.kind.pointValue
                lost[taker.kind, default: 0] += 1
            } else {
                net += taker.kind.pointValue
                won[taker.kind, default: 0] += 1
            }
        }
    }

    private func count(_ kind: PieceKind, of side: Side, in p: Position) -> Int {
        (0..<64).reduce(0) { $0 + (p.piece(at: $1) == Piece(kind: kind, side: side) ? 1 : 0) }
    }
}

// MARK: - Classifier

/// One played move with its engine values, all from the mover's point of view. Plain data so that
/// tests can feed hand-written evals and the classifier never touches the engine.
struct MoveFacts {
    struct Previous {
        var before: Position
        var move: Move
        /// Expected points the opponent lost with `move`.
        var epLost: Double
        /// The eval before `move`, from this mover's point of view.
        var evalBefore: Score?
    }

    var before: Position
    var move: Move
    var rating: Int?
    var isBook = false
    var best: Score
    var bestMove: Move?
    var bestLine: [Move] = []
    var played: Score
    /// Runner-up from MultiPV 2. Nil without a deep search, and then no Great or Brilliant.
    var second: Score?
    /// Engine line after the move, opponent's reply first.
    var refutation: [Move] = []
    var previous: Previous?
    /// When the game is in the middle of an exchange: the position before its first capture, and the
    /// captures since. Material is counted from there, so that retaking a piece is not winning one.
    var exchangeStart: Position?
    var exchange: [Move] = []

    var after: Position { before.applying(move) }
    var mover: Side { before.side }
    var isTopMove: Bool { move == bestMove }
    var epBest: Double { ExpectedPoints.of(best, rating: rating) }
    var epPlayed: Double { ExpectedPoints.of(played, rating: rating) }
    var epLoss: Double { isTopMove ? 0 : ExpectedPoints.loss(best: best, played: played, rating: rating) }
    var isNewPlayer: Bool { (rating ?? ExpectedPoints.defaultRating) < Thresholds.newPlayerRating }

    /// Takes back on the square where the opponent just captured.
    var isRecapture: Bool {
        guard let previous, let taken = before.captured(by: move) else { return false }
        return previous.move.to == taken.square && previous.before.captured(by: previous.move) != nil
    }

    /// What a line from here does to the mover's material, counted from before any exchange under way.
    func outcome(of line: [Move], horizon: Int = Thresholds.lineHorizonPlies) -> MaterialOutcome {
        MaterialOutcome(from: exchangeStart ?? before, line: exchange + line, side: mover, horizon: horizon + exchange.count)
    }
}

enum GreatReason: String, Codable, Sendable {
    case onlyMove, losingToEqual, equalToWinning
}

struct Classification: Hashable, Codable, Sendable {
    var moveClass: MoveClass
    var epLost: Double
    var secondBestGap: Double?
    var greatReason: GreatReason?
    /// Squares of the pieces offered, for a Brilliant.
    var sacrificed: [Square] = []
}

enum Classifier {
    /// The pipeline, in order: Forced, Book, mate delivered, bands, Blunder gate, Miss, Great, Brilliant.
    static func classify(_ f: MoveFacts) -> Classification {
        let loss = f.epLoss
        let gap = f.second.map { max(0, f.epBest - ExpectedPoints.of($0, rating: f.rating)) }
        func result(_ c: MoveClass, great: GreatReason? = nil, sacrificed: [Square] = []) -> Classification {
            Classification(moveClass: c, epLost: loss, secondBestGap: gap, greatReason: great, sacrificed: sacrificed)
        }

        if f.before.legalMoves().count == 1 { return result(.forced) }
        if f.isBook { return result(.book) }
        if f.after.isCheckmate { return result(.best) }

        var cls = band(loss: loss)
        var isRealBlunder = false
        if cls == .blunder {
            isRealBlunder = allowsMate(f) || losesMaterial(f)
            if !isRealBlunder { cls = .mistake }
        }
        if !f.isTopMove, !isRealBlunder, isMiss(f, loss: loss) { cls = .miss }

        var great: GreatReason?
        if f.isTopMove, let gap { great = greatReason(f, gap: gap) }
        if great != nil { cls = .great }

        if let gap, let offered = sacrifice(f, loss: loss, gap: gap) {
            return result(.brilliant, great: great, sacrificed: offered)
        }
        return result(cls, great: great)
    }

    static func band(loss: Double) -> MoveClass {
        if loss >= Thresholds.bandBlunder { return .blunder }
        if loss >= Thresholds.bandMistake { return .mistake }
        if loss >= Thresholds.bandInaccuracy { return .inaccuracy }
        if loss >= Thresholds.bandGood { return .good }
        return loss > 0 ? .excellent : .best
    }

    static func allowsMate(_ f: MoveFacts) -> Bool { f.played.isMated }

    static func losesMaterial(_ f: MoveFacts) -> Bool {
        f.outcome(of: [f.move] + f.refutation).net <= -Thresholds.blunderMinMaterial
    }

    /// Failing to punish the opponent's mistake, or letting a forced mate go.
    static func isMiss(_ f: MoveFacts, loss: Double) -> Bool {
        if f.best.isMating, !f.played.isMating, loss >= Thresholds.missLostMateMinLoss { return true }
        guard let previous = f.previous, previous.epLost >= Thresholds.missOpponentLoss else { return false }
        return (f.epBest >= Thresholds.winningFrom || f.best.isMating)
            && loss >= Thresholds.missMinLoss
            && f.epPlayed < Thresholds.winningFrom
    }

    static func onlyMoveGap(_ f: MoveFacts) -> Double {
        f.isNewPlayer ? Thresholds.onlyMoveGapNewPlayer : Thresholds.onlyMoveGap
    }

    /// Finding the second-best line would still be completely winning.
    private static func stillWinsAnyway(_ second: Score?) -> Bool {
        switch second {
        case .cp(let c)?: return c >= Thresholds.alreadyWinningCp
        case .mate(let n)?: return n > 0
        case nil: return true
        }
    }

    private static func greatReason(_ f: MoveFacts, gap: Double) -> GreatReason? {
        guard !stillWinsAnyway(f.second), !f.before.inCheck, f.move.promotion != .queen,
              f.previous?.evalBefore?.isMating != true else { return nil }
        if f.isRecapture { return nil }
        if let taken = f.before.captured(by: f.move), !f.before.isPieceSafe(at: taken.square) { return nil }
        if let earlier = f.previous?.evalBefore, gap >= Thresholds.turnaroundMinGap {
            let was = ExpectedPoints.of(earlier, rating: f.rating), now = f.epPlayed
            if was < Thresholds.losingBelow, now >= Thresholds.losingBelow { return .losingToEqual }
            if was >= Thresholds.losingBelow, was < Thresholds.winningFrom, now >= Thresholds.winningFrom { return .equalToWinning }
        }
        // The only good move decides something: without it the position lands in a worse zone.
        guard gap >= onlyMoveGap(f), f.epPlayed >= Thresholds.greatMinEPAfter, let second = f.second,
              ExpectedPoints.zone(ExpectedPoints.of(second, rating: f.rating)) < ExpectedPoints.zone(f.epBest) else { return nil }
        return .onlyMove
    }

    /// The pieces given up when the move is a sound sacrifice, or nil.
    static func sacrifice(_ f: MoveFacts, loss: Double, gap: Double) -> [Square]? {
        let new = f.isNewPlayer
        guard loss < (new ? Thresholds.brilliantMaxLossNewPlayer : Thresholds.brilliantMaxLoss),
              f.epPlayed >= Thresholds.greatMinEPAfter, !stillWinsAnyway(f.second),
              f.move.promotion == nil, !f.before.inCheck else { return nil }
        // In the endgame the sacrifice must be the only good move, earlier it may be one of several.
        if PhaseDivider.majorsAndMinors(f.before) <= PhaseDivider.endgameMaterial, gap < onlyMoveGap(f) { return nil }

        let after = f.after, mover = f.mover
        let taken = f.before.captured(by: f.move)?.piece
        let earlier = f.before.unsafePieces(of: mover)
        let now = after.unsafePieces(of: mover, captured: taken)
        guard !now.isEmpty else { return nil }
        // Moving a piece out of danger is the opposite of a sacrifice, unless it comes with check.
        if !after.inCheck, now.count < earlier.count { return nil }

        if !new {
            if now.allSatisfy({ takingLeavesCounterHit(after, piece: $0) }) { return nil }
            let earlierTrapped = earlier.filter { f.before.isTrapped(at: $0) }
            let nowTrapped = now.filter { after.isTrapped(at: $0) }
            // A piece that was lost anyway costs nothing to offer.
            if nowTrapped.count == now.count || earlierTrapped.contains(f.move.from) || nowTrapped.count < earlierTrapped.count {
                return nil
            }
        }
        guard lineConfirmsSacrifice(f, offered: now, minMaterial: new ? Thresholds.sacrificeMinMaterialNewPlayer : Thresholds.sacrificeMinMaterial) else {
            return nil
        }
        return now
    }

    /// True when every capture of the piece walks into an equal or bigger hit, or a mate in one.
    /// Such a piece is defended by tactics rather than offered.
    private static func takingLeavesCounterHit(_ after: Position, piece s: Square) -> Bool {
        guard let value = after.piece(at: s)?.kind.pointValue else { return true }
        let takes = after.legalMoves().filter { $0.to == s }
        return takes.allSatisfy { m in
            let next = after.applying(m)
            let taker = after.side
            let hit = next.unsafePieces(of: taker).contains { t in
                t != m.to && (next.piece(at: t)?.kind.pointValue ?? 0) >= value
            }
            return hit || (value < PieceKind.queen.pointValue && next.mateInOneExists())
        }
    }

    /// The engine line must show the material really going, or the opponent really declining it.
    private static func lineConfirmsSacrifice(_ f: MoveFacts, offered: [Square], minMaterial: Int) -> Bool {
        let baseline = f.before.materialBalance(for: f.mover)
        var pos = f.after
        for (i, m) in f.refutation.prefix(Thresholds.sacrificeHorizonPlies).enumerated() {
            guard pos.isLegal(m) else { return false }
            let next = pos.applying(m)
            if baseline - next.materialBalance(for: f.mover) >= minMaterial {
                // Won straight back is a trade, not a sacrifice.
                if i + 1 < f.refutation.count, next.isLegal(f.refutation[i + 1]),
                   next.applying(f.refutation[i + 1]).materialBalance(for: f.mover) >= baseline {
                    return false
                }
                return true
            }
            pos = next
        }
        guard let reply = f.refutation.first, f.after.isLegal(reply) else { return false }
        let next = f.after.applying(reply)
        return offered.contains { next.piece(at: $0)?.side == f.mover && !next.isPieceSafe(at: $0) }
    }
}

/// A retried move is accepted within 0.04 expected points of best, or if it mates.
/// Scores from the retrying player's point of view.
enum RetryCheck {
    static func accepts(best: Score, retried: Score, rating: Int?) -> Bool {
        if retried.isMating { return true }
        return ExpectedPoints.loss(best: best, played: retried, rating: rating) <= Thresholds.retryTolerance
    }
}
