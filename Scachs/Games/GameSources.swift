import Foundation

// MARK: Errors

enum ImportError: LocalizedError, Equatable {
    case userNotFound, rateLimited, offline, lichessLoginRequired
    case chessComUsernameNeeded, chessComRefused, chessComDataGone, computerGame
    case gameNotFound, invalidLink, notStandard, noGames, unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .userNotFound: return String(localized: "Usuari no trobat")
        case .rateLimited: return String(localized: "Massa peticions: torna-hi d'aquí a un minut")
        case .offline: return String(localized: "Sense connexió")
        case .lichessLoginRequired: return String(localized: "Lichess demana iniciar sessió per a aquesta partida")
        case .chessComUsernameNeeded: return String(localized: "Per trobar aquesta partida cal el teu usuari de chess.com")
        case .chessComRefused: return String(localized: "chess.com no ha acceptat la petició")
        case .chessComDataGone: return String(localized: "chess.com ja no ofereix aquestes dades")
        case .computerGame: return String(localized: "Les partides contra l'ordinador de chess.com no es poden importar amb l'enllaç")
        case .gameNotFound: return String(localized: "No hem trobat aquesta partida")
        case .invalidLink: return String(localized: "Aquest enllaç no és d'una partida")
        case .notStandard: return String(localized: "Només importem partides d'escacs estàndard")
        case .noGames: return String(localized: "No hi hem trobat cap partida")
        case .unexpectedResponse: return String(localized: "Resposta inesperada del servidor")
        }
    }

    /// The way out is a PGN paste, so the UI should offer one next to the message.
    var offersPGNPaste: Bool {
        switch self {
        case .lichessLoginRequired, .chessComUsernameNeeded, .chessComRefused, .computerGame, .gameNotFound, .invalidLink: return true
        default: return false
        }
    }
}

// MARK: Pasted links

enum ChessComKind: String { case live, daily, computer }

/// A game link. Only ever read for its id: the pasted URL itself is never fetched.
enum GameLink: Equatable {
    case chessCom(ChessComKind, id: String)     // numeric, or a lowercase uuid
    case lichess(id: String)                    // always the 8-char game id, case kept

    /// Finds the link in pasted text, which on a phone is often share text around the URL.
    static func parse(_ text: String) -> GameLink? {
        for token in text.split(whereSeparator: \.isWhitespace) {
            if let link = chessCom(String(token)) ?? lichess(String(token)) { return link }
        }
        return nil
    }

    private static let uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
    private static let chessComPattern = try! Regex(
        #"(?:https?://)?(?:www\.)?chess\.com(?:/[a-z]{2}(?:-[a-z]{2})?)?/(?:(?:analysis/)?game/(live|daily|computer)/(\d+|"# + uuid +
        #")|(live|daily)/game/(\d+)|(livechess|echess)/game\?(?:[^#]*&)?id=(\d+))(?:[/?#].*)?"#
    ).ignoresCase().asciiOnlyDigits()
    private static let lichessPattern = try! Regex(
        #"(?:https?://)?(?:www\.)?lichess\.org/(game/export/|embed/game/|game/|embed/)?([A-Za-z0-9]{8})([A-Za-z0-9]{4})?(?:\.pgn)?(?:/(?:white|black)(?:/analysis)?)?/?(?:[?#].*)?"#
    ).ignoresCase()
    /// Eight-letter site routes that would otherwise look like a root-level game id.
    private static let lichessRoutes: Set<String> = ["analysis", "bookmark", "features", "insights", "markdown", "password", "practice", "streamer", "timeline", "training"]

    private static func chessCom(_ s: String) -> GameLink? {
        guard let m = s.wholeMatch(of: chessComPattern) else { return nil }
        for group in [1, 3, 5] {
            guard let type = m.output[group].substring, let id = m.output[group + 1].substring else { continue }
            switch type.lowercased() {
            case "live", "livechess": return .chessCom(.live, id: id.lowercased())
            case "daily", "echess": return .chessCom(.daily, id: id.lowercased())
            default: return .chessCom(.computer, id: id.lowercased())
            }
        }
        return nil
    }

    private static func lichess(_ s: String) -> GameLink? {
        guard let m = s.wholeMatch(of: lichessPattern), let id = m.output[2].substring else { return nil }
        if m.output[1].substring == nil, lichessRoutes.contains(id.lowercased()) { return nil }
        return .lichess(id: String(id))
    }
}

// MARK: HTTP

