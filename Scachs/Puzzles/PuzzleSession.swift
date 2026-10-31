import Foundation

/// Ten puzzles: warm-up, core, one stretch, and up to two due retries that otherwise become core puzzles.
final class PuzzleSession {
    private enum Slot { case warmUp, core, stretch, retry(Int) }

    private let progress: Progress
    private let store: PuzzleStore
    private let slots: [Slot]
    private(set) var results: [Bool?]
    var harderBias = 0

    private var cursor = 0
    private var serving: (Puzzle, AttemptContext)?
    private var recentMotifs: [String] = []
    private var whites = 0, blacks = 0

    private static let biasPoints = 100

    init(progress: Progress, store: PuzzleStore) {
        self.progress = progress
        self.store = store
        var due = progress.dueRetries(limit: 2).compactMap(store.index(ofID:)).map(Slot.retry)[...]
        slots = [.warmUp, .core, .core, due.popFirst() ?? .core, .core, .core, due.popFirst() ?? .core, .stretch, .core, .core]
        results = Array(repeating: nil, count: slots.count)
    }

    var current: Int { min(cursor, results.count - 1) }

    /// The puzzle for the current slot; the same one until `finish` is called. Nil when the session is over.
    func next() -> (Puzzle, AttemptContext)? {
        if let serving { return serving }
        guard cursor < slots.count else { return nil }
        let picked: (Puzzle, AttemptContext)
        switch slots[cursor] {
        case .warmUp: picked = (pick(success: 0.85), .blind)
        case .core: picked = (pick(success: Double.random(in: 0.70...0.75)), .blind)
        case .stretch: picked = (pick(success: 0.50), .blind)
        case .retry(let i): picked = (store.puzzle(at: i), .retry)
        }
        if picked.0.solverSide == .white { whites += 1 } else { blacks += 1 }
        recentMotifs.append(ThemeNames.primaryTag(of: picked.0.themes))
        serving = picked
        return picked
    }

    func finish(solved: Bool) {
        guard serving != nil else { return }
        results[cursor] = solved
        cursor += 1
        serving = nil
    }

    private func pick(success p: Double) -> Puzzle {
        let target = Int((progress.rating - Glicko2.gap(forSuccess: p)).rounded()) + harderBias * Self.biasPoints
        let side: Side? = whites > blacks ? .black : blacks > whites ? .white : nil
        let last = recentMotifs.suffix(2)
        let tired = last.count == 2 && last.first == last.last ? last.first : nil
        let found = store.find(target: target, anyOf: nil) { i in
            if progress.played(i) { return true }
            if let side, store.solverSide(at: i) != side { return true }
            if let tired, ThemeNames.primaryTag(of: store.themes(at: i)) == tired { return true }
            return false
        }
        // Only when every puzzle has been played: a replay beats an empty slot.
        return found ?? store.find(target: target, anyOf: nil) { _ in false }!
    }
}

