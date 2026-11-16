import CryptoKit
import Foundation
import Observation

enum GameSource: String, Codable, Sendable { case chessCom, lichess, pgn }

enum TimeClass: String, Codable, Sendable {
    case ultraBullet, bullet, blitz, rapid, classical, daily, unknown

    /// Lichess's own bands over base + 40 x increment. Takes 60, 180+2, 10+0.1, 1/86400 and "14 days per move".
    init(timeControl: String?) {
        guard let tc = timeControl else { self = .unknown; return }
        if tc.contains("/") || tc.contains("day") { self = .daily; return }
        let parts = tc.split(separator: "+").map { Double($0) }
        guard let base = parts.first ?? nil else { self = .unknown; return }
        let increment = parts.count > 1 ? parts[1] ?? 0 : 0
        switch base + 40 * increment {
        case ..<30: self = .ultraBullet
        case ..<180: self = .bullet
        case ..<480: self = .blitz
        case ..<1500: self = .rapid
        default: self = .classical
        }
    }
}

enum Termination: String, Codable, Sendable {
    case checkmate, resignation, timeout, abandoned, stalemate, repetition, agreement, insufficientMaterial, fiftyMoves, timeVsInsufficient, draw, other

    /// The winner's code is just "win", so the loser's says how it ended. Both sides of a draw carry the same code.
    init(chessComWhite white: String?, black: String?) {
        switch (white == "win" ? black : white) ?? "" {
        case "checkmated": self = .checkmate
        case "resigned": self = .resignation
        case "timeout": self = .timeout
        case "abandoned": self = .abandoned
        case "stalemate": self = .stalemate
        case "repetition": self = .repetition
        case "agreed": self = .agreement
        case "insufficient": self = .insufficientMaterial
        case "50move": self = .fiftyMoves
        case "timevsinsufficient": self = .timeVsInsufficient
        default: self = .other
        }
    }

    /// Lichess's "timeout" is the opponent leaving; running out of time is "outoftime". Its "draw" also covers claims.
    init(lichessStatus status: String?) {
        switch status ?? "" {
        case "mate": self = .checkmate
        case "resign": self = .resignation
        case "outoftime": self = .timeout
        case "timeout": self = .abandoned
        case "stalemate": self = .stalemate
        case "draw": self = .draw
        case "insufficientMaterialClaim": self = .insufficientMaterial
        default: self = .other
        }
    }

    /// From a pasted PGN. Lichess writes "Normal" for both mate and resignation, so the last move settles it.
    init(pgn game: PGNGame) {
        let tag = (game.tags["Termination"] ?? "").lowercased()
        if tag.contains("checkmate") || game.moves.last?.san.hasSuffix("#") == true { self = .checkmate }
        else if tag.contains("insufficient") { self = tag.contains("time") ? .timeVsInsufficient : .insufficientMaterial }
        else if tag.contains("resign") { self = .resignation }
        else if tag.contains("abandon") { self = .abandoned }
        else if tag.contains("time") { self = .timeout }
        else if tag.contains("stalemate") { self = .stalemate }
        else if tag.contains("repetition") { self = .repetition }
        else if tag.contains("agreement") { self = .agreement }
        else if tag.contains("50") { self = .fiftyMoves }
        else { self = game.result == "1/2-1/2" ? .draw : .other }
    }
}

/// Lichess's evaluation after one ply, from White's view. The list can be one entry shorter than the game.
struct PlyEval: Codable, Hashable, Sendable {
    var cp: Int?
    var mate: Int?
}

struct ImportedGame: Identifiable, Hashable, Codable, Sendable {
    var id: String              // "chesscom-<uuid>", "lichess-<id>", "pgn-<hash>"
    var source: GameSource
    var url: String?            // same game seen twice, pasted and then fetched, shares this
    var white: String
    var black: String
    var whiteRating: Int?
    var blackRating: Int?
    var mySide: Side?
    var result: String          // 1-0 0-1 1/2-1/2 *
    var termination: Termination
    var timeClass: TimeClass
    var date: Date
    var pgn: String
    var whiteAccuracy: Double?  // only what the site already calculated
    var blackAccuracy: Double?
    var lichessEvals: [PlyEval]?
    var reviewed = false
    /// Your accuracy from this app's own review.
    var myAccuracy: Double?

