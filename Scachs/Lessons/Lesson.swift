import Foundation

// Lesson file format and how LessonRunner should treat each step.
//
// A step with `fen` sets the board. Without `fen` it continues from where the previous step left it, which is after
// its last move and `reply`. `Lesson.startPositions()` does that walk. Orient the board for the side to move at the
// first `find`. Show `say` while the step is live and `draw` as shapes until the first move.
//
// explain  Board, text and shapes. The user taps on.
// watch    Autoplays `line` on the board under `say`. `mate` says the line ends in checkmate.
//          `shows.mistakeAt` marks the ply that is a deliberate error, followed by its punishment.
// guided   Only `uci` is accepted, with no penalty. Other moves just snap back. Then `reply` plays.
// find     No shapes up front. Any move in `ok` solves it: show `after` and play `reply` if there is one.
//          `reply` follows `ok[0]`. A step with several `ok` moves is followed by a step with its own `fen`.
//          A move in `bad` plays its `reply` on the board and shows its `say`, then the position resets.
//          Any other move: if `goal` is set, ask Engine and accept the move when it meets the goal. Otherwise use
//          Engine for the real refutation, or at least flash it wrong. `hints` are revealed one per request.
//          `goal` is what the engine verified for `ok`: mate in N, a kept win, or a held draw.
// tap      Tap the squares in `squares`, all of them and only them. `rule` is for the validator, not the runner.
// test     Blind: no theme shown, no hints. Query form: draw `n` puzzles with `drawTest`, `decoys` of them outside the
//          tags. Record each with context `.lesson`. Hand-written form: `items` are `find` steps played in order and
//          one has `decoy` set. Passed at `pass` first-try solves.
// recap    The named pattern card: `name`, `say`, and the board at `fen` with `draw`. `card` is a stable id.
//
// A lesson with a query test opens with 3 blind puzzles from `drawTest`, and 3 of 3 first try offers a skip. Lessons
// with hand-written tests have no such pre-test, because it would spoil the items. After the recap `review` schedules
// re-exposure, see `LessonReviews` in Recommender.swift. Hand-written tests cycle through their items for re-exposure.

struct LocalizedText: Codable, Hashable {
    let values: [String: String]
    init(ca: String, es: String, en: String) { values = ["ca": ca, "es": es, "en": en] }
    init(from decoder: Decoder) throws { values = try [String: String](from: decoder) }
    func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }

    /// Text in the app's current language, Catalan when that language is missing.
    var text: String { text(in: Self.currentLanguage) }
    func text(in language: String) -> String { values[language] ?? values["ca"] ?? "" }

    static var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "ca"
        let base = String(code.prefix { $0 != "-" && $0 != "_" })
        return ["ca", "es", "en"].contains(base) ? base : "ca"
    }
}

/// One %cal/%csl shape: a colour letter then one square (a mark) or two (an arrow), as in "Gd5c7" or "Rc7".
struct LessonShape: Codable, Hashable {
    enum Tint: Character { case green = "G", red = "R", yellow = "Y", blue = "B" }
    let tint: Tint
    let from: Square
    let to: Square?

    init?(_ raw: String) {
        let c = Array(raw)
        guard c.count == 3 || c.count == 5, let tint = Tint(rawValue: c[0]),
              let from = square(named: String(c[1...2])) else { return nil }
        self.tint = tint
        self.from = from
        if c.count == 5 {
            guard let to = square(named: String(c[3...4])) else { return nil }
            self.to = to
        } else { to = nil }
    }
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let shape = LessonShape(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad shape \(raw)"))
        }
        self = shape
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(tint.rawValue) + squareName(from) + (to.map(squareName) ?? ""))
    }
}

struct LessonGoal: Codable, Hashable {
    var mate: Int?
    var win: Bool?
    var draw: Bool?
}

struct LessonRefutation: Codable, Hashable {
    var reply: String?
    var say: LocalizedText?
}

struct LessonHint: Codable, Hashable {
    var say: LocalizedText?
    var draw: [LessonShape]?
}

