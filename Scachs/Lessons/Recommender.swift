import Foundation

/// Picks the next lesson. Everything is recomputed from the attempt log, so there is no extra state to migrate.
///
/// For each attempt p = 1/(1+exp((d-R)/173.72)), s = solved, and with half-life 300 attempts:
///     A_t = d0*A_t + e*a_t*(s-p),  B_t = d0*B_t + e*a_t*p*(1-p),  theta_t = 173.72*A_t/(B_t+2)
/// e is 1 blind, 0.2 win / 0.7 loss when the theme is known, 0 for a retry or a hint. a_t shares the attempt over the
/// puzzle's curriculum tags, context tags counting half. A lesson then scores (Need*Value + Order)*Fit.
///
/// The per-tag estimates are noisy and rare motifs never separate from mixed play, so `weak` will rarely be true.
/// Copy should default to "next on your path" and treat "you are missing these" as the exception.
enum Recommender {
    struct Pick { let lesson: LessonMeta; let weak: Bool }

    struct Ranked {
        let lesson: LessonMeta
        let score: Double
        let theta: Double
        let evidence: Double
        var isWeak: Bool { theta * (evidence + prior).squareRoot() / scale <= -1.5 && evidence >= 1.5 }
    }

    static let scale = 173.72
    static let prior = 2.0
    private static let decay = pow(0.5, 1.0 / 300.0)
    private static let contextTags: Set<String> = ["sacrifice", "kingsideAttack", "queensideAttack", "exposedKing", "advancedPawn", "mateIn1", "mateIn2", "mateIn3"]
    /// Only completing the first opens the second, whatever the rating: otherwise a cold start at 1400 ranks L07 before L06.
    private static let siblingPrerequisites = ["L07": "L06", "L09": "L08"]

    struct Skills {
        var a: [String: Double] = [:]
        var b: [String: Double] = [:]
        func theta(_ tag: String) -> Double { scale * (a[tag] ?? 0) / ((b[tag] ?? 0) + prior) }
    }

    /// Inferred, not simulated: `reviewEvidence` holds tactics Game Review found per tag, positive when missed and negative
    /// when found. Each one counts as a blind attempt at even odds, so it moves the same counters and does not decay here.
    static func skills(attempts: [Attempt], curriculum: Set<String>, reviewEvidence: [String: Double]) -> Skills {
        var skills = Skills()
        for (i, attempt) in attempts.enumerated() {
            if attempt.hinted || attempt.context == .retry { continue }
            let weight = attempt.context == .blind ? 1 : (attempt.solved ? 0.2 : 0.7)
            let tags = attempt.themes.filter(curriculum.contains)
            guard !tags.isEmpty else { continue }
            let total = tags.reduce(0.0) { $0 + (contextTags.contains($1) ? 0.5 : 1) }
            let p = 1 / (1 + exp((Double(attempt.puzzleRating) - attempt.ratingBefore) / scale))
            let s = attempt.solved ? 1.0 : 0.0
            let age = pow(decay, Double(attempts.count - 1 - i))
            for tag in tags {
                let share = (contextTags.contains(tag) ? 0.5 : 1) / total
                skills.a[tag, default: 0] += age * weight * share * (s - p)
                skills.b[tag, default: 0] += age * weight * share * p * (1 - p)
            }
        }
        for (tag, missed) in reviewEvidence where curriculum.contains(tag) {
            skills.a[tag, default: 0] -= 0.5 * missed
            skills.b[tag, default: 0] += 0.25 * abs(missed)
        }
        return skills
    }

    static func ranked(rating: Double, attempts: [Attempt], completed: Set<String>, dismissed: [String: Date],
                       lessons: [LessonMeta], reviewEvidence: [String: Double], frequency: TagFrequency = .bundled,
                       now: Date = .now) -> [Ranked] {
        let curriculum = Set(lessons.flatMap(\.tags.keys))
        let skills = Self.skills(attempts: attempts, curriculum: curriculum, reviewEvidence: reviewEvidence)
        let byID = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let f = frequency.band(rating: rating)
        let fMax = curriculum.map { f[$0] ?? 0 }.max() ?? 0

        func thetaOf(_ l: LessonMeta) -> Double { l.tags.reduce(0) { $0 + $1.value * skills.theta($1.key) } }
        func evidenceOf(_ l: LessonMeta) -> Double { l.tags.reduce(0) { $0 + $1.value * (skills.b[$1.key] ?? 0) } }
        func prerequisiteMet(_ q: String, for lesson: LessonMeta) -> Bool {
            if completed.contains(q) { return true }
            if siblingPrerequisites[lesson.id] == q { return false }
            guard let pre = byID[q] else { return true }
            return rating >= Double(pre.level + 150) || (thetaOf(pre) >= 0 && evidenceOf(pre) >= 2)
        }

        var out: [Ranked] = []
        for (i, lesson) in lessons.enumerated() {
            if completed.contains(lesson.id) || lesson.section == "openings" { continue }
            if let when = dismissed[lesson.id], now.timeIntervalSince(when) < 14 * 86400 { continue }
            if !lesson.requires.allSatisfy({ prerequisiteMet($0, for: lesson) }) { continue }
            let theta = thetaOf(lesson)
            let need = max(0, min(1, (25 - theta) / 150))
            let fL = lesson.tags.reduce(0) { $0 + $1.value * (f[$1.key] ?? 0) }
            let value = fMax > 0 ? (fL / fMax).squareRoot() : 0
            let c = Double(lesson.level)
            let fit = c > rating ? exp(-pow((c - rating) / 250, 2)) : exp(-pow((rating - c) / 700, 2))
            let order = 0.08 * (1 - Double(i) / Double(lessons.count))
            // Someone just starting gets the golden rules first, in order. Their tags are too broad for puzzle evidence to rank them.
            let score = lesson.section == "rules" && rating < 1100 ? 2 - Double(i) / Double(lessons.count) : (need * value + order) * fit
            out.append(Ranked(lesson: lesson, score: score, theta: theta, evidence: evidenceOf(lesson)))
        }
        return out.sorted { $0.score > $1.score }
    }