    /// chess.com Daily %clk is not a remaining clock, so nothing downstream gets to read it as one.
    static func strippingClocks(_ pgn: String) -> String {
        pgn.replacing(#/\s*\{\s*\[%clk [^\]]*\]\s*\}/#, with: "").replacing(#/\[%clk [^\]]*\]\s*/#, with: "")
    }

    mutating func assignSide(chessCom: String, lichess: String) {
        let names: [String]
        switch source {
        case .chessCom: names = [chessCom]
        case .lichess: names = [lichess]
        case .pgn: names = [chessCom, lichess]
        }
        let mine = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        mySide = mine.contains(white.lowercased()) ? .white : mine.contains(black.lowercased()) ? .black : nil
    }
}

// In an extension so the memberwise initialiser stays available.
extension ImportedGame {
    /// One game of a pasted PGN. Throws for anything that is not standard chess with moves.
    init(pasted text: String) throws {
        guard let game = PGN.parse(text).first else { throw ImportError.noGames }
        guard game.hasStandardStart else { throw ImportError.notStandard }
        guard !game.moves.isEmpty else { throw ImportError.noGames }
        let timeClass = TimeClass(timeControl: game.tags["TimeControl"])
        self.init(
            id: "", source: .pgn,
            white: game.tags["White"] ?? "?", black: game.tags["Black"] ?? "?",
            whiteRating: game.tags["WhiteElo"].flatMap { Int($0) }, blackRating: game.tags["BlackElo"].flatMap { Int($0) },
            result: game.result,
            termination: Termination(pgn: game),
            timeClass: timeClass,
            date: game.playedDate,
            pgn: timeClass == .daily ? Self.strippingClocks(text) : text
        )
        switch GameLink.parse(game.tags["Link"] ?? "") ?? GameLink.parse(game.tags["Site"] ?? "") {
        case .lichess(let id)?:
            source = .lichess
            self.id = "lichess-\(id)"
            url = "https://lichess.org/game/\(id)"
        case .chessCom(let kind, let id)?:
            source = .chessCom
            url = "https://www.chess.com/game/\(kind.rawValue)/\(id)"
            self.id = "chesscom-\(url!)"
        case nil:
            let key = ([white, black, game.tags["Date"] ?? ""] + game.moves.map(\.san)).joined(separator: " ")
            let hash = SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
            self.id = "pgn-\(hash)"
        }
    }

    /// Splits a multi-game paste at each tag line that follows movetext, so every game keeps its own raw text.
    static func splitGames(_ text: String) -> [String] {
        var chunks: [String] = []
        var current: [Substring] = []
        var sawMoves = false
        for line in text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["\u{FEFF}"])).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let isTag = line.wholeMatch(of: #/\s*\[\s*\w+\s+".*/#) != nil
            if isTag, sawMoves {
                chunks.append(current.joined(separator: "\n"))
                current = []
                sawMoves = false
            }
            if !isTag, let first = line.first(where: { !$0.isWhitespace }), first != "%", first != ";" { sawMoves = true }
            current.append(line)
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }
        return chunks
    }

    /// Text starting with [ or holding a move number is PGN; anything else is treated as a link.
    static func looksLikePGN(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["\u{FEFF}"]))
        return t.hasPrefix("[") || t.firstMatch(of: #/(?:^|\s)1\.\s*\S/#) != nil
    }
}

@MainActor @Observable final class GameLibrary {
    static let shared = GameLibrary()

    private(set) var games: [ImportedGame] = []
    private(set) var isRefreshing = false
    private(set) var refreshErrors: [GameSource: ImportError] = [:]
    private(set) var reachedOldest = false

    var chessComUsername: String {
        didSet { defaults.set(chessComUsername, forKey: Self.chessComKey); usernamesChanged() }
    }
    var lichessUsername: String {
        didSet { defaults.set(lichessUsername, forKey: Self.lichessKey); usernamesChanged() }
    }

    private static let chessComKey = "chessComUsername"
    private static let lichessKey = "lichessUsername"

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let chessCom: ChessComClient
    @ObservationIgnored private let lichess: LichessClient
    /// Ids and urls the user deleted, so a refresh does not bring them back. Adding one by hand clears it.
    @ObservationIgnored private var deleted: Set<String> = []
    /// Motif counts per game, so the recommender does not decode every review file each time.
    @ObservationIgnored private var evidenceCache: [String: [String: Double]] = [:]
    /// In memory only, so a fresh launch always looks. nil also after a username changes.
    @ObservationIgnored private var lastRefresh: Date?
    private static let staleAfter: TimeInterval = 300

