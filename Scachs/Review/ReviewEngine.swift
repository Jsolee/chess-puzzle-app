import Foundation

// MARK: - Model

struct Ratings: Hashable, Codable, Sendable {
    var white: Int?
    var black: Int?

    init(white: Int? = nil, black: Int? = nil) {
        self.white = white
        self.black = black
    }

    /// From the game's Elo headers. A player without one borrows `fallback`, then the other player's.
    init(game: PGNGame, fallback: Int? = nil) {
        func header(_ key: String) -> Int? { game.tags[key].flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } }
        white = header("WhiteElo") ?? fallback ?? header("BlackElo")
        black = header("BlackElo") ?? fallback ?? header("WhiteElo")
    }

    func rating(for side: Side) -> Int? { side == .white ? white : black }
}

struct GameReview: Codable, Sendable, Identifiable {
    struct ReviewedMove: Codable, Sendable, Identifiable {
        /// Zero-based, so ply 0 is White's first move in a normal game.
        var ply: Int
        var side: Side
        var san: String
        var uci: String
        /// Nil while its evals are still missing.
        var moveClass: MoveClass?
        /// White's point of view. Nil on book moves, which get no search. After mate on the board these
        /// read `.mate(1)` when White has mated and `.mate(0)` when White is mated.
        var evalBefore: Score?
        var evalAfter: Score?
        var bestMove: Move?
        var bestSAN: String?
        var bestLine: [Move]
        /// Engine line after the played move, opponent's reply first.
        var refutation: [Move]
        /// Expected points between the best and second-best move. Nil without a deep search.
        var secondBestGap: Double?
        var epLost: Double
        var clock: Double?
        var coach: CoachNote?
        var isKey: Bool
        var wasDeepSearched: Bool

        var id: Int { ply }
    }

    struct PlayerReview: Codable, Sendable {
        var accuracy: Double?
        var counts: [MoveClass: Int]
        /// A playful estimate for this one game. Never present it as a rating.
        var gameRating: Int?
        var averageCentipawnLoss: Double?
    }

    struct PhaseReview: Codable, Sendable, Identifiable {
        struct Grade: Codable, Sendable {
            var accuracy: Double?
            /// Nil when the phase was already decided for most of its length.
            var grade: MoveClass?
        }
        var phase: GamePhase
        var firstPly: Int
        var lastPly: Int
        var white: Grade
        var black: Grade

        var id: GamePhase { phase }
    }

    struct EngineInfo: Codable, Sendable {
        var name: String
        var firstPassNodes: Int
        var deepPassNodes: Int
        var searchedPositions: Int
        var deepPlies: Int
        var averageDepth: Double?
        var maxDepth: Int?
    }

    var id: String
    var startFEN: String
    var moves: [ReviewedMove]
    var white: PlayerReview
    var black: PlayerReview
    var phases: [PhaseReview]
    var opening: Openings.Entry?
    var engine: EngineInfo
    var isComplete: Bool
    /// White's score per position, all at the first pass's budget so the line stays smooth.
    var whiteEvals: [Score?] = []

    /// White win percent per position, for the graph. Nil where the eval is not known yet.
    var graph: [Double?] { whiteEvals.map { $0.map(Accuracy.winPercent) } }
}

/// Everything the engine found so far. Pure data, so a review can resume after being killed
/// and tests can hand-feed it without an engine.
struct ReviewState: Codable, Sendable {
    struct Search: Hashable, Codable, Sendable {
        /// Side to move's view.
        var score: Score
        var line: [Move]
        var depth: Int = 0
        var nodes: Int = 0

        init(score: Score, line: [Move] = [], depth: Int = 0, nodes: Int = 0) {
            self.score = score
            self.line = line
            self.depth = depth
            self.nodes = nodes
        }

        init(_ line: EngineLine) {
            self.init(score: line.score, line: line.pv, depth: line.depth, nodes: line.nodes)
        }
    }

