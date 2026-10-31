enum Side: UInt8, Codable, Sendable {
    case white, black

    var opposite: Side { self == .white ? .black : .white }
}

enum PieceKind: UInt8, Codable, CaseIterable, Sendable {
    case pawn, knight, bishop, rook, queen, king

    fileprivate init?(letter: UInt8) {
        switch letter {
        case UInt8(ascii: "P"): self = .pawn
        case UInt8(ascii: "N"): self = .knight
        case UInt8(ascii: "B"): self = .bishop
        case UInt8(ascii: "R"): self = .rook
        case UInt8(ascii: "Q"): self = .queen
        case UInt8(ascii: "K"): self = .king
        default: return nil
        }
    }

    fileprivate var letter: UInt8 {
        switch self {
        case .pawn: return UInt8(ascii: "P")
        case .knight: return UInt8(ascii: "N")
        case .bishop: return UInt8(ascii: "B")
        case .rook: return UInt8(ascii: "R")
        case .queen: return UInt8(ascii: "Q")
        case .king: return UInt8(ascii: "K")
        }
    }

    fileprivate var isPromotion: Bool {
        self == .knight || self == .bishop || self == .rook || self == .queen
    }
}

struct Piece: Hashable, Codable, Sendable {
    var kind: PieceKind
    var side: Side
}

typealias Square = Int

func squareName(_ s: Square) -> String {
    guard isOnBoard(s) else { return "-" }
    return String(decoding: [UInt8(ascii: "a") + UInt8(s % 8), UInt8(ascii: "1") + UInt8(s / 8)], as: UTF8.self)
}

func square(named name: String) -> Square? {
    let bytes = Array(name.utf8.prefix(3))
    guard bytes.count == 2 else { return nil }
    return squareIndex(file: bytes[0], rank: bytes[1])
}

struct Move: Hashable, Codable, Sendable {
    var from: Square
    var to: Square
    var promotion: PieceKind?

    var uci: String {
        var text = squareName(from) + squareName(to)
        if let promotion { text.unicodeScalars.append(Unicode.Scalar(promotion.letter | lowercaseBit)) }
        return text
    }
}

// In an extension so the memberwise initialiser stays available.
extension Move {
    init?(uci: String) {
        let bytes = Array(uci.utf8.prefix(6))
        guard bytes.count == 4 || bytes.count == 5,
              let from = squareIndex(file: bytes[0], rank: bytes[1]),
              let to = squareIndex(file: bytes[2], rank: bytes[3]),
              from != to else { return nil }
        var promotion: PieceKind?
        if bytes.count == 5 {
            guard let kind = PieceKind(letter: bytes[4] & ~lowercaseBit),
                  kind.isPromotion,
                  bytes[4] & lowercaseBit != 0 else { return nil }
            promotion = kind
        }
        self.init(from: from, to: to, promotion: promotion)
    }
}

struct Position: Hashable, Sendable {
    private var pawns: UInt64 = 0
    private var knights: UInt64 = 0
    private var bishops: UInt64 = 0
    private var rooks: UInt64 = 0
    private var queens: UInt64 = 0
    private var kings: UInt64 = 0
    private var whites: UInt64 = 0
    private var blacks: UInt64 = 0
    private var castling: UInt8 = 0
    // The FEN target square, set after every double push. `epd` applies the legality rule on top.
    private var ep: Square?
    private(set) var side: Side = .white
    private(set) var halfmoveClock = 0
    private(set) var fullmoveNumber = 1

    // Stockfish refuses a FEN whose clocks go past these, so `fen` must never produce one.
    private static let maxHalfmoveClock = 32767
    private static let maxFullmoveNumber = 100_000

    static let start = Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")!

