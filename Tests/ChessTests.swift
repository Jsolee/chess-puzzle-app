import XCTest
@testable import Scachs

final class ChessTests: XCTestCase {
    private static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    private static let kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -"
    private static let position3 = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -"
    private static let position4 = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
    private static let position5 = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"

    private static let scachsDamor = """
    1.e4 d5 2.exd5 Qxd5 3.Nc3 Qd8 4.Bc4 Nf6 5.Nf3 Bg4 6.h3 Bxf3 7.Qxf3 e6 8.Qxb7 Nbd7 9.Nb5 Rc8 \
    10.Nxa7 Nb6 11.Nxc8 Nxc8 12.d4 Nd6 13.Bb5+ Nxb5 14.Qxb5+ Nd7 15.d5 exd5 16.Be3 Bd6 17.Rd1 Qf6 \
    18.Rxd5 Qg6 19.Bf4 Bxf4 20.Qxd7+ Kf8 21.Qd8# 1-0
    """
    private static let scachsDamorFinalFEN = "3Q1k1r/2p2ppp/6q1/3R4/5b2/7P/PPP2PP1/4K2R b K - 2 21"

    // MARK: - Perft

    private func assertPerft(_ fen: String, _ expected: [UInt64], file: StaticString = #filePath, line: UInt = #line) {
        guard let position = Position(fen: fen) else {
            return XCTFail("FEN rejected: \(fen)", file: file, line: line)
        }
        for (index, nodes) in expected.enumerated() {
            XCTAssertEqual(position.perft(index + 1), nodes, "depth \(index + 1) of \(fen)", file: file, line: line)
        }
    }

    func testPerftStartPosition() {
        assertPerft(Self.startFEN, [20, 400, 8902, 197_281, 4_865_609])
    }

    func testPerftKiwipete() {
        assertPerft(Self.kiwipete, [48, 2039, 97862, 4_085_603])
    }

    func testPerftPosition3() {
        assertPerft(Self.position3, [14, 191, 2812, 43238, 674_624])
    }

    func testPerftPosition4() {
        assertPerft(Self.position4, [6, 264, 9467, 422_333])
    }

    func testPerftPosition5() {
        assertPerft(Self.position5, [44, 1486, 62379, 2_103_487])
    }

    // MARK: - FEN

    func testFENRoundTrip() {
        let fens = [
            Self.startFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            Self.position4,
            Self.position5,
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
            "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2",
        ]
        for fen in fens {
            XCTAssertEqual(Position(fen: fen)?.fen, fen)
        }
    }