/// How a `tap` answer is recomputed by the validator. See tools/validate_lessons.swift for the rules.
struct LessonTapRule: Codable, Hashable {
    var rule: String
    var targets: [String]?
    var of: String?
    var by: String?
    var side: String?
    var attacked: Bool?
    var from: String?
    var pawn: String?
}

struct LessonQuery: Codable, Hashable {
    var any: [String]
    var piece: String?          // the solver's first move is made by this piece: p n b r q k
    var notPiece: String?
    var gap: Int                // target puzzle rating is the player's rating minus this
    var maxPlies: Int
}

struct LessonStep: Codable, Hashable {
    enum Kind: String, Codable { case explain, watch, guided, find, tap, recap, test }
    struct Shows: Codable, Hashable { var mistakeAt: Int? }

    var t: Kind
    var fen: String?
    var say: LocalizedText?
    var after: LocalizedText?
    var draw: [LessonShape]?
    var line: [String]?                     // watch
    var shows: Shows?
    var mate: Bool?
    var uci: String?                        // guided
    var reply: String?
    var ok: [String]?                       // find
    var bad: [String: LessonRefutation]?
    var hints: [LessonHint]?
    var goal: LessonGoal?
    var squares: [String]?                  // tap
    var rule: LessonTapRule?
    var card: String?                       // recap
    var name: LocalizedText?
    var n: Int?                             // test
    var pass: Int?
    var query: LessonQuery?
    var decoys: Int?
    var items: [LessonStep]?
    var decoy: Bool?
}

struct LessonReview: Codable, Hashable {
    var days: [Int]
    var n: Int
}

struct Lesson: Codable, Identifiable, Hashable {
    let v: Int
    let id: String
    let section: String
    let title: LocalizedText
    let min: Int
    let c: Int
    let requires: [String]
    let tags: [String: Double]
    let steps: [LessonStep]
    let review: LessonReview

    var meta: LessonMeta {
        LessonMeta(id: id, title: title.text, level: c, section: section, minutes: min, requires: requires, tags: tags)
    }

    /// The position each step starts from, nil for a `test` or if the data does not walk. The validator proves it does.
    func startPositions() -> [Position?] {
        var current: Position?
        func play(_ uci: String?) {
            guard let uci, let p = current, let m = p.move(uci: uci) else { return }
            current = p.applying(m)
        }
        return steps.map { step in
            if step.t == .test { return nil }
            if let fen = step.fen { current = Position(fen: fen) }
            let start = current
            switch step.t {
            case .watch: step.line?.forEach(play)
            case .guided: play(step.uci); play(step.reply)
            case .find: play(step.ok?.first); play(step.reply)
            default: break
            }
            return start
        }
    }
}

struct LessonMeta: Identifiable, Hashable {
    let id: String
    let title: String
    let level: Int
    let section: String
    let minutes: Int
    let requires: [String]
    let tags: [String: Double]
}

final class LessonLibrary {
    static let shared = LessonLibrary()

    struct Section: Identifiable, Hashable {
        let id: String
        let name: LocalizedText
        let lessonIDs: [String]
    }

    static let sections: [Section] = [
        Section(id: "seeing", name: LocalizedText(ca: "Veure i mats bàsics", es: "Ver y mates básicos", en: "Seeing and basic mates"),
                lessonIDs: ["L01", "L02", "L03", "L04", "L05"]),
        Section(id: "double", name: LocalizedText(ca: "Atacs dobles", es: "Ataques dobles", en: "Double attacks"),
                lessonIDs: ["L06", "L07", "L08", "L09", "L10", "L11", "L12"]),
        Section(id: "obstacles", name: LocalizedText(ca: "Treure obstacles", es: "Quitar obstáculos", en: "Removing obstacles"),
                lessonIDs: ["L13", "L14", "L15", "L16", "L17", "L18", "L19", "L20"]),
        Section(id: "attack", name: LocalizedText(ca: "Xarxes de mat i atac", es: "Redes de mate y ataque", en: "Mating nets and attack"),
                lessonIDs: ["L21", "L22", "L23", "L24", "L25", "L26"]),
        Section(id: "defence", name: LocalizedText(ca: "Defensa i càlcul", es: "Defensa y cálculo", en: "Defence and calculation"),
                lessonIDs: ["L27", "L28"]),
        Section(id: "endgames", name: LocalizedText(ca: "Finals", es: "Finales", en: "Endgames"),
                lessonIDs: ["L29", "L30"]),
    ]