    init?(fen: String) {
        guard fen.utf8.count <= 256 else { return nil }
        let fields = fen.split(whereSeparator: \.isWhitespace)
        guard (4...6).contains(fields.count) else { return nil }

        guard parsePlacement(fields[0]) else { return nil }

        switch fields[1] {
        case "w": side = .white
        case "b": side = .black
        default: return nil
        }

        guard parseCastling(fields[2]) else { return nil }

        if fields[3] != "-" {
            guard let target = square(named: String(fields[3])), target / 8 == (side == .white ? 5 : 2) else { return nil }
            ep = isValidEnPassantTarget(target) ? target : nil
        }

        if fields.count > 4 {
            guard let halfmove = Int(fields[4]), (0...Self.maxHalfmoveClock).contains(halfmove) else { return nil }
            halfmoveClock = halfmove
        }
        if fields.count > 5 {
            guard let fullmove = Int(fields[5]), (0...Self.maxFullmoveNumber).contains(fullmove) else { return nil }
            fullmoveNumber = max(fullmove, 1)
        }

        // The mover could capture the king. Stockfish refuses these too.
        if let enemyKing = king(of: side.opposite), attackersMask(of: enemyKing, by: side) != 0 { return nil }
    }

    // MARK: - FEN parsing

    private mutating func parsePlacement(_ field: Substring) -> Bool {
        var rank = 7
        var file = 0
        var previousWasDigit = false
        for byte in field.utf8 {
            if byte == UInt8(ascii: "/") {
                guard file == 8, rank > 0 else { return false }
                rank -= 1
                file = 0
                previousWasDigit = false
            } else if (UInt8(ascii: "1")...UInt8(ascii: "8")).contains(byte) {
                guard !previousWasDigit else { return false }
                file += Int(byte - UInt8(ascii: "0"))
                guard file <= 8 else { return false }
                previousWasDigit = true
            } else {
                guard file < 8, let kind = PieceKind(letter: byte & ~lowercaseBit) else { return false }
                if kind == .pawn && (rank == 0 || rank == 7) { return false }
                place(kind, byte & lowercaseBit == 0 ? .white : .black, bit(rank * 8 + file))
                file += 1
                previousWasDigit = false
            }
        }
        guard rank == 0, file == 8 else { return false }

        return (kings & whites).nonzeroBitCount == 1 && (kings & blacks).nonzeroBitCount == 1
            && hasReachableMaterial(.white) && hasReachableMaterial(.black)
    }

    // Each piece beyond the starting set needs a promoted pawn. Stockfish applies the same limit.
    private func hasReachableMaterial(_ owner: Side) -> Bool {
        let own = occupancy(owner)
        func extra(_ mask: UInt64, beyond count: Int) -> Int { max((mask & own).nonzeroBitCount - count, 0) }
        let promoted = extra(knights, beyond: 2) + extra(bishops, beyond: 2) + extra(rooks, beyond: 2) + extra(queens, beyond: 1)
        return promoted + (pawns & own).nonzeroBitCount <= 8
    }

    // Rights the placement cannot back up are dropped, as python-chess does when cleaning castling rights.
    private mutating func parseCastling(_ field: Substring) -> Bool {
        guard field != "-" else { return true }
        guard field.utf8.count <= 4 else { return false }
        for byte in field.utf8 {
            switch byte {
            case UInt8(ascii: "K"):
                if kings & whites & bit(4) != 0 && rooks & whites & bit(7) != 0 { castling |= whiteKingside }
            case UInt8(ascii: "Q"):
                if kings & whites & bit(4) != 0 && rooks & whites & bit(0) != 0 { castling |= whiteQueenside }
            case UInt8(ascii: "k"):
                if kings & blacks & bit(60) != 0 && rooks & blacks & bit(63) != 0 { castling |= blackKingside }
            case UInt8(ascii: "q"):
                if kings & blacks & bit(60) != 0 && rooks & blacks & bit(56) != 0 { castling |= blackQueenside }
            default:
                return false
            }
        }
        return true
    }

    private func isValidEnPassantTarget(_ target: Square) -> Bool {
        let (pawnSquare, originSquare) = side == .white ? (target - 8, target + 8) : (target + 8, target - 8)
        let empty = ~(whites | blacks)
        return pawns & occupancy(side.opposite) & bit(pawnSquare) != 0
            && empty & bit(target) != 0
            && empty & bit(originSquare) != 0
    }

    // MARK: - FEN output

    var fen: String {
        "\(fourFields(ep: ep)) \(halfmoveClock) \(fullmoveNumber)"
    }

    var epd: String {
        fourFields(ep: legalEnPassantTarget)
    }