    struct DeepSearch: Hashable, Codable, Sendable {
        var best: Search
        var second: Search?
        /// The played move, searched alone, when it is not the best. Its line starts with that move.
        var played: Search?
        var threat: ThreatLine?
        /// Stopped at the quick look, since the top move had no real rival.
        var isProbe = false
    }

    var gameID: String
    /// First pass, one per position including the start and the final one.
    var shallow: [Search?]
    /// Deep pass, one per ply.
    var deep: [DeepSearch?]

    init(gameID: String, positions: Int) {
        self.gameID = gameID
        shallow = Array(repeating: nil, count: positions)
        deep = Array(repeating: nil, count: max(positions - 1, 0))
    }

    /// The best knowledge of a position.
    func top(_ position: Int) -> Search? {
        if position < deep.count, let d = deep[position], !d.isProbe { return d.best }
        return position < shallow.count ? shallow[position] : nil
    }
}

enum ReviewError: Error, Equatable {
    case invalidStart
    case illegalMove(ply: Int)
}

/// A game replayed once, with what the classifier asks of each position.
struct GameReplay: Sendable {
    let game: PGNGame
    let startFEN: String
    let moves: [Move]
    let positions: [Position]
    /// Exactly one legal move here, so the search can be skipped when the game goes on.
    let isForced: [Bool]
    let id: String

    init(_ game: PGNGame) throws {
        let fen = game.startFEN ?? Position.start.fen
        guard var position = Position(fen: fen) else { throw ReviewError.invalidStart }
        var positions = [position]
        for (ply, pgnMove) in game.moves.enumerated() {
            guard position.isLegal(pgnMove.move) else { throw ReviewError.illegalMove(ply: ply) }
            position = position.applying(pgnMove.move)
            positions.append(position)
        }
        self.game = game
        startFEN = fen
        moves = game.moves.map(\.move)
        self.positions = positions
        let plies = game.moves.count
        isForced = positions.enumerated().map { $0.offset < plies && $0.element.legalMoves().count == 1 }

        // FNV-1a: stable across launches, unlike Hasher.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(fen)|\(moves.map(\.uci).joined(separator: " "))".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        id = String(hash, radix: 16)
    }

    func terminalScore(at position: Int) -> Score? {
        let board = positions[position]
        if board.isCheckmate { return .mate(0) }
        return board.isStalemate || board.hasInsufficientMaterial ? .cp(0) : nil
    }
}

// MARK: - Review

enum ReviewEngine {
    static let engineName = "Stockfish 19"
    // Budgets from the two-pass design, none of them measured on a device yet.
    static let firstPassNodes = 150_000
    static let firstPassMoveTimeMs = 800
    static let deepPassNodes = 1_000_000
    static let deepPassMoveTimeMs = 2_500
    static let threatNodes = 150_000
    static let probeNodes = 100_000
    static let firstPassProgressShare = 0.35
    /// Longest rest between searches on a warm device.
    static let maxRestSeconds = 1.5

    /// Runs the two passes and returns the finished review.
    ///
    /// Resumes from the state saved in `directory` for this game, if any. `evals` gets White's score per
    /// position as they come in, so a graph can render long before the end. Task cancellation stops the
    /// search and throws, keeping what was found so far.
    static func review(
        game: PGNGame,
        ratings: Ratings,
        engine: Engine = .shared,
        openings: Openings = .shared,
        directory: URL? = nil,
        searchThreats: Bool = true,
        evals: (([Score?]) -> Void)? = nil,
        progress: (Double) -> Void
    ) async throws -> GameReview {
        let replay = try GameReplay(game)
        let file = stateFile(gameID: replay.id, directory: directory)
        var state = loadState(file, replay: replay) ?? ReviewState(gameID: replay.id, positions: replay.positions.count)
        let book = openings.bookPlies(start: replay.positions[0], moves: replay.moves)

        if state.shallow.allSatisfy({ $0 == nil }) { await engine.clearHash() }

        try await firstPass(&state, replay, book, engine, file, evals, progress)
        try await deepPass(&state, replay, ratings, book, engine, file, searchThreats, evals, progress)

        progress(1)
        try? FileManager.default.removeItem(at: file)
        return assemble(replay: replay, state: state, ratings: ratings, openings: openings)
    }

