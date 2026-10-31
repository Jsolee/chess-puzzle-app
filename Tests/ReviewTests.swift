import XCTest
@testable import Scachs

final class ReviewTests: XCTestCase {
    private static let scachsDamor = """
    1.e4 d5 2.exd5 Qxd5 3.Nc3 Qd8 4.Bc4 Nf6 5.Nf3 Bg4 6.h3 Bxf3 7.Qxf3 e6 8.Qxb7 Nbd7 9.Nb5 Rc8 \
    10.Nxa7 Nb6 11.Nxc8 Nxc8 12.d4 Nd6 13.Bb5+ Nxb5 14.Qxb5+ Nd7 15.d5 exd5 16.Be3 Bd6 17.Rd1 Qf6 \
    18.Rxd5 Qg6 19.Bf4 Bxf4 20.Qxd7+ Kf8 21.Qd8# 1-0
    """

    // lichess.org/q7ZvsdUF as exported by the Lichess API, with their evals and their results for it.
    private static let lichessMoves = """
    d4 d5 c4 c6 Nc3 e6 e4 Nd7 exd5 cxd5 cxd5 exd5 Nxd5 Nb6 Bb5+ Bd7 Qe2+ Ne7 Nxb6 Qxb6 Bxd7+ Kxd7 Nf3 Qa6 \
    Ne5+ Ke8 Qf3 f6 Nd3 Qc6 Qe2 Kf7 O-O Kg8 Bd2 Re8 Rac1 Nf5 Be3 Qe6 Rfe1 g6 b3 Bd6 Qd2 Kf7 Bf4 Qd7 Bxd6 Nxd6 \
    Nc5 Rxe1+ Rxe1 Qc6 f3 Re8 Rxe8 Nxe8 Kf2 Nc7 Qb4 b6 Qc4+ Nd5 Nd3 Qe6 Nb4 Ne7 Qxe6+ Kxe6 Ke3 Kd6 g3 h6 Kd3 h5 \
    Nc2 Kd5 a3 Nc6 Ne3+ Kd6 h4 Nd8 g4 Ne6 Ke4 Ng7 Nc4+ Ke6 d5+ Kd7 a4 g5 gxh5 Nxh5 hxg5 fxg5 Kf5 Nf4 Ne3 Nh3 Kg4 \
    Ng1 Nc4 Kc7 Nd2 Kd6 Kxg5 Kxd5 f4 Nh3+ Kg4 Nf2+ Kf3 Nd3 Ke3 Nc5 Kf3 Ke6 Ke3 Kf5 Kd4 Ne6+ Kc4
    """
    private static let lichessEvals = [
        8, 7, 10, 14, 2, 9, 5, 85, 96, 98, 88, 87, 81, 88, 82, 90, 79, 160, 146, 151, 149, 160, 151, 150, 164, 190, 44, 61, 59, 54,
        -34, 158, 142, 183, 177, 340, 169, 200, 120, 167, 147, 200, 92, 102, 95, 95, 61, 79, 72, 201, 190, 183, 106, 108, 93, 101,
        101, 107, 100, 105, 103, 118, 117, 116, 83, 95, 90, 94, 94, 93, 88, 102, 79, 120, 114, 124, 108, 133, 100, 156, 198, 179,
        167, 227, 225, 209, 207, 192, 173, 243, 219, 234, 201, 342, 318, 342, 307, 323, 270, 313, 279, 303, 286, 277, 215, 213,
        8, 8, 8, 8, 21, 54, 42, 57, 25, 63, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    ]
    /// Lichess's own value for the start position, which it keeps out of the export.
    private static let lichessInitialEval = 15

    private func position(_ fen: String, file: StaticString = #filePath, line: UInt = #line) -> Position {
        guard let p = Position(fen: fen) else {
            XCTFail("bad FEN \(fen)", file: file, line: line)
            return .start
        }
        return p
    }

    private func facts(
        _ fen: String, _ uci: String, best: Score, bestMove: String? = nil, played: Score? = nil, second: Score? = nil,
        refutation: [String] = [], rating: Int? = 1500, isBook: Bool = false, previous: MoveFacts.Previous? = nil
    ) -> MoveFacts {
        let m = Move(uci: uci)!
        let top = bestMove.flatMap(Move.init(uci:)) ?? m
        return MoveFacts(before: position(fen), move: m, rating: rating, isBook: isBook, best: best, bestMove: top, bestLine: [top],
                         played: played ?? best, second: second, refutation: refutation.compactMap(Move.init(uci:)), previous: previous)
    }

    private func replayedGame(_ pgn: String) -> PGNGame { PGN.parse(pgn)[0] }

    private func lichessPositions() -> [Position] {
        var board = Position.start
        var out = [board]
        for san in Self.lichessMoves.split(separator: " ") {
            board = board.applying(board.move(san: String(san))!)
            out.append(board)
        }
        return out
    }

    private func lichessScores() -> [Score?] {
        ([Self.lichessInitialEval] + Self.lichessEvals).map { .cp($0) }
    }

    // MARK: - Expected points

    func testKFollowsRatingAndStaysInRange() {
        let table = ExpectedPoints.kTable
        XCTAssertEqual(ExpectedPoints.k(rating: 300), table[0].k)
        XCTAssertEqual(ExpectedPoints.k(rating: 3000), table[table.count - 1].k)
        XCTAssertEqual(ExpectedPoints.k(rating: table[4].rating), table[4].k, accuracy: 1e-12)
        XCTAssertEqual(ExpectedPoints.k(rating: (table[4].rating + table[5].rating) / 2), (table[4].k + table[5].k) / 2, accuracy: 1e-5)
        XCTAssertEqual(ExpectedPoints.k(rating: nil), ExpectedPoints.k(rating: ExpectedPoints.defaultRating))
        for (lower, higher) in zip(table, table.dropFirst()) {
            XCTAssertLessThan(lower.rating, higher.rating)
            XCTAssertLessThanOrEqual(lower.k, higher.k)
        }
    }

    func testMateRunsThroughTheCurve() {
        XCTAssertEqual(ExpectedPoints.of(.mate(0), rating: 1500), 0)
        XCTAssertGreaterThan(ExpectedPoints.of(.mate(1), rating: 1500), ExpectedPoints.of(.mate(5), rating: 1500))
        XCTAssertGreaterThan(ExpectedPoints.of(.mate(5), rating: 1500), ExpectedPoints.of(.cp(1000), rating: 1500))
        XCTAssertEqual(ExpectedPoints.of(.mate(40), rating: 1500), ExpectedPoints.of(.cp(1000), rating: 1500))
        XCTAssertEqual(ExpectedPoints.of(.mate(-3), rating: 1500), 1 - ExpectedPoints.of(.mate(3), rating: 1500), accuracy: 1e-12)
        XCTAssertLessThan(ExpectedPoints.of(.mate(-5), rating: 800), 0.05)
        XCTAssertEqual(Score.mate(0).flipped, .mate(1))
        XCTAssertEqual(Score.mate(-2).flipped, .mate(2))
        XCTAssertEqual(Score.cp(30).whitePOV(sideToMove: .black), .cp(-30))
    }