    private var legalEnPassantTarget: Square? {
        guard let ep else { return nil }
        let capturers = pawnAttacks(bit(ep), side.opposite) & pawns & occupancy(side)
        return legalMoves(fromMask: capturers, toMask: bit(ep)).isEmpty ? nil : ep
    }

    private func fourFields(ep: Square?) -> String {
        "\(placementFEN) \(side == .white ? "w" : "b") \(castlingFEN) \(ep.map(squareName) ?? "-")"
    }

    private var placementFEN: String {
        var out: [UInt8] = []
        out.reserveCapacity(72)
        for rank in stride(from: 7, through: 0, by: -1) {
            var empty: UInt8 = 0
            for file in 0..<8 {
                guard let piece = piece(at: rank * 8 + file) else {
                    empty += 1
                    continue
                }
                if empty > 0 {
                    out.append(UInt8(ascii: "0") + empty)
                    empty = 0
                }
                out.append(piece.side == .white ? piece.kind.letter : piece.kind.letter | lowercaseBit)
            }
            if empty > 0 { out.append(UInt8(ascii: "0") + empty) }
            if rank > 0 { out.append(UInt8(ascii: "/")) }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private var castlingFEN: String {
        guard castling != 0 else { return "-" }
        var out = ""
        if castling & whiteKingside != 0 { out += "K" }
        if castling & whiteQueenside != 0 { out += "Q" }
        if castling & blackKingside != 0 { out += "k" }
        if castling & blackQueenside != 0 { out += "q" }
        return out
    }

    // MARK: - Queries

    func piece(at s: Square) -> Piece? {
        guard isOnBoard(s) else { return nil }
        let mask = bit(s)
        let owner: Side
        if whites & mask != 0 {
            owner = .white
        } else if blacks & mask != 0 {
            owner = .black
        } else {
            return nil
        }
        let kind: PieceKind
        if pawns & mask != 0 {
            kind = .pawn
        } else if knights & mask != 0 {
            kind = .knight
        } else if bishops & mask != 0 {
            kind = .bishop
        } else if rooks & mask != 0 {
            kind = .rook
        } else if queens & mask != 0 {
            kind = .queen
        } else {
            kind = .king
        }
        return Piece(kind: kind, side: owner)
    }

    func king(of owner: Side) -> Square? {
        let mask = kings & occupancy(owner)
        return mask == 0 ? nil : mask.trailingZeroBitCount
    }

    func attackers(of s: Square, by attacker: Side) -> [Square] {
        guard isOnBoard(s) else { return [] }
        var mask = attackersMask(of: s, by: attacker)
        var squares: [Square] = []
        while mask != 0 { squares.append(popLowest(&mask)) }
        return squares
    }

    var inCheck: Bool {
        guard let own = king(of: side) else { return false }
        return attackersMask(of: own, by: side.opposite) != 0
    }

    var isCheckmate: Bool { inCheck && legalMoves().isEmpty }

    var isStalemate: Bool { !inCheck && legalMoves().isEmpty }

    var hasInsufficientMaterial: Bool {
        guard pawns | rooks | queens == 0 else { return false }
        if (knights | bishops).nonzeroBitCount <= 1 { return true }
        // Bishops confined to one colour can never cover a king's flight squares.
        return knights == 0 && (bishops & darkSquares == 0 || bishops & ~darkSquares == 0)
    }

    private func occupancy(_ owner: Side) -> UInt64 {
        owner == .white ? whites : blacks
    }

    private func pieces(_ kind: PieceKind) -> UInt64 {
        switch kind {
        case .pawn: return pawns
        case .knight: return knights
        case .bishop: return bishops
        case .rook: return rooks
        case .queen: return queens
        case .king: return kings
        }
    }

    private func attackersMask(of s: Square, by attacker: Side) -> UInt64 {
        let occupied = whites | blacks
        var mask = Attacks.knight[s] & knights
            | Attacks.king[s] & kings
            | pawnAttacks(bit(s), attacker.opposite) & pawns
        let diagonal = (bishops | queens) & occupancy(attacker)
        if diagonal != 0 { mask |= bishopAttacks(s, occupied) & diagonal }
        let straight = (rooks | queens) & occupancy(attacker)
        if straight != 0 { mask |= rookAttacks(s, occupied) & straight }
        return mask & occupancy(attacker)
    }

    // MARK: - Move generation

    func legalMoves() -> [Move] {
        legalMoves(fromMask: ~0, toMask: ~0)
    }

    func legalMoves(from s: Square) -> [Move] {
        guard isOnBoard(s) else { return [] }
        return legalMoves(fromMask: bit(s), toMask: ~0)
    }

    func isLegal(_ m: Move) -> Bool {
        guard isOnBoard(m.from), isOnBoard(m.to) else { return false }
        return legalMoves(fromMask: bit(m.from), toMask: bit(m.to)).contains(m)
    }

    // Pseudo-legal candidates, each kept only if the mover's king is safe on the resulting board.
    // That single test covers pins, double check, king steps and the en passant horizontal pin.
    private func legalMoves(fromMask: UInt64, toMask: UInt64) -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)

        let own = occupancy(side)
        let occupied = whites | blacks

        func add(_ from: Square, _ to: Square) {
            if isKingSafe(after: Move(from: from, to: to)) {
                moves.append(Move(from: from, to: to))
            }
        }

        func addPawnMove(_ from: Square, _ to: Square) {
            guard bit(to) & toMask != 0 else { return }
            if to / 8 == 0 || to / 8 == 7 {
                guard isKingSafe(after: Move(from: from, to: to, promotion: .queen)) else { return }
                moves.append(Move(from: from, to: to, promotion: .queen))
                moves.append(Move(from: from, to: to, promotion: .rook))
                moves.append(Move(from: from, to: to, promotion: .bishop))
                moves.append(Move(from: from, to: to, promotion: .knight))
            } else {
                add(from, to)
            }
        }

        let forward = side == .white ? 8 : -8
        let doubleRank = side == .white ? 1 : 6
        let capturable = occupancy(side.opposite) | (ep.map(bit) ?? 0)
        var ownPawns = pawns & own & fromMask & notBackRanks
        while ownPawns != 0 {
            let from = popLowest(&ownPawns)
            let single = from + forward
            if occupied & bit(single) == 0 {
                addPawnMove(from, single)
                if from / 8 == doubleRank, occupied & bit(single + forward) == 0 {
                    addPawnMove(from, single + forward)
                }
            }
            var captures = pawnAttacks(bit(from), side) & capturable
            while captures != 0 { addPawnMove(from, popLowest(&captures)) }
        }

        var others = own & fromMask & ~pawns
        while others != 0 {
            let from = popLowest(&others)
            let mask = bit(from)
            var targets: UInt64
            if knights & mask != 0 {
                targets = Attacks.knight[from]
            } else if bishops & mask != 0 {
                targets = bishopAttacks(from, occupied)
            } else if rooks & mask != 0 {
                targets = rookAttacks(from, occupied)
            } else if queens & mask != 0 {
                targets = bishopAttacks(from, occupied) | rookAttacks(from, occupied)
            } else {
                targets = Attacks.king[from]
            }
            targets &= ~own & toMask
            while targets != 0 { add(from, popLowest(&targets)) }
        }

        if castling != 0, kings & own & fromMask != 0 {
            appendCastlingMoves(to: &moves, occupied: occupied, toMask: toMask)
        }
        return moves
    }

