import XCTest
@testable import Scachs

final class RecommenderTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private var lessons: [LessonMeta] {
        let bundled = LessonLibrary.shared.metas
        return bundled.isEmpty ? LessonLibrary(directory: Self.repo.appendingPathComponent("Scachs/Resources/Lessons")).metas : bundled
    }

    private var frequency: TagFrequency {
        if !TagFrequency.bundled.bands.isEmpty { return .bundled }
        let data = try! Data(contentsOf: Self.repo.appendingPathComponent("Scachs/Resources/tag_frequency.json"))
        return try! JSONDecoder().decode(TagFrequency.self, from: data)
    }

    private func attempt(_ themes: [String], solved: Bool, rating: Int = 1300, before: Double = 1300,
                         hinted: Bool = false, context: AttemptContext = .blind) -> Attempt {
        Attempt(puzzleID: "x", index: 0, date: Date(), solved: solved, hinted: hinted, context: context,
                puzzleRating: rating, ratingBefore: before, themes: themes)
    }

    private func top(_ n: Int, rating: Double, attempts: [Attempt] = [], completed: Set<String> = [], dismissed: [String: Date] = [:],
                     review: [String: Double] = [:], now: Date = Date()) -> [String] {
        Recommender.ranked(rating: rating, attempts: attempts, completed: completed, dismissed: dismissed, lessons: lessons,
                           reviewEvidence: review, frequency: frequency, now: now).prefix(n).map(\.lesson.id)
    }

    func testAllThirtyLessonsLoad() {
        XCTAssertEqual(lessons.count, 30)
        XCTAssertEqual(LessonLibrary.sections.flatMap(\.lessonIDs).count, 30)
    }

    // The research's order, with the sibling fix: at 1200 L06 now comes before L07, which is not eligible until L06 is done.
    func testColdStartOrder() {
        XCTAssertEqual(top(3, rating: 800), ["L03", "L01", "L29"])
        XCTAssertEqual(top(3, rating: 1200), ["L05", "L06", "L03"])
        XCTAssertEqual(top(3, rating: 1800), ["L26", "L15", "L14"])
    }

    func testSiblingsNeedTheirFirstLessonDone() {
        for rating in [1200.0, 1400, 1800, 2400] {
            let ids = top(30, rating: rating)
            XCTAssertFalse(ids.contains("L07"), "L07 at \(rating)")
            XCTAssertFalse(ids.contains("L09"), "L09 at \(rating)")
        }
        XCTAssertTrue(top(30, rating: 1400, completed: ["L06"]).contains("L07"))
        XCTAssertTrue(top(30, rating: 1400, completed: ["L08"]).contains("L09"))
    }

    // A stronger player is presumed to know an ordinary prerequisite; a weaker one is not.
    func testOrdinaryPrerequisite() {
        XCTAssertTrue(top(30, rating: 1250).contains("L10"), "L08 is presumed known at 1250")
        XCTAssertFalse(top(30, rating: 1249).contains("L10"))
        XCTAssertTrue(top(30, rating: 1200, completed: ["L08"]).contains("L10"))
    }

    func testCompletedAndDismissed() {
        let now = Date()
        XCTAssertFalse(top(30, rating: 1200, completed: ["L05"]).contains("L05"))
        XCTAssertFalse(top(30, rating: 1200, dismissed: ["L05": now.addingTimeInterval(-13 * 86400)], now: now).contains("L05"))
        XCTAssertTrue(top(30, rating: 1200, dismissed: ["L05": now.addingTimeInterval(-15 * 86400)], now: now).contains("L05"))
    }

    // The closed form in `skills` must equal the attempt-by-attempt update in the research.
    func testEvidenceMatchesIncrementalFormula() {
        let d0 = pow(0.5, 1.0 / 300)
        var rng = SystemRandomNumberGenerator()
        let attempts = (0..<500).map { _ in
            attempt(Bool.random(using: &rng) ? ["fork", "kingsideAttack"] : ["pin"], solved: Bool.random(using: &rng),
                    rating: Int.random(in: 900...1700, using: &rng), before: 1300,
                    context: [.blind, .themed, .lesson, .retry].randomElement(using: &rng)!)
        }
        var a: [String: Double] = [:], b: [String: Double] = [:]
        for x in attempts {
            for t in ["fork", "kingsideAttack", "pin"] { a[t, default: 0] *= d0; b[t, default: 0] *= d0 }
            let e = x.context == .retry ? 0 : x.context == .blind ? 1 : (x.solved ? 0.2 : 0.7)
            let u = x.themes.map { $0 == "kingsideAttack" ? 0.5 : 1.0 }
            let p = 1 / (1 + exp((Double(x.puzzleRating) - x.ratingBefore) / 173.72))
            for (t, w) in zip(x.themes, u) {
                let share = w / u.reduce(0, +)
                a[t]! += e * share * ((x.solved ? 1 : 0) - p)
                b[t]! += e * share * p * (1 - p)
            }
        }
        let skills = Recommender.skills(attempts: attempts, curriculum: ["fork", "kingsideAttack", "pin"], reviewEvidence: [:])
        for t in ["fork", "kingsideAttack", "pin"] {
            XCTAssertEqual(skills.a[t] ?? 0, a[t]!, accuracy: 1e-9)
            XCTAssertEqual(skills.b[t] ?? 0, b[t]!, accuracy: 1e-9)
        }
    }

    func testEvidenceWeights() {
        let curriculum: Set<String> = ["fork"]
        func a(_ x: Attempt) -> Double { Recommender.skills(attempts: [x], curriculum: curriculum, reviewEvidence: [:]).a["fork"] ?? 0 }
        XCTAssertEqual(a(attempt(["fork"], solved: false)), -0.5, accuracy: 1e-9)
        XCTAssertEqual(a(attempt(["fork"], solved: true)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(a(attempt(["fork"], solved: false, context: .themed)), -0.35, accuracy: 1e-9)
        XCTAssertEqual(a(attempt(["fork"], solved: true, context: .lesson)), 0.1, accuracy: 1e-9)
        XCTAssertEqual(a(attempt(["fork"], solved: false, context: .retry)), 0)
        XCTAssertEqual(a(attempt(["fork"], solved: false, hinted: true)), 0)
    }

    func testWeaknessRaisesTheLessonAndClaimsOnlyWithEvidence() {
        let misses = (0..<40).map { _ in attempt(["fork"], solved: false, rating: 1100, before: 1300) }
        let ranked = Recommender.ranked(rating: 1300, attempts: misses, completed: [], dismissed: [:], lessons: lessons,
                                        reviewEvidence: [:], frequency: frequency)
        XCTAssertEqual(ranked.first?.lesson.id, "L06")
        XCTAssertTrue(ranked.first?.isWeak ?? false)
        let cold = Recommender.ranked(rating: 1300, attempts: [], completed: [], dismissed: [:], lessons: lessons,
                                      reviewEvidence: [:], frequency: frequency)
        XCTAssertFalse(cold.contains { $0.isWeak })
    }

    func testReviewEvidenceFeedsTheCounters() {
        let plain = Recommender.skills(attempts: [], curriculum: ["pin"], reviewEvidence: [:])
        let missed = Recommender.skills(attempts: [], curriculum: ["pin"], reviewEvidence: ["pin": 4, "unknownTag": 9])
        XCTAssertEqual(plain.theta("pin"), 0)
        XCTAssertEqual(missed.a["pin"]!, -2, accuracy: 1e-9)
        XCTAssertEqual(missed.b["pin"]!, 1, accuracy: 1e-9)
        XCTAssertLessThan(missed.theta("pin"), 0)
        XCTAssertEqual(top(1, rating: 1300, review: ["pin": 12]), ["L08"])
    }

    func testSpacedDue() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 20))!
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: start))!.addingTimeInterval(9 * 3600) }
        let reviews = LessonReviews(file: nil)
        reviews.markCompleted("L06", at: start)
        XCTAssertTrue(reviews.due(now: start).isEmpty)
        XCTAssertEqual(reviews.due(now: day(1)).map(\.lessonID), ["L06"])
        XCTAssertEqual(reviews.due(now: day(1)).first?.exposure, 0)
        reviews.record("L06", solved: [true, false], at: day(1))
        XCTAssertTrue(reviews.due(now: day(2)).isEmpty)
        XCTAssertEqual(reviews.due(now: day(3)).first?.exposure, 1)
        // Done late, on day 10: the third exposure waits its full four-day gap, not day 7.
        reviews.record("L06", solved: [true, true], at: day(10))
        XCTAssertTrue(reviews.due(now: day(13)).isEmpty)
        XCTAssertEqual(reviews.due(now: day(14)).first?.exposure, 2)
        reviews.record("L06", solved: [true, false], at: day(14))
        XCTAssertTrue(reviews.due(now: day(60)).isEmpty)
        XCTAssertTrue(reviews.isMastered("L06"))
    }
}