    /// A move from -4.25 to mated in 5 costs less the stronger the player, since -4.25 is already lost for them.
    func testTheSameCollapseCostsLessAtHigherRatings() {
        func band(_ rating: Int) -> MoveClass {
            Classifier.band(loss: ExpectedPoints.loss(best: .cp(-425), played: .mate(-5), rating: rating))
        }
        XCTAssertEqual(band(670), .blunder)
        XCTAssertEqual(band(1670), .blunder)
        XCTAssertEqual(band(2670), .mistake)
    }

    func testBandEdgesBelongToTheWorseClass() {
        XCTAssertEqual(Classifier.band(loss: 0), .best)
        XCTAssertEqual(Classifier.band(loss: 0.0001), .excellent)
        XCTAssertEqual(Classifier.band(loss: 0.0199), .excellent)
        XCTAssertEqual(Classifier.band(loss: 0.02), .good)
        XCTAssertEqual(Classifier.band(loss: 0.0499), .good)
        XCTAssertEqual(Classifier.band(loss: 0.05), .inaccuracy)
        XCTAssertEqual(Classifier.band(loss: 0.0999), .inaccuracy)
        XCTAssertEqual(Classifier.band(loss: 0.10), .mistake)
        XCTAssertEqual(Classifier.band(loss: 0.1999), .mistake)
        XCTAssertEqual(Classifier.band(loss: 0.20), .blunder)
        XCTAssertEqual(Classifier.band(loss: 1), .blunder)
    }

    func testMoveClassCopyAndColours() {
        XCTAssertEqual(MoveClass.allCases.count, 11)
        XCTAssertEqual(MoveClass.best.displayName, "La millor")
        XCTAssertEqual(MoveClass.miss.displayName, "Oportunitat perduda")
        XCTAssertEqual(MoveClass.blunder.displayName, "Pífia")
        XCTAssertEqual(MoveClass.brilliant.glyph, "!!")
        XCTAssertEqual(MoveClass.blunder.fillHex, 0xE2483A)
        XCTAssertEqual(MoveClass.blunder.onHex, 0xF6F1E6)
        XCTAssertEqual(MoveClass.book.fillHex, 0xD8AD85)
        XCTAssertFalse(MoveClass.forced.isCounted)
    }

    // MARK: - Pipeline, one fixture per class

    private static let quiet = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"

    func testForced() {
        // Only the rook can block the check.
        let f = facts("k5rr/8/8/8/1R6/8/8/7K w - - 0 1", "b4h4", best: .cp(-900))
        XCTAssertEqual(Classifier.classify(f).moveClass, .forced)
    }

    func testBook() {
        let f = facts(Self.quiet, "f1b5", best: .cp(0), isBook: true)
        XCTAssertEqual(Classifier.classify(f).moveClass, .book)
    }

    func testForcedBeatsBook() {
        let f = facts("k5rr/8/8/8/1R6/8/8/7K w - - 0 1", "b4h4", best: .cp(0), isBook: true)
        XCTAssertEqual(Classifier.classify(f).moveClass, .forced)
    }

    func testMateDeliveredIsBest() {
        let f = facts("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", "h5f7",
                      best: .mate(1), bestMove: "f3f4", played: .cp(0))
        XCTAssertEqual(Classifier.classify(f).moveClass, .best)
    }

    func testTopMoveAndBandsWithHandFedEvals() {
        func cls(_ played: Int) -> MoveClass {
            Classifier.classify(facts(Self.quiet, "f1b5", best: .cp(0), bestMove: "d2d4", played: .cp(played))).moveClass
        }
        XCTAssertEqual(Classifier.classify(facts(Self.quiet, "f1b5", best: .cp(20))).moveClass, .best)
        XCTAssertEqual(cls(0), .best)
        XCTAssertEqual(cls(-20), .excellent)
        XCTAssertEqual(cls(-60), .good)
        XCTAssertEqual(cls(-120), .inaccuracy)
        XCTAssertEqual(cls(-250), .mistake)
    }

    func testBlunderNeedsMaterialOrMate() {
        // Nxe5 Nxe5 gives a knight for a pawn.
        let losesPiece = facts(Self.quiet, "f3e5", best: .cp(30), bestMove: "d2d4", played: .cp(-500), refutation: ["c6e5"])
        XCTAssertEqual(Classifier.classify(losesPiece).moveClass, .blunder)

        // The same drop with no material lost is only a Mistake.
        let quietDrop = facts(Self.quiet, "h2h3", best: .cp(30), bestMove: "d2d4", played: .cp(-500), refutation: ["g8f6", "d2d3"])
        XCTAssertEqual(Classifier.classify(quietDrop).moveClass, .mistake)

        // One pawn is under the gate.
        let onePawn = facts("r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 3", "h2h3",
                            best: .cp(30), bestMove: "d4d5", played: .cp(-300), refutation: ["e5d4", "g2g3"])
        XCTAssertEqual(Classifier.classify(onePawn).moveClass, .mistake)

        // Mate allowed passes with no material at all.
        let fool = facts("rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2", "g2g4",
                         best: .cp(-50), bestMove: "e2e4", played: .mate(-1), refutation: ["d8h4"])
        XCTAssertEqual(Classifier.classify(fool).moveClass, .blunder)
    }

    func testMaterialOutcomeWritesOffARetakenCapture() {
        let start = position(Self.quiet)
        let line = [Move(uci: "f3e5")!, Move(uci: "c6e5")!]
        XCTAssertEqual(MaterialOutcome(from: start, line: line, side: .white).net, -2)
        // The line stops on Nxe5, which the knight on c6 would retake.
        XCTAssertEqual(MaterialOutcome(from: start, line: [line[0]], side: .white).net, -2)
    }

    func testMiss() {
        let quietGame = Self.quiet
        let opponentErred = MoveFacts.Previous(before: position("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 2 2"),
                                               move: Move(uci: "g7g6")!, epLost: 0.3, evalBefore: .cp(0))
        let punished = facts(quietGame, "h2h3", best: .cp(400), bestMove: "f3e5", played: .cp(30), refutation: ["g8f6"], previous: opponentErred)
        XCTAssertEqual(Classifier.classify(punished).moveClass, .miss)

        // No error to punish, so it stays in the bands.
        let noError = facts(quietGame, "h2h3", best: .cp(400), bestMove: "f3e5", played: .cp(30), refutation: ["g8f6"])
        XCTAssertEqual(Classifier.classify(noError).moveClass, .mistake)

        // Still winning afterwards, so nothing was missed.
        let stillWinning = facts(quietGame, "h2h3", best: .cp(700), bestMove: "f3e5", played: .cp(350), refutation: ["g8f6"], previous: opponentErred)
        XCTAssertEqual(Classifier.classify(stillWinning).moveClass, .mistake)

        // A lost forced mate qualifies alone.
        let lostMate = facts(quietGame, "h2h3", best: .mate(2), bestMove: "f3e5", played: .cp(200), refutation: ["g8f6"])
        XCTAssertEqual(Classifier.classify(lostMate).moveClass, .miss)

        // A real Blunder stays a Blunder.
        let blunder = facts(quietGame, "f3e5", best: .cp(400), bestMove: "d2d4", played: .cp(-300), refutation: ["c6e5"], previous: opponentErred)
        XCTAssertEqual(Classifier.classify(blunder).moveClass, .blunder)
    }