    private func appendCastlingMoves(to moves: inout [Move], occupied: UInt64, toMask: UInt64) {
        let enemy = side.opposite
        let e = side == .white ? 4 : 60
        let (kingside, queenside) = side == .white
            ? (whiteKingside, whiteQueenside)
            : (blackKingside, blackQueenside)

        func isClear(_ squares: Square...) -> Bool {
            squares.allSatisfy { attackersMask(of: $0, by: enemy) == 0 }
        }

        if castling & kingside != 0,
           bit(e + 2) & toMask != 0,
           occupied & (bit(e + 1) | bit(e + 2)) == 0,
           isClear(e, e + 1, e + 2) {
            moves.append(Move(from: e, to: e + 2))
        }
        // The b-file square must be empty but may be attacked, since the king never crosses it.
        if castling & queenside != 0,
           bit(e - 2) & toMask != 0,
           occupied & (bit(e - 1) | bit(e - 2) | bit(e - 3)) == 0,
           isClear(e, e - 1, e - 2) {
            moves.append(Move(from: e, to: e - 2))
        }
    }

    private func isKingSafe(after m: Move) -> Bool {
        let next = applying(m)
        guard let own = next.king(of: side) else { return true }
        return next.attackersMask(of: own, by: side.opposite) == 0
    }

