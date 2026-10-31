import Foundation

struct Puzzle: Identifiable, Hashable {
    let id: String
    let index: Int
    let start: Position
    let line: [Move]
    let rating: Int
    let themes: [String]
    let popularity: Int
    var solverSide: Side { start.side.opposite }
}

/// Memory-mapped `puzzles.bin`; tools/curate_puzzles.py documents the format and writes it.
final class PuzzleStore {
    static let shared = PuzzleStore(url: Bundle.main.url(forResource: "puzzles", withExtension: "bin")!)

    let count: Int
    private let data: Data
    private let tags: [String]
    private let mateBit: UInt64
    private let ratingAt, idAt, maskAt, flagsAt, pliesAt, popularityAt, occupancyAt, offsetAt, blobsAt: Int
    private let dailies: [Int]

    private static let black: UInt8 = 1, hasEP: UInt8 = 32, daily: UInt8 = 64
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    private static let pieces = Array("PNBRQKpnbrqk".utf8)
    private static let promotions: [PieceKind?] = [nil, .knight, .bishop, .rook, .queen]

    init(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count >= 64 else {
            fatalError("Cannot map \(url.lastPathComponent)")
        }
        self.data = data
        let field = { (at: Int) -> Int in
            Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) })
        }
        guard data.prefix(4).elementsEqual("SCPZ".utf8), data[4] == 1, data[5] == 0, field(52) == data.count else {
            fatalError("Unrecognised \(url.lastPathComponent)")
        }
        let n = field(8)
        count = n
        ratingAt = field(16); idAt = field(20); maskAt = field(24); flagsAt = field(28); pliesAt = field(32)
        popularityAt = field(36); occupancyAt = field(40); offsetAt = field(44); blobsAt = field(48)
        let names = String(decoding: data[field(12)..<ratingAt], as: UTF8.self).split(separator: "\n").map(String.init)
        tags = names
        mateBit = names.firstIndex(of: "mate").map { 1 << UInt64($0) } ?? 0
        let flags = flagsAt
        dailies = data.withUnsafeBytes { raw in (0..<n).filter { raw[flags + $0] & Self.daily != 0 } }
    }

    // MARK: Records

    func puzzle(at index: Int) -> Puzzle {
        precondition(index >= 0 && index < count)
        let (fen, line): (String, [Move]) = data.withUnsafeBytes { raw in
            let flags = raw[flagsAt + index]
            let occupancy = raw.loadUnaligned(fromByteOffset: occupancyAt + index * 8, as: UInt64.self)
            let blob = blobsAt + Int(raw.loadUnaligned(fromByteOffset: offsetAt + index * 4, as: UInt32.self))
            var at = blob + (occupancy.nonzeroBitCount + 1) / 2

            var fen = [UInt8]()
            fen.reserveCapacity(96)
            for rank in stride(from: 7, through: 0, by: -1) {
                var empty: UInt8 = 0
                for file in 0..<8 {
                    let square = rank * 8 + file
                    guard occupancy >> UInt64(square) & 1 == 1 else { empty += 1; continue }
                    if empty > 0 { fen.append(48 + empty); empty = 0 }
                    let n = (occupancy & ((1 << UInt64(square)) - 1)).nonzeroBitCount
                    let byte = raw[blob + n / 2]
                    fen.append(Self.pieces[Int(n % 2 == 0 ? byte & 15 : byte >> 4)])
                }
                if empty > 0 { fen.append(48 + empty) }
                if rank > 0 { fen.append(47) }
            }
            let isBlack = flags & Self.black != 0
            fen.append(contentsOf: isBlack ? " b ".utf8 : " w ".utf8)
            if flags & 30 == 0 { fen.append(45) }
            for (bit, letter) in zip([2, 4, 8, 16] as [UInt8], "KQkq".utf8) where flags & bit != 0 { fen.append(letter) }
            fen.append(32)
            if flags & Self.hasEP != 0 {
                fen.append(97 + raw[at]); fen.append(isBlack ? 51 : 54)
                at += 1
            } else {
                fen.append(45)
            }
            fen.append(contentsOf: " 0 1".utf8)

            let plies = Int(raw[pliesAt + index])
            let line = (0..<plies).map { i -> Move in
                let v = Int(raw.loadUnaligned(fromByteOffset: at + i * 2, as: UInt16.self))
                return Move(from: v & 63, to: v >> 6 & 63, promotion: Self.promotions[v >> 12])
            }
            return (String(decoding: fen, as: UTF8.self), line)
        }
        guard let start = Position(fen: fen) else { fatalError("Bad FEN in puzzles.bin: \(fen)") }
        return Puzzle(id: id(at: index), index: index, start: start, line: line, rating: rating(at: index),
                      themes: themes(at: index), popularity: Int(read(popularityAt + index, as: Int8.self)))
    }

    func id(at index: Int) -> String {
        var v = read(idAt + index * 4, as: UInt32.self)
        var out = [UInt8](repeating: 48, count: 5)
        for i in stride(from: 4, through: 0, by: -1) {
            out[i] = Self.alphabet[Int(v % 62)]
            v /= 62
        }
        return String(decoding: out, as: UTF8.self)
    }

    func index(ofID id: String) -> Int? {
        guard id.utf8.count == 5 else { return nil }
        var code: UInt32 = 0
        for c in id.utf8 {
            guard let d = Self.alphabet.firstIndex(of: c) else { return nil }
            code = code * 62 + UInt32(d)
        }
        return data.withUnsafeBytes { raw in
            (0..<count).first { raw.loadUnaligned(fromByteOffset: idAt + $0 * 4, as: UInt32.self) == code }
        }
    }

    func rating(at index: Int) -> Int { Int(read(ratingAt + index * 2, as: UInt16.self)) }

    func solverSide(at index: Int) -> Side { data[flagsAt + index] & Self.black != 0 ? .white : .black }

    func themes(at index: Int) -> [String] {
        let mask = read(maskAt + index * 8, as: UInt64.self)
        var out = tags.indices.filter { mask >> UInt64($0) & 1 == 1 }.map { tags[$0] }
        out.append(contentsOf: Self.derivedTags(mate: mask & mateBit != 0, plies: Int(data[pliesAt + index])))
        return out
    }

    private static func derivedTags(mate: Bool, plies: Int) -> [String] {
        let moves = plies / 2
        let length = moves <= 1 ? "oneMove" : moves == 2 ? "short" : moves == 3 ? "long" : "veryLong"
        return mate ? [length, "mateIn\(min(moves, 5))"] : [length]
    }

    private func read<T: FixedWidthInteger>(_ offset: Int, as: T.Type) -> T {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }

    // MARK: Search

    /// Random pick among the matches in a window around `target`. The window starts at +-75, widens as Lichess
    /// does ((100 + |1500 - target| / 4) * k up to k = 4), then keeps doubling so a rare theme still finds its
    /// nearest puzzles. Nil only when nothing in the whole file matches.
    func find(target: Int, anyOf themes: Set<String>?, excluding played: (Int) -> Bool) -> Puzzle? {
        guard count > 0 else { return nil }
        let wantedMask = themes.map { wanted in
            tags.indices.reduce(UInt64(0)) { wanted.contains(tags[$1]) ? $0 | 1 << UInt64($1) : $0 }
        }
        let wantedDerived: Set<String> = themes?.filter { Self.isDerived($0) } ?? []
        if themes != nil && wantedMask == 0 && wantedDerived.isEmpty { return nil }

        let target = max(rating(at: 0), min(rating(at: count - 1), target))
        let step = 100 + abs(1500 - target) / 4
        var radius = 75, k = 1
        while true {
            let lo = lowerBound(target - radius), hi = lowerBound(target + radius + 1)
            if let i = scan(lo..<hi, mask: wantedMask, derived: wantedDerived, excluding: played) { return puzzle(at: i) }
            if lo == 0 && hi == count { return nil }
            radius = k <= 4 ? step * k : radius * 2
            k += 1
        }
    }

    private func scan(_ range: Range<Int>, mask: UInt64?, derived: Set<String>, excluding played: (Int) -> Bool) -> Int? {
        guard !range.isEmpty else { return nil }
        let start = Int.random(in: 0..<range.count)
        return data.withUnsafeBytes { raw in
            for k in 0..<range.count {
                let i = range.lowerBound + (start + k) % range.count
                if let mask {
                    let m = raw.loadUnaligned(fromByteOffset: maskAt + i * 8, as: UInt64.self)
                    if m & mask == 0 {
                        guard !derived.isEmpty else { continue }
                        let tags = Self.derivedTags(mate: m & mateBit != 0, plies: Int(raw[pliesAt + i]))
                        guard tags.contains(where: derived.contains) else { continue }
                    }
                }
                if !played(i) { return i }
            }
            return nil
        }
    }

    private func lowerBound(_ r: Int) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if rating(at: mid) < r { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private static func isDerived(_ tag: String) -> Bool {
        tag.hasPrefix("mateIn") || ["oneMove", "short", "long", "veryLong"].contains(tag)
    }

    // MARK: Daily

    /// Same puzzle all day and on every launch. The prime stride walks the whole pool of Lichess dailies before repeating.
    func daily(for date: Date) -> Puzzle {
        let day = Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: date) ?? 0
        guard !dailies.isEmpty else { return puzzle(at: day % count) }
        return puzzle(at: dailies[day * 1151 % dailies.count])
    }
}

/// One attempt at one puzzle.
struct PuzzleRun {
    let puzzle: Puzzle
    var step = 1

    enum Outcome: Equatable { case correct(reply: Move?), solved, wrong }

    init(_ puzzle: Puzzle) { self.puzzle = puzzle }

    var expected: Move? { step < puzzle.line.count ? puzzle.line[step] : nil }

    /// The line still to be played, from the next solver move on.
    var remaining: ArraySlice<Move> { puzzle.line[min(step, puzzle.line.count)...] }

    /// `position` is the board before `m`. A correct move also consumes the opponent's reply, which the caller plays.
    mutating func attempt(_ m: Move, on position: Position) -> Outcome {
        guard let expected, let move = position.move(uci: m.uci) else { return .wrong }
        if position.applying(move).isCheckmate {
            step = puzzle.line.count
            return .solved
        }
        guard move == (position.move(uci: expected.uci) ?? expected) else { return .wrong }
        step += 2
        if step >= puzzle.line.count { return .solved }
        return .correct(reply: puzzle.line[step - 1])
    }
}
