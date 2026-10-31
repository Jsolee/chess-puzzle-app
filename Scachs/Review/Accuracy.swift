import Foundation

// Accuracy follows the formula Lichess publishes, reimplemented from its description and numbers.
// It keeps Lichess's fixed k for every rating on purpose: this is their maths, not our EP curve.
// Maths and PhaseDivider below are ported from scalalib and scalachess under the MIT licence:
//
//   Copyright (c) 2012-2014 Thibault Duplessis (scalachess); Copyright (c) Thibault Duplessis (scalalib)
//
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software
//   and associated documentation files (the "Software"), to deal in the Software without restriction,
//   including without limitation the rights to use, copy, modify, merge, publish, distribute,
//   sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions: The above copyright notice and this
//   permission notice shall be included in all copies or substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
//   BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//   DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

enum Maths {
    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func harmonicMean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : Double(values.count) / values.reduce(0) { $0 + 1 / max(1, $1) }
    }

    static func weightedMean(_ pairs: [(value: Double, weight: Double)]) -> Double? {
        let total = pairs.reduce(0) { $0 + $1.weight }
        return total == 0 ? nil : pairs.reduce(0) { $0 + $1.value * $1.weight } / total
    }

    /// Population standard deviation.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard let m = mean(values) else { return nil }
        return (values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)).squareRoot()
    }
}

enum Accuracy {
    static let winMultiplier = 0.00368208
    static let cpCeiling = 1000
    static let curveScale = 103.1668100711649
    static let curveDecay = 0.04354415386753951
    static let curveOffset = -3.166924740191411
    /// Lichess's bonus for imperfect analysis. It is in their code but not on their docs page.
    static let uncertaintyBonus = 1.0
    static let minWindow = 2
    static let maxWindow = 8
    static let minWeight = 0.5
    static let maxWeight = 12.0

    static func winPercent(cp: Int) -> Double {
        let c = Double(min(max(cp, -cpCeiling), cpCeiling))
        return 50 + 50 * (2 / (1 + exp(-winMultiplier * c)) - 1)
    }

    /// White's centipawns for a White-POV score, mate at the ceiling.
    static func whiteCp(_ score: Score) -> Int {
        switch score {
        case .cp(let c): return min(max(c, -cpCeiling), cpCeiling)
        case .mate(let n): return n > 0 ? cpCeiling : -cpCeiling
        }
    }

    static func winPercent(_ whiteScore: Score) -> Double { winPercent(cp: whiteCp(whiteScore)) }

    /// Win percentages from the mover's point of view.
    static func ofMove(winBefore: Double, winAfter: Double) -> Double {
        if winAfter >= winBefore { return 100 }
        let raw = curveScale * exp(-curveDecay * (winBefore - winAfter)) + curveOffset + uncertaintyBonus
        return min(max(raw, 0), 100)
    }

    /// Per-colour accuracy: the mean of a volatility-weighted mean and a harmonic mean, so that calm
    /// positions weigh little and one blunder hurts. `scores` are White-POV, one per position
    /// including the start; a gap only drops the moves that touch it.
    static func game(scores: [Score?], start: Side) -> (white: Double?, black: Double?) {
        let wins = scores.map { $0.map(winPercent) }
        guard wins.count >= 2 else { return (nil, nil) }

        let size = min(max((wins.count - 1) / 10, minWindow), maxWindow)
        var windows = Array(repeating: Array(wins.prefix(size)), count: size - minWindow)
        for i in 0...(wins.count - size) { windows.append(Array(wins[i..<(i + size)])) }

        var white: [(value: Double, weight: Double)] = []
        var black: [(value: Double, weight: Double)] = []
        for i in 0..<(wins.count - 1) {
            guard let previous = wins[i], let next = wins[i + 1] else { continue }
            let window = windows[i].compactMap { $0 }
            guard window.count == size, let deviation = Maths.standardDeviation(window) else { continue }
            let weight = min(max(deviation, minWeight), maxWeight)
            if (i % 2 == 0) == (start == .white) {
                white.append((ofMove(winBefore: previous, winAfter: next), weight))
            } else {
                black.append((ofMove(winBefore: next, winAfter: previous), weight))
            }
        }
        return (combined(white), combined(black))
    }

