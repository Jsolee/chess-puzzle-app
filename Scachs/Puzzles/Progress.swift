import Foundation
import Observation

enum AttemptContext: String, Codable { case blind, themed, lesson, retry }

struct Attempt: Codable {
    var puzzleID: String
    var index: Int
    var date: Date
    var solved: Bool
    var hinted: Bool
    var context: AttemptContext
    var puzzleRating: Int
    var ratingBefore: Double
    var themes: [String]
}

@Observable final class Progress {
    static let shared = Progress(url: defaultURL)

    private struct Stored: Codable {
        var glicko = Glicko2.Rating.start
        var lastRated = Date()
        var attempts: [Attempt] = []
        var completedLessons: Set<String> = []
        var dismissedLessons: [String: Date] = [:]
        /// Optional because files saved before the daily puzzle don't have the key, and a missing key would fail the whole file.
        var dailyDays: Set<Int>?
    }

    private var stored: Stored
    @ObservationIgnored private let url: URL
    // Both rebuilt from the attempt log on load, and keyed by id so they survive a recut of puzzles.bin.
    @ObservationIgnored private var playedIDs: Set<String> = []
    @ObservationIgnored private var retries: [String: Retry] = [:]

    private struct Retry { var box: Int; var due: Date }
    private static let ladderDays = [1, 3, 7, 21, 60]

    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("progress.json")
    }

    init(url: URL) {
        self.url = url
        stored = Self.load(url)
        for a in stored.attempts { absorb(a) }
    }

    private static func load(_ url: URL) -> Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return Stored() }
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stored.self, from: data) { return s }
        // Unreadable: keep the bytes for later, since the next save would overwrite them.
        let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return Stored()
    }

    // MARK: Rating

    var rating: Double { stored.glicko.rating }
    var deviation: Double { deviation(at: Date()) }
    var isProvisional: Bool { deviation >= Glicko2.provisionalDeviation }
    var attempts: [Attempt] { stored.attempts }

    private func deviation(at date: Date) -> Double {
        Glicko2.liveDeviation(stored.glicko, days: date.timeIntervalSince(stored.lastRated) / 86400)
    }

    func setInitialRating(_ r: Double) {
        stored.glicko = Glicko2.Rating(rating: r, deviation: 350, volatility: Glicko2.Rating.start.volatility)
        stored.lastRated = Date()
        save()
    }

    /// Logs the attempt and returns the rating change. Hints, retries and replays leave the rating alone.
    @discardableResult
    func record(_ p: Puzzle, solved: Bool, hinted: Bool, context: AttemptContext, at date: Date = Date()) -> Double {
        let before = rating
        if !hinted && context != .retry && !playedIDs.contains(p.id) {
            // When the theme was known, its class of hint is taken from the puzzle's most telling tag.
            let theme = context == .blind ? nil : ThemeNames.primaryTag(of: p.themes)
            var live = stored.glicko
            live.deviation = deviation(at: date)
            stored.glicko = Glicko2.update(live, puzzle: p.rating, solved: solved, weight: Glicko2.weight(theme: theme, solved: solved))
            stored.lastRated = date
        }
        let attempt = Attempt(puzzleID: p.id, index: p.index, date: date, solved: solved, hinted: hinted, context: context,
                              puzzleRating: p.rating, ratingBefore: before, themes: p.themes)
        stored.attempts.append(attempt)
        absorb(attempt)
        save()
        return rating - before
    }

    // MARK: Daily puzzle

    var dailyDays: Set<Int> { stored.dailyDays ?? [] }

    func recordDaily(on date: Date = Date()) {
        stored.dailyDays = dailyDays.union([PuzzleStore.dayNumber(date)])
        save()
    }

    // MARK: Lessons

    var completedLessons: Set<String> {
        get { stored.completedLessons }
        set { stored.completedLessons = newValue; save() }
    }

    var dismissedLessons: [String: Date] {
        get { stored.dismissedLessons }
        set { stored.dismissedLessons = newValue; save() }
    }

    // MARK: Played and retries

    func played(_ index: Int) -> Bool { playedIDs.contains(PuzzleStore.shared.id(at: index)) }

    /// Ids of due retries, oldest first, at most `limit`. There is deliberately no way to ask how many are waiting.
    func dueRetries(limit: Int, at date: Date = Date()) -> [String] {
        let due = retries.filter { $0.value.due <= date }.sorted { ($0.value.due, $0.key) < ($1.value.due, $1.key) }
        return due.prefix(limit).map(\.key)
    }

    private func absorb(_ a: Attempt) {
        playedIDs.insert(a.puzzleID)
        if !a.solved || a.hinted {
            retries[a.puzzleID] = Retry(box: 0, due: Self.days(Self.ladderDays[0], after: a.date))
        } else if var r = retries[a.puzzleID] {
            r.box += 1
            if r.box < Self.ladderDays.count {
                r.due = Self.days(Self.ladderDays[r.box], after: a.date)
                retries[a.puzzleID] = r
            } else {
                retries[a.puzzleID] = nil
            }
        }
    }

    /// Counted in calendar days, so "tomorrow" holds whatever the hour you come back.
    private static func days(_ n: Int, after date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(Double(n) * 86400)
    }

    // MARK: Persistence

    func save() {
        do {
            try JSONEncoder().encode(stored).write(to: url, options: .atomic)
        } catch {
            print("Progress not saved: \(error)")
        }
    }
}