    func testGreatOnlyMove() {
        let only = facts(Self.quiet, "f1b5", best: .cp(20), second: .cp(-150), refutation: ["g8f6"])
        let c = Classifier.classify(only)
        XCTAssertEqual(c.moveClass, .great)
        XCTAssertEqual(c.greatReason, .onlyMove)
        XCTAssertEqual(c.secondBestGap!, ExpectedPoints.of(.cp(20), rating: 1500) - ExpectedPoints.of(.cp(-150), rating: 1500), accuracy: 1e-9)

        XCTAssertEqual(Classifier.classify(facts(Self.quiet, "f1b5", best: .cp(20), second: .cp(0))).moveClass, .best, "another move does the job")
        XCTAssertEqual(Classifier.classify(facts(Self.quiet, "f1b5", best: .cp(300), second: .cp(200))).moveClass, .best, "a clear gap, but winning either way")
        XCTAssertEqual(Classifier.classify(facts(Self.quiet, "f1b5", best: .cp(-100), second: .cp(-300))).moveClass, .best, "still worse afterwards")
        XCTAssertEqual(Classifier.classify(facts(Self.quiet, "f1b5", best: .cp(900), second: .cp(700))).moveClass, .best, "winning anyway")
        XCTAssertEqual(Classifier.classify(facts(Self.quiet, "f1b5", best: .mate(3), second: .mate(5))).moveClass, .best, "mates anyway")
        XCTAssertEqual(Classifier.classify(facts(Self.quiet, "f1b5", best: .cp(20))).moveClass, .best, "no second line")
    }

    func testGreatIsMoreGenerousForNewPlayers() {
        let fixture: (Int) -> MoveClass = { rating in
            Classifier.classify(self.facts(Self.quiet, "f1b5", best: .cp(200), second: .cp(118), rating: rating)).moveClass
        }
        XCTAssertEqual(fixture(1150), .great)
        XCTAssertEqual(fixture(1250), .best)
    }

    func testGreatTurnarounds() {
        func previous(_ eval: Score) -> MoveFacts.Previous {
            MoveFacts.Previous(before: position("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 2 2"), move: Move(uci: "g7g6")!, epLost: 0.2, evalBefore: eval)
        }
        let losing = facts(Self.quiet, "f1b5", best: .cp(0), second: .cp(-80), previous: previous(.cp(-400)))
        XCTAssertEqual(Classifier.classify(losing).greatReason, .losingToEqual)
        let equal = facts(Self.quiet, "f1b5", best: .cp(400), second: .cp(250), previous: previous(.cp(0)))
        XCTAssertEqual(Classifier.classify(equal).greatReason, .equalToWinning)
        XCTAssertEqual(Classifier.classify(equal).moveClass, .great)
        let alreadyMating = facts(Self.quiet, "f1b5", best: .mate(4), second: .cp(0), previous: previous(.mate(5)))
        XCTAssertEqual(Classifier.classify(alreadyMating).moveClass, .best, "continuing a mate is not a turnaround")
    }

    func testGreatExclusions() {
        // Getting out of check has to be played anyway.
        let check = facts("4k3/8/8/8/8/8/4R3/4K3 b - - 0 1", "e8d7", best: .cp(20), second: .cp(-200))
        XCTAssertEqual(Classifier.classify(check).moveClass, .best)

        // A free capture needs no finding.
        let free = facts("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1", "d1d5", best: .cp(20), second: .cp(-200))
        XCTAssertEqual(Classifier.classify(free).moveClass, .best)

        // Neither does taking back.
        let recapture = facts("r1bqkbnr/pppp1ppp/2n5/8/3pP3/5N2/PPP2PPP/RNBQKB1R w KQkq - 0 4", "f3d4", best: .cp(20), second: .cp(-200),
                              previous: MoveFacts.Previous(before: position("r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq - 0 3"), move: Move(uci: "e5d4")!, epLost: 0, evalBefore: .cp(0)))
        XCTAssertEqual(Classifier.classify(recapture).moveClass, .best)

        // Queening is obvious too.
        let queening = facts("8/P6k/8/8/8/8/8/6K1 w - - 0 1", "a7a8q", best: .cp(20), second: .cp(-200))
        XCTAssertEqual(Classifier.classify(queening).moveClass, .best)
    }

    // MARK: - Brilliant

    /// The Greek gift: Bxh7+ leaves the bishop to the king, for an attack.
    private static let greekGift = "r1bq1rk1/pppn1ppp/4p3/3pP3/1b1P4/2NB1N2/PPP2PPP/R1BQK2R w KQ - 0 8"

    func testBrilliantGreekGift() {
        let f = facts(Self.greekGift, "d3h7", best: .cp(150), second: .cp(40), refutation: ["g8h7", "f3g5", "h7g8", "d1h5"], rating: 1800)
        let c = Classifier.classify(f)
        XCTAssertEqual(c.moveClass, .brilliant)
        XCTAssertEqual(c.sacrificed, [square(named: "h7")!])
    }

    func testBrilliantExchangeSacrifice() {
        let f = facts("2r2rk1/pp1bppbp/3p1np1/q7/3NP3/2N1BP2/PPPQ2PP/2KR1B1R b - - 0 12", "c8c3",
                      best: .cp(50), second: .cp(10), refutation: ["b2c3", "f6e4"], rating: 2000)
        XCTAssertEqual(Classifier.classify(f).moveClass, .brilliant)
    }

    func testBrilliantAcceptsADeclinedSacrifice() {
        // The engine does not take: the bishop just stays en prise.
        let f = facts(Self.greekGift, "d3h7", best: .cp(150), second: .cp(40), refutation: ["g8h8", "f3g5"], rating: 1800)
        XCTAssertEqual(Classifier.classify(f).moveClass, .brilliant)
    }

    func testNotBrilliant() {
        func cls(_ f: MoveFacts) -> MoveClass { Classifier.classify(f).moveClass }
        // Still winning anyway.
        XCTAssertNotEqual(cls(facts(Self.greekGift, "d3h7", best: .cp(900), second: .cp(750), refutation: ["g8h7"], rating: 1800)), .brilliant)
        // Standing badly afterwards.
        XCTAssertNotEqual(cls(facts(Self.greekGift, "d3h7", best: .cp(-60), second: .cp(-90), refutation: ["g8h7"], rating: 1800)), .brilliant)
        // No second line, so no deep search yet.
        XCTAssertNotEqual(cls(facts(Self.greekGift, "d3h7", best: .cp(150), refutation: ["g8h7"], rating: 1800)), .brilliant)
        // A quiet move sacrifices nothing.
        XCTAssertNotEqual(cls(facts(Self.greekGift, "h2h3", best: .cp(150), second: .cp(40), refutation: ["g8h8"], rating: 1800)), .brilliant)
        // An even trade: nothing is worth more than what it took.
        XCTAssertNotEqual(cls(facts("r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4", "b5c6", best: .cp(30), second: .cp(0), refutation: ["d7c6"], rating: 1800)), .brilliant)
    }

