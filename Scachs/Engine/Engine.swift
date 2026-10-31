// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Side to move's view. `.mate(3)` it mates in 3 moves, `.mate(-2)` it is mated in 2, `.mate(0)` it is checkmated now.
enum Score: Hashable, Codable, Sendable {
    case cp(Int), mate(Int)

    fileprivate init(kind: Int32, value: Int32) {
        if kind == Int32(SF_SCORE_MATE) {
            self = .mate(Int(value > 0 ? (value + 1) / 2 : value / 2))
        } else {
            self = .cp(Int(value))
        }
    }
}

struct WDL: Hashable, Sendable {
    var win: Int, draw: Int, loss: Int   // per mille
}

struct EngineLine: Hashable, Sendable {
    var multipv: Int
    var depth: Int
    var score: Score
    var pv: [Move]
    var nodes: Int
    var wdl: WDL? = nil
}

enum EngineError: Error, Equatable {
    case netMissing, netCorrupt, lowMemory
    case invalidPosition(String)
    case illegalSearchMove
}

actor Engine {
    static let shared = Engine()

    // Every bridge call blocks, so the actor runs on its own queue instead of the cooperative pool.
    private let queue = DispatchSerialQueue(label: "com.jsolee.scachs.engine", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let netDirectory: URL?
    private let threads: Int
    private let hashMB: Int
    private var handle: OpaquePointer?
    private var netVerified = false

    // While a search runs the actor is busy waiting for it, so `stop` can't go through isolation.
    private let running = OSAllocatedUnfairLock<SearchRun?>(initialState: nil)

    /// `netDirectory` defaults to the app bundle, `threads` and `hashMB` to what suits the device.
    init(netDirectory: URL? = nil, threads: Int? = nil, hashMB: Int? = nil) {
        self.netDirectory = netDirectory
        self.threads = threads ?? (ProcessInfo.processInfo.activeProcessorCount >= 8 ? 4 : 2)
        self.hashMB = hashMB ?? (ProcessInfo.processInfo.physicalMemory >= 7 << 30 ? 128 : 64)
        #if canImport(UIKit)
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.shutdown() }
        }
        #endif
    }

    /// Searches the position after `moves`, so repetitions and the 50-move rule are seen.
    ///
    /// Calls run one at a time, in order. With neither `nodes` nor `movetimeMs` it searches until
    /// stopped, 5 minutes at most so a missed stop can't cook the phone. Returns the final lines in
    /// multipv order; after `stop` these are whatever was reached, or empty if it came before depth 2.
    /// A position with no legal moves gives one line with an empty pv, `.mate(0)` or `.cp(0)`. Task
    /// cancellation stops the search and throws `CancellationError`. `onUpdate` gets the latest lines
    /// at most 10 times a second, on the engine's queue: hop off it for anything slow.
    func analyse(
        startFEN: String,
        moves: [Move],
        multiPV: Int,
        nodes: Int?,
        movetimeMs: Int?,
        searchMoves: [Move]?,
        onUpdate: (@Sendable ([EngineLine]) -> Void)?
    ) async throws -> [EngineLine] {
        try Task.checkCancellation()
        let engine = try loadedEngine()
        let run = SearchRun()
        running.withLock { $0 = run }
        defer { running.withLock { $0 = nil } }

        let lines = try await withTaskCancellationHandler {
            let started = sf_go(
                engine, startFEN, moves.uciList, searchMoves?.uciList,
                Int32(clamping: min(max(multiPV, 1), 256)),
                nodes.map { UInt64(max($0, 1)) } ?? 0,
                movetimeMs.map { Int64(max($0, 1)) } ?? (nodes == nil ? 300_000 : 0),
                Unmanaged.passUnretained(run).toOpaque(), onLine, onDone
            )
            guard started != 0 else {
                throw EngineError.invalidPosition(String(cString: sf_error(engine)))
            }
            return wait(for: run, on: engine, onUpdate: onUpdate)
        } onCancel: {
            run.stop()
        }
        try Task.checkCancellation()

        // Stockfish quietly widens to all moves when none of searchmoves is legal.
        if let searchMoves, !searchMoves.isEmpty,
           lines.contains(where: { line in line.pv.first.map { !searchMoves.contains($0) } ?? false }) {
            throw EngineError.illegalSearchMove
        }
        return lines
    }

    /// Stops the running search, if any. A search that hasn't started yet is not touched, not even
    /// one that is about to, so use Task cancellation when the order isn't certain.
    nonisolated func stop() {
        running.withLock { $0 }?.stop()
    }

    /// Frees the engine, about 225 MiB. The next `analyse` loads it again.
    nonisolated func shutdown() async {
        // A search that gets in ahead of destroy would hold up the actor, so keep stopping until destroy has run.
        let stopper = Task {
            while !Task.isCancelled {
                stop()
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        await destroy()
        stopper.cancel()
    }

    /// Forgets the hash and histories, for between games. Waits for a running search.
    func clearHash() {
        if let handle { sf_clear(handle) }
    }

    var isLoaded: Bool { handle != nil }

    private func wait(
        for run: SearchRun, on engine: OpaquePointer, onUpdate: (@Sendable ([EngineLine]) -> Void)?
    ) -> [EngineLine] {
        run.started(on: engine)
        while run.finished.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            if let onUpdate, let latest = run.takeUnseen() { onUpdate(latest) }
        }
        sf_wait(engine)
        run.ended()
        return run.lines
    }

    private func destroy() {
        if let handle { sf_destroy(handle) }
        handle = nil
    }

    private func loadedEngine() throws -> OpaquePointer {
        if let handle { return handle }
        let name = String(cString: sf_net_name())
        guard let directory = netDirectory
                ?? Bundle.main.url(forResource: name, withExtension: nil)?.deletingLastPathComponent()
        else { throw EngineError.netMissing }
        if !netVerified { try verifyNet(directory.appendingPathComponent(name), name: name) }
        try checkMemory()
        handle = sf_create(directory.path, Int32(clamping: threads), Int32(clamping: hashMB))
        return handle!
    }

    // The engine ends the process on a missing or corrupt net, so that has to be caught here.
    private func verifyNet(_ url: URL, name: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw EngineError.netMissing }
        let digest = SHA256.hash(data: try Data(contentsOf: url, options: .alwaysMapped))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard name == "nn-\(hex.prefix(12)).nnue" else { throw EngineError.netCorrupt }
        netVerified = true
    }

    // The engine also ends the process when an allocation fails. Loading briefly holds the 110 MiB
    // net twice, before the hash exists. Measured peak: 237 MiB for 2 threads and 64 MiB of hash.
    private func checkMemory() throws {
        #if os(iOS) && !targetEnvironment(simulator)
        let needed = (110 + max(110, hashMB) + threads * 25 + 64) << 20
        if os_proc_available_memory() < needed { throw EngineError.lowMemory }
        #endif
    }

    // MARK: Budgets

    /// Node budget scaled down for the device's heat and Low Power Mode.
    static func budget(_ nodes: Int) -> Int {
        budget(nodes, thermal: ProcessInfo.processInfo.thermalState,
               lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    static func budget(_ nodes: Int, thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Int {
        let scale: Double
        switch thermal {
        case .nominal: scale = 1
        case .fair: scale = 0.75
        case .serious: scale = 0.4
        case .critical: scale = 0.2
        @unknown default: scale = 0.4
        }
        // Never 0: to the engine that means no limit.
        return max(1, Int(Double(nodes) * scale * (lowPower ? 0.5 : 1)))
    }
}

private extension Array where Element == Move {
    var uciList: String { map(\.uci).joined(separator: " ") }
}

private let onLine: sf_line_cb = { context, line in
    guard let context, let line else { return }
    Unmanaged<SearchRun>.fromOpaque(context).takeUnretainedValue().record(line.pointee)
}

private let onDone: sf_done_cb = { context, _ in
    guard let context else { return }
    Unmanaged<SearchRun>.fromOpaque(context).takeUnretainedValue().finished.signal()
}

/// One search, shared between the engine's queue, the search thread's callbacks and whoever stops it.
private final class SearchRun: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var engine: OpaquePointer?
    private var stopped = false
    private var byIndex: [Int: EngineLine] = [:]
    private var unseen = false

    // go clears the engine's stop flag, so a stop that came before it has to be replayed after.
    // sf_stop stays under the lock so the engine can't be destroyed halfway through it.
    func started(on engine: OpaquePointer) {
        lock.withLock {
            self.engine = engine
            if stopped { sf_stop(engine) }
        }
    }

    func ended() {
        lock.withLock { engine = nil }
    }

    func stop() {
        lock.withLock {
            stopped = true
            if let engine { sf_stop(engine) }
        }
    }

    func record(_ raw: sf_line) {
        let line = EngineLine(
            multipv: Int(raw.multipv),
            depth: Int(raw.depth),
            score: Score(kind: raw.score_kind, value: raw.score_value),
            pv: String(cString: raw.pv).split(separator: " ").compactMap { Move(uci: String($0)) },
            nodes: Int(clamping: raw.nodes),
            wdl: raw.depth > 0
                ? WDL(win: Int(raw.wdl_win), draw: Int(raw.wdl_draw), loss: Int(raw.wdl_loss)) : nil
        )
        lock.withLock {
            byIndex[line.multipv] = line
            unseen = true
        }
    }

    func takeUnseen() -> [EngineLine]? {
        lock.withLock {
            guard unseen else { return nil }
            unseen = false
            return sorted
        }
    }

    // Stopped before depth 2, all the engine reports is a placeholder score of 0.
    var lines: [EngineLine] {
        lock.withLock { stopped && sorted.allSatisfy { $0.depth == 1 } ? [] : sorted }
    }

    private var sorted: [EngineLine] {
        byIndex.values.sorted { $0.multipv < $1.multipv }
    }
}
