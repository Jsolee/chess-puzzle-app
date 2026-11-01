import XCTest
@testable import Scachs

private let uuidA = "4177d622-abdd-11f0-98f0-1f5aca01000f"
private let uuidDaily = "d554da06-2020-11ef-a372-fb8c6f01000b"

// Trimmed from real responses, players renamed.
private let chessComMonth = #"""
{"games":[
{"url":"https://www.chess.com/game/live/144425637008","pgn":"[Event \"Live Chess\"]\n[Site \"Chess.com\"]\n[Date \"2026.10.18\"]\n[White \"Anna\"]\n[Black \"Bernat\"]\n[Result \"1-0\"]\n[UTCDate \"2026.10.18\"]\n[UTCTime \"04:45:22\"]\n[WhiteElo \"1500\"]\n[BlackElo \"1480\"]\n[TimeControl \"180\"]\n[Termination \"Anna won by checkmate\"]\n[Link \"https://www.chess.com/game/live/144425637008\"]\n\n1. e4 {[%clk 0:03:00]} 1... e5 {[%clk 0:02:58.7]} 2. Qh5 {[%clk 0:02:57]} 2... Nc6 {[%clk 0:02:55]} 3. Bc4 {[%clk 0:02:50]} 3... Nf6 {[%clk 0:02:50]} 4. Qxf7# {[%clk 0:02:44]} 1-0\n","time_control":"180","end_time":1760762784,"rated":true,"accuracies":{"white":98.5,"black":41},"tcn":"mC","uuid":"4177d622-abdd-11f0-98f0-1f5aca01000f","initial_setup":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","fen":"r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4","time_class":"blitz","rules":"chess","white":{"rating":1500,"result":"win","@id":"https://api.chess.com/pub/player/anna","username":"Anna","uuid":"a"},"black":{"rating":1480,"result":"checkmated","@id":"https://api.chess.com/pub/player/bernat","username":"Bernat","uuid":"b"},"eco":"https://www.chess.com/openings/Kings-Pawn-Opening"},
{"url":"https://www.chess.com/game/daily/814505376","pgn":"[Event \"Let's Play!\"]\n[Site \"Chess.com\"]\n[Date \"2026.10.01\"]\n[White \"Bernat\"]\n[Black \"Anna\"]\n[Result \"1-0\"]\n[UTCDate \"2026.10.01\"]\n[UTCTime \"14:11:26\"]\n[TimeControl \"1/259200\"]\n[Termination \"Bernat won on time\"]\n[Link \"https://www.chess.com/game/daily/814505376\"]\n\n1. e4 {[%clk 0:00:00.2]} 1... d5 {[%clk 4:51:07.4]} 2. exd5 {[%clk 0:04:53.3]} 1-0\n","time_control":"1/259200","end_time":1759687952,"rated":true,"tcn":"mCZJCJ","uuid":"d554da06-2020-11ef-a372-fb8c6f01000b","initial_setup":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -","fen":"rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq -","start_time":1759251086,"time_class":"daily","rules":"chess","white":{"rating":1583,"result":"win","username":"Bernat"},"black":{"rating":2000,"result":"timeout","username":"Anna"}},
{"url":"https://www.chess.com/game/live/160792625665","time_control":"300","end_time":1766479576,"rated":false,"tcn":"owZJ","uuid":"f7c5df84-dfda-11f0-b03a-a0369feff220","initial_setup":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","fen":"1r5r/p3nk1p/3p1p1b/8/2P1P2P/P2P2P1/5P1p/3K3N w - - 1 33","time_class":"blitz","rules":"bughouse","white":{"rating":737,"result":"resigned","username":"Anna"},"black":{"rating":1500,"result":"win","username":"Bernat"}},
{"url":"https://www.chess.com/game/live/26422898995","pgn":"[Event \"Live Chess\"]\n[White \"Anna\"]\n[Black \"Bernat\"]\n[Result \"1-0\"]\n[SetUp \"1\"]\n[FEN \"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1\"]\n[TimeControl \"180\"]\n\n1. e4 e5 2. Nf3 1-0\n","time_control":"180","end_time":1632684171,"rated":false,"tcn":"mC0K","uuid":"165bc713-1eff-11ec-9f2a-09ff3c010001","initial_setup":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq -","fen":"x","time_class":"blitz","rules":"chess","white":{"rating":2058,"result":"win","username":"Anna"},"black":{"rating":1249,"result":"resigned","username":"Bernat"}},
{"url":"https://www.chess.com/game/live/26422898996","pgn":"[Event \"Live Chess\"]\n[White \"Anna\"]\n[Black \"Bernat\"]\n[Result \"1-0\"]\n[SetUp \"1\"]\n[FEN \"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R1BQKB1R w KQkq - 0 1\"]\n\n1. e4 e5 1-0\n","end_time":1632684172,"uuid":"165bc713-1eff-11ec-9f2a-09ff3c010002","fen":"x","time_class":"blitz","rules":"chess","white":{"rating":2058,"result":"win","username":"Anna"},"black":{"rating":1249,"result":"resigned","username":"Bernat"}},
{"url":"https://www.chess.com/game/daily/6398971","pgn":"[Event \"California\"]\n[White \"Anna\"]\n[Black \"Bernat\"]\n[Result \"0-1\"]\n[TimeControl \"1/259200\"]\n\n0-1\n","time_control":"1/259200","end_time":1206039638,"rated":true,"tcn":"","uuid":"1653516c-f384-11dc-83cb-00000001000b","initial_setup":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","fen":"x","time_class":"daily","rules":"chess","white":{"rating":1189,"result":"timeout","username":"Anna"},"black":{"rating":1677,"result":"win","username":"Bernat"}},
{"url":"https://www.chess.com/game/live/1","pgn":"[Variant \"Chess960\"]\n\n1. e4 1-0\n","end_time":1,"uuid":"c","rules":"chess960","white":{"username":"Anna"},"black":{"username":"Bernat"}},
{"url":"https://www.chess.com/game/live/2","white":"not an object","black":7}
]}
"""#

private let lichessStream = #"""
{"id":"AIpLTNPB","rated":true,"variant":"standard","speed":"blitz","perf":"blitz","createdAt":1793301861151,"lastMoveAt":1793301885397,"status":"mate","source":"arena","players":{"white":{"user":{"name":"Anna","flair":"activity.basketball","id":"anna"},"rating":1830,"ratingDiff":0,"analysis":{"inaccuracy":1,"mistake":0,"blunder":1,"acpl":106,"accuracy":71.5}},"black":{"user":{"name":"Bernat","title":"FM","id":"bernat"},"rating":2442,"ratingDiff":0,"analysis":{"inaccuracy":0,"mistake":0,"blunder":0,"acpl":6,"accuracy":97}}},"winner":"black","opening":{"eco":"C20","name":"King's Pawn","ply":2},"moves":"f3 e5 g4 Qh4#","pgn":"[Event \"Rated blitz game\"]\n[Site \"https://lichess.org/game/AIpLTNPB\"]\n[White \"Anna\"]\n[Black \"Bernat\"]\n[Result \"0-1\"]\n[Variant \"Standard\"]\n[TimeControl \"300+0\"]\n[Termination \"Normal\"]\n\n1. f3 { [%eval 0.08] [%clk 0:05:00] } 1... e5 { [%eval 0.09] [%clk 0:05:00] } 2. g4 { [%eval -6.31] [%clk 0:05:00] } 2... Qh4# { [%clk 0:04:58] } 0-1\n","clocks":[30003,30003,30003,29800],"analysis":[{"eval":8},{"eval":9},{"eval":-631,"best":"g1f3","variation":"Nf3","judgment":{"name":"Blunder","comment":"Blunder. Nf3 was best."}}],"clock":{"initial":300,"increment":0,"totalTime":300},"division":{"middle":12}}

{"id":"lZmYVpIl","rated":false,"variant":"standard","speed":"classical","perf":"classical","createdAt":1791703276398,"lastMoveAt":1791703286270,"status":"outoftime","source":"ai","players":{"white":{"user":{"name":"Anna","id":"anna"},"rating":1858,"provisional":true},"black":{"aiLevel":3}},"winner":"black","moves":"e4 e5","pgn":"[Event \"Casual classical game\"]\n[Site \"https://lichess.org/game/lZmYVpIl\"]\n[White \"Anna\"]\n[Black \"lichess AI level 3\"]\n[Result \"0-1\"]\n[Variant \"Standard\"]\n[TimeControl \"1800+20\"]\n\n1. e4 e5 0-1\n","clock":{"initial":1800,"increment":20,"totalTime":2600}}
{"id":"zhVar001","variant":"crazyhouse","speed":"blitz","createdAt":1,"status":"mate","players":{"white":{"user":{"name":"Anna"}},"black":{"user":{"name":"Bernat"}}},"moves":"e4","pgn":"[Variant \"Crazyhouse\"]\n\n1. e4 1-0\n"}
{"id":"fromPos1","variant":"fromPosition","speed":"blitz","createdAt":1,"status":"mate","initialFen":"8/8/8/8/8/8/4K3/4k3 w - - 0 1","players":{"white":{"user":{"name":"Anna"}},"black":{"user":{"name":"Bernat"}}},"moves":"Kd2","pgn":"[SetUp \"1\"]\n[FEN \"8/8/8/8/8/8/4K3/4k3 w - - 0 1\"]\n\n1. Kd2 1-0\n"}
{"id":"noStart1","variant":"standard","speed":"classical","createdAt":1,"status":"noStart","players":{"white":{"user":{"name":"Anna"}},"black":{"aiLevel":1}}}
{"id":"aborted1","variant":"standard","speed":"blitz","createdAt":1,"status":"aborted","players":{"white":{"user":{"name":"Anna"}},"black":{"user":{"name":"Bernat"}}},"moves":"e4","pgn":"[White \"Anna\"]\n\n1. e4 *\n"}
{"broken json
"""#

final class ImportLinkTests: XCTestCase {
    func testChessComLinks() {
        let table: [(String, GameLink)] = [
            ("https://www.chess.com/game/live/144425637008", .chessCom(.live, id: "144425637008")),
            ("http://chess.com/game/live/123", .chessCom(.live, id: "123")),
            ("chess.com/game/daily/814505376", .chessCom(.daily, id: "814505376")),
            ("HTTPS://WWW.CHESS.COM/GAME/LIVE/123", .chessCom(.live, id: "123")),
            ("https://www.chess.com/live/game/123", .chessCom(.live, id: "123")),
            ("https://www.chess.com/daily/game/123", .chessCom(.daily, id: "123")),
            ("https://www.chess.com/analysis/game/live/123", .chessCom(.live, id: "123")),
            ("https://www.chess.com/game/live/123/review", .chessCom(.live, id: "123")),
            ("https://www.chess.com/game/live/123?tab=review", .chessCom(.live, id: "123")),
            ("https://www.chess.com/game/live/123#move", .chessCom(.live, id: "123")),
            ("https://www.chess.com/es/game/live/123", .chessCom(.live, id: "123")),
            ("https://www.chess.com/pt-br/game/daily/123", .chessCom(.daily, id: "123")),
            ("https://www.chess.com/livechess/game?id=123", .chessCom(.live, id: "123")),
            ("https://www.chess.com/echess/game?id=123", .chessCom(.daily, id: "123")),
            ("https://www.chess.com/echess/game?a=1&id=123", .chessCom(.daily, id: "123")),
            ("https://www.chess.com/game/computer/123", .chessCom(.computer, id: "123")),
            ("https://www.chess.com/game/live/\(uuidA)", .chessCom(.live, id: uuidA)),
            ("https://www.chess.com/game/daily/\(uuidDaily)", .chessCom(.daily, id: uuidDaily)),
            ("https://www.chess.com/game/live/\(uuidA.uppercased())", .chessCom(.live, id: uuidA)),
            ("Mira aquesta partida: https://www.chess.com/game/live/123 quin final", .chessCom(.live, id: "123")),
        ]
        for (text, expected) in table { XCTAssertEqual(GameLink.parse(text), expected, text) }
    }

    func testLichessLinks() {
        let table: [(String, GameLink)] = [
            ("https://lichess.org/k8OVq8Y5", .lichess(id: "k8OVq8Y5")),
            ("lichess.org/k8OVq8Y5", .lichess(id: "k8OVq8Y5")),
            ("https://www.lichess.org/k8OVq8Y5/", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/game/k8OVq8Y5", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/k8OVq8Y5abcd", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/game/k8OVq8Y5abcd", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/k8OVq8Y5/white", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/k8OVq8Y5/black/analysis", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/k8OVq8Y5#12", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/k8OVq8Y5?ref=x", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/game/export/k8OVq8Y5", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/game/export/k8OVq8Y5.pgn", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/embed/game/k8OVq8Y5", .lichess(id: "k8OVq8Y5")),
            ("https://lichess.org/embed/k8OVq8Y5", .lichess(id: "k8OVq8Y5")),
            // Ambiguous at the root: _ids answers empty for a username, and the import reports no game.
            ("https://lichess.org/thibault", .lichess(id: "thibault")),
            // A route name only counts as a route at the root.
            ("https://lichess.org/game/analysis", .lichess(id: "analysis")),
        ]
        for (text, expected) in table { XCTAssertEqual(GameLink.parse(text), expected, text) }
    }

    func testNotGameLinks() {
        let table = [
            "https://www.chess.com/game/123",
            "https://www.chess.com/game/\(uuidA)",
            "https://www.chess.com/analysis/game/pgn/abc123",
            "https://www.chess.com/a/abc123",
            "https://www.chess.com/analysis",
            "https://www.chess.com/member/anna",
            "https://www.chess.com/games/archive/anna",
            "https://www.chess.com/game/live/abc",
            "https://www.chess.com/game/live/",
            "https://www.chess.com/livechess/game",
            "https://chess.com.example.org/game/live/123",
            "https://notchess.com/game/live/123",
            "https://example.org/https://www.chess.com/game/live/123",
            "https://lichess.org/analysis",
            "https://lichess.org/bookmark",
            "https://lichess.org/features",
            "https://lichess.org/insights",
            "https://lichess.org/markdown",
            "https://lichess.org/password",
            "https://lichess.org/practice",
            "https://lichess.org/streamer",
            "https://lichess.org/timeline",
            "https://lichess.org/training",
            "https://lichess.org/g/k8OVq8Y5",
            "https://lichess.org/@/thibault",
            "https://lichess.org/study/k8OVq8Y5",
            "https://lichess.org/tournament/k8OVq8Y5",
            "https://lichess.org/k8OVq8Y",
            "https://lichess.org/k8OVq8Y5X",
            "https://lichess.org.example.org/k8OVq8Y5",
            "k8OVq8Y5",
            "",
        ]
        for text in table { XCTAssertNil(GameLink.parse(text), text) }
    }

    func testPasteRouting() {
        XCTAssertTrue(ImportedGame.looksLikePGN("[Event \"x\"]\n1. e4"))
        XCTAssertTrue(ImportedGame.looksLikePGN("\u{FEFF}[Event \"x\"]"))
        XCTAssertTrue(ImportedGame.looksLikePGN("1.e4 e5 2.Nf3"))
        XCTAssertTrue(ImportedGame.looksLikePGN("  1. e4 e5"))
        XCTAssertFalse(ImportedGame.looksLikePGN("https://lichess.org/k8OVq8Y5"))
        XCTAssertFalse(ImportedGame.looksLikePGN("https://www.chess.com/game/live/1"))
    }
}

final class ImportDecodingTests: XCTestCase {
    private func month() -> [ChessComGame] { (try? ChessComClient.decodeMonth(Data(chessComMonth.utf8))) ?? [] }

    func testBadElementIsSkippedAndBughouseStillDecodes() {
        let games = month()
        XCTAssertEqual(games.count, 7, "only the element with broken players is lost")
        XCTAssertNil(games.first { $0.rules == "bughouse" }?.pgn)
    }

    func testABodyThatIsNotAMonthIsAnError() {
        for body in [#"{"code":0}"#, "<html>", #"{"games":"none"}"#] {
            XCTAssertThrowsError(try ChessComClient.decodeMonth(Data(body.utf8)), body) { XCTAssertEqual($0 as? ImportError, .unexpectedResponse) }
        }
    }

    func testChessComFiltersToStandardChessWithMoves() {
        XCTAssertEqual(month().compactMap { $0.imported()?.url }, [
            "https://www.chess.com/game/live/144425637008",
            "https://www.chess.com/game/daily/814505376",
        ])
    }

    func testChessComFields() throws {
        let game = try XCTUnwrap(month()[0].imported())
        XCTAssertEqual(game.id, "chesscom-\(uuidA)")
        XCTAssertEqual(game.source, .chessCom)
        XCTAssertEqual(game.white, "Anna")
        XCTAssertEqual(game.blackRating, 1480)
        XCTAssertEqual(game.result, "1-0")
        XCTAssertEqual(game.termination, .checkmate)
        XCTAssertEqual(game.timeClass, .blitz)
        XCTAssertEqual(game.date, Date(timeIntervalSince1970: 1760762784))
        XCTAssertEqual(game.whiteAccuracy, 98.5)
        XCTAssertEqual(game.blackAccuracy, 41, "accuracies can be JSON ints")
        XCTAssertNil(game.lichessEvals)
        XCTAssertFalse(game.reviewed)
        XCTAssertEqual(PGN.parse(game.pgn).first?.moves.first?.clock, 180, "live clocks stay")
    }

    func testDailyClocksAreHidden() throws {
        let game = try XCTUnwrap(month()[1].imported())
        XCTAssertEqual(game.timeClass, .daily)
        XCTAssertEqual(game.termination, .timeout)
        XCTAssertFalse(game.pgn.contains("%clk"))
        let parsed = try XCTUnwrap(PGN.parse(game.pgn).first)
        XCTAssertEqual(parsed.moves.map(\.san), ["e4", "d5", "exd5"])
        XCTAssertTrue(parsed.moves.allSatisfy { $0.clock == nil && $0.comment == nil })
    }

    func testLichessStream() {
        let games = LichessClient.decode(Data(lichessStream.utf8))
        XCTAssertEqual(games.map(\.id), ["AIpLTNPB", "lZmYVpIl", "zhVar001", "fromPos1", "noStart1", "aborted1"], "blank line and broken line skipped")
        XCTAssertEqual(games.compactMap { $0.imported()?.id }, ["lichess-AIpLTNPB", "lichess-lZmYVpIl"])
    }

    func testLichessFields() throws {
        let game = try XCTUnwrap(LichessClient.decode(Data(lichessStream.utf8))[0].imported())
        XCTAssertEqual(game.url, "https://lichess.org/game/AIpLTNPB")
        XCTAssertEqual(game.result, "0-1")
        XCTAssertEqual(game.termination, .checkmate)
        XCTAssertEqual(game.timeClass, .blitz)
        XCTAssertEqual(game.whiteAccuracy, 71.5)
        XCTAssertEqual(game.blackAccuracy, 97)
        XCTAssertEqual(game.date, Date(timeIntervalSince1970: 1793301885.397))
        XCTAssertEqual(game.lichessEvals?.count, 3, "one entry shorter than the plies")
        XCTAssertEqual(game.lichessEvals?[2], PlyEval(cp: -631, mate: nil))
    }

    func testLichessAIPlayer() throws {
        let game = try XCTUnwrap(LichessClient.decode(Data(lichessStream.utf8))[1].imported())
        XCTAssertEqual(game.white, "Anna")
        XCTAssertFalse(game.black.isEmpty)
        XCTAssertNil(game.blackRating)
        XCTAssertEqual(game.termination, .timeout)
        XCTAssertEqual(game.timeClass, .classical)
        XCTAssertNil(game.lichessEvals)
    }

    func testTerminationAndTimeClassMappings() {
        XCTAssertEqual(Termination(chessComWhite: "resigned", black: "win"), .resignation)
        XCTAssertEqual(Termination(chessComWhite: "win", black: "abandoned"), .abandoned)
        XCTAssertEqual(Termination(chessComWhite: "agreed", black: "agreed"), .agreement)
        XCTAssertEqual(Termination(chessComWhite: "50move", black: "50move"), .fiftyMoves)
        XCTAssertEqual(Termination(lichessStatus: "timeout"), .abandoned)
        XCTAssertEqual(Termination(lichessStatus: "outoftime"), .timeout)
        XCTAssertEqual(TimeClass(timeControl: "60"), .bullet)
        XCTAssertEqual(TimeClass(timeControl: "180+2"), .blitz)
        XCTAssertEqual(TimeClass(timeControl: "10+0.1"), .ultraBullet)
        XCTAssertEqual(TimeClass(timeControl: "600+0"), .rapid)
        XCTAssertEqual(TimeClass(timeControl: "1800+20"), .classical)
        XCTAssertEqual(TimeClass(timeControl: "1/86400"), .daily)
        XCTAssertEqual(TimeClass(timeControl: "14 days per move"), .daily)
        XCTAssertEqual(TimeClass(timeControl: "-"), .unknown)
        XCTAssertEqual(TimeClass(timeControl: nil), .unknown)
    }

    func testPastedPGN() throws {
        let lichess = try ImportedGame(pasted: "[Site \"https://lichess.org/game/AIpLTNPB\"]\n[White \"Anna\"]\n[Black \"Bernat\"]\n[Termination \"Normal\"]\n\n1. f3 e5 2. g4 Qh4# 0-1")
        XCTAssertEqual(lichess.id, "lichess-AIpLTNPB")
        XCTAssertEqual(lichess.source, .lichess)
        XCTAssertEqual(lichess.termination, .checkmate)

        let chessCom = try ImportedGame(pasted: "[Site \"Chess.com\"]\n[TimeControl \"1/86400\"]\n[Link \"https://www.chess.com/game/daily/5\"]\n\n1. e4 {[%clk 0:00:01]} e5 *")
        XCTAssertEqual(chessCom.url, "https://www.chess.com/game/daily/5")
        XCTAssertEqual(chessCom.source, .chessCom)
        XCTAssertFalse(chessCom.pgn.contains("%clk"))

        let plain = try ImportedGame(pasted: "1.e4 e5 2.Nf3 *")
        XCTAssertTrue(plain.id.hasPrefix("pgn-"))
        XCTAssertEqual(plain.source, .pgn)
        XCTAssertEqual(plain.id, try ImportedGame(pasted: "1. e4 e5 2. Nf3 *").id, "same moves, same id")

        XCTAssertThrowsError(try ImportedGame(pasted: "[SetUp \"1\"]\n[FEN \"8/8/8/8/8/8/4K3/4k3 w - - 0 1\"]\n\n1. Kd2 *")) { XCTAssertEqual($0 as? ImportError, .notStandard) }
        XCTAssertThrowsError(try ImportedGame(pasted: "[Variant \"Crazyhouse\"]\n\n1. e4 *")) { XCTAssertEqual($0 as? ImportError, .notStandard) }
        XCTAssertThrowsError(try ImportedGame(pasted: "[White \"Anna\"]\n\n1-0")) { XCTAssertEqual($0 as? ImportError, .noGames) }
    }

    func testSplitGames() {
        let parts = ImportedGame.splitGames("\u{FEFF}[White \"A\"]\r\n[Black \"B\"]\r\n\r\n1. e4 {[%clk 0:01:00]\n[%clk 0:00:59]} e5 1-0\r\n\r\n[White \"C\"]\n\n1. d4 *\n")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(PGN.parse(parts[0]).first?.tags["White"], "A")
        XCTAssertEqual(PGN.parse(parts[0]).first?.moves.count, 2)
        XCTAssertEqual(PGN.parse(parts[1]).first?.tags["White"], "C")
    }
}

final class ImportHTTPTests: XCTestCase {
    private func response(_ status: Int, _ type: String?, url: String = "https://example.org/") -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: "HTTP/2", headerFields: type.map { ["Content-Type": $0] })!
    }

    private func error(_ check: (HTTPURLResponse) throws -> Void, _ r: HTTPURLResponse) -> ImportError? {
        do { try check(r); return nil } catch { return error as? ImportError }
    }

    func testLichessResponses() {
        let check = LichessClient.check
        XCTAssertNil(error(check, response(200, "application/x-ndjson")))
        XCTAssertEqual(error(check, response(200, "text/html; charset=utf-8", url: "https://lichess.org/signup")), .lichessLoginRequired, "the followed 303")
        XCTAssertEqual(error(check, response(200, "text/html")), .lichessLoginRequired)
        XCTAssertEqual(error(check, response(401, "application/json")), .lichessLoginRequired)
        XCTAssertEqual(error(check, response(303, nil)), .lichessLoginRequired)
        XCTAssertEqual(error(check, response(404, "text/html")), .userNotFound)
        XCTAssertEqual(error(check, response(429, "application/json")), .rateLimited)
        XCTAssertEqual(error(check, response(500, "text/html")), .unexpectedResponse)
        XCTAssertEqual(error(check, response(200, "application/x-chess-pgn")), .unexpectedResponse)
    }

    func testChessComResponses() {
        let check = ChessComClient.check
        XCTAssertNil(error(check, response(200, "application/json")))
        XCTAssertEqual(error(check, response(200, "text/html")), .chessComRefused)
        XCTAssertEqual(error(check, response(403, "text/html")), .chessComRefused, "Cloudflare challenge")
        let challenge = HTTPURLResponse(url: URL(string: "https://api.chess.com/pub")!, statusCode: 503, httpVersion: nil, headerFields: ["cf-mitigated": "challenge"])!
        XCTAssertEqual(error(check, challenge), .chessComRefused)
        XCTAssertEqual(error(check, response(404, "application/json")), .userNotFound)
        XCTAssertEqual(error(check, response(410, "application/json")), .chessComDataGone)
        XCTAssertEqual(error(check, response(429, "application/json")), .rateLimited)
        XCTAssertEqual(error(check, response(502, "text/html")), .unexpectedResponse)
    }

    func testCatalanMessages() {
        XCTAssertEqual(ImportError.userNotFound.errorDescription, "Usuari no trobat")
        XCTAssertEqual(ImportError.rateLimited.errorDescription, "Massa peticions: torna-hi d'aquí a un minut")
        XCTAssertEqual(ImportError.offline.errorDescription, "Sense connexió")
        XCTAssertEqual(ImportError.lichessLoginRequired.errorDescription, "Lichess demana iniciar sessió per a aquesta partida")
        XCTAssertEqual(GameHTTP.mapped(URLError(.notConnectedToInternet)) as? ImportError, .offline)
        XCTAssertTrue(GameHTTP.mapped(URLError(.cancelled)) is CancellationError)
    }

    /// Lichess answers these with a 404 on the games list, and a contact address could contain one by accident.
    func testUserAgentAvoidsCrawlerTokens() {
        let ua = GameHTTP.userAgent
        XCTAssertTrue(ua.hasPrefix("Scachs/"))
        XCTAssertTrue(ua.contains("contact: \(GameHTTP.contact)"))
        for token in ["okhttp", "axios", "undici", "wget", "curl", "python-requests", "aiohttp", "commons-httpclient", "python-urllib", "python-httpx", "Nessus", "HeadlessChrome", "bot", "Bot", "Spider", "openai.com", "anthropic.com", "anthropic.ai", "ChatGPT", "WhatsApp", "Mozilla"] {
            XCTAssertFalse(ua.contains(token), token)
        }
    }

    func testSessionKeepsNoCookies() {
        XCTAssertNil(GameHTTP.session.configuration.httpCookieStorage)
        XCTAssertEqual(GameHTTP.session.configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(GameHTTP.session.configuration.httpShouldSetCookies)
    }
}

// MARK: Client flows against a stubbed network

private final class StubNetwork: URLProtocol {
    struct Reply { var status = 200; var type = "application/json"; var body = ""; var redirect: String? }
    private static let lock = NSLock()
    private static var route: (URLRequest, Data?) -> Reply = { _, _ in Reply(status: 500) }
    private static var seen: [(request: URLRequest, body: Data?)] = []
    private static var inFlight = 0
    private(set) static var maxInFlight = 0

    static func reset(_ route: @escaping (URLRequest, Data?) -> Reply) {
        lock.withLock { self.route = route; seen = []; inFlight = 0; maxInFlight = 0 }
    }
    static var requests: [(request: URLRequest, body: Data?)] { lock.withLock { seen } }
    static var urls: [String] { requests.compactMap { $0.request.url?.absoluteString } }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubNetwork.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        let reply = Self.lock.withLock {
            Self.seen.append((request, body))
            Self.inFlight += 1
            Self.maxInFlight = max(Self.maxInFlight, Self.inFlight)
            return Self.route(request, body)
        }
        // Stays open long enough for a second request to overlap if anything let it through.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { [self] in
            Self.lock.withLock { Self.inFlight -= 1 }
            var headers = ["Content-Type": reply.type]
            if let redirect = reply.redirect { headers["Location"] = redirect }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/2", headerFields: headers)!
            if let redirect = reply.redirect, let next = URL(string: redirect) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: next), redirectResponse: response)
            }
            // A refused redirect ends with the 3xx itself, as it does over real HTTP.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

private func chessComGame(_ n: Int, end: Int, kind: String = "live", uuid: String? = nil, rules: String = "chess") -> String {
    #"{"url":"https://www.chess.com/game/\#(kind)/\#(n)","uuid":"\#(uuid ?? "uuid-\(n)")","pgn":"[White \"Anna\"]\n[Black \"Bernat\"]\n[Result \"1-0\"]\n\n1. e4 e5 1-0\n","end_time":\#(end),"time_class":"blitz","rules":"\#(rules)","initial_setup":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","white":{"username":"Anna","rating":1500,"result":"win"},"black":{"username":"Bernat","rating":1400,"result":"resigned"},"accuracies":{"white":90,"black":50}}"#
}

private func chessComRoute(months: [String: [String]]) -> (URLRequest, Data?) -> StubNetwork.Reply {
    { request, _ in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/games/archives") {
            let urls = months.keys.sorted().map { "\"https://api.chess.com/pub/player/anna/games/\($0)\"" }.joined(separator: ",")
            return .init(body: #"{"archives":[\#(urls)]}"#)
        }
        for (month, games) in months where path.hasSuffix("/games/\(month)") {
            return .init(body: #"{"games":[\#(games.joined(separator: ","))]}"#)
        }
        return .init(status: 404, body: #"{"code":0,"message":"not found"}"#)
    }
}

final class ImportClientTests: XCTestCase {
    private var client: ChessComClient { ChessComClient(session: StubNetwork.session) }
    private var lichess: LichessClient { LichessClient(session: StubNetwork.session) }

    func testRecentWalksNewestMonthsUntilLimitAndStaysOnPubAPI() async throws {
        StubNetwork.reset(chessComRoute(months: [
            "2026/08": [chessComGame(1, end: 100)],
            "2026/09": [chessComGame(2, end: 200), chessComGame(3, end: 300), chessComGame(9, end: 900, rules: "bughouse")],
            "2026/10": [chessComGame(4, end: 400), chessComGame(5, end: 500)],
        ]))
        let games = try await client.recentGames(username: " ANNA ", limit: 3)
        XCTAssertEqual(games.map(\.url), [5, 4, 3].map { "https://www.chess.com/game/live/\($0)" }, "newest first, across months")
        XCTAssertEqual(StubNetwork.urls, [
            "https://api.chess.com/pub/player/anna/games/archives",
            "https://api.chess.com/pub/player/anna/games/2026/10",
            "https://api.chess.com/pub/player/anna/games/2026/09",
        ], "stops once it has enough, and asks for lowercase names")
        for (request, _) in StubNetwork.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), GameHTTP.userAgent)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
    }

    func testRequestsAreSerialEvenWhenCalledConcurrently() async throws {
        StubNetwork.reset(chessComRoute(months: ["2026/10": [chessComGame(1, end: 1)]]))
        let client = client
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 { group.addTask { _ = try await client.archiveMonths("anna") } }
            try await group.waitForAll()
        }
        XCTAssertEqual(StubNetwork.requests.count, 6)
        XCTAssertEqual(StubNetwork.maxInFlight, 1)
    }

    func testLiveLinkNeverMatchesDailyGameWithSameID() async throws {
        StubNetwork.reset(chessComRoute(months: ["2026/10": [chessComGame(814505376, end: 1, kind: "daily")]]))
        do {
            _ = try await client.findGame(.live, id: "814505376", username: "anna")
            XCTFail("matched a daily game for a live link")
        } catch { XCTAssertEqual(error as? ImportError, .gameNotFound) }
        let daily = try await client.findGame(.daily, id: "814505376", username: "anna")
        XCTAssertEqual(daily.url, "https://www.chess.com/game/daily/814505376")
    }

    func testLinkMatchesByUUIDAndReportsVariants() async throws {
        StubNetwork.reset(chessComRoute(months: [
            "2026/09": [chessComGame(7, end: 1, uuid: uuidA)],
            "2026/10": [chessComGame(8, end: 2, rules: "chess960")],
        ]))
        let byUUID = try await client.findGame(.daily, id: uuidA, username: "anna")
        XCTAssertEqual(byUUID.url, "https://www.chess.com/game/live/7", "a uuid is unique whichever type the link names")
        do {
            _ = try await client.findGame(.live, id: "8", username: "anna")
            XCTFail("imported a Chess960 game")
        } catch { XCTAssertEqual(error as? ImportError, .notStandard) }
    }

    func testChessComNeverFollowsARedirectOffItsHost() async {
        StubNetwork.reset { request, _ in
            request.url?.host == "api.chess.com" ? .init(status: 301, redirect: "https://www.chess.com/callback/live/game/1") : .init(body: "{}")
        }
        do {
            _ = try await client.archiveMonths("anna")
            XCTFail("expected an error")
        } catch { XCTAssertEqual(error as? ImportError, .unexpectedResponse) }
        XCTAssertEqual(StubNetwork.urls, ["https://api.chess.com/pub/player/anna/games/archives"])
    }

    func testBadUsernameNeverReachesTheNetwork() async {
        StubNetwork.reset { _, _ in .init() }
        for name in ["", "   ", "../../callback", "a b", "anna?x=1"] {
            do {
                _ = try await client.recentGames(username: name)
                XCTFail(name)
            } catch { XCTAssertEqual(error as? ImportError, .userNotFound, name) }
        }
        XCTAssertTrue(StubNetwork.urls.isEmpty)
    }

    func testLichessList() async throws {
        StubNetwork.reset { _, _ in .init(type: "application/x-ndjson", body: lichessStream) }
        let games = try await lichess.recentGames(username: "Anna", limit: 5)
        XCTAssertEqual(games.count, 2)
        let request = try XCTUnwrap(StubNetwork.requests.first?.request)
        let parts = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "lichess.org")
        XCTAssertEqual(parts.path, "/api/games/user/Anna")
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["max"], "5")
        for flag in ["pgnInJson", "clocks", "evals", "accuracy", "opening", "division"] { XCTAssertEqual(query[flag], "true", flag) }
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/x-ndjson")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), GameHTTP.userAgent)
    }

    func testLichessSingleGame() async throws {
        StubNetwork.reset { _, _ in .init(type: "application/x-ndjson", body: lichessStream.components(separatedBy: "\n")[0]) }
        let game = try await lichess.game(id: "AIpLTNPB")
        XCTAssertEqual(game.id, "lichess-AIpLTNPB")
        let sent = try XCTUnwrap(StubNetwork.requests.first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.path, "/api/games/export/_ids")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Content-Type"), "text/plain")
        XCTAssertEqual(sent.body.map { String(decoding: $0, as: UTF8.self) }, "AIpLTNPB")
    }

    func testLichessEmptyAnswerAndLoginWall() async {
        StubNetwork.reset { _, _ in .init(type: "application/x-ndjson", body: "") }
        do { _ = try await lichess.game(id: "thibault"); XCTFail() } catch { XCTAssertEqual(error as? ImportError, .gameNotFound) }

        StubNetwork.reset { _, _ in .init(type: "text/html; charset=utf-8", body: "<html>sign up</html>") }
        do { _ = try await lichess.game(id: "0E6djlbw"); XCTFail() } catch { XCTAssertEqual(error as? ImportError, .lichessLoginRequired) }

        StubNetwork.reset { _, _ in .init(status: 401, body: #"{"error":"Login required"}"#) }
        do { _ = try await lichess.game(id: "0E6djlbw"); XCTFail() } catch { XCTAssertEqual(error as? ImportError, .lichessLoginRequired) }
    }
}

// MARK: Library

@MainActor
final class GameLibraryTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private let suite = "ImportTests.\(UUID().uuidString)"

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    private func library() -> GameLibrary {
        GameLibrary(folder: folder, defaults: defaults, chessCom: ChessComClient(session: StubNetwork.session), lichess: LichessClient(session: StubNetwork.session))
    }

    private func combinedRoute(months: [String: [String]], stream: String) -> (URLRequest, Data?) -> StubNetwork.Reply {
        let chess = chessComRoute(months: months)
        return { request, body in
            request.url?.host == "lichess.org" ? .init(type: "application/x-ndjson", body: stream) : chess(request, body)
        }
    }

    func testUsernamesPersistInDefaultsUnderTheContractKeys() {
        let lib = library()
        lib.chessComUsername = "Anna"
        lib.lichessUsername = "bernat"
        XCTAssertEqual(defaults.string(forKey: "chessComUsername"), "Anna")
        XCTAssertEqual(defaults.string(forKey: "lichessUsername"), "bernat")
        XCTAssertEqual(library().chessComUsername, "Anna")
    }

    func testRefreshOnlyAsksForSetUsernamesAndDeduplicates() async {
        let lib = library()
        StubNetwork.reset(combinedRoute(months: [:], stream: lichessStream))
        await lib.refresh()
        XCTAssertTrue(StubNetwork.urls.isEmpty)

        lib.chessComUsername = "anna"
        lib.lichessUsername = "ANNA"
        StubNetwork.reset(combinedRoute(months: ["2026/10": [chessComGame(1, end: 2_000_000_000), chessComGame(2, end: 1_000)]], stream: lichessStream))
        await lib.refresh()
        await lib.refresh()
        XCTAssertEqual(lib.games.count, 4)
        XCTAssertEqual(Set(lib.games.map(\.id)).count, 4)
        XCTAssertEqual(lib.games.first?.url, "https://www.chess.com/game/live/1", "newest first")
        XCTAssertEqual(lib.games.first?.mySide, .white, "case-insensitive")
        XCTAssertEqual(lib.games.first { $0.id == "lichess-AIpLTNPB" }?.mySide, .white)
        XCTAssertTrue(lib.refreshErrors.isEmpty)
    }

    func testLoadingOlderAsksForEarlierGamesAndStopsWhenThereAreNone() async {
        let lib = library()
        lib.chessComUsername = "anna"
        lib.lichessUsername = "anna"
        StubNetwork.reset(combinedRoute(months: ["2026/10": [chessComGame(1, end: 1_792_000_000), chessComGame(2, end: 1_790_000_000)], "2026/09": [chessComGame(3, end: 1_788_000_000)]], stream: lichessStream))
        await lib.refresh()
        let before = lib.games.count
        XCTAssertGreaterThan(before, 0)
        StubNetwork.reset(combinedRoute(months: ["2026/10": [chessComGame(1, end: 1_792_000_000)], "2026/09": []], stream: lichessStream))
        await lib.loadOlder()
        XCTAssertEqual(lib.games.count, before, "the same games again are nothing new")
        XCTAssertTrue(lib.reachedOldest)
        XCTAssertTrue(StubNetwork.urls.contains { $0.contains("until=") }, "Lichess is asked for earlier ones")
    }

    func testStaleRefreshAsksOnlyAfterFiveMinutesOrANewName() async {
        let lib = library()
        StubNetwork.reset(combinedRoute(months: [:], stream: lichessStream))
        await lib.refreshIfStale()
        XCTAssertTrue(StubNetwork.urls.isEmpty, "no accounts, nothing to ask")

        lib.lichessUsername = "anna"
        await lib.refreshIfStale()
        let asked = StubNetwork.urls.count
        XCTAssertGreaterThan(asked, 0)
        XCTAssertTrue(lib.isLinked(.lichess))
        XCTAssertFalse(lib.isLinked(.chessCom))
        await lib.refreshIfStale(now: .now + 200)
        XCTAssertEqual(StubNetwork.urls.count, asked)
        await lib.refreshIfStale(now: .now + 301)
        XCTAssertEqual(StubNetwork.urls.count, asked * 2)
        lib.lichessUsername = "bea"
        XCTAssertFalse(lib.isLinked(.lichess), "the games are not this name's own")
        await lib.refreshIfStale()
        XCTAssertEqual(StubNetwork.urls.count, asked * 3)
    }

    func testOneSiteFailingKeepsTheOther() async {
        let lib = library()
        lib.chessComUsername = "anna"
        lib.lichessUsername = "anna"
        StubNetwork.reset { request, _ in
            request.url?.host == "lichess.org" ? .init(status: 429) : .init(status: 404, body: "{}")
        }
        await lib.refresh()
        XCTAssertEqual(lib.refreshErrors[.chessCom], .userNotFound)
        XCTAssertEqual(lib.refreshErrors[.lichess], .rateLimited)
        StubNetwork.reset { request, _ in
            request.url?.host == "lichess.org" ? .init(type: "application/x-ndjson", body: lichessStream) : .init(status: 403, type: "text/html")
        }
        await lib.refresh()
        XCTAssertEqual(lib.refreshErrors[.chessCom], .chessComRefused)
        XCTAssertNil(lib.refreshErrors[.lichess])
        XCTAssertEqual(lib.games.count, 2)
    }

    func testPastedThenFetchedKeepsIDAndGainsSiteData() async throws {
        let lib = library()
        let pasted = try await lib.add(pgn: "[Site \"Chess.com\"]\n[Link \"https://www.chess.com/game/live/1\"]\n[White \"Anna\"]\n[Black \"Bernat\"]\n\n1. e4 e5 1-0")
        XCTAssertEqual(pasted.count, 1)
        let id = pasted[0].id
        XCTAssertNil(pasted[0].whiteAccuracy)

        lib.chessComUsername = "anna"
        XCTAssertEqual(lib.games.first?.mySide, .white, "changing the username re-derives sides")
        StubNetwork.reset(chessComRoute(months: ["2026/10": [chessComGame(1, end: 5)]]))
        await lib.refresh()
        XCTAssertEqual(lib.games.count, 1)
        XCTAssertEqual(lib.games.first?.id, id, "the review hangs off the first id")
        XCTAssertEqual(lib.games.first?.whiteAccuracy, 90)

        // Pasting again changes nothing.
        try await lib.add(pgn: "[Link \"https://www.chess.com/game/live/1\"]\n\n1. e4 e5 1-0")
        XCTAssertEqual(lib.games.first?.whiteAccuracy, 90)
    }

    func testDeletedGameStaysDeletedUntilAddedByHand() async throws {
        let lib = library()
        lib.chessComUsername = "anna"
        StubNetwork.reset(chessComRoute(months: ["2026/10": [chessComGame(1, end: 5)]]))
        await lib.refresh()
        lib.delete(try XCTUnwrap(lib.games.first))
        XCTAssertTrue(lib.games.isEmpty)
        await lib.refresh()
        XCTAssertTrue(lib.games.isEmpty)
        XCTAssertTrue(library().games.isEmpty, "the tombstone survives a relaunch")

        try await lib.add(link: "https://www.chess.com/game/live/1")
        XCTAssertEqual(lib.games.count, 1)
        await lib.refresh()
        XCTAssertEqual(lib.games.count, 1)
    }

    func testChessComLinkWithoutUsernameAsksForOne() async {
        let lib = library()
        StubNetwork.reset { _, _ in .init() }
        do {
            try await lib.add(link: "https://www.chess.com/game/live/1")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ImportError, .chessComUsernameNeeded)
            XCTAssertEqual((error as? ImportError)?.offersPGNPaste, true)
        }
        do {
            try await lib.add(link: "https://www.chess.com/game/computer/1")
            XCTFail()
        } catch { XCTAssertEqual(error as? ImportError, .computerGame) }
        XCTAssertTrue(StubNetwork.urls.isEmpty)
    }

    func testPasteRoutesAndMultiGame() async throws {
        let lib = library()
        StubNetwork.reset { _, _ in .init(type: "application/x-ndjson", body: lichessStream.components(separatedBy: "\n")[0]) }
        let fromLink = try await lib.add(pasted: "https://lichess.org/game/AIpLTNPB")
        XCTAssertEqual(fromLink.first?.id, "lichess-AIpLTNPB")
        XCTAssertEqual(fromLink.first?.lichessEvals?.count, 3)

        StubNetwork.reset { _, _ in .init(status: 500) }
        try await lib.add(pasted: "https://lichess.org/AIpLTNPB")
        XCTAssertTrue(StubNetwork.urls.isEmpty, "a known game does not need the network")

        let added = try await lib.add(pasted: "[White \"A\"]\n\n1. e4 *\n\n[Variant \"Crazyhouse\"]\n\n1. e4 *\n\n[White \"B\"]\n\n1. d4 *\n")
        XCTAssertEqual(added.map(\.white), ["A", "B"], "the variant is skipped")
        XCTAssertEqual(lib.games.count, 3)

        do { try await lib.add(pgn: "[Variant \"Crazyhouse\"]\n\n1. e4 *"); XCTFail() } catch { XCTAssertEqual(error as? ImportError, .notStandard) }
        do { try await lib.add(pgn: "not chess"); XCTFail() } catch { XCTAssertEqual(error as? ImportError, .noGames) }
    }

    func testLibrarySurvivesRelaunchAndCorruption() async throws {
        let lib = library()
        try await lib.add(pgn: "[White \"A\"]\n\n1. e4 *")
        XCTAssertEqual(library().games.map(\.white), ["A"])

        let file = folder.appending(path: "library.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["games"] = (json["games"] as? [Any] ?? []) + [["id": "broken"]]
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertEqual(library().games.map(\.white), ["A"], "one bad entry loses only that entry")

        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(library().games.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path), "kept aside, not overwritten")
    }
}

// MARK: Review evidence

private func reviewed(_ uci: String, _ side: Side, _ cls: MoveClass?, best: [String] = [], refutation: [String] = [], ply: Int) -> GameReview.ReviewedMove {
    GameReview.ReviewedMove(ply: ply, side: side, san: uci, uci: uci, moveClass: cls, evalBefore: nil, evalAfter: nil, bestMove: nil, bestSAN: nil,
                            bestLine: best.compactMap(Move.init(uci:)), refutation: refutation.compactMap(Move.init(uci:)),
                            secondBestGap: nil, epLost: 0, clock: nil, coach: nil, isKey: false, wasDeepSearched: false)
}

private func review(fen: String, _ moves: [GameReview.ReviewedMove]) -> GameReview {
    let player = GameReview.PlayerReview(accuracy: nil, counts: [:], gameRating: nil, averageCentipawnLoss: nil)
    let engine = GameReview.EngineInfo(name: "test", firstPassNodes: 0, deepPassNodes: 0, searchedPositions: 0, deepPlies: 0, averageDepth: nil, maxDepth: nil)
    return GameReview(id: "t", startFEN: fen, moves: moves, white: player, black: player, phases: [], opening: nil, engine: engine, isComplete: true)
}

private let backRank = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"
private let knightFork = "r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1"

/// White misses Rd8#, Black then walks into it, White plays a mere mistake and Black a good move.
private let backRankReview = review(fen: backRank, [
    reviewed("g1f1", .white, .miss, best: ["d1d8"], ply: 0),
    reviewed("g8h8", .black, .blunder, refutation: ["d1d8"], ply: 1),
    reviewed("f1g1", .white, .mistake, best: ["d1d8"], ply: 2),
    reviewed("h8g8", .black, .good, best: ["h8g8"], ply: 3),
])

final class ReviewEvidenceTests: XCTestCase {
    func testOnlyMyMissesAndBlundersCount() {
        XCTAssertEqual(GameLibrary.evidence(in: backRankReview, side: .white), ["backRankMate": 1], "the mistake does not count")
        XCTAssertEqual(GameLibrary.evidence(in: backRankReview, side: .black), ["backRankMate": 1])
        XCTAssertEqual(GameLibrary.evidence(in: backRankReview, side: nil), [:])
    }

    func testMotifTags() {
        func tag(_ fen: String, _ line: [String]) -> String? {
            GameLibrary.motifTag(on: Position(fen: fen)!, line: line.compactMap(Move.init(uci:)))
        }
        XCTAssertEqual(tag(knightFork, ["d5c7", "e8d7", "c7a8"]), "fork")
        XCTAssertEqual(tag(backRank, ["d1d8"]), "backRankMate")
        XCTAssertEqual(tag("7k/8/5K2/6Q1/8/8/8/8 w - - 0 1", ["g5g7"]), "mate", "mate, but the king has no men in front of it")
        XCTAssertEqual(tag("6k1/8/8/8/3q4/8/5PPP/3R2K1 w - - 0 1", ["d1d4"]), "hangingPiece")
        XCTAssertNil(tag(backRank, ["g1f1"]))
        XCTAssertNil(tag(backRank, []))
        XCTAssertNil(tag(backRank, ["a1a2"]), "an illegal line says nothing")
    }

    func testBlunderFallsBackToTheLineItGaveUp() {
        let r = review(fen: knightFork, [reviewed("e1e2", .white, .blunder, best: ["d5c7", "e8d7", "c7a8"], ply: 0)])
        XCTAssertEqual(GameLibrary.evidence(in: r, side: .white), ["fork": 1])
    }

    func testCorruptStartOrIllegalMoveStopsQuietly() {
        XCTAssertEqual(GameLibrary.evidence(in: review(fen: "garbage", [reviewed("e2e4", .white, .miss, ply: 0)]), side: .white), [:])
        let r = review(fen: backRank, [reviewed("a1a2", .white, .miss, best: ["d1d8"], ply: 0)])
        XCTAssertEqual(GameLibrary.evidence(in: r, side: .white), [:])
    }
}

@MainActor
final class GameLibraryReviewTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private let suite = "ImportTests.\(UUID().uuidString)"

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    private func library() -> GameLibrary { GameLibrary(folder: folder, defaults: defaults) }

    private func twoGames(_ lib: GameLibrary) async throws -> (mine: ImportedGame, other: ImportedGame) {
        let added = try await lib.add(pgn: """
        [White "Anna"]
        [Black "Bernat"]

        1. e4 e5 *

        [White "Carla"]
        [Black "Dani"]

        1. d4 d5 *
        """)
        return (added[0], added[1])
    }

    func testEvidenceComesFromSavedReviewsOfMyGames() async throws {
        let lib = library()
        lib.chessComUsername = "anna"
        let (mine, other) = try await twoGames(lib)
        XCTAssertEqual(lib.missedTacticEvidence, [:])

        try lib.save(backRankReview, for: mine.id)
        try lib.save(backRankReview, for: other.id)
        XCTAssertEqual(lib.games.first { $0.id == mine.id }?.reviewed, true)
        XCTAssertEqual(lib.review(for: mine.id)?.moves.count, 4)
        XCTAssertEqual(lib.missedTacticEvidence, ["backRankMate": 1], "the game with neither username adds nothing")

        XCTAssertEqual(library().missedTacticEvidence, ["backRankMate": 1], "survives a relaunch")
        XCTAssertEqual(library().games.first { $0.id == mine.id }?.reviewed, true)

        lib.lichessUsername = "dani"
        XCTAssertEqual(lib.missedTacticEvidence, ["backRankMate": 2], "a new username re-attributes")

        lib.delete(try XCTUnwrap(lib.games.first { $0.id == mine.id }))
        XCTAssertEqual(lib.missedTacticEvidence, ["backRankMate": 1])
        XCTAssertNil(lib.review(for: mine.id))
    }

    func testCorruptReviewCountsAsNoReview() async throws {
        let lib = library()
        lib.chessComUsername = "anna"
        let (mine, _) = try await twoGames(lib)
        try lib.save(backRankReview, for: mine.id)

        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder.appending(path: "Reviews"), includingPropertiesForKeys: nil).first)
        try Data("not json".utf8).write(to: file)

        let relaunched = library()
        XCTAssertEqual(relaunched.missedTacticEvidence, [:])
        XCTAssertNil(relaunched.review(for: mine.id))
        XCTAssertEqual(relaunched.games.first { $0.id == mine.id }?.reviewed, false)
        try relaunched.save(backRankReview, for: mine.id)
        XCTAssertNotNil(relaunched.review(for: mine.id), "and it can be analysed again")
    }

    func testRemoteIDsCannotEscapeTheReviewsFolder() throws {
        let lib = library()
        try lib.save(backRankReview, for: "../../escape")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().appending(path: "escape.json").path))
        XCTAssertNotNil(lib.review(for: "../../escape"))
    }
}