    func testMaterialWonStraightBackIsNotASacrifice() {
        // Bxf7+ Kxf7 Qxd5+ only looks like a sacrifice.
        let f = facts("r3k2r/ppp2ppp/8/3q3B/8/8/PPP2PPP/R2QK2R w KQkq - 0 1", "h5f7", best: .cp(200), second: .cp(180), refutation: ["e8f7", "d1d5"], rating: 1800)
        XCTAssertNotEqual(Classifier.classify(f).moveClass, .brilliant)
    }

    func testEndgameSacrificeMustBeTheOnlyMove() {
        let fen = "2r3k1/5ppp/4Rn2/8/8/8/5PPP/6K1 w - - 0 1"
        let oneOfSeveral = facts(fen, "e6f6", best: .cp(50), second: .cp(40), refutation: ["g7f6"], rating: 1800)
        XCTAssertEqual(Classifier.classify(oneOfSeveral).moveClass, .best)
        let only = facts(fen, "e6f6", best: .cp(50), second: .cp(-200), refutation: ["g7f6"], rating: 1800)
        XCTAssertEqual(Classifier.classify(only).moveClass, .brilliant)
    }

    func testSacrificeTestIsLooserForNewPlayers() {
        func cls(_ rating: Int) -> MoveClass {
            Classifier.classify(facts(Self.greekGift, "d3h7", best: .cp(100), bestMove: "h2h3", played: .cp(86), second: .cp(100),
                                      refutation: ["g8h7", "f3g5"], rating: rating)).moveClass
        }
        XCTAssertEqual(cls(900), .brilliant)
        XCTAssertEqual(cls(1800), .excellent)
    }

    func testPieceSafety() {
        // Attacked by a pawn: unsafe however well defended.
        let pawnHit = position("4k3/8/3p4/4N3/3P4/8/8/4K3 w - - 0 1")
        XCTAssertFalse(pawnHit.isPieceSafe(at: square(named: "e5")!))
        // One attacker, one defender.
        let defended = position("4k3/4r3/8/4N3/3P4/8/8/4K3 w - - 0 1")
        XCTAssertTrue(defended.isPieceSafe(at: square(named: "e5")!))
        // One attacker, no defender.
        let bare = position("4k3/4r3/8/4N3/8/8/8/4K3 w - - 0 1")
        XCTAssertFalse(bare.isPieceSafe(at: square(named: "e5")!))
        // A rook battery counts as two attackers against one defender.
        let battery = position("4r1k1/4r3/8/4N3/3P4/8/8/4K3 w - - 0 1")
        XCTAssertTrue(battery.isPieceSafe(at: square(named: "e5")!), "a pawn defender holds it")
        let batteryPiece = position("4r1k1/4r3/8/4N3/8/8/8/4RK2 w - - 0 1")
        XCTAssertFalse(batteryPiece.isPieceSafe(at: square(named: "e5")!))
        // A pinned attacker cannot take. Here the rook on e7 is pinned to its king along the rank.
        let pinned = position("8/k3r2R/8/4N3/8/8/8/4K3 w - - 0 1")
        XCTAssertTrue(pinned.isPieceSafe(at: square(named: "e5")!))
    }

    // MARK: - Retry

    func testRetryCheck() {
        XCTAssertTrue(RetryCheck.accepts(best: .cp(100), retried: .cp(100), rating: 1500))
        let edge = ExpectedPoints.loss(best: .cp(100), played: .cp(80), rating: 1500)
        XCTAssertLessThan(edge, Thresholds.retryTolerance)
        XCTAssertTrue(RetryCheck.accepts(best: .cp(100), retried: .cp(80), rating: 1500))
        XCTAssertFalse(RetryCheck.accepts(best: .cp(100), retried: .cp(0), rating: 1500))
        XCTAssertTrue(RetryCheck.accepts(best: .mate(2), retried: .mate(9), rating: 1500))
        XCTAssertTrue(RetryCheck.accepts(best: .cp(300), retried: Score.mate(0).flipped, rating: 1500), "the retried move mates on the board")
        XCTAssertFalse(RetryCheck.accepts(best: .mate(2), retried: .cp(100), rating: 1500))
    }

    // MARK: - Accuracy

    func testAccuracySampleValues() {
        let samples: [(Double, Double)] = [(1, 96.6), (2, 92.4), (5, 80.8), (10, 64.6), (20, 41.0), (40, 15.9)]
        for (loss, expected) in samples {
            XCTAssertEqual(Accuracy.ofMove(winBefore: 60, winAfter: 60 - loss), expected, accuracy: 0.05, "win% loss \(loss)")
        }
        XCTAssertEqual(Accuracy.ofMove(winBefore: 60, winAfter: 61), 100)
        XCTAssertEqual(Accuracy.ofMove(winBefore: 90, winAfter: 0), 0, "clamped")
        XCTAssertEqual(Accuracy.winPercent(cp: 0), 50)
        XCTAssertEqual(Accuracy.winPercent(cp: 5000), Accuracy.winPercent(cp: 1000))
        XCTAssertEqual(Accuracy.winPercent(.mate(3)), Accuracy.winPercent(cp: 1000))
        XCTAssertEqual(Accuracy.winPercent(.mate(0)), Accuracy.winPercent(cp: -1000), "White to move is mated")
    }

