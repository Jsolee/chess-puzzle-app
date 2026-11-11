import XCTest
import CoreGraphics
import UIKit
@testable import Scachs

final class TodayTests: XCTestCase {
    private func move(_ ply: Int, _ side: Side, _ san: String, _ uci: String, cls: MoveClass, best: String, gap: Double? = 0.2, before: Score = .cp(50), lost: Double = 0.3) -> GameReview.ReviewedMove {
        GameReview.ReviewedMove(ply: ply, side: side, san: san, uci: uci, moveClass: cls, evalBefore: before, evalAfter: .cp(-300), bestMove: Move(uci: best), bestSAN: nil,
                                bestLine: Move(uci: best).map { [$0] } ?? [], refutation: [], secondBestGap: gap, epLost: lost, clock: nil, coach: nil, isKey: true, wasDeepSearched: true)
    }

    private func review(_ moves: [GameReview.ReviewedMove]) -> GameReview {
        let player = GameReview.PlayerReview(accuracy: 80, counts: [:], gameRating: nil, averageCentipawnLoss: nil)
        let engine = GameReview.EngineInfo(name: "x", firstPassNodes: 1, deepPassNodes: 1, searchedPositions: 1, deepPlies: 1, averageDepth: nil, maxDepth: nil)
        return GameReview(id: "r", startFEN: Position.start.fen, moves: moves, white: player, black: player, phases: [], opening: nil, engine: engine, isComplete: true)
    }

    private func game(side: Side? = .white, result: String = "1-0", pgn: String = "1. e4 e5") -> ImportedGame {
        ImportedGame(id: "g", source: .pgn, white: "me", black: "them", mySide: side, result: result, termination: .other, timeClass: .blitz, date: Date(timeIntervalSince1970: 1_000), pgn: pgn)
    }

    func testOnlyClearErrorsOfYoursBecomeCards() {
        let moves = [
            move(0, .white, "a3", "a2a3", cls: .blunder, best: "e2e4"),                       // yours, clear: kept
            move(1, .black, "a6", "a7a6", cls: .blunder, best: "e7e5"),                       // theirs
            move(2, .white, "b3", "b2b3", cls: .mistake, best: "e2e4", gap: 0.01),            // several fine moves
            move(3, .black, "b6", "b7b6", cls: .good, best: "e7e5"),
            move(4, .white, "c3", "c2c3", cls: .inaccuracy, best: "e2e4"),                    // too small
            move(5, .black, "c6", "c7c6", cls: .good, best: "e7e5"),
            move(6, .white, "d3", "d2d3", cls: .miss, best: "e2e4", before: .cp(-900)),       // already lost
        ]
        let cards = MistakeCard.cards(from: review(moves), game: game())
        XCTAssertEqual(cards.map(\.playedSAN), ["a3"])
        XCTAssertEqual(cards[0].fen, Position.start.fen)
        XCTAssertEqual(cards[0].bestUCI, "e2e4")
        XCTAssertEqual(cards[0].opponent, "them")
        XCTAssertTrue(MistakeCard.cards(from: review(moves), game: game(side: nil)).isEmpty, "whose game is it?")
    }

    func testCardsPerGameKeepTheWorst() {
        let moves = (0..<5).flatMap { i in [
            move(i * 2, .white, "m\(i)", ["a2a3", "b2b3", "c2c3", "d2d3", "f2f3"][i], cls: .blunder, best: "e2e4", lost: Double(i) / 10 + 0.2),
            move(i * 2 + 1, .black, "r\(i)", ["a7a6", "b7b6", "c7c6", "d7d6", "f7f6"][i], cls: .good, best: "e7e5"),
        ] }
        XCTAssertEqual(MistakeCard.cards(from: review(moves), game: game()).map(\.playedSAN), ["m4", "m3", "m2"])
    }

    func testMistakesClimbTheLadderAndComeBackWhenMissed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let progress = Progress(url: url)
        let now = Date()
        let r = review([move(0, .white, "a3", "a2a3", cls: .blunder, best: "e2e4")])
        progress.harvest(r, game: game(), now: now)
        progress.harvest(r, game: game(), now: now)
        XCTAssertEqual(progress.mistakes.count, 1, "a game is read once")