enum GameHTTP {
    /// Goes out from every install and is public to both sites, so never a personal address. chess.com's policy asks for contact details.
    /// Lichess's crawler filter is a case-sensitive substring match on the whole UA, so this must not contain curl, wget, okhttp...
    static let contact = "github.com/Jsolee/chess-puzzle-app"

    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return "Scachs/\(version) (iOS; contact: \(contact))"
    }

    /// Ephemeral with no cookies: chess.com's visitorid cookie embeds the device's public IP.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    static func mapped(_ error: Error) -> Error {
        guard let e = error as? URLError else { return error }
        switch e.code {
        case .cancelled: return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .secureConnectionFailed:
            return ImportError.offline
        default: return ImportError.unexpectedResponse
        }
    }

    /// Usernames go into a URL path, so anything but the site's own alphabet stops here.
    static func validated(username: String) throws -> String {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.wholeMatch(of: #/[A-Za-z0-9_-]{1,40}/#) != nil else { throw ImportError.userNotFound }
        return name
    }

    static func contentType(_ r: HTTPURLResponse) -> String {
        (r.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
    }
}

/// One request at a time per site, as both APIs ask. An actor alone would not do it: it re-enters at every await.
private actor RequestGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
    }

    func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }

    func send(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        await enter()
        defer { leave() }
        do {
            let (data, response) = try await session.data(for: request, delegate: SameHostRedirects.shared)
            guard let http = response as? HTTPURLResponse else { throw ImportError.unexpectedResponse }
            return (data, http)
        } catch {
            throw GameHTTP.mapped(error)
        }
    }
}

/// Keeps the app on the host it asked for, whatever a response points at.
private final class SameHostRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = SameHostRedirects()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        request.url?.host == task.originalRequest?.url?.host ? request : nil
    }
}

/// One bad element is skipped instead of failing the whole month or stream.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) { value = try? T(from: decoder) }
}

// MARK: chess.com

/// Official PubAPI only. No /callback/ endpoint and no TCN decoding: the User Agreement bars both.
struct ChessComClient {
    var session = GameHTTP.session
    private static let gate = RequestGate()
    private static let base = "https://api.chess.com/pub"
    /// Archives only list months with games, so this reaches well back. It stops a variants-only account, or a link to
    /// someone else's game, from walking 15 years of months. Past it a link reports not found and offers a PGN paste.
    private static let monthCap = 24

    /// Newest first. With `before`, only games that ended earlier than that, for walking back through a history.
    func recentGames(username: String, limit: Int = 20, before: Date? = nil) async throws -> [ImportedGame] {
        let user = try GameHTTP.validated(username: username).lowercased()
        var found: [ImportedGame] = []
        let lastMonth = before.map(Self.monthKey)
        for month in try await archiveMonths(user).filter({ lastMonth == nil || $0 <= lastMonth! }).prefix(Self.monthCap) {
            for game in try await games(user, month: month).sorted(by: { ($0.endTime ?? 0) > ($1.endTime ?? 0) }) {
                if let before, (game.endTime ?? 0) >= before.timeIntervalSince1970 { continue }
                guard let imported = game.imported() else { continue }
                found.append(imported)
                if found.count == limit { return found }
            }
        }
        return found
    }