    func testFENWithMissingClocks() {
        XCTAssertEqual(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq -")?.fen, "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        XCTAssertEqual(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 7")?.fen, "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 7 1")
        XCTAssertEqual(Position(fen: "  r3k2r/8/8/8/8/8/8/R3K2R   w  KQkq  -\n")?.halfmoveClock, 0)
    }

    func testFENDropsWhatThePlacementCannotBackUp() {
        XCTAssertEqual(Position(fen: "4k3/8/8/8/8/8/8/4K2R w KQkq - 0 1")?.fen, "4k3/8/8/8/8/8/8/4K2R w K - 0 1")
        XCTAssertEqual(Position(fen: "4k3/8/8/8/8/8/8/4K3 w - e6 0 1")?.fen, "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(Position(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 0")?.fullmoveNumber, 1)
    }

    func testGarbageFENIsRejected() {
        let garbage = [
            "", " ", "garbage", "8/8/8/8/8/8/8/8 w - - 0 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w XYZ - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq z9 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e3 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkqK - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 32768 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 100001",
            "4k3/8/8/8/8/8/PPPPPPPP/QQ2K3 w - - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - x 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 -1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 99999999999999999999",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 extra",
            "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/pppppppp/44/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnrr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/ppppxppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQ1BNR w kq - 0 1",
            "rnbqkknr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1",
            "P3k3/8/8/8/8/8/8/4K3 w - - 0 1",
            "4k3/8/8/8/8/8/8/p3K3 w - - 0 1",
            "4k3/pppppppp/p7/8/8/8/8/4K3 w - - 0 1",
            "4k3/8/8/8/8/8/8/4K2R w KQkq - 0 1 \u{0}",
            "4R1k1/8/8/8/8/8/8/4K3 w - - 0 1",
            "8/8/8/4k3/4K3/8/8/8 w - - 0 1",
            String(repeating: "8/", count: 100_000),
            "é♘🙂/8/8/8/8/8/8/8 w - - 0 1",
        ]
        for fen in garbage {
            XCTAssertNil(Position(fen: fen), fen)
        }
    }

    func testClocksStayWithinWhatTheEngineAccepts() {
        let position = Position(fen: "4k3/8/8/8/8/8/8/4K3 b - - 32767 100000")!
        let next = position.applying(position.legalMoves()[0])
        XCTAssertEqual(next.halfmoveClock, 32767)
        XCTAssertEqual(next.fullmoveNumber, 100_000)
        XCTAssertEqual(Position(fen: next.fen), next)
    }

    func testHashableCoversEveryField() {
        func position(_ fen: String) -> Position { Position(fen: fen)! }
        let base = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        XCTAssertEqual(position(base), position(base))
        XCTAssertEqual(position(base).hashValue, position(base).hashValue)
        XCTAssertEqual(Position.start.applying(Move(uci: "e2e4")!), position(base))

        for other in [
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQk e3 0 1",
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 1 1",
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 2",
            "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1",
        ] {
            XCTAssertNotEqual(position(base), position(other), other)
        }
        XCTAssertNotEqual(position("4k3/8/8/8/8/8/8/4K3 w - - 0 1"), position("4k3/8/8/8/8/8/8/4K3 b - - 0 1"))
    }

    func testEPDListsEnPassantOnlyWhenLegal() {
        XCTAssertEqual(
            Position.start.applying(Move(uci: "e2e4")!).epd,
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -"
        )
        XCTAssertEqual(
            Position(fen: "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 3")?.epd,
            "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3"
        )

        // Horizontal pin: bxc6 would clear both pawns off the king's rank.
        let horizontal = Position(fen: "8/8/8/KPp4r/8/8/8/7k w - c6 0 2")!
        XCTAssertFalse(horizontal.legalMoves().contains { $0.uci == "b5c6" })
        XCTAssertEqual(horizontal.epd, "8/8/8/KPp4r/8/8/8/7k w - -")
        XCTAssertTrue(horizontal.fen.contains(" c6 "))

        // Diagonal pin on the capturing pawn: leaving the diagonal exposes the king.
        XCTAssertEqual(
            Position(fen: "7k/6b1/8/3pP3/8/2K5/8/8 w - d6 0 2")?.epd,
            "7k/6b1/8/3pP3/8/2K5/8/8 w - -"
        )
        // Same pin, but the capture stays on the pinning diagonal.
        XCTAssertEqual(
            Position(fen: "7k/2b5/8/3pP3/5K2/8/8/8 w - d6 0 2")?.epd,
            "7k/2b5/8/3pP3/5K2/8/8/8 w - d6"
        )
        // File pin.
        XCTAssertEqual(
            Position(fen: "4r2k/8/8/3pP3/8/8/8/4K3 w - d6 0 2")?.epd,
            "4r2k/8/8/3pP3/8/8/8/4K3 w - -"
        )
        // In check from elsewhere: the capture does not answer it.
        XCTAssertEqual(
            Position(fen: "4k3/8/8/3pP3/8/8/8/r3K3 w - d6 0 2")?.epd,
            "4k3/8/8/3pP3/8/8/8/r3K3 w - -"
        )
        // The double-pushed pawn itself gives check: taking it en passant is an answer.
        XCTAssertEqual(
            Position(fen: "7k/8/8/3pP3/4K3/8/8/8 w - d6 0 2")?.epd,
            "7k/8/8/3pP3/4K3/8/8/8 w - d6"
        )
        // Black to move, stale target with no capturer next to it.
        XCTAssertEqual(
            Position(fen: "4k3/8/8/8/4P3/8/8/4K3 b - e3 0 1")?.epd,
            "4k3/8/8/8/4P3/8/8/4K3 b - -"
        )
    }

    // MARK: - Rules

    func testCastlingThroughCheck() {
        func castles(_ fen: String) -> [String] {
            Position(fen: fen)!.legalMoves(from: 4).map(\.uci).filter { $0 == "e1g1" || $0 == "e1c1" }.sorted()
        }
        XCTAssertEqual(castles("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1"), ["e1c1", "e1g1"])
        XCTAssertEqual(castles("4k3/8/8/8/8/8/8/R3K2R w - - 0 1"), [])
        XCTAssertEqual(castles("1k2r3/8/8/8/8/8/8/R3K2R w KQ - 0 1"), [])
        XCTAssertEqual(castles("1k3r2/8/8/8/8/8/8/R3K2R w KQ - 0 1"), ["e1c1"])
        XCTAssertEqual(castles("1k4r1/8/8/8/8/8/8/R3K2R w KQ - 0 1"), ["e1c1"])
        XCTAssertEqual(castles("1k1r4/8/8/8/8/8/8/R3K2R w KQ - 0 1"), ["e1g1"])
        XCTAssertEqual(castles("1kr5/8/8/8/8/8/8/R3K2R w KQ - 0 1"), ["e1g1"])
        // Only the rook crosses b1, so an attack there does not matter.
        XCTAssertEqual(castles("1r6/2k5/8/8/8/8/8/R3K2R w KQ - 0 1"), ["e1c1", "e1g1"])
        XCTAssertEqual(castles("1k6/8/8/8/8/8/8/RN2K1NR w KQ - 0 1"), [])
    }

    func testCastlingRightsAreLost() {
        let start = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        XCTAssertEqual(start.applying(Move(uci: "e1g1")!).fen, "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1")
        XCTAssertEqual(start.applying(Move(uci: "h1h2")!).fen, "r3k2r/8/8/8/8/8/7R/R3K3 b Qkq - 1 1")
        XCTAssertEqual(start.applying(Move(uci: "h1h8")!).fen, "r3k2R/8/8/8/8/8/8/R3K3 b Qq - 0 1")
    }

    func testDoubleCheckAllowsOnlyKingMoves() {
        // The queen could take the knight or block the file, but not both.
        let position = Position(fen: "3qk3/8/5N2/8/8/8/8/4R2K b - - 0 1")!
        XCTAssertEqual(position.attackers(of: 60, by: .white).sorted(), [4, 45])
        XCTAssertEqual(Set(position.legalMoves().map(\.from)), [60])
    }

    func testGameEndStates() {
        XCTAssertTrue(Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!.isStalemate)
        XCTAssertFalse(Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!.isCheckmate)
        XCTAssertTrue(Position(fen: "7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")!.isCheckmate)
        XCTAssertFalse(Position.start.isCheckmate)
        XCTAssertFalse(Position.start.isStalemate)
        XCTAssertEqual(Position.start.king(of: .black), 60)
    }

    func testInsufficientMaterial() {
        let dead = [
            "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
            "4k3/8/8/8/8/2B5/8/4K3 w - - 0 1",
            "4k3/8/8/8/8/2n5/8/4K3 w - - 0 1",
            "4k3/8/8/4b3/8/2B5/8/4K3 w - - 0 1",
        ]
        let alive = [
            "4k3/8/8/8/8/2N5/5N2/4K3 w - - 0 1",
            "4k3/8/8/8/2b5/2B5/8/4K3 w - - 0 1",
            "4k3/8/8/8/2n5/2B5/8/4K3 w - - 0 1",
            "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
            "4k3/8/8/8/8/8/8/4K2R w - - 0 1",
        ]
        for fen in dead { XCTAssertTrue(Position(fen: fen)!.hasInsufficientMaterial, fen) }
        for fen in alive { XCTAssertFalse(Position(fen: fen)!.hasInsufficientMaterial, fen) }
    }

    func testOutOfRangeInputDoesNotTrap() {
        let start = Position.start
        let wild = Move(from: 999, to: -3)
        XCTAssertNil(start.piece(at: 64))
        XCTAssertNil(start.piece(at: -1))
        XCTAssertEqual(start.legalMoves(from: 200), [])
        XCTAssertEqual(start.attackers(of: -9, by: .white), [])
        XCTAssertFalse(start.isLegal(wild))
        XCTAssertEqual(start.applying(wild), start)
        XCTAssertEqual(start.san(wild), "--")
        XCTAssertEqual(squareName(64), "-")
        XCTAssertEqual(start.perft(0), 1)
        XCTAssertEqual(start.perft(-4), 1)
    }

    // MARK: - SAN

    private func assertSAN(_ fen: String, _ uci: String, _ san: String, file: StaticString = #filePath, line: UInt = #line) {
        let position = Position(fen: fen)!
        guard let move = position.move(uci: uci) else {
            return XCTFail("\(uci) not legal in \(fen)", file: file, line: line)
        }
        XCTAssertEqual(position.san(move), san, file: file, line: line)
        XCTAssertEqual(position.move(san: san), move, file: file, line: line)
    }

    func testSANDisambiguation() {
        assertSAN("4k3/8/8/8/8/8/4K3/R6R w - - 0 1", "a1d1", "Rad1")
        assertSAN("4k3/8/8/8/8/8/4K3/R6R w - - 0 1", "h1d1", "Rhd1")
        assertSAN("4k3/R7/8/8/R7/8/8/4K3 w - - 0 1", "a7a5", "R7a5")
        assertSAN("4k3/R7/8/8/R7/8/8/4K3 w - - 0 1", "a4a5", "R4a5")
        assertSAN("1k6/8/8/8/4Q2Q/8/K7/7Q w - - 0 1", "h4e1", "Qh4e1")
        assertSAN("1k6/8/8/8/4Q2Q/8/K7/7Q w - - 0 1", "e4e1", "Qee1")
        assertSAN("1k6/8/8/8/4Q2Q/8/K7/7Q w - - 0 1", "h1e1", "Q1e1")
        // The e2 knight is pinned, so the b5 knight needs no disambiguation to reach d4.
        assertSAN("k3r3/8/8/1N6/8/8/4N3/4K3 w - - 0 1", "b5d4", "Nd4")
    }

    func testSANSpecialMoves() {
        assertSAN(Self.startFEN, "e2e4", "e4")
        assertSAN(Self.startFEN, "g1f3", "Nf3")
        assertSAN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1g1", "O-O")
        assertSAN("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", "e8c8", "O-O-O")
        assertSAN("3k4/8/8/8/8/8/8/R3K3 w Q - 0 1", "e1c1", "O-O-O+")
        assertSAN("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2", "e5d6", "exd6")
        assertSAN("1n2k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8q", "a8=Q")
        assertSAN("1n2k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7b8q", "axb8=Q+")
        assertSAN("1n2k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7b8n", "axb8=N")
        assertSAN("6k1/5ppp/8/8/8/8/8/R3K3 w Q - 0 1", "a1a8", "Ra8#")
        assertSAN("7k/8/8/8/8/8/8/R3K3 w Q - 0 1", "a1a8", "Ra8+")
    }

    func testSANTolerance() {
        let castling = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        for san in ["O-O", "0-0", "o-o", "O-O+", "O-O!", "O-O?!", " O-O "] {
            XCTAssertEqual(castling.move(san: san)?.uci, "e1g1", san)
        }
        for san in ["O-O-O", "0-0-0", "O-O-O#"] {
            XCTAssertEqual(castling.move(san: san)?.uci, "e1c1", san)
        }

        XCTAssertNil(Position.start.move(san: "O-O"))

        for san in ["e8=Q", "e8Q", "e8=q", "e8=Q+", "e8Q+", "e8=Q#!"] {
            XCTAssertEqual(Position(fen: "1n6/4P2k/8/8/8/8/8/4K3 w - - 0 1")!.move(san: san)?.uci, "e7e8q", san)
        }
        XCTAssertNil(Position(fen: "1n6/4P2k/8/8/8/8/8/4K3 w - - 0 1")!.move(san: "e8"))
        XCTAssertNil(Position(fen: "1n6/4P2k/8/8/8/8/8/4K3 w - - 0 1")!.move(san: "e8=K"))

        let passant = Position(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2")!
        for san in ["exd6", "exd6e.p.", "exd6 e.p.", "exd6 ep", "exd6+", "ed6", "e5xd6", "e5d6"] {
            XCTAssertEqual(passant.move(san: san)?.uci, "e5d6", san)
        }

        let start = Position.start
        for san in ["Nf3", "Nf3!", "Nf3?", "Nf3!!", "Nf3??", "Nf3!?", "Nf3?!", "Nf3+", "Ngf3", "N1f3", "Ng1f3", "Ng1-f3"] {
            XCTAssertEqual(start.move(san: san)?.uci, "g1f3", san)
        }
        for san in ["", " ", "?", "+", "x", "=", "O", "O-", "Z0", "--", "e9", "i4", "e4e4e4", "Nf9", "é4", "Ke2", "Nf4", "e5"] {
            XCTAssertNil(start.move(san: san), san)
        }
    }

    func testSANRejectsWhatItShouldNotGuess() {
        // Two rooks can reach d1: no disambiguation means no move.
        XCTAssertNil(Position(fen: "4k3/8/8/8/8/8/4K3/R6R w - - 0 1")!.move(san: "Rd1"))
        // A bare destination is a push, even when only a capture lands there.
        let capture = Position(fen: "4k3/8/8/3p4/2P5/8/8/4K3 w - - 0 1")!
        XCTAssertEqual(capture.move(san: "cxd5")?.uci, "c4d5")
        XCTAssertNil(capture.move(san: "d5"))
        // Kg1 is not how castling is written.
        XCTAssertNil(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!.move(san: "Kg1"))
        // Lowercase b is the b-pawn, uppercase is the bishop.
        let bishop = Position(fen: "4k3/8/8/8/8/1P6/8/2B1K3 w - - 0 1")!
        XCTAssertEqual(bishop.move(san: "b4")?.uci, "b3b4")
        XCTAssertEqual(bishop.move(san: "Bb2")?.uci, "c1b2")
    }

    func testSANRoundTripOverPerftTrees() {
        func walk(_ position: Position, depth: Int) {
            for move in position.legalMoves() {
                XCTAssertEqual(position.move(san: position.san(move)), move, "\(position.san(move)) in \(position.fen)")
                XCTAssertEqual(position.move(uci: move.uci), move, "\(move.uci) in \(position.fen)")
                XCTAssertEqual(Move(uci: move.uci), move)
                if depth > 1 { walk(position.applying(move), depth: depth - 1) }
            }
        }
        for fen in [Self.startFEN, Self.kiwipete, Self.position3, Self.position4, Self.position5] {
            walk(Position(fen: fen)!, depth: 3)
        }
    }

    // MARK: - UCI

    func testMoveFromUCI() {
        let castling = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        XCTAssertEqual(castling.move(uci: "e1h1")?.uci, "e1g1")
        XCTAssertEqual(castling.move(uci: "e1a1")?.uci, "e1c1")
        XCTAssertEqual(castling.move(uci: "e1g1")?.uci, "e1g1")
        let blackToMove = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")!
        XCTAssertEqual(blackToMove.move(uci: "e8h8")?.uci, "e8g8")
        XCTAssertEqual(blackToMove.move(uci: "e8a8")?.uci, "e8c8")
        XCTAssertEqual(blackToMove.applying(blackToMove.move(uci: "e8h8")!).fen, "r4rk1/8/8/8/8/8/8/R3K2R w KQ - 1 2")

        XCTAssertNil(Position(fen: "4k3/8/8/8/8/8/8/4K2R w - - 0 1")!.move(uci: "e1h1"))
        XCTAssertEqual(Position(fen: "3k4/8/8/8/8/8/8/K3R3 w - - 0 1")!.move(uci: "e1h1")?.uci, "e1h1")

        let start = Position.start
        for uci in ["", "e2", "e2e5", "e7e5", "e2e4q", "e2e2", "0000", "(none)", "z9z9", "e2e4extra", "é2é4", "a7a8k"] {
            XCTAssertNil(start.move(uci: uci), uci)
        }
        XCTAssertEqual(start.move(uci: "e2e4"), Move(from: 12, to: 28))

        let promotion = Position(fen: "8/4P2k/8/8/8/8/8/4K3 w - - 0 1")!
        XCTAssertNil(promotion.move(uci: "e7e8"))
        XCTAssertNil(promotion.move(uci: "e7e8k"))
        XCTAssertNil(promotion.move(uci: "e7e8Q"))
        XCTAssertEqual(promotion.move(uci: "e7e8n")?.promotion, .knight)
    }

    func testSquareHelpers() {
        XCTAssertEqual(squareName(0), "a1")
        XCTAssertEqual(squareName(7), "h1")
        XCTAssertEqual(squareName(56), "a8")
        XCTAssertEqual(squareName(63), "h8")
        XCTAssertEqual(square(named: "e4"), 28)
        for name in ["", "e", "e44", "i1", "a0", "a9", "E4", "é4"] {
            XCTAssertNil(square(named: name), name)
        }
    }

    func testMoveIsCodable() throws {
        let move = Move(from: 52, to: 60, promotion: .queen)
        XCTAssertEqual(try JSONDecoder().decode(Move.self, from: try JSONEncoder().encode(move)), move)
    }

    // MARK: - Replay

    func testScachsDamorReplay() throws {
        let game = try XCTUnwrap(PGN.parse(Self.scachsDamor).first)
        XCTAssertEqual(game.moves.count, 41)
        XCTAssertEqual(game.result, "1-0")
        XCTAssertNil(game.startFEN)
        XCTAssertEqual(game.moves.last?.san, "Qd8#")

        let final = game.moves.reduce(Position.start) { $0.applying($1.move) }
        XCTAssertEqual(final.fen, Self.scachsDamorFinalFEN)
        XCTAssertTrue(final.isCheckmate)
        XCTAssertTrue(final.inCheck)
    }

    // MARK: - PGN

    func testChessComGame() throws {
        let text = """
        [Event "Live Chess"]
        [Site "Chess.com"]
        [Date "2024.03.09"]
        [White "someone"]
        [Black "other"]
        [Result "0-1"]
        [TimeControl "60"]
        [EndTime "10:23:11 PST"]
        [Termination "other won on time"]

        1. e4 {[%clk 0:01:01.3]} 1... e5 {[%clk 0:00:59.8]} 2. Nf3 {[%clk 0:00:58]} 2... Nc6 {[%clk 0:00:57.1]} 0-1
        """
        let game = try XCTUnwrap(PGN.parse(text).first)
        XCTAssertEqual(game.tags["Site"], "Chess.com")
        XCTAssertEqual(game.tags["Termination"], "other won on time")
        XCTAssertEqual(game.result, "0-1")
        XCTAssertEqual(game.moves.map(\.san), ["e4", "e5", "Nf3", "Nc6"])
        XCTAssertEqual(game.moves[0].clock!, 61.3, accuracy: 1e-9)
        XCTAssertEqual(game.moves[1].clock!, 59.8, accuracy: 1e-9)
        XCTAssertEqual(game.moves[2].clock!, 58, accuracy: 1e-9)
        XCTAssertNil(game.moves[0].comment)
        XCTAssertNil(game.moves[0].evalCp)
    }

    func testLichessGame() throws {
        let text = """
        [Event "Rated Rapid game"]
        [Site "https://lichess.org/abcdefgh"]
        [Result "1-0"]

        1. e4 { [%eval 0.18] [%clk 0:10:00] } 1... c5 { [%clk 0:10:00] [%eval 0.25] } 2. Nf3?! { (0.25 → -0.30) Inaccuracy. c3 was best. } { [%eval -0.3] [%clk 0:09:58] } 2... e6 { [%eval #4] [%clk 0:09:55] } \
        3. d4 { [%eval #-3,28] } 3... cxd4 { [%eval +1.5,20] } 4. Nxd4 $1 $14 { [%eval 0.29] [%csl Gd4,Re5][%cal Gg1f3] Nice } 1-0
        """
        let game = try XCTUnwrap(PGN.parse(text).first)
        let moves = game.moves
        XCTAssertEqual(moves.count, 7)

        XCTAssertEqual(moves[0].evalCp, 18)
        XCTAssertEqual(moves[0].clock, 600)
        XCTAssertNil(moves[0].comment)
        XCTAssertEqual(moves[1].evalCp, 25)
        XCTAssertEqual(moves[1].clock, 600)

        XCTAssertEqual(moves[2].san, "Nf3")
        XCTAssertEqual(moves[2].nags, [6])
        XCTAssertEqual(moves[2].evalCp, -30)
        XCTAssertEqual(moves[2].clock, 598)
        XCTAssertEqual(moves[2].comment, "(0.25 → -0.30) Inaccuracy. c3 was best.")

        XCTAssertEqual(moves[3].evalMate, 4)
        XCTAssertNil(moves[3].evalCp)
        XCTAssertEqual(moves[4].evalMate, -3)
        XCTAssertEqual(moves[5].evalCp, 150)

        XCTAssertEqual(moves[6].evalCp, 29)
        XCTAssertEqual(moves[6].nags, [1, 14])
        XCTAssertEqual(moves[6].comment, "[%csl Gd4,Re5][%cal Gg1f3] Nice")
    }

    func testCommentCommandSpacing() throws {
        let cases: [(String, Double?, Int?)] = [
            ("{[%clk 0:01:01.3]}", 61.3, nil),
            ("{ [%eval 0.18] [%clk 0:10:00] }", 600, 18),
            ("{[%eval 0.18][%clk 0:10:00]}", 600, 18),
            ("{[%clk 0:10:00] [%eval 0.18]}", 600, 18),
            ("{ [ %clk  0:10:00 ] [ %eval  0.18 ] }", 600, 18),
            ("{[%clk 1:00:00.5]}", 3600.5, nil),
            ("{[%eval -0.00]}", nil, 0),
            ("{[%eval .5]}", nil, 50),
            ("{[%eval 327.67,40]}", nil, 32767),
        ]
        for (comment, clock, cp) in cases {
            let move = try XCTUnwrap(PGN.parse("1. e4 \(comment) *").first?.moves.first, comment)
            if let clock { XCTAssertEqual(move.clock!, clock, accuracy: 1e-9, comment) } else { XCTAssertNil(move.clock, comment) }
            XCTAssertEqual(move.evalCp, cp, comment)
            XCTAssertNil(move.comment, comment)
        }
    }

    func testMalformedCommandsStayInTheComment() throws {
        for comment in ["[%clk soon]", "[%eval nan]", "[%eval inf]", "[%eval 1e999]", "[%eval #x]", "[%eval 99999999999]", "[%clk 1:2:3:4]", "[%clk 0:10:00", "[%timestamp 15]"] {
            let move = try XCTUnwrap(PGN.parse("1. e4 {\(comment)} *").first?.moves.first, comment)
            XCTAssertEqual(move.comment, comment)
            XCTAssertNil(move.clock, comment)
            XCTAssertNil(move.evalCp, comment)
            XCTAssertNil(move.evalMate, comment)
        }
    }

    func testBOMAndCRLFAndMultipleGames() {
        let text = "\u{FEFF}[Event \"One\"]\r\n[Result \"1-0\"]\r\n\r\n1. e4 e5\r\n2. Nf3 1-0\r\n\r\n"
            + "\u{FEFF}[Event \"Two\"]\r\n[Result \"*\"]\r\n\r\n1. d4 *\r\n\r\n"
            + "[Event \"Three\"]\n\n1. c4 1/2-1/2\n"
        let games = PGN.parse(text)
        XCTAssertEqual(games.map { $0.tags["Event"] }, ["One", "Two", "Three"])
        XCTAssertEqual(games.map(\.result), ["1-0", "*", "1/2-1/2"])
        XCTAssertEqual(games.map(\.moves.count), [3, 1, 1])
    }

    func testTagsWithEscapesAndOddQuoting() {
        let text = #"""
        [Event "A \"quoted\" name \\ backslash"]
        [Site "the "big" one"]
        [White  "spaced"  ]
        [Black "]bracket[ inside"]
        [Annotator "two"] [Round "on one line"]
        [Broken "no closing

        1. e4 *
        """#
        let game = PGN.parse(text)[0]
        XCTAssertEqual(game.tags["Event"], #"A "quoted" name \ backslash"#)
        XCTAssertEqual(game.tags["Site"], #"the "big" one"#)
        XCTAssertEqual(game.tags["White"], "spaced")
        XCTAssertEqual(game.tags["Black"], "]bracket[ inside")
        XCTAssertEqual(game.tags["Annotator"], "two")
        XCTAssertEqual(game.tags["Round"], "on one line")
        XCTAssertEqual(game.tags["Broken"], "no closing")
        XCTAssertEqual(game.moves.count, 1)
    }

    func testMoveNumberAndSuffixForms() {
        let forms = [
            "1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 *",
            "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *",
            "1. e4 1... e5 2. Nf3 2... Nc6 3. Bb5 3... a6 *",
            "1.e4 1...e5 2.Nf3 2...Nc6 3.Bb5 3...a6 *",
            "1 e4 e5 2 Nf3 Nc6 3 Bb5 a6 *",
            "1. e4! e5? 2. Nf3!! Nc6?? 3. Bb5!? a6?! *",
            "1. e4 ! e5 ? 2. Nf3 !! Nc6 ?? 3. Bb5 !? a6 ?! *",
            "1.\u{A0}e4 e5\u{A0}2.\u{A0}Nf3 Nc6 3. Bb5 a6 *",
            "1. e4 $1 e5 $2 2. Nf3$3 Nc6$4 3. Bb5 a6 *",
            "1. e4{a}e5{b}2. Nf3(2. d4)Nc6;c\n3. Bb5 a6*",
        ]
        for text in forms {
            XCTAssertEqual(PGN.parse(text).first?.moves.map(\.san), ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"], text)
        }
        let glyphs = PGN.parse(forms[5])[0].moves.map(\.nags)
        XCTAssertEqual(glyphs, [[1], [2], [3], [4], [5], [6]])
        XCTAssertEqual(PGN.parse(forms[6])[0].moves.map(\.nags), glyphs)
    }

    func testSpecialMoveNotation() throws {
        let castled = try XCTUnwrap(PGN.parse("1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 5. d3 0-0 *").first)
        XCTAssertEqual(castled.moves.count, 10)
        XCTAssertEqual(castled.moves[6].san, "O-O")
        XCTAssertEqual(castled.moves[9].san, "O-O")

        let setup = #"""
        [SetUp "1"]
        [FEN "8/4P2k/8/8/8/8/8/4K3 w - - 0 1"]

        1. e8Q *
        """#
        XCTAssertEqual(PGN.parse(setup)[0].moves.map(\.san), ["e8=Q"])

        let passant = #"""
        [FEN "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"]

        2. exd6 e.p. Kd7 3. Ke2 *
        """#
        XCTAssertEqual(PGN.parse(passant)[0].moves.map(\.san), ["exd6", "Kd7", "Ke2"])
        let glued = #"""
        [FEN "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"]

        2. exd6e.p. Kd7 *
        """#
        XCTAssertEqual(PGN.parse(glued)[0].moves.map(\.san), ["exd6", "Kd7"])
    }

    func testSetUpAndFENTags() {
        let text = #"""
        [SetUp "1"]
        [FEN "r3k2r/8/8/8/8/8/8/R3K2R b KQkq -"]

        1... O-O 2. Rb1 *

        [FEN "not a fen"]

        1. e4 *

        [SetUp "0"]
        [FEN "4k3/8/8/8/8/8/8/4K3 w - - 0 1"]

        1. e4 *
        """#
        let games = PGN.parse(text)
        XCTAssertEqual(games.count, 3)
        XCTAssertEqual(games[0].startFEN, "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
        XCTAssertEqual(games[0].tags["FEN"], "r3k2r/8/8/8/8/8/8/R3K2R b KQkq -")
        XCTAssertEqual(games[0].moves.map(\.san), ["O-O", "Rb1"])
        XCTAssertNil(games[1].startFEN)
        XCTAssertEqual(games[1].moves.count, 0)
        XCTAssertNil(games[2].startFEN)
        XCTAssertEqual(games[2].moves.map(\.san), ["e4"])
    }

    func testCommentsOfEveryKind() throws {
        let text = """
        % a whole line escape, with a fake move 1. d4 and {brace
        [Event "x"]
        % another one, after a tag
        ; a line comment before any move

        {pre-game comment} 1. e4 {first} {second
        on two   lines} ; rest of line } counts as text
        e5 {uses { an inner brace} 2. Nf3 {semi;colon (paren) [bracket] 1-0 *} Nc6 *
        """
        let game = try XCTUnwrap(PGN.parse(text).first)
        XCTAssertEqual(game.tags["Event"], "x")
        XCTAssertEqual(game.moves.map(\.san), ["e4", "e5", "Nf3", "Nc6"])
        XCTAssertEqual(game.moves[0].comment, "first second on two lines rest of line } counts as text")
        XCTAssertEqual(game.moves[1].comment, "uses { an inner brace")
        XCTAssertEqual(game.moves[2].comment, "semi;colon (paren) [bracket] 1-0 *")
        XCTAssertNil(game.moves[3].comment)
    }

    func testPercentOnlyEscapesAtColumnZero() {
        XCTAssertEqual(PGN.parse("%skip\n1. e4 *")[0].moves.count, 1)
        XCTAssertEqual(PGN.parse("\u{FEFF}%skip\n1. e4 *")[0].moves.count, 1)
        XCTAssertEqual(PGN.parse("\r%skip\r1. e4 *")[0].moves.count, 1)
        XCTAssertEqual(PGN.parse("1. e4 %skip e5 *")[0].moves.count, 1)
    }

    func testVariationsAreSkipped() {
        let text = """
        1. e4 (1. d4 d5 (1... Nf6 2. c4 {a comment with ) in it} g6) 2. c4 ; line comment with )
        e6 1-0) 1... e5 {kept} (1... c5 $1 2. Nf3 {dropped} 0-1) 2. Nf3 1/2-1/2
        """
        let game = PGN.parse(text)[0]
        XCTAssertEqual(game.moves.map(\.san), ["e4", "e5", "Nf3"])
        XCTAssertEqual(game.moves[1].comment, "kept")
        XCTAssertEqual(game.moves[1].nags, [])
        XCTAssertEqual(game.result, "1/2-1/2")
    }

    func testResults() {
        XCTAssertEqual(PGN.parse("1. e4 1-0")[0].result, "1-0")
        XCTAssertEqual(PGN.parse("1. e4 0-1")[0].result, "0-1")
        XCTAssertEqual(PGN.parse("1. e4 1/2-1/2")[0].result, "1/2-1/2")
        XCTAssertEqual(PGN.parse("1. e4 *")[0].result, "*")
        XCTAssertEqual(PGN.parse("[Result \"0-1\"]\n\n1. e4")[0].result, "0-1")
        XCTAssertEqual(PGN.parse("[Result \"nonsense\"]\n\n1. e4")[0].result, "*")
        XCTAssertEqual(PGN.parse("1. e4")[0].result, "*")
    }

    func testIllegalMoveStopsOnlyThatGame() {
        let text = """
        [Event "Bad"]
        [Result "1-0"]

        1. e4 {ok} e5 2. Ke5 {after the stop} Nc6 $1 3. Nf3 1-0

        [Event "Good"]

        1. d4 d5 0-1

        [Event "No result then tags"]

        1. c4 Qxh1

        [Event "Last"]

        1. Nf3 *
        """
        let games = PGN.parse(text)
        XCTAssertEqual(games.map { $0.tags["Event"] }, ["Bad", "Good", "No result then tags", "Last"])
        XCTAssertEqual(games[0].moves.map(\.san), ["e4", "e5"])
        XCTAssertEqual(games[0].moves[1].comment, nil)
        XCTAssertEqual(games[0].moves[1].nags, [])
        XCTAssertEqual(games[0].result, "1-0")
        XCTAssertEqual(games[1].moves.map(\.san), ["d4", "d5"])
        XCTAssertEqual(games[2].moves.map(\.san), ["c4"])
        XCTAssertEqual(games[3].moves.map(\.san), ["Nf3"])
    }

    func testBrokenInputNeverCrashes() {
        XCTAssertEqual(PGN.parse("").count, 0)
        XCTAssertEqual(PGN.parse("   \n\r\n ").count, 0)
        XCTAssertEqual(PGN.parse("\u{FEFF}").count, 0)
        XCTAssertEqual(PGN.parse("complete nonsense").count, 0)
        XCTAssertEqual(PGN.parse("1. e4 {never closed")[0].moves.count, 1)
        XCTAssertEqual(PGN.parse("1. e4 (never closed")[0].moves.count, 1)
        XCTAssertEqual(PGN.parse("1. e4 $")[0].moves.count, 1)
        XCTAssertEqual(PGN.parse("1. e4 $99999999999999999999999")[0].moves[0].nags, [])
        XCTAssertEqual(PGN.parse("[").count, 0)
        XCTAssertEqual(PGN.parse("[Event \"")[0].tags["Event"], "")
        XCTAssertEqual(PGN.parse(String(repeating: "(", count: 100_000) + "1. e4").count, 0)
        XCTAssertEqual(PGN.parse(String(repeating: ")", count: 100_000) + "1. e4")[0].moves.count, 1)

        let recovered = PGN.parse("[Event \"A\"]\n\n1. e4 {oops\n\n[Event \"B\"]\n\n1. d4 *")
        XCTAssertEqual(recovered.map { $0.tags["Event"] }, ["A", "B"])
        XCTAssertEqual(recovered[1].moves.map(\.san), ["d4"])

        let unbalanced = PGN.parse("[Event \"A\"]\n\n1. e4 (1. d4 *\n\n[Event \"B\"]\n\n1. d4 *")
        XCTAssertEqual(unbalanced.map { $0.tags["Event"] }, ["A", "B"])
        XCTAssertEqual(unbalanced[1].moves.map(\.san), ["d4"])
    }

    func testThreeHundredGameFileIsFast() {
        var game = "[Event \"Bulk\"]\n[Result \"1-0\"]\n\n"
        var position = Position.start
        var number = 1
        for token in Self.scachsDamor.split(separator: " ") {
            let san = token.split(separator: ".").last.map(String.init) ?? String(token)
            guard let move = position.move(san: san) else { break }
            game += position.side == .white ? "\(number). " : "\(number)... "
            game += "\(san) { [%eval 0.18] [%clk 0:10:00] } "
            if position.side == .black { number += 1 }
            position = position.applying(move)
        }
        game += "1-0\n\n"
        let text = String(repeating: game, count: 300)

        var parsed: [PGNGame] = []
        let elapsed = ContinuousClock().measure { parsed = PGN.parse(text) }
        XCTAssertEqual(parsed.count, 300)
        XCTAssertTrue(parsed.allSatisfy { $0.moves.count == 41 })
        XCTAssertLessThan(elapsed, .seconds(10))
    }
}