    // MARK: First pass

    private static func firstPass(
        _ state: inout ReviewState, _ replay: GameReplay, _ book: Int, _ engine: Engine, _ file: URL,
        _ evals: (([Score?]) -> Void)?, _ progress: (Double) -> Void
    ) async throws {
        let last = replay.moves.count
        let total = max(last - book + 1, 1)
        for p in book...last {
            if state.shallow[p] == nil {
                if let terminal = replay.terminalScore(at: p) {
                    state.shallow[p] = ReviewState.Search(score: terminal)
                } else if !replay.isForced[p] {
                    let started = Date()
                    let lines = try await engine.analyse(
                        startFEN: replay.startFEN, moves: Array(replay.moves[..<p]), multiPV: 1,
                        nodes: Engine.budget(firstPassNodes), movetimeMs: firstPassMoveTimeMs, searchMoves: nil, onUpdate: nil)
                    guard let top = lines.first else { throw CancellationError() }
                    state.shallow[p] = ReviewState.Search(top)
                    try await rest(after: Date().timeIntervalSince(started))
                }
                fillForced(&state, replay, before: p)
                save(state, to: file)
                evals?(whiteScores(state, replay, book: book))
            }
            progress(firstPassProgressShare * Double(p - book + 1) / Double(total))
        }
    }

    /// A position with one legal move is worth what the next one is worth, so it needs no search.
    private static func fillForced(_ state: inout ReviewState, _ replay: GameReplay, before p: Int) {
        var i = p - 1
        while i >= 0, replay.isForced[i], state.shallow[i] == nil, let next = state.shallow[i + 1] {
            state.shallow[i] = ReviewState.Search(score: next.score.flipped, line: [replay.moves[i]] + next.line, depth: next.depth)
            i -= 1
        }
    }

    // MARK: Deep pass

    private static func deepPass(
        _ state: inout ReviewState, _ replay: GameReplay, _ ratings: Ratings, _ book: Int, _ engine: Engine, _ file: URL,
        _ threats: Bool, _ evals: (([Score?]) -> Void)?, _ progress: (Double) -> Void
    ) async throws {
        // The set is worked out again after each search, since a deeper eval can pull a neighbour into it.
        var done = 0
        var shown = firstPassProgressShare
        while let ply = deepCandidates(replay, state, ratings, book: book).first {
            let started = Date()
            let reason = facts(ply: ply, replay: replay, state: state, ratings: ratings, book: book).flatMap(deepReason)
            let probe = reason == .onlyMove || reason == .punish
            state.deep[ply] = try await deepSearch(replay, ply: ply, engine: engine, threats: threats, probe: probe,
                                                   rating: ratings.rating(for: replay.positions[ply].side))
            done += 1
            save(state, to: file)
            evals?(whiteScores(state, replay, book: book))
            let remaining = deepCandidates(replay, state, ratings, book: book).count
            let share = Double(done) / Double(done + remaining)
            shown = max(shown, firstPassProgressShare + (1 - firstPassProgressShare) * share)
            progress(shown)
            try await rest(after: Date().timeIntervalSince(started))
        }
    }