    private static func monthKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d/%02d", c.year ?? 0, c.month ?? 0)
    }

    /// chess.com has no official single-game endpoint, so a link is searched for in the player's own months.
    /// Live and daily ids overlap and point at different games, so the kind has to match too.
    func findGame(_ kind: ChessComKind, id: String, username: String) async throws -> ImportedGame {
        guard kind != .computer else { throw ImportError.computerGame }
        let user = try GameHTTP.validated(username: username).lowercased()
        for month in try await archiveMonths(user).prefix(Self.monthCap) {
            guard let match = try await games(user, month: month).first(where: { $0.matches(kind, id: id) }) else { continue }
            guard let imported = match.imported() else { throw ImportError.notStandard }
            return imported
        }
        throw ImportError.gameNotFound
    }

    /// Newest first. "YYYY/MM" as the API writes them, zero-padded: /2026/1 is a 404.
    func archiveMonths(_ user: String) async throws -> [String] {
        struct Archives: Decodable { let archives: [String] }
        let data = try await get("/player/\(user)/games/archives")
        guard let list = try? JSONDecoder().decode(Archives.self, from: data) else { throw ImportError.unexpectedResponse }
        return list.archives.reversed().compactMap { url in
            guard let m = url.firstMatch(of: #/\/(\d{4})\/(\d{2})$/#) else { return nil }
            return "\(m.1)/\(m.2)"
        }
    }

    func games(_ user: String, month: String) async throws -> [ChessComGame] {
        try Self.decodeMonth(try await get("/player/\(user)/games/\(month)"))
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: Self.base + path) else { throw ImportError.unexpectedResponse }
        var request = URLRequest(url: url)
        request.setValue(GameHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.gate.send(request, session: session)
        try Self.check(response)
        return data
    }

    /// A Cloudflare challenge is an HTML 403 a native client cannot solve, so it is never retried or decoded.
    static func check(_ r: HTTPURLResponse) throws {
        if r.value(forHTTPHeaderField: "cf-mitigated") != nil { throw ImportError.chessComRefused }
        switch r.statusCode {
        case 200:
            guard GameHTTP.contentType(r).contains("json") else { throw ImportError.chessComRefused }
        case 404: throw ImportError.userNotFound
        case 410: throw ImportError.chessComDataGone
        case 429: throw ImportError.rateLimited
        case 403: throw ImportError.chessComRefused
        default: throw ImportError.unexpectedResponse
        }
    }

    /// Bad elements are skipped; a body that is not a month at all is an error, not an empty month.
    static func decodeMonth(_ data: Data) throws -> [ChessComGame] {
        struct Month: Decodable { let games: [Lenient<ChessComGame>] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let month = try? decoder.decode(Month.self, from: data) else { throw ImportError.unexpectedResponse }
        return month.games.compactMap(\.value)
    }
}

struct ChessComGame: Decodable {
    struct Player: Decodable { let username: String; let rating: Int?; let result: String? }
    struct Accuracies: Decodable { let white: Double?; let black: Double? }
    let url: String
    let uuid: String?
    let pgn: String?           // absent on bughouse
    let rules: String?
    let initialSetup: String?  // sometimes only 4 FEN fields
    let timeClass: String?
    let endTime: Double?
    let white: Player
    let black: Player
    let accuracies: Accuracies?

    func matches(_ kind: ChessComKind, id: String) -> Bool {
        if id.contains("-") { return uuid?.lowercased() == id }
        return GameLink.parse(url) == .chessCom(kind, id: id)
    }

    /// nil unless it is standard chess from the normal start with at least one move.
    /// rules == "chess" is not enough: odds and from-position games also say "chess".
    func imported() -> ImportedGame? {
        guard rules == "chess", isStandardStart(initialSetup), let pgn,
              let parsed = PGN.parse(pgn).first, parsed.hasStandardStart, !parsed.moves.isEmpty else { return nil }
        let timeClass = timeClass.flatMap(TimeClass.init(rawValue:)) ?? TimeClass(timeControl: parsed.tags["TimeControl"])
        return ImportedGame(
            id: "chesscom-\(uuid ?? url)",
            source: .chessCom,
            url: url,
            white: white.username, black: black.username,
            whiteRating: white.rating, blackRating: black.rating,
            result: parsed.result,
            termination: Termination(chessComWhite: white.result, black: black.result),
            timeClass: timeClass,
            date: endTime.map(Date.init(timeIntervalSince1970:)) ?? parsed.playedDate,
            pgn: timeClass == .daily ? ImportedGame.strippingClocks(pgn) : pgn,
            whiteAccuracy: accuracies?.white, blackAccuracy: accuracies?.black
        )
    }
}

/// Compares the first four FEN fields only, since many archive months carry 4-field FENs. Absent means nothing to contradict.
private func isStandardStart(_ fen: String?) -> Bool {
    guard let fen, !fen.isEmpty else { return true }
    return fen.split(separator: " ").prefix(4).joined(separator: " ") == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
}

extension PGNGame {
    /// chess.com odds games and Lichess from-position games carry SetUp and a FEN; replaying them from the normal start gives illegal moves.
    var hasStandardStart: Bool {
        if let variant = tags["Variant"], variant.lowercased() != "standard" { return false }
        return tags["SetUp"] == "0" || isStandardStart(tags["FEN"])
    }

    var playedDate: Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy.MM.dd HH:mm:ss"
        let day = tags["UTCDate"] ?? tags["Date"] ?? ""
        return f.date(from: "\(day) \(tags["UTCTime"] ?? "00:00:00")") ?? .distantPast
    }
}

// MARK: Lichess

struct LichessClient {
    var session = GameHTTP.session
    private static let gate = RequestGate()
    private static let extras = ["pgnInJson", "clocks", "evals", "accuracy", "opening", "division"].map { URLQueryItem(name: $0, value: "true") }

