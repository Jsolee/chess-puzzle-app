import Foundation

/// Opening names and the book, from Resources/openings.tsv (tools/build_openings.py, CC0 data).
/// Rows are `epd<TAB>eco<TAB>name`. An empty name is book but unnamed, a prefix of a named line.
/// The tables are narrower than theory, so Book ends earlier than a master tree would end it.
final class Openings: @unchecked Sendable {
    struct Entry: Hashable, Codable, Sendable {
        var eco: String
        var name: String
    }

    static let shared = Openings(url: Bundle.main.url(forResource: "openings", withExtension: "tsv"))
    static let maxPlies = 40
    static let minPieces = 20

    private let url: URL?
    private let lock = NSLock()
    private var loaded: [String: Entry]?

    init(url: URL?) {
        self.url = url
    }

    private var table: [String: Entry] {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        var rows: [String: Entry] = [:]
        if let url, let text = try? String(contentsOf: url, encoding: .utf8) {
            rows.reserveCapacity(8192)
            for line in text.split(separator: "\n") {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count == 3 else { continue }
                rows[String(fields[0])] = Entry(eco: String(fields[1]), name: String(fields[2]))
            }
        }
        loaded = rows
        return rows
    }

    func isBook(epd: String) -> Bool { table[epd] != nil }

    /// Deepest named position reached in the first 40 plies, stopping once under 20 pieces.
    func name(start: Position, moves: [Move]) -> Entry? {
        let table = table
        var best: Entry?
        var position = start
        for m in moves.prefix(Self.maxPlies) {
            position = position.applying(m)
            if position.pieceCount < Self.minPieces { break }
            if let entry = table[position.epd], !entry.name.isEmpty { best = entry }
        }
        return best
    }

    /// How many plies from the start stay in the book, up to the first position outside it.
    func bookPlies(start: Position, moves: [Move]) -> Int {
        let table = table
        var count = 0
        var position = start
        for m in moves.prefix(Self.maxPlies) {
            position = position.applying(m)
            guard table[position.epd] != nil else { break }
            count += 1
        }
        return count
    }
}