/// Display names for the Lichess theme tags. Catalan source strings, written for this app.
enum ThemeNames {
    static func name(_ tag: String) -> String {
        switch tag {
        case "opening": return String(localized: "Obertura")
        case "middlegame": return String(localized: "Mig joc")
        case "endgame": return String(localized: "Final")
        case "rookEndgame": return String(localized: "Final de torres")
        case "bishopEndgame": return String(localized: "Final d'alfils")
        case "knightEndgame": return String(localized: "Final de cavalls")
        case "queenEndgame": return String(localized: "Final de dames")
        case "pawnEndgame": return String(localized: "Final de peons")
        case "queenRookEndgame": return String(localized: "Final de dama i torre")

        case "advancedPawn": return String(localized: "Peó avançat")
        case "attackingF2F7": return String(localized: "Atac a f2 o f7")
        case "capturingDefender": return String(localized: "Eliminació del defensor")
        case "discoveredAttack": return String(localized: "Atac a la descoberta")
        case "doubleCheck": return String(localized: "Escac doble")
        case "exposedKing": return String(localized: "Rei exposat")
        case "fork": return String(localized: "Forquilla")
        case "hangingPiece": return String(localized: "Peça penjada")
        case "kingsideAttack": return String(localized: "Atac al flanc de rei")
        case "queensideAttack": return String(localized: "Atac al flanc de dama")
        case "pin": return String(localized: "Clavada")
        case "sacrifice": return String(localized: "Sacrifici")
        case "skewer": return String(localized: "Enfilada")
        case "trappedPiece": return String(localized: "Peça atrapada")

        case "attraction": return String(localized: "Atracció")
        case "clearance": return String(localized: "Alliberament de línia")
        case "collinearMove": return String(localized: "Jugada col·lineal")
        case "discoveredCheck": return String(localized: "Escac a la descoberta")
        case "defensiveMove": return String(localized: "Jugada defensiva")
        case "deflection": return String(localized: "Desviació")
        case "interference": return String(localized: "Interferència")
        case "intermezzo": return String(localized: "Jugada intermèdia")
        case "quietMove": return String(localized: "Jugada tranquil·la")
        case "xRayAttack": return String(localized: "Atac de raigs X")
        case "zugzwang": return String(localized: "Zugzwang")

        case "mate": return String(localized: "Mat")
        case "mateIn1": return String(localized: "Mat en 1")
        case "mateIn2": return String(localized: "Mat en 2")
        case "mateIn3": return String(localized: "Mat en 3")
        case "mateIn4": return String(localized: "Mat en 4")
        case "mateIn5": return String(localized: "Mat en 5 o més")

        case "arabianMate": return String(localized: "Mat àrab")
        case "cornerMate": return String(localized: "Mat del racó")
        case "hookMate": return String(localized: "Mat del ganxo")
        case "smotheredMate": return String(localized: "Mat de la coça")
        case "vukovicMate": return String(localized: "Mat de Vuković")
        case "anastasiaMate": return String(localized: "Mat d'Anastàsia")
        case "backRankMate": return String(localized: "Mat del passadís")
        case "blindSwineMate": return String(localized: "Mat dels porcs cecs")
        case "dovetailMate": return String(localized: "Mat de la cua de milà")
        case "epauletteMate": return String(localized: "Mat de les xarreteres")
        case "killBoxMate": return String(localized: "Mat de la caixa")
        case "swallowstailMate": return String(localized: "Mat de la cua d'oreneta")
        case "triangleMate": return String(localized: "Mat del triangle")
        case "balestraMate": return String(localized: "Mat de la ballesta")
        case "bodenMate": return String(localized: "Mat de Boden")
        case "doubleBishopMate": return String(localized: "Mat dels dos alfils")
        case "pillsburysMate": return String(localized: "Mat de Pillsbury")
        case "morphysMate": return String(localized: "Mat de Morphy")
        case "operaMate": return String(localized: "Mat de l'òpera")

        case "castling": return String(localized: "Enroc")
        case "enPassant": return String(localized: "Captura al pas")
        case "promotion": return String(localized: "Promoció")
        case "underPromotion": return String(localized: "Subpromoció")

        case "equality": return String(localized: "Igualtat")
        case "advantage": return String(localized: "Avantatge")
        case "crushing": return String(localized: "Avantatge decisiu")

        case "oneMove": return String(localized: "Una jugada")
        case "short": return String(localized: "Dues jugades")
        case "long": return String(localized: "Tres jugades")
        case "veryLong": return String(localized: "Quatre jugades o més")

        case "master": return String(localized: "Partida de mestre")
        case "masterVsMaster": return String(localized: "Mestre contra mestre")
        case "superGM": return String(localized: "Partida de superGM")

        default: return tag
        }
    }

    /// The name to title a puzzle with once it is solved.
    static func primary(of themes: [String]) -> String { name(primaryTag(of: themes)) }

    /// True for tactical ideas and mate patterns; false for mate length, phase, goal, length and origin.
    static func isMotif(_ tag: String) -> Bool { (rank[tag] ?? .max) < rank["mateIn1", default: 0] }

    /// Most telling first: named patterns and motifs, then mate length, then phase.
    /// Context tags (attack on a wing, exposed king) sit last among the motifs because they say the least.
    static func primaryTag(of themes: [String]) -> String {
        var best = themes.first ?? "", bestRank = Int.max
        for t in themes {
            let r = rank[t] ?? Int.max - 1
            if r < bestRank { best = t; bestRank = r }
        }
        return best
    }

    private static let rank: [String: Int] = {
        let order = [
            "smotheredMate", "arabianMate", "anastasiaMate", "hookMate", "vukovicMate", "cornerMate", "backRankMate",
            "epauletteMate", "dovetailMate", "swallowstailMate", "triangleMate", "killBoxMate", "blindSwineMate",
            "bodenMate", "doubleBishopMate", "balestraMate", "pillsburysMate", "morphysMate", "operaMate",
            "underPromotion", "enPassant", "castling", "doubleCheck", "discoveredCheck", "zugzwang", "interference",
            "xRayAttack", "collinearMove", "clearance", "intermezzo", "attraction", "deflection", "capturingDefender",
            "skewer", "fork", "pin", "discoveredAttack", "trappedPiece", "quietMove", "defensiveMove", "hangingPiece",
            "promotion", "attackingF2F7", "sacrifice", "advancedPawn", "exposedKing", "kingsideAttack", "queensideAttack",
            "mateIn1", "mateIn2", "mateIn3", "mateIn4", "mateIn5", "mate",
            "rookEndgame", "pawnEndgame", "queenEndgame", "bishopEndgame", "knightEndgame", "queenRookEndgame",
            "endgame", "opening", "middlegame",
            "crushing", "advantage", "equality", "master", "masterVsMaster", "superGM",
            "oneMove", "short", "long", "veryLong",
        ]
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    }()
}