    func testMaths() {
        XCTAssertEqual(Maths.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9])!, 2, accuracy: 1e-12)
        XCTAssertEqual(Maths.harmonicMean([1, 4, 4])!, 2, accuracy: 1e-12)
        XCTAssertEqual(Maths.harmonicMean([0, 1])!, 1, accuracy: 1e-12, "floored at 1")
        XCTAssertEqual(Maths.weightedMean([(1, 1), (3, 3)])!, 2.5, accuracy: 1e-12)
        XCTAssertNil(Maths.weightedMean([]))
    }

    func testAccuracyWindowsByHand() {
        // Two moves, window 2, weights are the population deviation of each pair, clamped at 0.5.
        let wins = [0, 100, 100].map { Accuracy.winPercent(cp: $0) }
        let first = Accuracy.ofMove(winBefore: wins[0], winAfter: wins[1])
        XCTAssertEqual(first, 100)
        let result = Accuracy.game(scores: [.cp(0), .cp(100), .cp(100)], start: .white)
        XCTAssertEqual(result.white!, 100, accuracy: 1e-9)
        XCTAssertEqual(result.black!, 100, accuracy: 1e-9)

        let drop = Accuracy.game(scores: [.cp(0), .cp(-200)], start: .white)
        let lost = Accuracy.winPercent(cp: 0) - Accuracy.winPercent(cp: -200)
        let expected = 103.1668100711649 * exp(-0.04354415386753951 * lost) - 3.166924740191411 + 1
        XCTAssertEqual(drop.white!, expected, accuracy: 1e-9)
        XCTAssertNil(drop.black)
        XCTAssertNil(Accuracy.game(scores: [.cp(0)], start: .white).white)
    }

    /// Lichess's own figures for one game, from its evals: accuracy 90 and 90, acpl 26 and 26.
    func testAccuracyMatchesLichessOnARealGame() {
        let result = Accuracy.game(scores: lichessScores(), start: .white)
        XCTAssertEqual(result.white!.rounded(), 90)
        XCTAssertEqual(result.black!.rounded(), 90)
        let acpl = Accuracy.averageCentipawnLoss(scores: lichessScores(), start: .white)
        XCTAssertEqual(acpl.white!.rounded(), 26)
        XCTAssertEqual(acpl.black!.rounded(), 26)
    }

    func testDividerAndPhasesMatchLichessOnARealGame() {
        let division = PhaseDivider.divide(lichessPositions())
        XCTAssertEqual(division.middle, 22)
        XCTAssertEqual(division.end, 53)
        let phases = Accuracy.phases(scores: lichessScores(), start: .white, division: division)
        XCTAssertEqual(phases.map(\.phase), [.opening, .middlegame, .endgame])
        let white = phases.map { $0.white!.rounded() }
        let black = phases.map { $0.black!.rounded() }
        XCTAssertEqual(white, [98, 81, 91])
        XCTAssertEqual(black, [88, 80, 94])
    }

    func testDividerOnTheStartAndAShortGame() {
        let d = PhaseDivider.divide([.start])
        XCTAssertNil(d.middle)
        XCTAssertNil(d.end)
        XCTAssertEqual(d.phase(ofPly: 0), .opening)
        XCTAssertEqual(PhaseDivider.majorsAndMinors(.start), 14)
    }

    func testEstimatedGameRating() {
        XCTAssertEqual(Accuracy.estimatedGameRating(acpl: 50, rating: 1000), 1371)
        XCTAssertEqual(Accuracy.estimatedGameRating(acpl: 250, rating: 1000), 504)
        XCTAssertEqual(Accuracy.estimatedGameRating(acpl: 0, rating: nil), 3100)
        XCTAssertEqual(Accuracy.estimatedGameRating(acpl: 100, rating: nil), 1140)
    }

    func testPhaseGrades() {
        XCTAssertEqual(PhaseGrade.grade(accuracy: 95, hasBrilliant: false, hasGreat: false), .best)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 94.9, hasBrilliant: false, hasGreat: false), .excellent)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 80, hasBrilliant: false, hasGreat: false), .good)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 60, hasBrilliant: false, hasGreat: false), .inaccuracy)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 45, hasBrilliant: false, hasGreat: false), .mistake)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 44, hasBrilliant: false, hasGreat: false), .blunder)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 90, hasBrilliant: true, hasGreat: true), .brilliant)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 90, hasBrilliant: false, hasGreat: true), .great)
        XCTAssertEqual(PhaseGrade.grade(accuracy: 70, hasBrilliant: true, hasGreat: true), .inaccuracy)
        XCTAssertTrue(PhaseGrade.isDecided(whiteScores: [.cp(900), .cp(900), .cp(900), .cp(0)]))
        XCTAssertFalse(PhaseGrade.isDecided(whiteScores: [.cp(900), .cp(0)]))
    }

    // MARK: - Openings

    func testOpeningOfThe1475Game() {
        let game = replayedGame(Self.scachsDamor)
        let moves = game.moves.map(\.move)
        let entry = Openings.shared.name(start: .start, moves: moves)
        XCTAssertEqual(entry?.name, "Scandinavian Defense: Valencian Variation")
        XCTAssertEqual(entry?.eco, "B01")
        // 3...Qd8 is named, and 4.Bc4 leaves the tables.
        XCTAssertEqual(Openings.shared.bookPlies(start: .start, moves: moves), 6)
    }

    func testOpeningMatchesLichessOnARealGame() {
        let positions = lichessPositions()
        var moves: [Move] = []
        var board = Position.start
        for san in Self.lichessMoves.split(separator: " ") {
            let m = board.move(san: String(san))!
            moves.append(m)
            board = board.applying(m)
        }
        XCTAssertEqual(positions.count, moves.count + 1)
        XCTAssertEqual(Openings.shared.name(start: .start, moves: moves)?.name, "Semi-Slav Defense: Marshall Gambit")
    }

    func testBookStopsAtTheFirstUnknownPosition() {
        // 1.e4 e5 is theory, 2.Ba6 is not, and nothing after it counts even if it transposes back.
        let line = ["e2e4", "e7e5", "f1a6", "b7a6"].compactMap(Move.init(uci:))
        XCTAssertEqual(Openings.shared.bookPlies(start: .start, moves: line), 2)
        XCTAssertTrue(Openings.shared.isBook(epd: Position.start.applying(line[0]).epd))
        XCTAssertFalse(Openings.shared.isBook(epd: "8/8/8/8/8/8/8/8 w - -"))
    }

    func testBookKeysListEnPassantOnlyWhenLegal() {
        // In 1.e4 c5 2.Nf3 d5 3.exd5 the c-pawn already passed, while 1.e4 d6 2.e5 f5 leaves a real capture.
        let capture = ["e2e4", "d7d6", "e4e5", "f7f5"].compactMap(Move.init(uci:)).reduce(Position.start) { $0.applying($1) }
        XCTAssertTrue(capture.epd.hasSuffix(" f6"))
        // A double push with no capturing pawn must key without the square, as the tables do: 1.e4 is plain.
        XCTAssertTrue(Position.start.applying(Move(uci: "e2e4")!).epd.hasSuffix(" -"))
        XCTAssertTrue(Openings.shared.isBook(epd: Position.start.applying(Move(uci: "e2e4")!).epd))
    }

    // MARK: - Coach

    private func note(_ f: MoveFacts, threat: ThreatLine? = nil, opening: Openings.Entry? = nil) -> CoachNote {
        Coach.note(facts: f, classification: Classifier.classify(f), threat: threat, opening: opening)
    }

    private func detectors(_ n: CoachNote) -> [CoachDetector] { n.clauses.map(\.detector) }

    private func moves(_ uci: String...) -> [Move] { uci.compactMap(Move.init(uci:)) }

    func testMotifFork() {
        let found = Coach.findMotif(on: position("2r3k1/5ppp/8/3N4/8/8/5PPP/6K1 w - - 0 1"), line: moves("d5e7", "g8f8", "e7c8"))
        guard case .fork(_, let targets)? = found?.motif else { return XCTFail("no fork") }
        XCTAssertEqual(Set(targets), [square(named: "g8")!, square(named: "c8")!])
        // Geometry alone is not enough: the line must take something.
        XCTAssertNil(Coach.findMotif(on: position("2r3k1/5ppp/8/3N4/8/8/5PPP/6K1 w - - 0 1"), line: moves("d5e7", "g8f8", "g2g3")))
    }

    func testMotifPin() {
        let found = Coach.findMotif(on: position("4k3/8/8/4n3/8/8/8/R5K1 w - - 0 1"), line: moves("a1e1", "e8d7", "e1e5"))
        guard case .pin(_, let pinned, let rear)? = found?.motif else { return XCTFail("no pin") }
        XCTAssertEqual(pinned, square(named: "e5"))
        XCTAssertEqual(rear, square(named: "e8"))
    }

    func testMotifSkewer() {
        let found = Coach.findMotif(on: position("3r4/8/8/3k4/8/8/8/R6K w - - 0 1"), line: moves("a1d1", "d5e5", "d1d8"))
        guard case .skewer(_, let front, let rear)? = found?.motif else { return XCTFail("no skewer") }
        XCTAssertEqual(front, square(named: "d5"))
        XCTAssertEqual(rear, square(named: "d8"))
    }

    func testMotifDiscoveredAttack() {
        let found = Coach.findMotif(on: position("4k2q/8/8/8/3N4/8/1B6/K7 w - - 0 1"), line: moves("d4f5", "e8d7", "b2h8"))
        guard case .discovered(_, let slider, let target)? = found?.motif else { return XCTFail("no discovery") }
        XCTAssertEqual(slider, square(named: "b2"))
        XCTAssertEqual(target, square(named: "h8"))
    }

    func testMotifHangingPiece() {
        let found = Coach.findMotif(on: position("4k3/8/8/8/3q4/8/8/3R2K1 w - - 0 1"), line: moves("d1d4"))
        guard case .hanging(let victim, _, .undefended)? = found?.motif else { return XCTFail("nothing hanging") }
        XCTAssertEqual(victim, square(named: "d4"))
    }

    func testMotifTrappedPiece() {
        let found = Coach.findMotif(on: position("3rk3/B1p5/1p6/8/8/8/5PPP/6K1 b - - 0 1"), line: moves("d8a8", "g1f1", "a8a7"))
        guard case .trapped(let victim)? = found?.motif else { return XCTFail("nothing trapped") }
        XCTAssertEqual(victim, square(named: "a7"))
    }

    func testMotifPromotion() {
        let found = Coach.findMotif(on: position("8/P6k/8/8/8/8/8/6K1 w - - 0 1"), line: moves("a7a8q"))
        guard case .promotion(let at)? = found?.motif else { return XCTFail("no promotion") }
        XCTAssertEqual(at, square(named: "a8"))
    }

    func testBackRankMate() {
        XCTAssertEqual(Coach.backRankMate(on: position("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"), line: moves("a1a8")), square(named: "g8"))
        XCTAssertNil(Coach.backRankMate(on: position("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"), line: moves("a1a7")))
    }

    func testNullMove() {
        let board = position("4k3/8/8/8/4Pp2/8/8/4K3 b - e3 0 1")
        XCTAssertEqual(board.nullMoved?.side, .white)
        XCTAssertTrue(board.nullMoved!.fen.contains(" w - - "))
        XCTAssertNil(position("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1").nullMoved, "no null move out of check")
    }

    func testCoachMateAllowed() {
        let f = facts("rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2", "g2g4", best: .cp(-50), bestMove: "e2e4", played: .mate(-1), refutation: ["d8h4"])
        let n = note(f)
        XCTAssertEqual(n.clauses.first?.detector, .mateAllowed)
        XCTAssertEqual(n.show, .checkmate)
        XCTAssertTrue(n.lineStartsAfterMove)
        XCTAssertTrue(n.text.contains("Qh4#"))
        XCTAssertEqual(n.arrows.first?.role, .threat)
        XCTAssertEqual(n.arrows.last?.role, .best)
    }

    func testCoachMateMissedOnTheBackRank() {
        let f = facts("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "g1f1", best: .mate(1), bestMove: "a1a8", played: .cp(150), refutation: ["g8f8"])
        XCTAssertEqual(Classifier.classify(f).moveClass, .miss)
        let n = note(f)
        XCTAssertEqual(detectors(n), [.mateMissed, .backRank])
        XCTAssertEqual(n.show, .checkmate)
        XCTAssertFalse(n.lineStartsAfterMove)
        XCTAssertEqual(n.arrows.first?.role, .best)
        XCTAssertEqual(n.clauses[1].marks.first?.square, square(named: "g8"))
    }

    func testCoachMaterialLostNamesThePieceAndTheMotif() {
        let f = facts(Self.quiet, "f3e5", best: .cp(30), bestMove: "d2d4", played: .cp(-500), refutation: ["c6e5"])
        XCTAssertEqual(Classifier.classify(f).moveClass, .blunder)
        let n = note(f)
        XCTAssertTrue(detectors(n).contains(.materialLost))
        XCTAssertEqual(n.show, .lostPiece)
        XCTAssertTrue(n.text.contains("Nxe5"), n.text)
        XCTAssertTrue(n.text.contains("un cavall"), n.text)
        XCTAssertTrue(n.arrows.contains { $0.role == .threat })
    }

    func testALineCutMidExchangeDoesNotClaimAPiece() {
        // A real game: after 7...Bg4 the engine line is 8.Bxf4 Nc6 9.Kh1 Nxe4 10.Nxe4 d5 11.Bxc7 Qxc7 12.Bxd5.
        // Black gives the knight on e4 and wins a piece back, so 7...Bg4 costs pawns, not "un cavall".
        let f = facts("rnbq1rk1/ppp1bppp/3p1n2/8/2BPPp2/2N2N2/PPP3PP/R1BQ1RK1 b - - 0 7", "c8g4",
                      best: .cp(-2), bestMove: "f6e4", played: .cp(-95),
                      refutation: ["c1f4", "b8c6", "g1h1", "f6e4", "c3e4", "d6d5", "f4c7", "d8c7", "c4d5"])
        let n = note(f)
        XCTAssertFalse(n.text.contains("un cavall"), n.text)
        XCTAssertTrue(n.text.contains("Nxe4"), n.text)
    }

    func testAnExchangeUnderWayIsNotAMaterialSwing() throws {
        // 6.h3 Bxf3 7.Qxf3 is an even trade, so 7...e6 only drops the pawn on b7, not "a bishop".
        let replay = try GameReplay(replayedGame(Self.scachsDamor))
        var state = ReviewState(gameID: replay.id, positions: replay.positions.count)
        state.shallow[13] = ReviewState.Search(score: .cp(-60), line: moves("c7c6"))
        state.shallow[14] = ReviewState.Search(score: .cp(290), line: moves("f3b7"))
        var f = try XCTUnwrap(ReviewEngine.facts(ply: 13, replay: replay, state: state, ratings: Ratings(white: 1500, black: 1500), book: 6))
        XCTAssertEqual(f.exchange.count, 2)
        XCTAssertEqual(f.outcome(of: [f.move] + f.refutation).net, -1)
        XCTAssertFalse(Classifier.losesMaterial(f))
        let text = note(f).text
        XCTAssertTrue(text.contains("un peó"), text)
        XCTAssertFalse(text.contains("alfil"), text)

        // The recapture itself wins nothing either.
        state.shallow[12] = ReviewState.Search(score: .cp(50), line: [replay.moves[12]])
        f = try XCTUnwrap(ReviewEngine.facts(ply: 12, replay: replay, state: state, ratings: Ratings(white: 1500, black: 1500), book: 6))
        XCTAssertTrue(f.isRecapture)
        XCTAssertEqual(detectors(note(f)), [.recapture])
    }

    func testBeingRetakenIsNotAHangingPiece() {
        // Bxc6 dxc6 trades bishop for knight. Even when the line then loses a pawn, nothing hung.
        var f = facts("r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4", "b5c6", best: .cp(30), bestMove: "b5a4",
                      played: .cp(-120), refutation: ["d7c6", "h2h3", "d8d4", "f3d4", "e5d4"], rating: 1500)
        f.bestLine = moves("b5a4")
        XCTAssertFalse(detectors(note(f)).contains(.hanging), "\(detectors(note(f)))")
    }

    func testCoachMaterialMissedWithFork() {
        // Ne7+ wins the rook. The player pushes a pawn instead.
        var f = facts("2r3k1/5ppp/8/3N4/8/8/5PPP/6K1 w - - 0 1", "h2h3", best: .cp(500), bestMove: "d5e7", played: .cp(0), refutation: ["c8d8"])
        f.bestLine = moves("d5e7", "g8f8", "e7c8")
        let n = note(f)
        XCTAssertEqual(detectors(n), [.fork, .materialMissed])
        XCTAssertEqual(n.show, .fork)
        XCTAssertEqual(n.line, f.bestLine)
    }

    func testCoachThreatIgnored() {
        // Black's knight attacks the rook. White takes the other rook and the material stays level.
        let fen = "4k3/8/8/7r/8/1n6/8/R5KR w - - 0 1"
        var f = facts(fen, "h1h5", best: .cp(500), bestMove: "a1a2", played: .cp(0), refutation: ["b3a1"])
        f.bestLine = moves("a1a2")
        let threat = ThreatLine(line: moves("b3a1"), score: .cp(300))
        let n = note(f, threat: threat)
        XCTAssertTrue(detectors(n).contains(.threatIgnored), "\(detectors(n))")
        XCTAssertTrue(n.text.contains("Nxa1"), n.text)
        XCTAssertTrue(n.arrows.contains { $0.role == .opponent })
    }

    func testCoachThreatPrevented() {
        var f = facts("4k3/8/8/8/8/1n6/8/R5K1 w - - 0 1", "a1a2", best: .cp(0), refutation: ["e8d7"])
        f.bestLine = moves("a1a2", "e8d7")
        let n = note(f, threat: ThreatLine(line: moves("b3a1"), score: .cp(300)))
        XCTAssertEqual(detectors(n), [.threatPrevented])
    }

    func testCoachFallsBackToTheLine() {
        // A Mistake that stays in the equal zone, so no eval-change clause takes the line's place.
        var f = facts(Self.quiet, "h2h3", best: .cp(110), bestMove: "d2d4", played: .cp(-115), refutation: ["g8f6"])
        f.bestLine = moves("d2d4", "e5d4", "f3d4")
        let n = note(f)
        XCTAssertEqual(Classifier.classify(f).moveClass, .mistake)
        XCTAssertEqual(n.clauses.first?.detector, .verdict)
        XCTAssertEqual(n.clauses.last?.detector, .line)
        XCTAssertEqual(n.show, .idea)
        XCTAssertEqual(n.line, f.bestLine)
    }

    func testCoachPositiveNotes() {
        XCTAssertEqual(detectors(note(facts("k5rr/8/8/8/1R6/8/8/7K w - - 0 1", "b4h4", best: .cp(0)))), [.forced])
        let book = note(facts(Self.quiet, "f1b5", best: .cp(0), isBook: true), opening: Openings.Entry(eco: "C60", name: "Ruy Lopez"))
        XCTAssertEqual(detectors(book), [.book])
        XCTAssertTrue(book.text.contains("Ruy Lopez"))
        let mate = note(facts("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", "h5f7", best: .mate(1)))
        XCTAssertEqual(detectors(mate), [.mateDelivered])

        let brilliant = note(facts(Self.greekGift, "d3h7", best: .cp(150), second: .cp(40), refutation: ["g8h7", "f3g5", "h7g8", "d1h5"], rating: 1800))
        XCTAssertEqual(brilliant.clauses.first?.detector, .sacrifice)
        XCTAssertEqual(brilliant.show, .idea)
        XCTAssertEqual(brilliant.clauses.first?.marks.first?.square, square(named: "h7"))

        let great = note(facts(Self.quiet, "f1b5", best: .cp(20), second: .cp(-150), refutation: ["g8f6"]))
        XCTAssertEqual(great.clauses.first?.detector, .onlyMove)

        let verdict = note(facts(Self.quiet, "f1b5", best: .cp(20), refutation: ["g8f6"]))
        XCTAssertEqual(detectors(verdict), [.verdict])
    }

    func testCoachIsDeterministicAndKeepsTheHouseStyle() {
        let fixtures: [MoveFacts] = [
            facts("rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2", "g2g4", best: .cp(-50), bestMove: "e2e4", played: .mate(-1), refutation: ["d8h4"]),
            facts(Self.quiet, "f3e5", best: .cp(30), bestMove: "d2d4", played: .cp(-300), refutation: ["c6e5"]),
            facts(Self.quiet, "h2h3", best: .cp(30), bestMove: "d2d4", played: .cp(-120), refutation: ["g8f6"]),
            facts(Self.quiet, "a2a3", best: .cp(30), bestMove: "d2d4", played: .cp(-60), refutation: ["g8f6"]),
            facts(Self.quiet, "b2b3", best: .cp(30), bestMove: "d2d4", played: .cp(5), refutation: ["g8f6"]),
            facts(Self.quiet, "f1c4", best: .cp(30), bestMove: "d2d4", played: .cp(20), refutation: ["g8f6"]),
            facts(Self.greekGift, "d3h7", best: .cp(150), second: .cp(40), refutation: ["g8h7", "f3g5"], rating: 1800),
        ]
        for f in fixtures {
            let first = note(f), second = note(f)
            XCTAssertEqual(first, second)
            XCTAssertFalse(first.clauses.isEmpty)
            XCTAssertFalse(first.text.contains("!"), first.text)
            XCTAssertFalse(first.text.contains("—"), first.text)
            XCTAssertFalse(first.text.contains("–"), first.text)
            for clause in first.clauses { XCTAssertFalse(clause.text.isEmpty) }
        }
    }

    func testCatalanElisionBeforeSquares() {
        // The bishop on f5 reads "d'f5", the one on c3 reads "de c3".
        let n = note(facts("4k3/8/8/5b2/8/8/8/5RK1 w - - 0 1", "f1f5", best: .cp(500), refutation: ["e8d7"]))
        XCTAssertTrue(n.text.contains("d'f5"), n.text)
        let m = note(facts("4k3/8/8/8/8/2b5/8/2R3K1 w - - 0 1", "c1c3", best: .cp(500), refutation: ["e8d7"]))
        XCTAssertTrue(m.text.contains("de c3"), m.text)
    }

    func testCoachRolesMapToTheBoard() {
        XCTAssertEqual(CoachArrow(from: 0, to: 1, role: .threat).board, BoardArrow(from: 0, to: 1, role: .threat))
        XCTAssertEqual(CoachMark(square: 3, role: .best).board, BoardMark(square: 3, role: .good))
    }

    // MARK: - Assembly

    private func handFedState(_ replay: GameReplay, book: Int, cp: (Int) -> Int) -> ReviewState {
        var state = ReviewState(gameID: replay.id, positions: replay.positions.count)
        for p in book..<replay.positions.count {
            if let terminal = replay.terminalScore(at: p) {
                state.shallow[p] = ReviewState.Search(score: terminal)
            } else {
                let line = p < replay.moves.count ? [replay.moves[p]] : []
                state.shallow[p] = ReviewState.Search(score: .cp(cp(p)), line: line, depth: 12, nodes: 150_000)
            }
        }
        return state
    }

    func testAssembleWithFixedEvals() throws {
        let game = replayedGame(Self.scachsDamor)
        let replay = try GameReplay(game)
        let book = Openings.shared.bookPlies(start: replay.positions[0], moves: replay.moves)
        // Every played move is the engine's choice in this fixture, so the whole game reads as best.
        let state = handFedState(replay, book: book) { _ in 10 }
        let review = ReviewEngine.assemble(replay: replay, state: state, ratings: Ratings(white: 1800, black: 1800))

        XCTAssertTrue(review.isComplete)
        XCTAssertEqual(review.moves.count, 41)
        XCTAssertEqual(review.opening?.name, "Scandinavian Defense: Valencian Variation")
        XCTAssertEqual(review.moves[0].moveClass, .book)
        XCTAssertEqual(review.moves[5].moveClass, .book)
        XCTAssertTrue(review.moves[5].isKey, "the last book move")
        XCTAssertNil(review.moves[0].evalBefore)
        XCTAssertEqual(review.moves[6].san, "Bc4")
        XCTAssertEqual(review.moves[6].moveClass, .best)
        XCTAssertEqual(review.moves.last?.san, "Qd8#")
        XCTAssertEqual(review.moves.last?.moveClass, .best)
        XCTAssertEqual(review.moves.last?.evalAfter, .mate(1), "White has mated")
        XCTAssertEqual(review.white.counts[.book], 3)
        XCTAssertEqual(review.black.counts[.book], 3)
        XCTAssertNotNil(review.white.accuracy)
        XCTAssertNotNil(review.white.gameRating)
        XCTAssertEqual(review.graph.count, 42)
        XCTAssertFalse(review.phases.isEmpty)
        XCTAssertEqual(review.engine.searchedPositions, 35)
        XCTAssertEqual(review.engine.maxDepth, 12)

        let decoded = try JSONDecoder().decode(GameReview.self, from: JSONEncoder().encode(review))
        XCTAssertEqual(decoded.moves.last?.coach, review.moves.last?.coach)
        XCTAssertEqual(decoded.white.counts, review.white.counts)
    }

    func testAPartialStateStillAssembles() throws {
        let replay = try GameReplay(replayedGame(Self.scachsDamor))
        var state = ReviewState(gameID: replay.id, positions: replay.positions.count)
        state.shallow[6] = ReviewState.Search(score: .cp(20), line: [replay.moves[6]], depth: 10, nodes: 1)
        let review = ReviewEngine.assemble(replay: replay, state: state, ratings: Ratings())
        XCTAssertFalse(review.isComplete)
        XCTAssertEqual(review.moves[6].moveClass, .best)
        XCTAssertNil(review.moves[20].moveClass)
    }

    func testForcedPlyInAGameIsNotCounted() throws {
        // 1.Qh5+ style: a single legal reply stays out of the count table.
        let game = replayedGame("[FEN \"k5rr/8/8/8/1R6/8/8/7K w - - 0 1\"]\n\n1.Rh4 Rxh4+ *")
        let replay = try GameReplay(game)
        XCTAssertTrue(replay.isForced[0])
        var state = ReviewState(gameID: replay.id, positions: 3)
        state.shallow[0] = ReviewState.Search(score: .cp(-900), line: [replay.moves[0]])
        state.shallow[1] = ReviewState.Search(score: .cp(900), line: [replay.moves[1]])
        state.shallow[2] = ReviewState.Search(score: .cp(-1500))
        let review = ReviewEngine.assemble(replay: replay, state: state, ratings: Ratings())
        XCTAssertEqual(review.moves[0].moveClass, .forced)
        XCTAssertNil(review.white.counts[.forced])
    }

    func testDeepCandidateSelection() {
        func reason(_ f: MoveFacts) -> ReviewEngine.DeepReason? { ReviewEngine.deepReason(f) }
        // Inaccuracy or worse.
        XCTAssertEqual(reason(facts(Self.quiet, "h2h3", best: .cp(30), bestMove: "d2d4", played: .cp(-150))), .band)
        // Near the Excellent and Good edge.
        XCTAssertEqual(reason(facts(Self.quiet, "h2h3", best: .cp(0), bestMove: "d2d4", played: .cp(-37))), .band)
        // Mid-band Good, well away from any edge.
        XCTAssertNil(reason(facts(Self.quiet, "h2h3", best: .cp(0), bestMove: "d2d4", played: .cp(-60))))
        // A possible sacrifice.
        XCTAssertEqual(reason(facts(Self.greekGift, "d3h7", best: .cp(150), refutation: ["g8h7", "f3g5"], rating: 1800)), .sacrifice)
        // A top move in a live position may be the only one, so it gets the quick look.
        XCTAssertEqual(reason(facts(Self.quiet, "f1b5", best: .cp(50))), .onlyMove)
        // A top move in a lost position cannot be Great or Brilliant.
        XCTAssertNil(reason(facts(Self.quiet, "f1b5", best: .cp(-400))))
        // Mate delivered needs no second look.
        XCTAssertNil(reason(facts("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", "h5f7", best: .mate(1))))
    }

    func testNoiseGuardTakesTheKinderDeepLook() throws {
        // The played move searched alone looks better than the next position's own search.
        let replay = try GameReplay(replayedGame("1.e4 e5 2.Nf3 *"))
        var state = ReviewState(gameID: replay.id, positions: 4)
        let other = Move(uci: "d2d4")!
        state.shallow[2] = ReviewState.Search(score: .cp(30), line: [other])
        state.deep[2] = ReviewState.DeepSearch(best: ReviewState.Search(score: .cp(30), line: [other]),
                                               second: ReviewState.Search(score: .cp(10), line: [replay.moves[2]]),
                                               played: ReviewState.Search(score: .cp(10), line: [replay.moves[2], Move(uci: "g8f6")!]))
        state.shallow[3] = ReviewState.Search(score: .cp(200), line: [Move(uci: "g8f6")!])
        let f = ReviewEngine.facts(ply: 2, replay: replay, state: state, ratings: Ratings(), book: 0)
        XCTAssertEqual(f?.played, .cp(10))
        XCTAssertEqual(f?.second, .cp(10))
        XCTAssertEqual(f?.refutation, [Move(uci: "g8f6")!])
    }

    func testStatesSurviveARoundTrip() throws {
        var state = ReviewState(gameID: "x", positions: 2)
        state.shallow[0] = ReviewState.Search(score: .mate(3), line: [Move(uci: "e2e4")!], depth: 4, nodes: 9)
        state.deep[0] = ReviewState.DeepSearch(best: ReviewState.Search(score: .cp(4)), threat: ThreatLine(line: [], score: .cp(0)))
        let decoded = try JSONDecoder().decode(ReviewState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.shallow, state.shallow)
        XCTAssertEqual(decoded.deep, state.deep)
    }

    func testRatingsReadTheHeaders() {
        let game = replayedGame("[WhiteElo \"1711\"]\n[BlackElo \"?\"]\n\n1.e4 *")
        XCTAssertEqual(Ratings(game: game).white, 1711)
        XCTAssertEqual(Ratings(game: game).black, 1711, "the other player's rating beats nothing")
        XCTAssertEqual(Ratings(game: game, fallback: 1200).black, 1200)
        XCTAssertNil(Ratings(game: replayedGame("1.e4 *")).white)
    }
}