    private struct Head: Decodable {
        let id: String, section: String, title: LocalizedText, min: Int, c: Int, requires: [String], tags: [String: Double]
    }

    private let bundle: Bundle
    private let directory: URL?
    private var cache: [String: Lesson] = [:]

    init(bundle: Bundle = .main, directory: URL? = nil) {
        self.bundle = bundle
        self.directory = directory
    }

    private func data(for id: String) -> Data? {
        if let directory { return try? Data(contentsOf: directory.appendingPathComponent(id + ".json")) }
        // Resources are grouped by xcodegen, so the copy may land flat in the bundle or keep its folders.
        let url = ["Resources/Lessons", "Lessons", nil].lazy
            .compactMap { self.bundle.url(forResource: id, withExtension: "json", subdirectory: $0) }.first
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    /// Reads only the heads of the lesson files, in syllabus order, on first use. The title follows the current language.
    lazy var metas: [LessonMeta] = Self.sections.flatMap(\.lessonIDs).compactMap { id in
        guard let data = data(for: id), let h = try? JSONDecoder().decode(Head.self, from: data) else { return nil }
        return LessonMeta(id: h.id, title: h.title.text, level: h.c, section: h.section, minutes: h.min, requires: h.requires, tags: h.tags)
    }

    func lesson(id: String) -> Lesson? {
        if let hit = cache[id] { return hit }
        guard let data = data(for: id), let lesson = try? JSONDecoder().decode(Lesson.self, from: data) else { return nil }
        cache[id] = lesson
        return lesson
    }
}

#if !LESSON_TOOL
extension LessonShape {
    var arrow: BoardArrow? {
        guard let to else { return nil }
        let role: ArrowRole = switch tint { case .green: .best; case .red: .threat; case .yellow: .idea; case .blue: .opponent }
        return BoardArrow(from: from, to: to, role: role)
    }
    var mark: BoardMark? {
        guard to == nil else { return nil }
        let role: MarkRole = switch tint { case .green: .good; case .red: .bad; case .yellow: .target; case .blue: .hint }
        return BoardMark(square: from, role: role)
    }
}

extension LessonQuery {
    func matches(_ p: Puzzle) -> Bool {
        guard p.line.count <= maxPlies, p.line.count >= 2, !Set(p.themes).isDisjoint(with: any) else { return false }
        if piece == nil && notPiece == nil { return true }
        let setup = p.start.applying(p.line[0])
        guard let kind = setup.piece(at: p.line[1].from)?.kind else { return false }
        let letter = ["p", "n", "b", "r", "q", "k"][PieceKind.allCases.firstIndex(of: kind)!]
        return (piece == nil || piece == letter) && (notPiece == nil || notPiece != letter)
    }
}

extension LessonStep {
    /// Draws a `test` step's puzzles: `n - decoys` from the query and `decoys` from the same window outside its tags, shuffled.
    func drawTest(rating: Double, store: PuzzleStore, played: (Int) -> Bool) -> [Puzzle] {
        guard let query, let n else { return [] }
        let target = Int(rating) - query.gap
        let decoyCount = Swift.min(decoys ?? 0, n)
        var used = Set<Int>()
        var picked: [Puzzle] = []
        for _ in 0..<(n - decoyCount) {
            if let p = store.find(target: target, anyOf: Set(query.any), excluding: { i in
                played(i) || used.contains(i) || !query.matches(store.puzzle(at: i))
            }) {
                used.insert(p.index)
                picked.append(p)
            }
        }
        for _ in 0..<decoyCount {
            if let p = store.find(target: target, anyOf: nil, excluding: { i in
                played(i) || used.contains(i) || !Set(store.puzzle(at: i).themes).isDisjoint(with: query.any)
            }) {
                used.insert(p.index)
                picked.append(p)
            }
        }
        return picked.shuffled()
    }
}
#endif