        let card = try XCTUnwrap(progress.nextMistake(at: now))
        progress.answerMistake(card, solved: true, at: now)
        XCTAssertNil(progress.nextMistake(at: now), "not again today")
        let climbed = try XCTUnwrap(progress.mistakes.first)
        XCTAssertEqual(climbed.box, 1)
        let threeDays = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: now))!
        XCTAssertEqual(climbed.due, threeDays)

        progress.answerMistake(climbed, solved: false, at: threeDays)
        let fell = try XCTUnwrap(progress.mistakes.first)
        XCTAssertEqual(fell.box, 0)
        XCTAssertEqual(fell.due, Calendar.current.date(byAdding: .day, value: 1, to: threeDays))

        var last = fell
        for _ in 0..<5 {
            progress.answerMistake(last, solved: true, at: last.due)
            guard let next = progress.mistakes.first else { break }
            last = next
        }
        XCTAssertTrue(progress.mistakes.isEmpty, "off the top of the ladder it is learnt")
        XCTAssertEqual(Progress(url: url).mistakes.count, 0)
    }

    func testOnlyAFewADay() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let progress = Progress(url: url)
        let now = Date()
        for i in 0..<5 {
            var g = game()
            g.id = "g\(i)"
            progress.harvest(review([move(0, .white, "a3", "a2a3", cls: .blunder, best: "e2e4")]), game: g, now: now)
        }
        for _ in 0..<MistakeCard.perDay {
            let card = try XCTUnwrap(progress.nextMistake(at: now))
            progress.answerMistake(card, solved: true, at: now)
        }
        XCTAssertNil(progress.nextMistake(at: now))
        XCTAssertNotNil(progress.nextMistake(at: Calendar.current.date(byAdding: .day, value: 1, to: now)!))
    }

    func testAtlasGroupsByFamilyAndFindsDragons() {
        let sicilian = "1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6"
        var games = (0..<3).map { _ in game(result: "0-1", pgn: sicilian) }
        games.append(game(result: "1-0", pgn: "1. d4 d5 2. c4 e6 3. Nc3 Nf6"))
        games.append(game(side: .black, result: "0-1", pgn: "1. e4 e6 2. d4 d5"))
        let regions = Atlas.regions(games: games, side: .white)
        let found = regions.first { $0.name == "Sicilian Defense" }
        XCTAssertEqual(found?.games, 3)
        XCTAssertEqual(found?.land, .kingPawn)
        XCTAssertEqual(found?.isDragon, true)
        XCTAssertEqual(regions.first { $0.name == "Queen's Gambit Declined" }?.wins, 1)
        XCTAssertEqual(regions.first { $0.name == "French Defense" }?.games, 0, "that one was played with Black")
        XCTAssertEqual(Atlas.regions(games: games, side: .black).first { $0.name == "French Defense" }?.wins, 1)
        XCTAssertEqual(Atlas.family("Sicilian Defense: Najdorf Variation"), "Sicilian Defense")
    }

    func testTemperamentReadsTheGames() {
        let muzio = "1. e4 e5 2. f4 exf4 3. Nf3 g5 4. Bc4 g4 5. Nc3 gxf3 6. Qxf3 Nc6 7. Qxf4 Qf6 8. Qxf6 Nxf6 9. Bxf7+ Kxf7 10. d3 Bb4 11. Bg5 Bxc3+ 12. bxc3 d6 13. Bxf6 Kxf6 1-0"
        let quiet = "1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Be7 5. e3 h6 6. Bh4 b6 7. Nf3 Bb7 8. Be2 Nbd7 9. Rc1 c5 10. a3 a6 1/2-1/2"
        func games(_ pgn: String, _ n: Int, _ time: TimeClass = .rapid) -> [ImportedGame] {
            (0..<n).map { ImportedGame(id: "g\($0)", source: .pgn, white: "me", black: "them", mySide: .white, result: "1-0", termination: .other, timeClass: time, date: .now, pgn: pgn) }
        }
        XCTAssertEqual(Temperament(games: games(muzio, 3)).figure, .squire, "too few games to say")
        let knight = Temperament(games: games(muzio, 10))
        XCTAssertEqual(knight.counts.games, 10, "every game parses")
        XCTAssertEqual(knight.figure, .knight)
        XCTAssertFalse(knight.evidence.isEmpty)
        XCTAssertEqual(Temperament(games: games(quiet, 10, .bullet)).figure, .messenger)
    }

    func testChartPutsEveryPlaceOnLandAndAnswersTaps() throws {
        var regions = Atlas.regions(games: [], side: .white)
        regions[0].wins = 30
        regions[regions.count - 1].losses = 30
        let chart = try XCTUnwrap(AtlasPainter.paint(regions: regions, size: CGSize(width: 402, height: 515), scale: 1))
        XCTAssertEqual(chart.places.count, regions.count)
        for place in chart.places {
            XCTAssertEqual(chart.place(at: place.point)?.region, place.region, place.region.name)
        }
        XCTAssertNil(chart.place(at: CGPoint(x: 1, y: 1)))
        XCTAssertNil(chart.place(at: CGPoint(x: -5, y: 900)))
        XCTAssertNotNil(chart.highlight(chart.places[0].region))
        XCTAssertEqual(chart.titles.count, Land.allCases.count)
        let dragon = try XCTUnwrap(chart.places.first { $0.region.isDragon }?.dragon)
        XCTAssertNil(chart.place(at: dragon), "the monster is out at sea")
    }

    func testSundayGamesAreLegalAndTheirMomentsAreTheMovesPlayed() throws {
        XCTAssertFalse(SundayGames.all.isEmpty)
        for game in SundayGames.all {
            let pgn = try XCTUnwrap(PGN.parse(game.moves).first, game.id)
            let replay = try GameReplay(pgn)
            for moment in game.moments {
                XCTAssertEqual(pgn.moves[moment.ply].san, moment.san, "\(game.id) move \(moment.move)")
                XCTAssertEqual(moment.ply % 2 == 0 ? Side.white : .black, game.solver, "\(game.id): you guess for one side")
                XCTAssertTrue(replay.positions[moment.ply].isLegal(replay.moves[moment.ply]))
            }
            XCTAssertFalse(game.intro.ca.isEmpty || game.intro.es.isEmpty || game.intro.en.isEmpty)
        }
        let monday = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let next = monday.addingTimeInterval(7 * 86400)
        XCTAssertNotEqual(SundayGames.current(date: monday).id, SundayGames.current(date: next).id)
    }

    func testBlindfoldSaysThePositionInWords() throws {
        let position = try XCTUnwrap(Position(fen: "7k/8/6K1/8/8/8/8/R7 w - - 0 1"))
        let words = Blindfold.describe(position)
        XCTAssertTrue(words.contains("rei g6"), words)
        XCTAssertTrue(words.contains("torre a1"), words)
        XCTAssertTrue(words.contains("rei h8"), words)
        let mate = try XCTUnwrap(position.move(uci: "a1a8"))
        XCTAssertTrue(Blindfold.say(mate, on: position).contains("a8"))
        XCTAssertTrue(Blindfold.say(mate, on: position).contains("mat"))
    }

    func testHumanishMoveErrsMoreAtLowRatings() throws {
        let good = try XCTUnwrap(Move(uci: "e2e4")), bad = try XCTUnwrap(Move(uci: "a2a3"))
        let lines = [EngineLine(multipv: 1, depth: 1, score: .cp(100), pv: [good], nodes: 1), EngineLine(multipv: 2, depth: 1, score: .cp(0), pv: [bad], nodes: 1)]
        func worseShare(_ rating: Int) -> Int { (0..<100).filter { HumanishMove.choose(lines, rating: rating, roll: Double($0) / 100) == bad }.count }
        XCTAssertGreaterThan(worseShare(800), worseShare(2400))
        XCTAssertGreaterThan(worseShare(800), 15)
        XCTAssertLessThan(worseShare(2400), 5)
        XCTAssertNil(HumanishMove.choose([], rating: 1500))
    }

    // MARK: Reading a board

    private func render(fen: String, light: UIColor, dark: UIColor, size: CGFloat = 800, flipped: Bool = false, margin: CGFloat = 60) -> CGImage {
        let position = Position(fen: fen + " w - - 0 1")!
        let unit = size / 8
        let total = CGSize(width: size + margin * 2, height: size + margin * 5)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: total, format: format).image { ctx in
            UIColor(white: 0.1, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: total))
            for row in 0..<8 { for column in 0..<8 {
                ((row + column) % 2 == 0 ? light : dark).setFill()
                let rect = CGRect(x: margin + CGFloat(column) * unit, y: margin * 2 + CGFloat(row) * unit, width: unit, height: unit)
                ctx.fill(rect)
                let square = flipped ? row * 8 + (7 - column) : (7 - row) * 8 + column
                if let piece = position.piece(at: square) {
                    let letter = ["p", "n", "b", "r", "q", "k"][Int(piece.kind.rawValue)]
                    PieceImage.load((piece.side == .white ? "w" : "b") + letter).draw(in: rect.insetBy(dx: unit * 0.04, dy: unit * 0.04))
                }
            } }
        }.cgImage!
    }

    func testReadsABoardItKnows() throws {
        let fen = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR"
        let want = try XCTUnwrap(Position(fen: fen + " w KQkq - 0 1"))
        let kinds: [(PieceKind, String)] = [(.pawn, "p"), (.knight, "n"), (.bishop, "b"), (.rook, "r"), (.queen, "q"), (.king, "k")]
        let extra = kinds.compactMap { kind, letter in PieceImage.load("w" + letter).cgImage.map { (kind, $0) } }
        let templates = BoardReader.templates(extra: extra)
        XCTAssertFalse(templates.isEmpty)

        let colours: [(UIColor, UIColor)] = [
            (UIColor(red: 0.93, green: 0.90, blue: 0.84, alpha: 1), UIColor(red: 0.17, green: 0.44, blue: 0.37, alpha: 1)),
            (UIColor(red: 0.94, green: 0.85, blue: 0.71, alpha: 1), UIColor(red: 0.71, green: 0.53, blue: 0.39, alpha: 1)),
        ]
        for (light, dark) in colours {
            let reading = try XCTUnwrap(BoardReader.read(render(fen: fen, light: light, dark: dark), templates: templates))
            let right = (0..<64).filter { reading.pieces[$0] == want.piece(at: $0) }.count
            // A floor, not a target: our enamel is the hardest set for it, with gold on black and highlights on white.
            // Real screenshots do better, 64/64 on Lichess and 61/64 on chess.com when measured. The editor catches the rest.
            XCTAssertGreaterThanOrEqual(right, 58, "\(right)/64")
            let colours = (0..<64).filter { reading.pieces[$0]?.side == want.piece(at: $0)?.side }.count
            XCTAssertGreaterThanOrEqual(colours, 58, "\(colours)/64")
        }
        let flipped = try XCTUnwrap(BoardReader.read(render(fen: fen, light: colours[1].0, dark: colours[1].1, flipped: true), templates: templates))
        XCTAssertEqual(flipped.pieces[8]?.side, .white, "White's men back on White's edge")
        XCTAssertEqual(BoardReader.fen(flipped.pieces, sideToMove: .white).split(separator: " ")[1], "w")
    }

    func testNoBoardIsNoReading() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        }.cgImage!
        XCTAssertNil(BoardReader.read(image))
    }

    func testFENFromPiecesKeepsCastlingOnlyAtHome() throws {
        var pieces = [Piece?](repeating: nil, count: 64)
        pieces[4] = Piece(kind: .king, side: .white); pieces[7] = Piece(kind: .rook, side: .white)
        pieces[60] = Piece(kind: .king, side: .black)
        let fen = BoardReader.fen(pieces, sideToMove: .black)
        XCTAssertEqual(fen, "4k3/8/8/8/8/8/8/4K2R b K - 0 1")
        XCTAssertNotNil(Position(fen: fen))
    }
}