    // MARK: - Applying moves

    func applying(_ m: Move) -> Position {
        guard isOnBoard(m.from), isOnBoard(m.to), let moving = piece(at: m.from) else { return self }
        var next = self
        let isPawn = moving.kind == .pawn
        var isCapture = (whites | blacks) & bit(m.to) != 0

        next.clear(bit(m.from) | bit(m.to))
        if isPawn, m.to == ep {
            next.clear(bit(side == .white ? m.to - 8 : m.to + 8))
            isCapture = true
        }
        next.place(m.promotion ?? moving.kind, side, bit(m.to))

        if moving.kind == .king, abs(m.to - m.from) == 2 {
            let (rookFrom, rookTo) = m.to > m.from ? (m.from + 3, m.from + 1) : (m.from - 4, m.from - 1)
            if rooks & occupancy(side) & bit(rookFrom) != 0 {
                next.clear(bit(rookFrom))
                next.place(.rook, side, bit(rookTo))
            }
        }

        next.castling &= ~(castlingRightsLost(at: m.from) | castlingRightsLost(at: m.to))
        next.ep = isPawn && abs(m.to - m.from) == 16 ? (m.from + m.to) / 2 : nil
        next.halfmoveClock = isPawn || isCapture ? 0 : min(halfmoveClock + 1, Self.maxHalfmoveClock)
        if side == .black { next.fullmoveNumber = min(fullmoveNumber + 1, Self.maxFullmoveNumber) }
        next.side = side.opposite
        return next
    }

    private mutating func clear(_ mask: UInt64) {
        let keep = ~mask
        pawns &= keep
        knights &= keep
        bishops &= keep
        rooks &= keep
        queens &= keep
        kings &= keep
        whites &= keep
        blacks &= keep
    }

    private mutating func place(_ kind: PieceKind, _ owner: Side, _ mask: UInt64) {
        switch kind {
        case .pawn: pawns |= mask
        case .knight: knights |= mask
        case .bishop: bishops |= mask
        case .rook: rooks |= mask
        case .queen: queens |= mask
        case .king: kings |= mask
        }
        if owner == .white {
            whites |= mask
        } else {
            blacks |= mask
        }
    }

    // MARK: - SAN

    /// An illegal move has no SAN, so it comes back in UCI form.
    func san(_ m: Move) -> String {
        guard isLegal(m), let moving = piece(at: m.from) else { return m.uci }

        var text = ""
        if moving.kind == .king, abs(m.to - m.from) == 2 {
            text = m.to > m.from ? "O-O" : "O-O-O"
        } else {
            let isCapture = (whites | blacks) & bit(m.to) != 0 || (moving.kind == .pawn && m.to == ep)
            let fromName = Array(squareName(m.from).unicodeScalars)
            if moving.kind == .pawn {
                if isCapture { text.unicodeScalars.append(fromName[0]) }
            } else {
                text.unicodeScalars.append(Unicode.Scalar(moving.kind.letter))
                let sameKind = pieces(moving.kind) & occupancy(side) & ~bit(m.from)
                let rivals = legalMoves(fromMask: sameKind, toMask: bit(m.to))
                if !rivals.isEmpty {
                    let sharesFile = rivals.contains { $0.from % 8 == m.from % 8 }
                    let sharesRank = rivals.contains { $0.from / 8 == m.from / 8 }
                    if !sharesFile {
                        text.unicodeScalars.append(fromName[0])
                    } else if !sharesRank {
                        text.unicodeScalars.append(fromName[1])
                    } else {
                        text.unicodeScalars.append(contentsOf: fromName)
                    }
                }
            }
            if isCapture { text += "x" }
            text += squareName(m.to)
            if let promotion = m.promotion {
                text += "="
                text.unicodeScalars.append(Unicode.Scalar(promotion.letter))
            }
        }

        let next = applying(m)
        if next.inCheck { text += next.legalMoves().isEmpty ? "#" : "+" }
        return text
    }