    init(folder: URL? = nil, defaults: UserDefaults = .standard, chessCom: ChessComClient = ChessComClient(), lichess: LichessClient = LichessClient()) {
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.folder = folder ?? (support ?? FileManager.default.temporaryDirectory).appending(path: "Games", directoryHint: .isDirectory)
        self.defaults = defaults
        self.chessCom = chessCom
        self.lichess = lichess
        chessComUsername = defaults.string(forKey: Self.chessComKey) ?? ""
        lichessUsername = defaults.string(forKey: Self.lichessKey) ?? ""
        load()
    }

    // MARK: Importing

    var hasAccounts: Bool { !chessComUsername.isBlank || !lichessUsername.isBlank }

    /// The site answered and at least one game came back as that username's own.
    func isLinked(_ source: GameSource) -> Bool {
        refreshErrors[source] == nil && games.contains { $0.source == source && $0.mySide != nil }
    }

    /// Games played since the last look turn up on their own, without asking either site more than every few minutes.
    func refreshIfStale(now: Date = .now) async {
        guard hasAccounts, lastRefresh.map({ now.timeIntervalSince($0) >= Self.staleAfter }) ?? true else { return }
        await refresh()
    }

    /// The latest 20 from each username that is set. One site failing leaves the other's games and an entry in refreshErrors.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = .now }
        var fetched: [ImportedGame] = []
        var errors: [GameSource: ImportError] = [:]
        func attempt(_ source: GameSource, _ fetch: () async throws -> [ImportedGame]) async {
            do { fetched += try await fetch() }
            catch is CancellationError {}
            catch { errors[source] = error as? ImportError ?? .unexpectedResponse }
        }
        let chessName = chessComUsername, lichessName = lichessUsername
        if !chessName.isBlank { await attempt(.chessCom) { try await chessCom.recentGames(username: chessName) } }
        if !lichessName.isBlank { await attempt(.lichess) { try await lichess.recentGames(username: lichessName) } }
        refreshErrors = errors
        merge(fetched.filter { !deleted.contains($0.id) && !deleted.contains($0.url ?? "") }, fromSite: true)
    }

    /// Twenty more from each site, older than what's here. When none are new there is nothing further back.
    func loadOlder() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var fetched: [ImportedGame] = []
        var errors: [GameSource: ImportError] = [:]
        func oldest(_ source: GameSource) -> Date? { games.filter { $0.source == source }.map(\.date).min() }
        func attempt(_ source: GameSource, _ fetch: () async throws -> [ImportedGame]) async {
            do { fetched += try await fetch() }
            catch is CancellationError {}
            catch { errors[source] = error as? ImportError ?? .unexpectedResponse }
        }
        let chessName = chessComUsername, lichessName = lichessUsername
        if !chessName.isBlank { await attempt(.chessCom) { try await chessCom.recentGames(username: chessName, before: oldest(.chessCom)) } }
        if !lichessName.isBlank { await attempt(.lichess) { try await lichess.recentGames(username: lichessName, before: oldest(.lichess)) } }
        refreshErrors = errors
        let known = Set(games.map(\.id))
        let new = fetched.filter { !known.contains($0.id) && !deleted.contains($0.id) && !deleted.contains($0.url ?? "") }
        if errors.isEmpty && new.isEmpty { reachedOldest = true }
        merge(new, fromSite: true)
    }

    /// Pasted text of either kind.
    @discardableResult
    func add(pasted text: String) async throws -> [ImportedGame] {
        if ImportedGame.looksLikePGN(text) { return try await add(pgn: text) }
        return [try await add(link: text)]
    }

    /// Adds every standard game in the text and skips the rest; throws only if none could be added.
    @discardableResult
    func add(pgn text: String) async throws -> [ImportedGame] {
        let parsed = await Task.detached(priority: .userInitiated) {
            ImportedGame.splitGames(text).map { chunk in Result { try ImportedGame(pasted: chunk) } }
        }.value
        let added = parsed.compactMap { try? $0.get() }
        guard !added.isEmpty else {
            for case .failure(let error) in parsed where error as? ImportError == .notStandard { throw error }
            throw ImportError.noGames
        }
        added.forEach(clearDeleted)
        return merge(added, fromSite: false)
    }

    @discardableResult
    func add(link text: String) async throws -> ImportedGame {
        guard let link = GameLink.parse(text) else { throw ImportError.invalidLink }
        let game: ImportedGame
        switch link {
        case .lichess(let id):
            if let known = games.first(where: { $0.id == "lichess-\(id)" }) { return known }
            game = try await lichess.game(id: id)
        case .chessCom(let kind, let id):
            guard kind != .computer else { throw ImportError.computerGame }
            if let known = games.first(where: { $0.id == "chesscom-\(id)" || $0.url == "https://www.chess.com/game/\(kind.rawValue)/\(id)" }) { return known }
            guard !chessComUsername.isBlank else { throw ImportError.chessComUsernameNeeded }
            game = try await chessCom.findGame(kind, id: id, username: chessComUsername)
        }
        clearDeleted(game)
        return merge([game], fromSite: true)[0]
    }

    func delete(_ game: ImportedGame) {
        games.removeAll { $0.id == game.id }
        deleted.insert(game.id)
        if let url = game.url { deleted.insert(url) }
        evidenceCache[game.id] = nil
        try? FileManager.default.removeItem(at: reviewURL(game.id))
        save()
    }

    private func clearDeleted(_ game: ImportedGame) {
        deleted.remove(game.id)
        if let url = game.url { deleted.remove(url) }
    }

    /// Site data replaces an earlier copy, which may have gained accuracies or evals since; a paste never overwrites anything.
    /// Either way the first id stays, because the saved review hangs off it.
    @discardableResult
    private func merge(_ incoming: [ImportedGame], fromSite: Bool) -> [ImportedGame] {
        var stored: [ImportedGame] = []
        for game in incoming {
            var game = game
            game.assignSide(chessCom: chessComUsername, lichess: lichessUsername)
            if let i = games.firstIndex(where: { $0.id == game.id || ($0.url != nil && $0.url == game.url) }) {
                if fromSite {
                    game.id = games[i].id
                    game.reviewed = games[i].reviewed
                    game.myAccuracy = games[i].myAccuracy
                    games[i] = game
                }
                stored.append(games[i])
            } else {
                games.append(game)
                stored.append(game)
            }
        }
        games.sort { $0.date > $1.date }
        save()
        return stored
    }

    private func usernamesChanged() {
        for i in games.indices { games[i].assignSide(chessCom: chessComUsername, lichess: lichessUsername) }
        evidenceCache = [:]
        refreshErrors = [:]
        lastRefresh = nil
        reachedOldest = false
        save()
    }

    // MARK: Reviews

    func save(_ review: GameReview, for id: String) throws {
        try FileManager.default.createDirectory(at: reviewsFolder, withIntermediateDirectories: true)
        try JSONEncoder().encode(review).write(to: reviewURL(id), options: .atomic)
        evidenceCache[id] = nil
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        games[i].reviewed = true
        note(review, at: i)
        save()
        WidgetSnapshot.write()
    }

    private func note(_ review: GameReview, at i: Int) {
        if let side = games[i].mySide { games[i].myAccuracy = (side == .white ? review.white : review.black).accuracy }
        Progress.shared.harvest(review, game: games[i])
    }

    /// Reviews finished before mistakes were kept, or before a username was linked.
    func harvestOldReviews() {
        var changed = false
        for i in games.indices where games[i].reviewed && games[i].mySide != nil && games[i].myAccuracy == nil {
            guard let review = review(for: games[i].id), review.isComplete else { continue }
            note(review, at: i)
            changed = true
        }
        if changed { save() }
    }

    /// The card with its note written again in the language the app runs in now, while its game's review can still do that.
    func relocalized(_ card: MistakeCard) -> MistakeCard {
        guard let ply = card.id.split(separator: "#").last.flatMap({ Int($0) }),
              let review = review(for: card.gameID), review.state != nil,
              let pgn = games.first(where: { $0.id == card.gameID }).flatMap({ PGN.parse($0.pgn).first }),
              let replay = try? GameReplay(pgn),
              let note = review.relocalized(replay: replay).moves[safe: ply]?.coach?.text else { return card }
        var copy = card
        copy.note = note
        return copy
    }

    /// A corrupt file counts as no review: it goes away and the game can be analysed again.
    func review(for id: String) -> GameReview? {
        let url = reviewURL(id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let review = try? JSONDecoder().decode(GameReview.self, from: data) { return review }
        try? FileManager.default.removeItem(at: url)
        if let i = games.firstIndex(where: { $0.id == id }), games[i].reviewed {
            games[i].reviewed = false
            save()
        }
        return nil
    }

    /// Times you missed or walked into each motif, by Lichess theme tag. Only your own moves count,
    /// so a game where the username matches neither player adds nothing.
    var missedTacticEvidence: [String: Double] {
        var total: [String: Double] = [:]
        for game in games where game.reviewed && game.mySide != nil {
            let counts = evidenceCache[game.id] ?? review(for: game.id).map { Self.evidence(in: $0, side: game.mySide) }
            evidenceCache[game.id] = counts
            for (tag, n) in counts ?? [:] { total[tag, default: 0] += n }
        }
        return total
    }

    /// A Miss is about the line you had, from the position before the move. A Blunder is about the line you allowed,
    /// from the position after it, or failing that the line you gave up.
    nonisolated static func evidence(in review: GameReview, side: Side?) -> [String: Double] {
        var counts: [String: Double] = [:]
        guard var board = Position(fen: review.startFEN) else { return counts }
        for reviewed in review.moves {
            guard let move = board.move(uci: reviewed.uci) else { break }
            let after = board.applying(move)
            if reviewed.side == side {
                let tag: String?
                switch reviewed.moveClass {
                case .miss: tag = motifTag(on: board, line: reviewed.bestLine)
                case .blunder: tag = motifTag(on: after, line: reviewed.refutation) ?? motifTag(on: board, line: reviewed.bestLine)
                default: tag = nil
                }
                if let tag { counts[tag, default: 0] += 1 }
            }
            board = after
        }
        return counts
    }

    /// What the line teaches: its mate if it ends in one, otherwise the tactic its first move shows.
    nonisolated static func motifTag(on board: Position, line: [Move]) -> String? {
        var replay = board
        for move in line {
            guard replay.isLegal(move) else { break }
            replay = replay.applying(move)
            if replay.isCheckmate { return replay.isBackRankMate ? "backRankMate" : "mate" }
        }
        switch Coach.findMotif(on: board, line: line)?.motif {
        case .fork: return "fork"
        case .pin: return "pin"
        case .skewer: return "skewer"
        case .discovered: return "discoveredAttack"
        case .hanging: return "hangingPiece"
        case .trapped: return "trappedPiece"
        case .promotion: return "promotion"
        case nil: return nil
        }
    }

    // MARK: Files

    private struct Snapshot: Codable {
        var games: [ImportedGame]
        var deleted: Set<String>

        init(games: [ImportedGame], deleted: Set<String>) {
            self.games = games
            self.deleted = deleted
        }

        /// One unreadable game does not cost the rest of the library.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            games = try c.decode([Lenient<ImportedGame>].self, forKey: .games).compactMap(\.value)
            deleted = (try? c.decode(Set<String>.self, forKey: .deleted)) ?? []
        }
    }

    private var libraryURL: URL { folder.appending(path: "library.json") }
    private var reviewsFolder: URL { folder.appending(path: "Reviews", directoryHint: .isDirectory) }

    /// Ids hold remote text, so they never reach the path as they are.
    private func reviewURL(_ id: String) -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")) ?? "invalid"
        return reviewsFolder.appending(path: safe + ".json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            let aside = libraryURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: libraryURL, to: aside)
            return
        }
        games = snapshot.games
        deleted = snapshot.deleted
        for i in games.indices { games[i].reviewed = FileManager.default.fileExists(atPath: reviewURL(games[i].id).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Snapshot(games: games, deleted: deleted)) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: libraryURL, options: .atomic)
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

private extension Position {
    /// Mated on the home rank by a piece on that rank, with the squares in front of the king blocked by its own men.
    var isBackRankMate: Bool {
        guard isCheckmate, let king = king(of: side) else { return false }
        let rank = king / 8, file = king % 8, forward = side == .white ? 1 : -1
        guard rank == (side == .white ? 0 : 7) else { return false }
        let front = (max(file - 1, 0)...min(file + 1, 7)).map { (rank + forward) * 8 + $0 }
        return front.allSatisfy { piece(at: $0)?.side == side } && attackers(of: king, by: side.opposite).contains { $0 / 8 == rank }
    }
}