    private static func combined(_ pairs: [(value: Double, weight: Double)]) -> Double? {
        guard let weighted = Maths.weightedMean(pairs),
              let harmonic = Maths.harmonicMean(pairs.map(\.value)) else { return nil }
        return (weighted + harmonic) / 2
    }

    // MARK: Phases

    /// Plies of a phase, as position indices, sharing the boundary eval with the phase next door.
    static func phaseSlice(_ phase: GamePhase, division d: Division, positions: Int) -> Range<Int>? {
        let indices = (0..<positions).filter { d.phase(ofPly: $0) == phase || d.phase(ofPly: $0 + 1) == phase }
        guard let first = indices.first, let last = indices.last, last > first else { return nil }
        return first..<(last + 1)
    }

    static func phases(scores: [Score?], start: Side, division: Division) -> [PhaseAccuracy] {
        GamePhase.allCases.compactMap { phase in
            guard let slice = phaseSlice(phase, division: division, positions: scores.count) else { return nil }
            let sliceStart = slice.lowerBound % 2 == 0 ? start : start.opposite
            let result = game(scores: Array(scores[slice]), start: sliceStart)
            return PhaseAccuracy(phase: phase, plies: slice, white: result.white, black: result.black)
        }
    }

    // MARK: Game rating

    /// Average centipawn loss per side, each move capped at the ceiling.
    static func averageCentipawnLoss(scores: [Score?], start: Side) -> (white: Double?, black: Double?) {
        var totals: [Side: (sum: Int, count: Int)] = [.white: (0, 0), .black: (0, 0)]
        for i in 0..<max(scores.count - 1, 0) {
            guard let a = scores[i], let b = scores[i + 1] else { continue }
            let mover: Side = (i % 2 == 0) == (start == .white) ? .white : .black
            let drop = mover == .white ? whiteCp(a) - whiteCp(b) : whiteCp(b) - whiteCp(a)
            totals[mover]!.sum += min(max(drop, 0), cpCeiling)
            totals[mover]!.count += 1
        }
        func average(_ side: Side) -> Double? {
            let t = totals[side]!
            return t.count == 0 ? nil : Double(t.sum) / Double(t.count)
        }
        return (average(.white), average(.black))
    }

    /// A playful guess at the level of one game, not a rating. It uses an approximation published on
    /// the Lichess forum, and that same thread shows ACPL correlates weakly with strength, so the
    /// UI must present it as a bit of fun.
    static func estimatedGameRating(acpl: Double, rating: Int?) -> Int {
        let ceiling = 3100.0, slope = 0.005
        guard let rating, rating > 0 else { return Int((ceiling * exp(-0.01 * acpl)).rounded()) }
        let r = Double(rating)
        let expected = -100 * log(min(r, ceiling) / ceiling)
        let estimate = acpl >= expected ? r * exp(-slope * (acpl - expected)) : r / exp(-slope * (expected - acpl))
        return Int(estimate.rounded())
    }
}

// MARK: - Phases

enum GamePhase: String, Codable, CaseIterable, Sendable {
    case opening, middlegame, endgame

    var displayName: String {
        switch self {
        case .opening: return String(localized: "Obertura")
        case .middlegame: return String(localized: "Mig joc")
        case .endgame: return String(localized: "Final")
        }
    }
}

struct PhaseAccuracy: Hashable, Sendable {
    var phase: GamePhase
    var plies: Range<Int>
    var white: Double?
    var black: Double?
}

/// Where the middlegame and endgame start, as indices into the list of boards from the start position.
struct Division: Hashable, Codable, Sendable {
    var middle: Int?
    var end: Int?
    var plies: Int

    /// A game that never reaches a later phase is all opening.
    func phase(ofPly ply: Int) -> GamePhase {
        if let boundary = middle ?? end, ply >= boundary {
            if let end, end <= ply { return .endgame }
            return .middlegame
        }
        return .opening
    }
}