    private static func deepSearch(_ replay: GameReplay, ply: Int, engine: Engine, threats: Bool, probe: Bool, rating: Int?) async throws -> ReviewState.DeepSearch {
        let moves = Array(replay.moves[..<ply])
        let played = replay.moves[ply]
        if probe {
            // Most top moves have a rival close by, and a cheap MultiPV 2 on a primed hash shows it.
            let lines = try await engine.analyse(
                startFEN: replay.startFEN, moves: moves, multiPV: 2,
                nodes: Engine.budget(probeNodes), movetimeMs: firstPassMoveTimeMs, searchMoves: nil, onUpdate: nil)
            guard let top = lines.first else { throw CancellationError() }
            if top.pv.first == played, lines.count > 1 {
                let gap = ExpectedPoints.loss(best: top.score, played: lines[1].score, rating: rating)
                if gap < Thresholds.probeEscalateGap { return ReviewState.DeepSearch(best: ReviewState.Search(top), isProbe: true) }
            }
        }
        let lines = try await engine.analyse(
            startFEN: replay.startFEN, moves: moves, multiPV: 2,
            nodes: Engine.budget(deepPassNodes), movetimeMs: deepPassMoveTimeMs, searchMoves: nil, onUpdate: nil)
        guard let top = lines.first else { throw CancellationError() }
        var deep = ReviewState.DeepSearch(best: ReviewState.Search(top), second: lines.dropFirst().first.map { ReviewState.Search($0) })

        if top.pv.first != played {
            if let second = deep.second, second.line.first == played {
                deep.played = second
            } else {
                let alone = try await engine.analyse(
                    startFEN: replay.startFEN, moves: moves, multiPV: 1,
                    nodes: Engine.budget(deepPassNodes), movetimeMs: deepPassMoveTimeMs, searchMoves: [played], onUpdate: nil)
                guard let line = alone.first else { throw CancellationError() }
                deep.played = ReviewState.Search(line)
            }
        }
        if threats, let board = replay.positions[ply].nullMoved {
            let lines = try await engine.analyse(
                startFEN: board.fen, moves: [], multiPV: 1,
                nodes: Engine.budget(threatNodes), movetimeMs: firstPassMoveTimeMs, searchMoves: nil, onUpdate: nil)
            if let line = lines.first, !line.pv.isEmpty { deep.threat = ThreatLine(line: line.pv, score: line.score) }
        }
        return deep
    }

    /// Plies that still deserve a deep search.
    static func deepCandidates(_ replay: GameReplay, _ state: ReviewState, _ ratings: Ratings, book: Int) -> [Int] {
        guard book < replay.moves.count else { return [] }
        return (book..<replay.moves.count).filter { ply in
            guard state.deep[ply] == nil, !replay.isForced[ply],
                  let f = facts(ply: ply, replay: replay, state: state, ratings: ratings, book: book) else { return false }
            // The next position's deep search can show a tactic the shallow look at this move missed.
            if ply + 1 < state.deep.count, let next = state.deep[ply + 1]?.best, !f.isTopMove,
               ExpectedPoints.loss(best: f.best, played: next.score.flipped, rating: f.rating) >= Thresholds.bandMistake {
                return true
            }
            return deepReason(f) != nil
        }
    }

    enum DeepReason { case band, sacrifice, punish, onlyMove }

    /// Why a move deserves the deep pass: near a band edge, Inaccuracy or worse, or a possible Great or Brilliant.
    static func deepReason(_ f: MoveFacts) -> DeepReason? {
        if f.after.isCheckmate { return nil }
        let loss = f.epLoss
        if loss >= Thresholds.bandInaccuracy { return .band }
        for edge in [Thresholds.bandGood, Thresholds.bandInaccuracy] where abs(loss - edge) <= edge * Thresholds.nearBandFraction {
            return .band
        }
        // The real sacrifice rule, with the runner-up it cannot know yet assumed harmless.
        var hopeful = f
        hopeful.second = .cp(0)
        if Classifier.sacrifice(hopeful, loss: loss, gap: 1) != nil { return .sacrifice }
        guard f.isTopMove, !f.before.inCheck else { return nil }
        if let previous = f.previous, previous.epLost >= Thresholds.deepOpponentLoss, f.epPlayed >= Thresholds.losingBelow { return .punish }
        return f.epPlayed >= Thresholds.greatMinEPAfter && f.epPlayed <= Thresholds.deepCandidateMaxEP ? .onlyMove : nil
    }

