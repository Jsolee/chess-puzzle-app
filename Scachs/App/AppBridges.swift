import SwiftUI
import WidgetKit
import ActivityKit

/// Keeps the widgets' copy of today up to date.
enum WidgetSnapshot {
    private static let daysAhead = 14

    @MainActor static func write(now: Date = Date()) {
        let today = PuzzleStore.dayNumber(now)
        let days = Progress.shared.dailyDays
        var data = WidgetData.load() ?? WidgetData()
        let before = data
        data.dailyDays = days.sorted()
        data.streak = DailyStreak(days: days, today: today).current
        data.showStreak = UserDefaults.standard.object(forKey: "showStreak") as? Bool ?? true
        if !data.puzzles.contains(where: { $0.day == today + daysAhead - 1 }) {
            data.puzzles = (0..<daysAhead).compactMap { mate(day: today + $0) }
        }
        guard data != before else { return }
        data.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Mates in one around club strength, a different target each day so the store hands back a different one.
    private static func mate(day: Int) -> WidgetData.MatePuzzle? {
        let target = 800 + day * 37 % 900
        guard let p = PuzzleStore.shared.find(target: target, anyOf: ["mateIn1"], excluding: { _ in false }), p.line.count >= 2 else { return nil }
        let setup = p.start.move(uci: p.line[0].uci) ?? p.line[0]
        return WidgetData.MatePuzzle(day: day, fen: p.start.applying(setup).fen, best: p.line[1].uci, last: p.line[0].uci)
    }
}

/// The Live Activity for an analysis running on its own. Quietly does nothing where they're turned off.
@MainActor enum AnalysisActivity {
    private static var activity: Activity<AnalysisAttributes>?
    private static var lastShown = 0.0

    static func start(opponent: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        lastShown = 0
        activity = try? Activity.request(attributes: AnalysisAttributes(opponent: opponent), content: .init(state: .init(progress: 0), staleDate: nil))
    }

    /// Every few percent: updates have a budget.
    static func update(progress: Double) {
        guard let activity, progress - lastShown >= 0.05 else { return }
        lastShown = progress
        Task { await activity.update(.init(state: .init(progress: progress), staleDate: nil)) }
    }

    static func end() {
        guard let finished = activity else { return }
        activity = nil
        Task { await finished.end(nil, dismissalPolicy: .immediate) }
    }
}

/// What arrived from outside the app and should open as soon as it can.
@MainActor @Observable final class ShareCenter {
    static let shared = ShareCenter()
    struct Picture: Identifiable { let id = UUID(); let image: CGImage }
    struct Failure: Identifiable { let id = UUID(); let message: String }

    var game: ImportedGame?
    var picture: Picture?
    /// A position read by Visual Intelligence, on its way to the editor.
    var fen: String?
    var failure: Failure?
}

enum InboxReader {
    @MainActor static func drain() {
        for item in Inbox.take() {
            switch item {
            case .image(let data):
                if let image = UIImage(data: data)?.cgImage { ShareCenter.shared.picture = .init(image: image) }
            case .text(let text):
                Task {
                    do {
                        ShareCenter.shared.game = try await GameLibrary.shared.add(pasted: text).first
                    } catch {
                        let message = (error as? ImportError)?.errorDescription ?? String(localized: "No s'ha pogut llegir.")
                        ShareCenter.shared.failure = .init(message: message)
                    }
                }
            }
        }
    }
}