    func move(san text: String) -> Move? {
        guard text.utf8.count <= 24, var s = strippedSAN(text) else { return nil }

        if let castled = castlingMove(san: s) { return castled }

        var promotion: PieceKind?
        if s.count >= 3, let kind = PieceKind(letter: s[s.count - 1] & ~lowercaseBit), kind.isPromotion {
            s.removeLast()
            if s.last == UInt8(ascii: "=") { s.removeLast() }
            promotion = kind
        }

        guard s.count >= 2, let to = squareIndex(file: s[s.count - 2], rank: s[s.count - 1]) else { return nil }
        let end = s.count - 2

        var i = 0
        var kind = PieceKind.pawn
        if i < end, let letter = PieceKind(letter: s[i]) {
            kind = letter
            i += 1
        }
        var fromMask = pieces(kind) & occupancy(side)
        var hasFromFile = false
        if i < end, (UInt8(ascii: "a")...UInt8(ascii: "h")).contains(s[i]) {
            fromMask &= fileA << UInt64(s[i] - UInt8(ascii: "a"))
            hasFromFile = true
            i += 1
        }
        if i < end, (UInt8(ascii: "1")...UInt8(ascii: "8")).contains(s[i]) {
            fromMask &= rank1 << UInt64(8 * (s[i] - UInt8(ascii: "1")))
            i += 1
        }
        if i < end, s[i] == UInt8(ascii: "x") || s[i] == UInt8(ascii: "-") { i += 1 }
        guard i == end else { return nil }

        // A bare "d5" is a push, never cxd5.
        if kind == .pawn, !hasFromFile { fromMask &= fileA << UInt64(to % 8) }

        var match: Move?
        for candidate in legalMoves(fromMask: fromMask, toMask: bit(to)) where candidate.promotion == promotion {
            if kind == .king, abs(candidate.to - candidate.from) == 2 { continue }
            if match != nil { return nil }
            match = candidate
        }
        return match
    }

    private func castlingMove(san s: [UInt8]) -> Move? {
        let normalised = s.map { $0 == UInt8(ascii: "0") || $0 == UInt8(ascii: "o") ? UInt8(ascii: "O") : $0 }
        let delta: Int
        if normalised.elementsEqual("O-O".utf8) {
            delta = 2
        } else if normalised.elementsEqual("O-O-O".utf8) {
            delta = -2
        } else {
            return nil
        }
        guard let from = king(of: side) else { return nil }
        let candidate = Move(from: from, to: from + delta)
        return isOnBoard(candidate.to) && isLegal(candidate) ? candidate : nil
    }

    // MARK: - UCI

    func move(uci text: String) -> Move? {
        guard var m = Move(uci: text) else { return nil }
        let own = occupancy(side)
        if m.promotion == nil, kings & own & bit(m.from) != 0, rooks & own & bit(m.to) != 0 {
            switch (m.from, m.to) {
            case (4, 7), (60, 63): m.to = m.from + 2
            case (4, 0), (60, 56): m.to = m.from - 2
            default: break
            }
        }
        return isLegal(m) ? m : nil
    }

    // MARK: - Perft

    func perft(_ depth: Int) -> UInt64 {
        guard depth > 0 else { return 1 }
        let moves = legalMoves()
        if depth == 1 { return UInt64(moves.count) }
        var nodes: UInt64 = 0
        for m in moves { nodes += applying(m).perft(depth - 1) }
        return nodes
    }
}

// MARK: - SAN helpers

private let enPassantSuffixes = ["e.p.", "e.p", "ep"].map { Array($0.utf8) }
private let sanDecorations = Array("+#!? \t\r\n".utf8)

private func strippedSAN(_ text: String) -> [UInt8]? {
    var s = Array(text.utf8)
    while let first = s.first, sanDecorations.contains(first) { s.removeFirst() }
    trimming: while let last = s.last {
        if sanDecorations.contains(last) {
            s.removeLast()
            continue
        }
        for suffix in enPassantSuffixes where s.count >= suffix.count && s.suffix(suffix.count).elementsEqual(suffix) {
            s.removeLast(suffix.count)
            continue trimming
        }
        break
    }
    return s.isEmpty ? nil : s
}

// MARK: - Bitboard helpers

private let lowercaseBit: UInt8 = 0x20