    // MARK: Facts

    /// The classifier's input for one ply, or nil while its evals are missing.
    static func facts(ply i: Int, replay: GameReplay, state: ReviewState, ratings: Ratings, book: Int) -> MoveFacts? {
        let before = replay.positions[i]
        let move = replay.moves[i]
        let rating = ratings.rating(for: before.side)
        if i < book {
            return MoveFacts(before: before, move: move, rating: rating, isBook: true, best: .cp(0), played: .cp(0))
        }
        guard let top = state.top(i), let played = playedLook(ply: i, replay: replay, state: state, rating: rating) else { return nil }

        var previous: MoveFacts.Previous?
        if i > 0 {
            var lost = 0.0
            var evalBefore: Score?
            if i - 1 >= book, !replay.isForced[i - 1], let earlier = state.top(i - 1) {
                evalBefore = earlier.score.flipped
                let opponentRating = ratings.rating(for: replay.positions[i - 1].side)
                if earlier.line.first != replay.moves[i - 1],
                   let theirs = playedLook(ply: i - 1, replay: replay, state: state, rating: opponentRating) {
                    lost = ExpectedPoints.loss(best: earlier.score, played: theirs.score, rating: opponentRating)
                }
            }
            previous = MoveFacts.Previous(before: replay.positions[i - 1], move: replay.moves[i - 1], epLost: lost, evalBefore: evalBefore)
        }

        var exchangeFrom = i
        while exchangeFrom > 0, replay.positions[exchangeFrom - 1].captured(by: replay.moves[exchangeFrom - 1]) != nil { exchangeFrom -= 1 }

        return MoveFacts(before: before, move: move, rating: rating, best: top.score, bestMove: top.line.first, bestLine: top.line,
                         played: played.score, second: state.deep[i]?.second?.score, refutation: played.line, previous: previous,
                         exchangeStart: exchangeFrom < i ? replay.positions[exchangeFrom] : nil,
                         exchange: Array(replay.moves[exchangeFrom..<i]))
    }

    /// What the played move is worth to its mover, and the line after it. Compares like with like, since a
    /// deep best against a shallow reply would label search noise as a mistake. When two equally deep looks
    /// at the move disagree, the noise guard takes the kinder one.
    private static func playedLook(ply i: Int, replay: GameReplay, state: ReviewState, rating: Int?) -> (score: Score, line: [Move])? {
        guard let top = state.top(i) else { return nil }
        if top.line.first == replay.moves[i] { return (top.score, Array(top.line.dropFirst())) }
        var looks: [(score: Score, line: [Move])] = []
        if let deep = state.deep[i], !deep.isProbe {
            if let alone = deep.played { looks.append((alone.score, Array(alone.line.dropFirst()))) }
            if i + 1 < state.deep.count, let next = state.deep[i + 1], !next.isProbe {
                looks.append((next.best.score.flipped, next.best.line))
            }
        }
        if looks.isEmpty, let next = state.shallow[i + 1] { looks.append((next.score.flipped, next.line)) }
        return looks.max { ExpectedPoints.of($0.score, rating: rating) < ExpectedPoints.of($1.score, rating: rating) }
    }