    func recentGames(username: String, limit: Int = 20, before: Date? = nil) async throws -> [ImportedGame] {
        let user = try GameHTTP.validated(username: username)
        var parts = URLComponents(string: "https://lichess.org/api/games/user/\(user)")
        // perfType keeps variants from using up the max before the standard-chess filter runs.
        parts?.queryItems = [URLQueryItem(name: "max", value: String(limit)),
                             URLQueryItem(name: "perfType", value: "ultraBullet,bullet,blitz,rapid,classical,correspondence")] + Self.extras
        if let before { parts?.queryItems?.append(URLQueryItem(name: "until", value: String(Int64(before.timeIntervalSince1970 * 1000)))) }
        guard let url = parts?.url else { throw ImportError.unexpectedResponse }
        var request = URLRequest(url: url)
        let data = try await send(&request)
        return Self.decode(data).compactMap { $0.imported() }
    }

    /// POST _ids because GET /game/export is login-only for most older games since 2026-10.
    func game(id: String) async throws -> ImportedGame {
        guard id.wholeMatch(of: #/[A-Za-z0-9]{8}/#) != nil else { throw ImportError.invalidLink }
        var parts = URLComponents(string: "https://lichess.org/api/games/export/_ids")
        parts?.queryItems = Self.extras
        guard let url = parts?.url else { throw ImportError.unexpectedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(id.utf8)
        // A root-level 8-char name can be a username; _ids answers those 200 with an empty body.
        guard let game = Self.decode(try await send(&request)).first else { throw ImportError.gameNotFound }
        guard let imported = game.imported() else { throw ImportError.notStandard }
        return imported
    }

    private func send(_ request: inout URLRequest) async throws -> Data {
        request.setValue(GameHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.gate.send(request, session: session)
        try Self.check(response)
        return data
    }

    /// A default URLSession follows the 303 to /signup, so a login wall can arrive as a 200 with an HTML body. Unknown users are HTML too.
    static func check(_ r: HTTPURLResponse) throws {
        switch r.statusCode {
        case 200:
            let type = GameHTTP.contentType(r)
            if type.contains("html") || r.url?.path.hasPrefix("/signup") == true { throw ImportError.lichessLoginRequired }
            guard type.contains("json") else { throw ImportError.unexpectedResponse }
        case 303, 401: throw ImportError.lichessLoginRequired
        case 404: throw ImportError.userNotFound
        case 429: throw ImportError.rateLimited
        default: throw ImportError.unexpectedResponse
        }
    }

    static func decode(_ data: Data) -> [LichessGame] {
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(LichessGame.self, from: Data($0)) }
    }
}

struct LichessGame: Decodable {
    struct Player: Decodable {
        struct User: Decodable { let name: String }
        struct Analysis: Decodable { let accuracy: Double? }
        let user: User?          // absent for the AI and for anonymous players
        let aiLevel: Int?
        let rating: Int?
        let analysis: Analysis?

        var displayName: String {
            if let user { return user.name }
            if let aiLevel { return String(localized: "IA nivell \(aiLevel)") }
            return String(localized: "Anònim")
        }
    }
    struct Players: Decodable { let white: Player; let black: Player }
    struct Eval: Decodable { let eval: Int?; let mate: Int? }

    let id: String
    let variant: String?
    let speed: String?
    let status: String?
    let createdAt: Double?
    let lastMoveAt: Double?
    let pgn: String?
    let initialFen: String?
    let players: Players
    let analysis: [Eval]?

    private static let unplayed: Set<String> = ["created", "started", "aborted", "noStart"]

    /// nil unless it is standard chess from the normal start with at least one move.
    func imported() -> ImportedGame? {
        guard variant == "standard", isStandardStart(initialFen), !Self.unplayed.contains(status ?? ""), let pgn,
              let parsed = PGN.parse(pgn).first, parsed.hasStandardStart, !parsed.moves.isEmpty else { return nil }
        let white = players.white, black = players.black
        let millis = lastMoveAt ?? createdAt
        let timeClass: TimeClass = speed == "correspondence" ? .daily : speed.flatMap(TimeClass.init(rawValue:)) ?? TimeClass(timeControl: parsed.tags["TimeControl"])
        return ImportedGame(
            id: "lichess-\(id)",
            source: .lichess,
            url: "https://lichess.org/game/\(id)",
            white: white.displayName, black: black.displayName,
            whiteRating: white.rating, blackRating: black.rating,
            result: parsed.result,
            termination: Termination(lichessStatus: status),
            timeClass: timeClass,
            date: millis.map { Date(timeIntervalSince1970: $0 / 1000) } ?? parsed.playedDate,
            pgn: pgn,
            whiteAccuracy: white.analysis?.accuracy, blackAccuracy: black.analysis?.accuracy,
            lichessEvals: analysis?.map { PlyEval(cp: $0.eval, mate: $0.mate) }
        )
    }
}