enum PhaseDivider {
    static let middlegameMaterial = 10
    static let endgameMaterial = 6
    static let backRankPieces = 4
    static let middlegameMixedness = 150

    static func divide(_ boards: [Position]) -> Division {
        let midGame = boards.firstIndex {
            majorsAndMinors($0) <= middlegameMaterial || isBackRankSparse($0) || mixedness($0) > middlegameMixedness
        }
        let endGame = midGame == nil ? nil : boards.firstIndex { majorsAndMinors($0) <= endgameMaterial }
        let middle = midGame.flatMap { m in endGame.map { m < $0 } ?? true ? m : nil }
        return Division(middle: middle, end: endGame, plies: boards.count)
    }

    static func majorsAndMinors(_ board: Position) -> Int {
        (0..<64).reduce(0) { total, s in
            guard let kind = board.piece(at: s)?.kind, kind != .king, kind != .pawn else { return total }
            return total + 1
        }
    }

    // A sparse back rank means the pieces have been developed.
    private static func isBackRankSparse(_ board: Position) -> Bool {
        let white = (0..<8).filter { board.piece(at: $0)?.side == .white }.count
        let black = (56..<64).filter { board.piece(at: $0)?.side == .black }.count
        return white < backRankPieces || black < backRankPieces
    }

    private static func mixedness(_ board: Position) -> Int {
        var total = 0
        for y in 0..<7 {
            for x in 0..<7 {
                var white = 0, black = 0
                for s in [x + 8 * y, x + 1 + 8 * y, x + 8 * (y + 1), x + 1 + 8 * (y + 1)] {
                    switch board.piece(at: s)?.side {
                    case .white?: white += 1
                    case .black?: black += 1
                    case nil: break
                    }
                }
                total += mixednessScore(y: y + 1, white: white, black: black)
            }
        }
        return total
    }

    private static func mixednessScore(y: Int, white: Int, black: Int) -> Int {
        switch (white, black) {
        case (0, 1): return 1 + y
        case (0, 2): return y < 6 ? 2 + (6 - y) : 0
        case (0, 3), (0, 4): return y < 7 ? 3 + (7 - y) : 0
        case (1, 0): return 1 + (8 - y)
        case (1, 1): return 5 + abs(4 - y)
        case (1, 2): return 4 + (7 - y)
        case (1, 3): return 5 + (7 - y)
        case (2, 0): return y > 2 ? 2 + (y - 2) : 0
        case (2, 1): return 4 + (y - 1)
        case (2, 2): return 7
        case (3, 0), (4, 0): return y > 1 ? 3 + (y - 1) : 0
        case (3, 1): return 5 + (y - 1)
        default: return 0
        }
    }
}

/// Phase grades are our own guess, since the published report card gives no mapping.
enum PhaseGrade {
    static let bestFrom = 95.0
    static let excellentFrom = 85.0
    static let goodFrom = 75.0
    static let inaccuracyFrom = 60.0
    static let mistakeFrom = 45.0
    /// White win% outside 10...90 counts as one side being far ahead.
    static let decisiveWinPercent = 90.0
    /// A phase spent mostly in a decided position says little, so it gets no grade.
    static let skipDecisiveShare = 0.75

    static func grade(accuracy: Double, hasBrilliant: Bool, hasGreat: Bool) -> MoveClass {
        if accuracy >= excellentFrom {
            if hasBrilliant { return .brilliant }
            if hasGreat { return .great }
        }
        if accuracy >= bestFrom { return .best }
        if accuracy >= excellentFrom { return .excellent }
        if accuracy >= goodFrom { return .good }
        if accuracy >= inaccuracyFrom { return .inaccuracy }
        if accuracy >= mistakeFrom { return .mistake }
        return .blunder
    }

    static func isDecided(whiteScores: [Score]) -> Bool {
        guard !whiteScores.isEmpty else { return false }
        let decided = whiteScores.filter {
            let w = Accuracy.winPercent($0)
            return w >= decisiveWinPercent || w <= 100 - decisiveWinPercent
        }
        return Double(decided.count) / Double(whiteScores.count) >= skipDecisiveShare
    }
}