    /// White's score per position, for the accuracy and the graph. They stay on the first pass's budget,
    /// because mixing in deep values reads their disagreement with the shallow ones as lost points. A deep
    /// search only replaces a shallow eval it flatly contradicts. Book positions get no search and take
    /// the first eval after them, so book moves read as losing nothing and count as 100 in the accuracy.
    static func whiteScores(_ state: ReviewState, _ replay: GameReplay, book: Int) -> [Score?] {
        var scores: [Score?] = replay.positions.indices.map { p in
            guard p >= book, let shallow = state.shallow[p] else { return nil }
            let side = replay.positions[p].side
            let first = shallow.score.whitePOV(sideToMove: side)
            guard p < state.deep.count, let deep = state.deep[p], !deep.isProbe else { return first }
            let second = deep.best.score.whitePOV(sideToMove: side)
            return abs(Accuracy.winPercent(first) - Accuracy.winPercent(second)) >= Thresholds.deepOverridesWinPercent ? second : first
        }
        if book > 0, book < scores.count, let first = scores[book] {
            for p in 0..<book { scores[p] = first }
        }
        return scores
    }

    // MARK: Assembly

    /// Builds the review from whatever the state holds. Pure, so tests can feed fixed evals.
    static func assemble(replay: GameReplay, state: ReviewState, ratings: Ratings, openings: Openings = .shared, withCoach: Bool = true) -> GameReview {
        let start = replay.positions[0]
        let opening = openings.name(start: start, moves: replay.moves)
        let book = openings.bookPlies(start: start, moves: replay.moves)
        let scores = whiteScores(state, replay, book: book)

        var moves: [GameReview.ReviewedMove] = []
        for (i, move) in replay.moves.enumerated() {
            let before = replay.positions[i]
            let f = facts(ply: i, replay: replay, state: state, ratings: ratings, book: book)
            let c = f.map(Classifier.classify)
            let coach = withCoach ? f.flatMap { facts in
                c.map { Coach.note(facts: facts, classification: $0, threat: state.deep[i]?.threat,
                                   opening: i < book ? openings.name(start: start, moves: Array(replay.moves[...i])) : opening) }
            } : nil
            let best = i < book ? nil : f?.bestMove
            let isKey = i == book - 1 || c.map { [.brilliant, .great, .mistake, .miss, .blunder].contains($0.moveClass) } ?? false
            // The pair the class was judged on, so the numbers next to a label explain it.
            let after = replay.positions[i + 1]
            let evalBefore = i < book ? nil : f?.best.whitePOV(sideToMove: before.side)
            let evalAfter = i + 1 == book || replay.terminalScore(at: i + 1) != nil ? scores[i + 1]
                : i < book ? nil : f?.played.flipped.whitePOV(sideToMove: after.side)
            moves.append(GameReview.ReviewedMove(
                ply: i, side: before.side, san: before.san(move), uci: move.uci, moveClass: c?.moveClass,
                evalBefore: evalBefore, evalAfter: evalAfter,
                bestMove: best, bestSAN: best.flatMap { before.isLegal($0) ? before.san($0) : nil },
                bestLine: i < book ? [] : f?.bestLine ?? [], refutation: i < book ? [] : f?.refutation ?? [],
                secondBestGap: c?.secondBestGap, epLost: c?.epLost ?? 0, clock: replay.game.moves[i].clock,
                coach: coach, isKey: isKey, wasDeepSearched: state.deep[i].map { !$0.isProbe } ?? false))
        }

        let accuracy = Accuracy.game(scores: scores, start: start.side)
        let acpl = Accuracy.averageCentipawnLoss(scores: scores, start: start.side)
        func player(_ side: Side, _ accuracy: Double?, _ acpl: Double?) -> GameReview.PlayerReview {
            var counts: [MoveClass: Int] = [:]
            for m in moves where m.side == side {
                if let c = m.moveClass, c.isCounted { counts[c, default: 0] += 1 }
            }
            return GameReview.PlayerReview(accuracy: accuracy, counts: counts,
                                           gameRating: acpl.map { Accuracy.estimatedGameRating(acpl: $0, rating: ratings.rating(for: side)) },
                                           averageCentipawnLoss: acpl)
        }

        let searches = state.shallow.compactMap { $0 }.filter { $0.nodes > 0 } + state.deep.compactMap { $0 }.filter { !$0.isProbe }.map(\.best)
        let depths = searches.map(\.depth)
        let info = GameReview.EngineInfo(
            name: engineName, firstPassNodes: firstPassNodes, deepPassNodes: deepPassNodes,
            searchedPositions: state.shallow.compactMap { $0 }.filter { $0.nodes > 0 }.count,
            deepPlies: state.deep.compactMap { $0 }.filter { !$0.isProbe }.count,
            averageDepth: depths.isEmpty ? nil : Double(depths.reduce(0, +)) / Double(depths.count),
            maxDepth: depths.max())

        let isComplete = (book...replay.moves.count).allSatisfy { state.top($0) != nil }
        return GameReview(
            id: replay.id, startFEN: replay.startFEN, moves: moves,
            white: player(.white, accuracy.white, acpl.white), black: player(.black, accuracy.black, acpl.black),
            phases: phases(replay, scores, moves), opening: opening, engine: info, isComplete: isComplete, whiteEvals: scores)
    }