    static func next(progress: Progress, lessons: [LessonMeta], reviewEvidence: [String: Double]) -> Pick? {
        ranked(rating: progress.rating, attempts: progress.attempts, completed: progress.completedLessons,
               dismissed: progress.dismissedLessons, lessons: lessons, reviewEvidence: reviewEvidence)
            .first.map { Pick(lesson: $0.lesson, weak: $0.isWeak) }
    }

    /// Lessons whose next re-exposure is due, oldest first. Calendar delays are minimums: never show a backlog count.
    static func spacedDue(now: Date = .now) -> [LessonReviews.Due] { LessonReviews.shared.due(now: now) }
}

/// f_t(R): how often each curriculum tag appears at a rating, from tag_frequency.json. tools/gen_tag_frequency.py builds it
/// from the natural puzzle pool, not the curated bundle, whose motif mix is deliberately flattened.
struct TagFrequency: Decodable {
    let bands: [Int]
    let freq: [String: [Double]]

    static let bundled: TagFrequency = {
        let url = ["Resources", nil].lazy.compactMap { Bundle.main.url(forResource: "tag_frequency", withExtension: "json", subdirectory: $0) }.first
        guard let url, let data = try? Data(contentsOf: url), let table = try? JSONDecoder().decode(TagFrequency.self, from: data) else {
            return TagFrequency(bands: [], freq: [:])
        }
        return table
    }()

    func band(rating: Double) -> [String: Double] {
        guard let first = bands.first, let last = bands.last else { return [:] }
        let key = max(first, min(last, Int(rating) / 100 * 100))
        guard let i = bands.firstIndex(of: key) else { return [:] }
        return freq.mapValues { $0[i] }
    }
}

/// Re-exposure after a lesson: `days` after completion, `n` blind puzzles each, mastered at two thirds solved.
/// Progress only keeps a set of completed ids, so the dates live here, in their own file in Application Support.
final class LessonReviews {
    static let shared = LessonReviews(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("lesson_reviews.json"))

    struct Entry: Codable {
        var completed: Date
        var days: [Int]
        var solved: [[Bool]] = []
        var last: Date?
    }
    struct Due: Hashable {
        let lessonID: String
        let exposure: Int       // 0, 1 or 2
        let date: Date
    }

    private(set) var entries: [String: Entry]
    private let file: URL?

    init(file: URL?) {
        self.file = file
        entries = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func markCompleted(_ id: String, days: [Int] = [1, 3, 7], at date: Date = .now) {
        guard entries[id] == nil else { return }
        entries[id] = Entry(completed: date, days: days)
        save()
    }

    func record(_ id: String, solved: [Bool], at date: Date = .now) {
        entries[id]?.solved.append(solved)
        entries[id]?.last = date
        save()
    }

    func isMastered(_ id: String) -> Bool {
        guard let e = entries[id] else { return false }
        return e.solved.joined().filter { $0 }.count >= 4
    }

    /// A late exposure pushes the next one out, so the gaps between exposures are never shorter than planned.
    func due(now: Date = .now, calendar: Calendar = .current) -> [Due] {
        entries.compactMap { id, e -> Due? in
            let box = e.solved.count
            guard box < e.days.count else { return nil }
            let day = calendar.startOfDay(for: e.completed)
            guard var date = calendar.date(byAdding: .day, value: e.days[box], to: day) else { return nil }
            if box > 0, let last = e.last,
               let spaced = calendar.date(byAdding: .day, value: e.days[box] - e.days[box - 1], to: calendar.startOfDay(for: last)) {
                date = max(date, spaced)
            }
            return date <= now ? Due(lessonID: id, exposure: box, date: date) : nil
        }.sorted { ($0.date, $0.lessonID) < ($1.date, $1.lessonID) }
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
