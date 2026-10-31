import Foundation

/// Glicko-2 with one elapsed period per puzzle and frozen puzzle ratings, using Lichess's constants.
enum Glicko2 {
    struct Rating: Codable, Equatable {
        var rating: Double
        var deviation: Double
        var volatility: Double
        static let start = Rating(rating: 1500, deviation: 500, volatility: 0.09)
    }

    static let tau = 0.75
    static let scale = 173.7178
    static let tolerance = 1e-6
    static let puzzleDeviation = 78.0
    static let decayPerDay = 0.21436
    static let provisionalDeviation = 110.0
    private static let maxMove = 700.0
    /// Glicko's g(phi) for the frozen puzzle deviation.
    private static let g: Double = {
        let phi = puzzleDeviation / scale
        return 1 / sqrt(1 + 3 * phi * phi / (Double.pi * Double.pi))
    }()

    /// `weight` averages the computed rating, deviation and volatility with the old ones.
    static func update(_ r: Rating, puzzle: Int, solved: Bool, weight: Double = 1) -> Rating {
        let mu = (r.rating - 1500) / scale, phi = r.deviation / scale
        let opponent = (Double(puzzle) - 1500) / scale
        let expected = 1 / (1 + exp(-g * (mu - opponent)))
        let v = 1 / (g * g * expected * (1 - expected))
        let s = solved ? 1.0 : 0.0
        let delta = v * g * (s - expected)

        let a = log(r.volatility * r.volatility)
        func f(_ x: Double) -> Double {
            let ex = exp(x), d = phi * phi + v + ex
            return ex * (delta * delta - phi * phi - v - ex) / (2 * d * d) - (x - a) / (tau * tau)
        }
        var lo = a
        var hi: Double
        if delta * delta > phi * phi + v {
            hi = log(delta * delta - phi * phi - v)
        } else {
            var k = 1.0
            while f(a - k * tau) < 0 { k += 1 }
            hi = a - k * tau
        }
        var fLo = f(lo), fHi = f(hi), rounds = 0
        while abs(hi - lo) > tolerance && rounds < 100 {
            let mid = lo + (lo - hi) * fLo / (fHi - fLo), fMid = f(mid)
            if fMid * fHi <= 0 { lo = hi; fLo = fHi } else { fLo /= 2 }
            hi = mid; fHi = fMid
            rounds += 1
        }
        let volatility = exp(lo / 2)
        let phiStar = sqrt(phi * phi + volatility * volatility)
        let newPhi = 1 / sqrt(1 / (phiStar * phiStar) + 1 / v)
        let newMu = mu + newPhi * newPhi * g * (s - expected)

        let rating = r.rating + weight * (newMu * scale + 1500 - r.rating)
        return Rating(
            rating: max(400, min(r.rating + maxMove, max(r.rating - maxMove, rating))),
            deviation: min(500, max(45, r.deviation + weight * (newPhi * scale - r.deviation))),
            volatility: min(0.1, r.volatility + weight * (volatility - r.volatility))
        )
    }

    /// The deviation after `days` without playing: phi^2 grows by days * 0.21436 * vol^2.
    static func liveDeviation(_ r: Rating, days: Double) -> Double {
        let phi = r.deviation / scale
        let grown = sqrt(phi * phi + max(days, 0) * decayPerDay * r.volatility * r.volatility) * scale
        return min(500, max(45, grown))
    }

    /// Rating points below the player that give a success probability of `p` against a frozen puzzle.
    static func gap(forSuccess p: Double) -> Double {
        scale * log(p / (1 - p)) / g
    }

    /// Weight of a result when the player knew the theme; `nil` means a blind mix.
    static func weight(theme: String?, solved: Bool) -> Double {
        guard let theme else { return 1 }
        if isObvious(theme) { return solved ? 0.1 : 0.4 }
        if nonHinting.contains(theme) { return solved ? 0.7 : 0.8 }
        return solved ? 0.2 : 0.7
    }

    private static func isObvious(_ theme: String) -> Bool {
        theme.hasSuffix("Mate") || ["mateIn1", "enPassant", "attackingF2F7", "doubleCheck", "castling"].contains(theme)
    }

    private static let nonHinting: Set<String> = [
        "opening", "middlegame", "endgame", "rookEndgame", "bishopEndgame", "knightEndgame", "queenEndgame",
        "pawnEndgame", "queenRookEndgame", "master", "masterVsMaster", "superGM",
    ]
}
