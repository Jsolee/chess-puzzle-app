// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import XCTest
@testable import Scachs

final class EngineTests: XCTestCase {
    private static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    private static let kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"

    private func move(_ uci: String) -> Move { Move(uci: uci)! }

    private func analyse(
        _ fen: String, moves: [String] = [], multiPV: Int = 1, nodes: Int? = 100_000, searchMoves: [String]? = nil
    ) async throws -> [EngineLine] {
        try await Engine.shared.analyse(
            startFEN: fen, moves: moves.map(move), multiPV: multiPV, nodes: nodes, movetimeMs: nil,
            searchMoves: searchMoves?.map(move), onUpdate: nil
        )
    }

    func testMateInOne() async throws {
        let line = try await analyse("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1").first
        XCTAssertEqual(line?.score, .mate(1))
        XCTAssertEqual(line?.pv.first, move("a1a8"))
    }

    func testBeingMatedIsNegativeAndInMoves() async throws {
        let line = try await analyse("7k/8/5K2/6Q1/8/8/8/8 b - - 0 1").first
        XCTAssertEqual(line?.score, .mate(-1))
    }

    func testSearchMovesAnalysesOnlyThatMove() async throws {
        let lines = try await analyse(Self.startFEN, searchMoves: ["a2a3"])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.pv.first, move("a2a3"))
    }

    func testIllegalSearchMoveThrowsInsteadOfWidening() async {
        await assertThrows(.illegalSearchMove) { try await self.analyse(Self.startFEN, searchMoves: ["a2a5"]) }
    }

    func testMultiPVReturnsTwoLines() async throws {
        let lines = try await analyse(Self.startFEN, multiPV: 2)
        XCTAssertEqual(lines.map(\.multipv), [1, 2])
        XCTAssertNotEqual(lines[0].pv.first, lines[1].pv.first)
    }

    // The third Nf6-g8 is a draw only if the engine really saw the moves before the root.
    func testRepetitionThroughMoveList() async throws {
        let moves = ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1"]
        let line = try await analyse(Self.startFEN, moves: moves, searchMoves: ["f6g8"]).first
        XCTAssertEqual(line?.score, .cp(0))
    }

    func testRootWithoutMoves() async throws {
        let mated = try await analyse("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3").first
        XCTAssertEqual(mated?.score, .mate(0))
        XCTAssertEqual(mated?.pv, [])
        let stalemated = try await analyse("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").first
        XCTAssertEqual(stalemated?.score, .cp(0))
    }

    func testRejectedInputLeavesTheEngineUsable() async throws {
        for fen in ["", "garbage", "8/8/8/8/8/8/8/8 w - - 0 1", "4k3/4R3/8/8/8/8/8/4K3 w - - 0 1"] {
            do {
                _ = try await analyse(fen)
                XCTFail("accepted \(fen)")
            } catch {
                guard case EngineError.invalidPosition = error else { return XCTFail("\(error)") }
            }
        }
        do {
            _ = try await analyse(Self.startFEN, moves: ["e2e5"])
            XCTFail("accepted an illegal move")
        } catch {
            guard case EngineError.invalidPosition = error else { return XCTFail("\(error)") }
        }
        let lines = try await analyse(Self.startFEN, moves: ["e2e4"], nodes: 20_000)
        XCTAssertFalse(lines.isEmpty)
    }

    /// An unlimited search that is known to be running, since a `stop` before that does nothing.
    private func runningSearch() async throws -> Task<[EngineLine], Error> {
        let updates = LockedDates()
        let search = Task {
            try await Engine.shared.analyse(
                startFEN: Self.kiwipete, moves: [], multiPV: 1, nodes: nil, movetimeMs: nil, searchMoves: nil
            ) { _ in updates.append(Date()) }
        }
        while updates.values.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        return search
    }

    func testStopReturnsPromptly() async throws {
        let search = try await runningSearch()
        let stopped = Date()
        Engine.shared.stop()
        let lines = try await search.value
        XCTAssertLessThan(Date().timeIntervalSince(stopped), 1)
        XCTAssertFalse(lines.isEmpty)
    }

    func testCancellingTheTaskStopsTheSearch() async throws {
        let search = try await runningSearch()
        let cancelled = Date()
        search.cancel()
        do {
            _ = try await search.value
            XCTFail("did not throw")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancelled), 1)
    }

    func testOnUpdateIsThrottled() async throws {
        let times = LockedDates()
        _ = try await Engine.shared.analyse(
            startFEN: Self.kiwipete, moves: [], multiPV: 1, nodes: nil, movetimeMs: 1500, searchMoves: nil
        ) { _ in times.append(Date()) }
        let gaps = zip(times.values, times.values.dropFirst()).map { $1.timeIntervalSince($0) }
        XCTAssertFalse(times.values.isEmpty)
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 1, 0.09)
    }

    // onIter stays silent until the main thread passes 10M nodes, then aborts if it was left unset.
    func testSurvivesPastTenMillionNodes() async throws {
        let engine = Engine(threads: 1, hashMB: 16)
        let lines = try await engine.analyse(
            startFEN: Self.startFEN, moves: [], multiPV: 1, nodes: 10_500_000, movetimeMs: nil, searchMoves: nil, onUpdate: nil
        )
        XCTAssertGreaterThanOrEqual(lines.first?.nodes ?? 0, 10_000_000)
        await engine.shutdown()
    }

    func testMemoryWarningFreesTheEngineAndItReloads() async throws {
        let engine = Engine(threads: 1, hashMB: 16)
        _ = try await engine.analyse(startFEN: Self.startFEN, moves: [], multiPV: 1, nodes: 1000, movetimeMs: nil, searchMoves: nil, onUpdate: nil)
        var loaded = await engine.isLoaded
        XCTAssertTrue(loaded)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        for _ in 0..<100 where loaded {
            try await Task.sleep(for: .milliseconds(50))
            loaded = await engine.isLoaded
        }
        XCTAssertFalse(loaded)
        let lines = try await engine.analyse(startFEN: Self.startFEN, moves: [], multiPV: 1, nodes: 1000, movetimeMs: nil, searchMoves: nil, onUpdate: nil)
        XCTAssertFalse(lines.isEmpty)
        await engine.shutdown()
    }

    func testClearHashKeepsTheEngine() async throws {
        _ = try await analyse(Self.startFEN, nodes: 1000)
        await Engine.shared.clearHash()
        let loaded = await Engine.shared.isLoaded
        XCTAssertTrue(loaded)
    }

    func testBudget() {
        XCTAssertEqual(Engine.budget(1_000_000, thermal: .nominal, lowPower: false), 1_000_000)
        XCTAssertEqual(Engine.budget(1_000_000, thermal: .fair, lowPower: false), 750_000)
        XCTAssertEqual(Engine.budget(1_000_000, thermal: .serious, lowPower: true), 200_000)
        XCTAssertEqual(Engine.budget(1_000_000, thermal: .critical, lowPower: false), 200_000)
        XCTAssertEqual(Engine.budget(1, thermal: .critical, lowPower: true), 1)
    }

    private func assertThrows(
        _ expected: EngineError, _ body: @escaping () async throws -> [EngineLine],
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("did not throw", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? EngineError, expected, file: file, line: line)
        }
    }
}

private final class LockedDates: @unchecked Sendable {
    private let lock = NSLock()
    private var dates: [Date] = []

    func append(_ date: Date) { lock.withLock { dates.append(date) } }
    var values: [Date] { lock.withLock { dates } }
}
