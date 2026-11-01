import Foundation
import Observation
import BackgroundTasks

/// Analyses your games without being asked, so something is waiting when you come back. One at a time, and it steps
/// aside as soon as you open a review, which picks up from the state it saved.
@MainActor @Observable final class AutoReview {
    static let shared = AutoReview()
    static let taskID = "com.jsolee.scachs.review"
    /// In the foreground only recent games: an old one isn't worth the battery while you are looking at the phone.
    private static let foregroundDays = 14.0

    private(set) var current: ImportedGame?
    private(set) var progress = 0.0
    /// Goes up each time a game finishes, so views can look for what it left.
    private(set) var finished = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var holds = 0

    func hold() { holds += 1; task?.cancel() }
    func release() { holds = max(0, holds - 1); kick() }

    /// Starts on the newest game of yours still without a review, if the phone can spare it.
    func kick() {
        let info = ProcessInfo.processInfo
        // The test host runs this same app, and the engine tests need the engine to themselves.
        guard info.environment["XCTestConfigurationFilePath"] == nil, task == nil, holds == 0, !info.isLowPowerModeEnabled, info.thermalState == .nominal || info.thermalState == .fair,
              let game = next(within: Self.foregroundDays) else { return }
        task = Task { [weak self] in
            await self?.review(game)
            self?.task = nil
        }
    }

    private func next(within days: Double?) -> ImportedGame? {
        GameLibrary.shared.games.first { game in
            game.mySide != nil && !game.reviewed && (days.map { Date().timeIntervalSince(game.date) < $0 * 86400 } ?? true)
        }
    }

    private func review(_ game: ImportedGame) async {
        guard let pgn = PGN.parse(game.pgn).first else { return }
        current = game
        progress = 0
        AnalysisActivity.start(opponent: game.mySide == .white ? game.black : game.white)
        defer { current = nil; AnalysisActivity.end() }
        let ratings = Ratings(game: pgn, fallback: Int(Progress.shared.rating))
        do {
            let result = try await ReviewEngine.review(game: pgn, ratings: ratings) { p in
                Task { @MainActor [weak self] in
                    self?.progress = p
                    AnalysisActivity.update(progress: p)
                }
            }
            try? GameLibrary.shared.save(result, for: game.id)
            finished += 1
        } catch {
            // Cancelled or failed: the state on disk lets the next run go on from here.
        }
    }

    // MARK: Overnight

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            Task { @MainActor in AutoReview.shared.runOvernight(task) }
        }
    }

    /// Plugged in and on a network, as iOS sees fit: new games come in and all of them get read.
    func scheduleOvernight() {
        let request = BGProcessingTaskRequest(identifier: Self.taskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(request)
    }

    private func runOvernight(_ background: BGProcessingTask) {
        scheduleOvernight()
        let work = Task { @MainActor [weak self] in
            await GameLibrary.shared.refresh()
            while !Task.isCancelled, let self, let game = self.next(within: nil) {
                await self.review(game)
            }
            background.setTaskCompleted(success: !Task.isCancelled)
        }
        background.expirationHandler = { work.cancel() }
    }
}
