import XCTest
@testable import Scachs

final class PuzzleTests: XCTestCase {
    private var store: PuzzleStore { .shared }

    private func tempProgress() -> Scachs.Progress {
        Scachs.Progress(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json"))
    }

    // MARK: Glicko-2

    func testFirstPuzzleMovesAbout237() {
        let win = Glicko2.update(.start, puzzle: 1500, solved: true)
        let loss = Glicko2.update(.start, puzzle: 1500, solved: false)
        XCTAssertEqual(win.rating - 1500, 236.7, accuracy: 0.5)
        XCTAssertEqual(loss.rating - 1500, -236.7, accuracy: 0.5)
        XCTAssertLessThan(win.deviation, 500)
    }

    func testSteadyStateSwings() {
        let steady = Glicko2.Rating(rating: 1500, deviation: 72.9, volatility: 0.087)
        XCTAssertEqual(Glicko2.update(steady, puzzle: 1500, solved: true).rating - 1500, 14.8, accuracy: 0.3)
        XCTAssertEqual(Glicko2.update(steady, puzzle: 1303, solved: true).rating - 1500, 7.5, accuracy: 0.3)
        XCTAssertEqual(Glicko2.update(steady, puzzle: 1303, solved: false).rating - 1500, -22.5, accuracy: 0.3)
    }

    func testAbsenceDecayAndGaps() {
        let steady = Glicko2.Rating(rating: 1500, deviation: 72.9, volatility: 0.087)
        for (days, rd) in [(30.0, 82.0), (90, 99), (180, 119), (365, 153)] {
            XCTAssertEqual(Glicko2.liveDeviation(steady, days: days), rd, accuracy: 1)
        }
        XCTAssertEqual(Glicko2.gap(forSuccess: 0.70), 151.6, accuracy: 0.5)
        XCTAssertEqual(Glicko2.gap(forSuccess: 0.75), 196.6, accuracy: 0.5)
        XCTAssertEqual(Glicko2.gap(forSuccess: 0.85), 310, accuracy: 1)
    }

    func testThemeWeightsAndCaps() {
        XCTAssertEqual(Glicko2.weight(theme: nil, solved: false), 1)
        XCTAssertEqual(Glicko2.weight(theme: "backRankMate", solved: true), 0.1)
        XCTAssertEqual(Glicko2.weight(theme: "fork", solved: false), 0.7)
        XCTAssertEqual(Glicko2.weight(theme: "rookEndgame", solved: true), 0.7)
        let steady = Glicko2.Rating(rating: 1500, deviation: 72.9, volatility: 0.087)
        let full = Glicko2.update(steady, puzzle: 1500, solved: true)
        let weighted = Glicko2.update(steady, puzzle: 1500, solved: true, weight: 0.2)
        XCTAssertEqual(weighted.rating - 1500, (full.rating - 1500) * 0.2, accuracy: 1e-6)
        XCTAssertEqual(Glicko2.update(Glicko2.Rating(rating: 401, deviation: 300, volatility: 0.09), puzzle: 400, solved: false).rating, 400)
    }

    // MARK: Binary round trip

    func testRecordsMatchTheCSV() throws {
        for row in Self.csvRows {
            let c = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let (id, fen, moves, rating, popularity, themes) = (c[0], c[1], c[2], Int(c[3])!, Int(c[5])!, c[7])
            let i = try XCTUnwrap(store.index(ofID: id), id)
            let p = store.puzzle(at: i)
            XCTAssertEqual(p.id, id)
            XCTAssertEqual(p.index, i)
            XCTAssertEqual(p.rating, rating)
            XCTAssertEqual(p.popularity, popularity)
            XCTAssertEqual(p.line.map(\.uci).joined(separator: " "), moves)
            XCTAssertEqual(p.start, Position(fen: fen.split(separator: " ").prefix(4).joined(separator: " ")), id)
            XCTAssertEqual(Set(p.themes), Set(themes.split(separator: " ").map(String.init)), id)
            XCTAssertEqual(p.solverSide, fen.contains(" w ") ? .black : .white)
        }
    }

    // MARK: PuzzleRun

    func testRealMateInTwo() throws {
        let p = store.puzzle(at: try XCTUnwrap(store.index(ofID: Self.mateInTwo)))
        XCTAssertTrue(p.themes.contains("mateIn2"))
        XCTAssertEqual(p.line.count, 4)
        var run = PuzzleRun(p)
        var board = p.start.applying(p.line[0])
        XCTAssertEqual(run.expected, p.line[1])

        let wrong = try XCTUnwrap(board.legalMoves().first { $0 != p.line[1] && !board.applying($0).isCheckmate })
        XCTAssertEqual(run.attempt(wrong, on: board), .wrong)
        XCTAssertEqual(run.step, 1)

        XCTAssertEqual(run.attempt(p.line[1], on: board), .correct(reply: p.line[2]))
        XCTAssertEqual(run.step, 3)
        XCTAssertEqual(Array(run.remaining), [p.line[3]])
        board = board.applying(p.line[1]).applying(p.line[2])

        XCTAssertEqual(run.attempt(p.line[3], on: board), .solved)
        XCTAssertTrue(board.applying(p.line[3]).isCheckmate)
        XCTAssertNil(run.expected)
    }

    func testAnyMateWinsAndCastlingIsNormalised() throws {
        func puzzle(_ fen: String, _ line: String) -> Puzzle {
            Puzzle(id: "test0", index: 0, start: Position(fen: fen)!, line: line.split(separator: " ").map { Move(uci: String($0))! },
                   rating: 1500, themes: [], popularity: 100)
        }
        let mates = puzzle("6k1/5Q2/6K1/8/8/8/8/8 b - - 0 1", "g8h8 f7g7")
        let board = mates.start.applying(mates.line[0])
        var run = PuzzleRun(mates)
        XCTAssertEqual(run.attempt(try XCTUnwrap(Move(uci: "f7f6")), on: board), .wrong)
        XCTAssertEqual(run.attempt(try XCTUnwrap(Move(uci: "f7f8")), on: board), .solved)

        let castle = puzzle("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", "e8d7 e1g1")
        var kingTakesRook = PuzzleRun(castle)
        XCTAssertEqual(kingTakesRook.attempt(try XCTUnwrap(Move(uci: "e1h1")), on: castle.start.applying(castle.line[0])), .solved)
    }

    // MARK: Curated set

    func testCuratedSet() {
        XCTAssertGreaterThan(store.count, 95_000)
        XCTAssertLessThan(store.count, 106_000)
        var previous = 0
        for i in stride(from: 0, to: store.count, by: 97) {
            let p = store.puzzle(at: i)
            XCTAssertGreaterThanOrEqual(p.rating, previous)
            previous = p.rating
            XCTAssertFalse(p.themes.contains("equality"))
            var board = p.start
            for m in p.line {
                XCTAssertTrue(board.isLegal(m), p.id)
                board = board.applying(m)
            }
            if p.themes.contains("mate") { XCTAssertTrue(board.isCheckmate, p.id) }
        }
    }

    func testFindWidensAndFilters() throws {
        let fork = try XCTUnwrap(store.find(target: 1300, anyOf: ["fork"], excluding: { _ in false }))
        XCTAssertTrue(fork.themes.contains("fork"))
        XCTAssertLessThanOrEqual(abs(fork.rating - 1300), 75)
        let mate = try XCTUnwrap(store.find(target: 1300, anyOf: ["mateIn2"], excluding: { _ in false }))
        XCTAssertTrue(mate.themes.contains("mateIn2"))
        XCTAssertNil(store.find(target: 1300, anyOf: ["noSuchTag"], excluding: { _ in false }))
        XCTAssertNil(store.find(target: 1300, anyOf: nil, excluding: { _ in true }))
        // Everything within 400 points excluded: still finds something, as near as the widening gets.
        let far = try XCTUnwrap(store.find(target: 1500, anyOf: nil, excluding: { abs(self.store.rating(at: $0) - 1500) <= 400 }))
        XCTAssertGreaterThan(abs(far.rating - 1500), 400)
    }

    func testStreakForgivesOneDayOffAndNotTwo() {
        XCTAssertEqual(DailyStreak(days: [], today: 100).current, 0)
        XCTAssertEqual(DailyStreak(days: [100], today: 100).current, 1)
        XCTAssertEqual(DailyStreak(days: [98, 99], today: 100).current, 2, "today not done yet takes nothing away")
        XCTAssertEqual(DailyStreak(days: [96, 97, 99], today: 100).current, 3, "one day off inside the run")
        XCTAssertEqual(DailyStreak(days: [97, 98], today: 100).current, 2, "one day off so far")
        let lapsed = DailyStreak(days: [90, 91, 92, 93, 97], today: 100)
        XCTAssertEqual(lapsed.current, 0, "two days off end it")
        XCTAssertEqual(lapsed.best, 4)
        XCTAssertEqual(DailyStreak(days: [90, 91, 95, 96, 97], today: 97).current, 3, "a new run starts after a gap")
        XCTAssertEqual(DailyStreak(days: [99, 105], today: 100).current, 1, "a day from a wrong clock doesn't count")
    }

    func testConsecutiveDatesAreConsecutiveDayNumbers() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        for offset in 1...400 {
            let next = calendar.date(byAdding: .day, value: offset, to: today)!
            XCTAssertEqual(PuzzleStore.dayNumber(next), PuzzleStore.dayNumber(today) + offset)
        }
    }

    func testDailyDaysSurviveAndOldFilesStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = Progress(url: url)
        old.setInitialRating(1400)
        // A file from before the daily puzzle: everything but the new key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["dailyDays"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let loaded = Progress(url: url)
        XCTAssertEqual(loaded.rating, 1400)
        XCTAssertEqual(loaded.dailyDays, [])
        loaded.recordDaily()
        loaded.recordDaily()
        XCTAssertEqual(Progress(url: url).dailyDays, [PuzzleStore.dayNumber(Date())])
    }

    func testLogoOutlinesParse() {
        let square = LogoPath.parse("M 0.0 0.0 L 10.0 0.0 Q 10.0 5.0 10.0 10.0 C 8.0 10.0 2.0 10.0 0.0 10.0 Z")
        XCTAssertEqual(square.boundingBox, CGRect(x: 0, y: 0, width: 10, height: 10))
        let initial = LogoPath.parse(LogoOutlines.initial).boundingBox
        let rest = LogoPath.parse(LogoOutlines.rest).boundingBox
        XCTAssertGreaterThan(initial.height, 500)
        XCTAssertGreaterThan(rest.minX, initial.midX, "the other letters follow the S")
        XCTAssertLessThan(initial.minY, 0, "y runs down from the baseline")
    }

    func testDailyIsStable() {
        let today = Date(timeIntervalSinceReferenceDate: 815_000_000)
        XCTAssertEqual(store.daily(for: today).id, store.daily(for: today).id)
        XCTAssertNotEqual(store.daily(for: today).id, store.daily(for: today.addingTimeInterval(86400)).id)
    }

    func testEveryThemeIsNamed() {
        for t in Self.allThemes { XCTAssertNotEqual(ThemeNames.name(t), t, t) }
        XCTAssertEqual(ThemeNames.primaryTag(of: ["advantage", "fork", "middlegame", "short"]), "fork")
        XCTAssertEqual(ThemeNames.primaryTag(of: ["backRankMate", "endgame", "mate", "mateIn2", "short"]), "backRankMate")
        XCTAssertEqual(ThemeNames.primaryTag(of: ["mate", "mateIn2", "middlegame", "short"]), "mateIn2")
        XCTAssertEqual(ThemeNames.primaryTag(of: ["advantage", "rookEndgame", "long"]), "rookEndgame")
    }

    // MARK: Progress

    func testHintsRetriesAndReplaysAreUnrated() {
        let progress = tempProgress()
        let p = store.puzzle(at: 40_000), q = store.puzzle(at: 40_001)
        progress.setInitialRating(1500)
        XCTAssertEqual(progress.deviation, 350, accuracy: 0.01)
        XCTAssertEqual(progress.record(p, solved: true, hinted: true, context: .blind), 0)
        XCTAssertEqual(progress.record(q, solved: true, hinted: false, context: .retry), 0)
        XCTAssertEqual(progress.record(p, solved: true, hinted: false, context: .blind), 0, "replay")
        XCTAssertEqual(progress.attempts.count, 3)
        XCTAssertTrue(progress.played(p.index))
        XCTAssertFalse(progress.played(40_002))
        XCTAssertGreaterThan(progress.record(store.puzzle(at: 40_002), solved: true, hinted: false, context: .blind), 0)
    }

    func testRetryLadder() {
        let progress = tempProgress()
        let p = store.puzzle(at: 30_000)
        let calendar = Calendar.current
        let day0 = calendar.startOfDay(for: Date()).addingTimeInterval(3600)
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: day0)! }

        progress.record(p, solved: false, hinted: false, context: .blind, at: day0)
        XCTAssertEqual(progress.dueRetries(limit: 2, at: day0), [])
        XCTAssertEqual(progress.dueRetries(limit: 2, at: day(1)), [p.id])

        var now = 1
        for gap in [3, 7, 21, 60] {
            progress.record(p, solved: true, hinted: false, context: .retry, at: day(now))
            XCTAssertEqual(progress.dueRetries(limit: 2, at: day(now + gap - 1)), [], "gap \(gap)")
            now += gap
            XCTAssertEqual(progress.dueRetries(limit: 2, at: day(now)), [p.id], "gap \(gap)")
        }
        progress.record(p, solved: false, hinted: false, context: .retry, at: day(now))
        XCTAssertEqual(progress.dueRetries(limit: 2, at: day(now + 1)), [p.id], "a miss returns to one day")
        var last = now + 1
        for gap in [3, 7, 21, 60] {
            progress.record(p, solved: true, hinted: false, context: .retry, at: day(last))
            last += gap
        }
        progress.record(p, solved: true, hinted: false, context: .retry, at: day(last))
        XCTAssertEqual(progress.dueRetries(limit: 2, at: day(last + 400)), [], "retired after 60 days")
    }

    func testPersistenceAndCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("progress.json")
        let first = Scachs.Progress(url: url)
        let p = store.puzzle(at: 20_000)
        first.record(p, solved: false, hinted: false, context: .blind)
        first.completedLessons.insert("L01")

        let second = Scachs.Progress(url: url)
        XCTAssertEqual(second.rating, first.rating)
        XCTAssertEqual(second.attempts.count, 1)
        XCTAssertTrue(second.played(p.index))
        XCTAssertEqual(second.completedLessons, ["L01"])

        try Data("not json".utf8).write(to: url)
        let third = Scachs.Progress(url: url)
        XCTAssertEqual(third.rating, Glicko2.Rating.start.rating)
        XCTAssertTrue(third.attempts.isEmpty)
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("corrupt") }
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(aside[0])), Data("not json".utf8))
    }

    // MARK: Session

    func testSessionMix() {
        let progress = tempProgress()
        progress.setInitialRating(1500)
        let session = PuzzleSession(progress: progress, store: store)
        XCTAssertEqual(session.results.count, 10)
        var gaps: [Int] = [], whites = 0, motifs: [String] = []
        for slot in 0..<10 {
            XCTAssertEqual(session.current, slot)
            let (p, context) = session.next()!
            XCTAssertEqual(session.next()!.0.id, p.id, "the same puzzle until finished")
            XCTAssertEqual(context, .blind)
            XCTAssertFalse(progress.played(p.index))
            gaps.append(1500 - p.rating)
            whites += p.solverSide == .white ? 1 : 0
            motifs.append(ThemeNames.primaryTag(of: p.themes))
            progress.record(p, solved: true, hinted: true, context: context)  // hinted keeps the rating fixed at 1500
            session.finish(solved: true)
        }
        XCTAssertNil(session.next())
        XCTAssertEqual(session.results.compactMap { $0 }.count, 10)
        XCTAssertEqual(gaps[0], 310, accuracy: 75)
        XCTAssertEqual(gaps[7], 0, accuracy: 75)
        for slot in [1, 2, 3, 4, 5, 6, 8, 9] { XCTAssertEqual(gaps[slot], 175, accuracy: 100) }
        XCTAssertTrue((4...6).contains(whites), "\(whites)")
        for i in 2..<10 { XCTAssertFalse(motifs[i] == motifs[i - 1] && motifs[i] == motifs[i - 2], "\(motifs)") }
    }

    func testSessionServesDueRetries() {
        let progress = tempProgress()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let missed = [10_000, 10_001, 10_002].map { store.puzzle(at: $0) }
        for p in missed { progress.record(p, solved: false, hinted: false, context: .blind, at: yesterday) }
        let session = PuzzleSession(progress: progress, store: store)
        var retried: [String] = []
        while let (p, context) = session.next() {
            if context == .retry { retried.append(p.id) }
            session.finish(solved: true)
        }
        XCTAssertEqual(retried.count, 2)
        XCTAssertTrue(retried.allSatisfy { id in missed.contains { $0.id == id } })
    }

    func testHarderBiasMovesTheTarget() {
        let progress = tempProgress()
        progress.setInitialRating(1500)
        let session = PuzzleSession(progress: progress, store: store)
        session.harderBias = 1
        let (p, _) = session.next()!
        XCTAssertEqual(1500 - p.rating, 210, accuracy: 75)
    }

    // MARK: Fixtures

    private static let mateInTwo = "8jDu3"
    // The first eight columns of lichess_db_puzzle.csv (CC0): lowest and highest rated, ep square, all castling rights, promotion, daily, mate.
    private static let csvRows = [
        "1AYLA,8/p4pp1/2k1p2p/1pp1P3/1PP1K1P1/P3P2P/8/8 w - - 0 34,c4b5 c6b5 b4c5 b5c5,400,89,82,187,crushing endgame pawnEndgame short",
        "NEkKD,8/4k3/5p2/p1pp1K2/1P4P1/P1P5/8/8 b - - 0 45,c5b4 c3b4 a5a4 f5f4 e7d7 f4e3 d7d6 e3d3,3119,96,93,753,crushing defensiveMove endgame pawnEndgame veryLong",
        "X3dqr,5r1k/1R1R4/4Bb1p/5Pp1/3p1KPP/4r3/8/8 w - g6 0 46,f5g6 f6e5,1006,78,99,1508,discoveredCheck doubleCheck endgame mate mateIn1 oneMove",
        "ssWVa,rnbqkb1r/ppp1npp1/3p3p/4N3/2B1P3/2N5/PP3PPP/R1BQK2R b KQkq - 2 7,d6e5 c4f7 e8f7 d1d8,1401,75,95,22917,attackingF2F7 crushing deflection opening short",
        "Mg93c,3K4/p4PR1/7p/6P1/3k3P/2p5/P7/5r2 w - - 0 49,d8e8 c3c2 f7f8q f1f8 e8f8 c2c1q,1601,76,97,14145,advancedPawn crushing endgame long promotion rookEndgame",
        "S2dNd,5r1k/2qb4/p4PRN/1p1p3p/5B2/bP2PP1P/Pn5K/1B6 b - - 0 31,a3d6 g6g8 f8g8 h6f7,1801,85,92,128507,kingsideAttack mate mateIn2 middlegame sacrifice short",
        "8jDu3,4rbk1/2RR4/1B2p1pp/4P3/p3NP2/n5K1/1q4PP/8 b - - 5 35,b2b6 e4f6 g8h8 d7h7,1151,77,95,22486,arabianMate fork mate mateIn2 middlegame short",
    ]

    private static let allThemes = [
        "opening", "middlegame", "endgame", "rookEndgame", "bishopEndgame", "knightEndgame", "queenEndgame", "pawnEndgame", "queenRookEndgame",
        "advancedPawn", "attackingF2F7", "capturingDefender", "discoveredAttack", "doubleCheck", "exposedKing", "fork", "hangingPiece",
        "kingsideAttack", "queensideAttack", "pin", "sacrifice", "skewer", "trappedPiece",
        "attraction", "clearance", "collinearMove", "discoveredCheck", "defensiveMove", "deflection", "interference", "intermezzo",
        "quietMove", "xRayAttack", "zugzwang",
        "mate", "mateIn1", "mateIn2", "mateIn3", "mateIn4", "mateIn5",
        "arabianMate", "cornerMate", "hookMate", "smotheredMate", "vukovicMate", "anastasiaMate",
        "backRankMate", "blindSwineMate", "dovetailMate", "epauletteMate", "killBoxMate", "swallowstailMate", "triangleMate",
        "balestraMate", "bodenMate", "doubleBishopMate", "pillsburysMate", "morphysMate", "operaMate",
        "castling", "enPassant", "promotion", "underPromotion",
        "equality", "advantage", "crushing",
        "oneMove", "short", "long", "veryLong",
        "master", "masterVsMaster", "superGM",
    ]
}