private let whiteKingside: UInt8 = 1
private let whiteQueenside: UInt8 = 2
private let blackKingside: UInt8 = 4
private let blackQueenside: UInt8 = 8

private let fileA: UInt64 = 0x0101_0101_0101_0101
private let fileH: UInt64 = 0x8080_8080_8080_8080
private let rank1: UInt64 = 0x0000_0000_0000_00FF
private let notBackRanks: UInt64 = 0x00FF_FFFF_FFFF_FF00
private let darkSquares: UInt64 = 0xAA55_AA55_AA55_AA55

private func isOnBoard(_ s: Int) -> Bool {
    s >= 0 && s < 64
}

private func squareIndex(file: UInt8, rank: UInt8) -> Square? {
    guard (UInt8(ascii: "a")...UInt8(ascii: "h")).contains(file),
          (UInt8(ascii: "1")...UInt8(ascii: "8")).contains(rank) else { return nil }
    return Int(rank - UInt8(ascii: "1")) * 8 + Int(file - UInt8(ascii: "a"))
}

@inline(__always)
private func bit(_ s: Int) -> UInt64 {
    1 &<< UInt64(truncatingIfNeeded: s)
}

@inline(__always)
private func popLowest(_ mask: inout UInt64) -> Int {
    let s = mask.trailingZeroBitCount
    mask &= mask &- 1
    return s
}

private func castlingRightsLost(at s: Square) -> UInt8 {
    switch s {
    case 0: return whiteQueenside
    case 4: return whiteKingside | whiteQueenside
    case 7: return whiteKingside
    case 56: return blackQueenside
    case 60: return blackKingside | blackQueenside
    case 63: return blackKingside
    default: return 0
    }
}

@inline(__always)
private func pawnAttacks(_ mask: UInt64, _ owner: Side) -> UInt64 {
    owner == .white
        ? (mask &<< 7) & ~fileH | (mask &<< 9) & ~fileA
        : (mask &>> 9) & ~fileH | (mask &>> 7) & ~fileA
}

private enum Attacks {
    static let knight = leaperTable([(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)])
    static let king = leaperTable([(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)])

    // Indexed by direction * 64 + square. Directions 0...3 raise the square index, 4...7 lower it,
    // which decides whether the first blocker on a ray is its lowest or highest set bit.
    static let rays: [UInt64] = {
        let directions = [(0, 1), (1, 0), (1, 1), (-1, 1), (0, -1), (-1, 0), (-1, -1), (1, -1)]
        var table = [UInt64](repeating: 0, count: 8 * 64)
        for (index, (fileStep, rankStep)) in directions.enumerated() {
            for s in 0..<64 {
                var file = s % 8 + fileStep
                var rank = s / 8 + rankStep
                while (0..<8).contains(file), (0..<8).contains(rank) {
                    table[index * 64 + s] |= bit(rank * 8 + file)
                    file += fileStep
                    rank += rankStep
                }
            }
        }
        return table
    }()

    private static func leaperTable(_ steps: [(Int, Int)]) -> [UInt64] {
        (0..<64).map { s in
            steps.reduce(UInt64(0)) { mask, step in
                let file = s % 8 + step.0
                let rank = s / 8 + step.1
                guard (0..<8).contains(file), (0..<8).contains(rank) else { return mask }
                return mask | bit(rank * 8 + file)
            }
        }
    }
}

@inline(__always)
private func ray(_ direction: Int, _ s: Int, _ occupied: UInt64) -> UInt64 {
    let full = Attacks.rays[direction &* 64 &+ s]
    let blockers = full & occupied
    guard blockers != 0 else { return full }
    let first = direction < 4 ? blockers.trailingZeroBitCount : 63 &- blockers.leadingZeroBitCount
    return full ^ Attacks.rays[direction &* 64 &+ first]
}

private func rookAttacks(_ s: Int, _ occupied: UInt64) -> UInt64 {
    ray(0, s, occupied) | ray(1, s, occupied) | ray(4, s, occupied) | ray(5, s, occupied)
}

private func bishopAttacks(_ s: Int, _ occupied: UInt64) -> UInt64 {
    ray(2, s, occupied) | ray(3, s, occupied) | ray(6, s, occupied) | ray(7, s, occupied)
}