    private static func phases(_ replay: GameReplay, _ scores: [Score?], _ moves: [GameReview.ReviewedMove]) -> [GameReview.PhaseReview] {
        let division = PhaseDivider.divide(replay.positions)
        return Accuracy.phases(scores: scores, start: replay.positions[0].side, division: division).map { phase in
            let plies = phase.plies.lowerBound..<max(phase.plies.upperBound - 1, phase.plies.lowerBound)
            let inPhase = moves.filter { plies.contains($0.ply) }
            let decided = PhaseGrade.isDecided(whiteScores: scores[phase.plies].compactMap { $0 })
            func grade(_ side: Side, _ accuracy: Double?) -> GameReview.PhaseReview.Grade {
                let own = inPhase.filter { $0.side == side }
                let letter = accuracy.flatMap { a -> MoveClass? in
                    decided ? nil : PhaseGrade.grade(accuracy: a,
                                                     hasBrilliant: own.contains { $0.moveClass == .brilliant },
                                                     hasGreat: own.contains { $0.moveClass == .great })
                }
                return GameReview.PhaseReview.Grade(accuracy: accuracy, grade: letter)
            }
            return GameReview.PhaseReview(phase: phase.phase, firstPly: plies.lowerBound, lastPly: plies.upperBound,
                                          white: grade(.white, phase.white), black: grade(.black, phase.black))
        }
    }

    // MARK: Persistence and heat

    private static func stateFile(gameID: String, directory: URL?) -> URL {
        let base = directory ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("ReviewsInProgress", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(gameID).json")
    }

    private static func loadState(_ url: URL, replay: GameReplay) -> ReviewState? {
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(ReviewState.self, from: data),
              state.gameID == replay.id, state.shallow.count == replay.positions.count else { return nil }
        return state
    }

    /// Best effort: if a write fails the review goes on, and only a resume would be poorer for it.
    private static func save(_ state: ReviewState, to url: URL) {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: .atomic) }
    }

    /// Lets the phone cool between searches once it starts warming up.
    private static func rest(after seconds: TimeInterval) async throws {
        let factor: Double
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return
        case .fair: factor = 0.7
        case .serious: factor = 1.4
        default: factor = 2.5
        }
        try await Task.sleep(for: .seconds(min(seconds * factor, maxRestSeconds)))
    }
}

extension RetryCheck {
    /// Searches a retried move and judges it. Waits for the result: 1M nodes or 3 s.
    static func check(_ move: Move, startFEN: String, moves: [Move], best: Score, rating: Int?, engine: Engine = .shared) async throws -> Bool {
        let lines = try await engine.analyse(
            startFEN: startFEN, moves: moves + [move], multiPV: 1,
            nodes: Engine.budget(ReviewEngine.deepPassNodes), movetimeMs: 3_000, searchMoves: nil, onUpdate: nil)
        guard let score = lines.first?.score else { throw CancellationError() }
        return accepts(best: best, retried: score.flipped, rating: rating)
    }
}