final class SeaChartTests: XCTestCase {
    private func attempt(_ theme: String, solved: Bool, hinted: Bool = false, context: AttemptContext = .blind) -> Attempt {
        Attempt(puzzleID: "p", index: 0, date: Date(), solved: solved, hinted: hinted, context: context, puzzleRating: 1500, ratingBefore: 1500, themes: [theme, "short"])
    }

    func testLandsMoveFromFogToChartedToHeld() {
        XCTAssertEqual(SeaChart.Standing().state, .fog)
        let charted = SeaChart.standings((0..<3).map { _ in attempt("fork", solved: false) })
        XCTAssertEqual(charted["fork"]?.state, .charted)
        let held = SeaChart.standings((0..<12).map { attempt("fork", solved: $0 < 9) })
        XCTAssertEqual(held["fork"]?.state, .held)
        let even = SeaChart.standings((0..<12).map { attempt("fork", solved: $0 < 6) })
        XCTAssertEqual(even["fork"]?.state, .charted, "at your level is not yet above it")
    }

    func testHintsAndOtherContextsChartButDoNotHold() {
        let hinted = SeaChart.standings((0..<20).map { _ in attempt("pin", solved: true, hinted: true) })
        XCTAssertEqual(hinted["pin"]?.state, .charted)
        XCTAssertNil(SeaChart.standings([attempt("short", solved: true)])["short"], "only themes on the chart count")
    }

    func testFlagsStayAndRanksClimb() {
        let states = SeaChart.states([:], held: ["fork"])
        XCTAssertEqual(states["fork"], .held)
        XCTAssertEqual(states.count, SeaChart.themes.count)
        XCTAssertEqual(SeaChart.rank(held: 0), 0)
        XCTAssertEqual(SeaChart.rank(held: 3), 1)
        XCTAssertEqual(SeaChart.rank(held: 17), 2)
        XCTAssertEqual(SeaChart.rank(held: 45), 4)
    }

    @MainActor func testEveryThemeHasItsOwnLand() {
        let world = SeaChart.world
        XCTAssertEqual(world.territories.count, SeaChart.themes.count)
        XCTAssertEqual(Set(world.territories.map(\.id)).count, SeaChart.themes.count)
        for t in world.territories { XCTAssertTrue(world.lands[t.land].contains(t.seed), t.id) }
        XCTAssertEqual(world.territory(at: world.territories[0].seed)?.id, world.territories[0].id)
    }
}
