// Validates Scachs/Resources/Lessons/*.json with the app's own decoder and rules core: every lesson decodes, FENs parse,
// moves are legal in order, shapes are real squares, tap answers match their rule, and the text is there in three languages.
// Chess truth against an engine is tools/engine_check_lessons.py.
//
// xcrun swiftc -parse-as-library -D LESSON_TOOL Scachs/Chess/Position.swift Scachs/Lessons/Lesson.swift \
//     tools/validate_lessons.swift -o /tmp/validate_lessons && /tmp/validate_lessons Scachs/Resources/Lessons
import Foundation

@main struct ValidateLessons {
    static let handTests: Set<String> = ["L02", "L29", "L30", "R01", "R02", "R03", "O01", "O02", "O03", "O04", "O05", "O06", "O07", "O08", "O09", "O10", "O11", "O12", "O13", "O14", "O15", "O16", "O17", "O18", "O19", "O20", "E01", "E02", "E03", "E04", "E05", "E06", "M01", "M02", "M03", "M04", "M05", "M06", "A01", "A02", "A03", "A04", "A05"]
    static var failures: [String] = []
    static var counts: [String: Int] = [:]

    static func main() {
        let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Scachs/Resources/Lessons")
        let library = LessonLibrary(directory: dir)
        var seen = Set<String>()
        for section in LessonLibrary.sections {
            for id in section.lessonIDs {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(id + ".json")) else { fail(id, "file missing"); continue }
                do { _ = try JSONDecoder().decode(Lesson.self, from: data) } catch { fail(id, "does not decode: \(error)"); continue }
                guard let lesson = library.lesson(id: id) else { fail(id, "library cannot load it"); continue }
                seen.insert(id)
                if lesson.id != id { fail(id, "id field is \(lesson.id)") }
                if lesson.section != section.id { fail(id, "section \(lesson.section), expected \(section.id)") }
                check(lesson)
            }
        }
        if library.metas.count != seen.count { fail("library", "metas \(library.metas.count), lessons \(seen.count)") }
        for meta in library.metas {
            if meta.title.isEmpty { fail(meta.id, "empty title") }
            for q in meta.requires where !seen.contains(q) { fail(meta.id, "requires unknown \(q)") }
            let total = meta.tags.values.reduce(0, +)
            if abs(total - 1) > 1e-6 { fail(meta.id, "tag weights sum to \(total)") }
        }
        for f in failures { print("FAIL", f) }
        print("\(seen.count) lessons decoded and walked; \(failures.count) failures; \(counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        exit(failures.isEmpty ? 0 : 1)
    }

    static func fail(_ w: String, _ m: String) { failures.append("\(w): \(m)") }
    static func count(_ k: String, _ n: Int = 1) { counts[k, default: 0] += n }

    static func text(_ t: LocalizedText?, _ w: String, required: Bool = false) {
        guard let t else { if required { fail(w, "text missing") }; return }
        count("texts")
        for lang in ["ca", "es", "en"] where (t.values[lang] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            fail(w, "missing \(lang)")
        }
        for (lang, v) in t.values {
            if v.contains("!") || v.contains("¡") { fail(w, "exclamation mark in \(lang)") }
            if v.contains("\u{2014}") || v.contains("\u{2013}") { fail(w, "long dash in \(lang)") }
        }
    }

    static func play(_ uci: String?, on p: Position?, _ w: String) -> Position? {
        guard let uci, let p else { return nil }
        guard let m = p.move(uci: uci), p.isLegal(m) else { fail(w, "\(uci) is not legal in \(p.fen)"); return nil }
        count("moves")
        // The SAN the app will show must parse back to the same move.
        if p.move(san: p.san(m)) != m { fail(w, "SAN round trip fails for \(uci) in \(p.fen)") }
        return p.applying(m)
    }

    static func check(_ lesson: Lesson) {
        text(lesson.title, "\(lesson.id) title", required: true)
        if !(7...14).contains(lesson.steps.count) { fail(lesson.id, "\(lesson.steps.count) steps") }
        if !(3...5).contains(lesson.min) { fail(lesson.id, "min \(lesson.min)") }
        if lesson.review.days != [1, 3, 7] || lesson.review.n != 2 { fail(lesson.id, "review is not 1,3,7 x 2") }
        if lesson.steps.suffix(2).map(\.t) != [.test, .recap] { fail(lesson.id, "must end with test, recap") }
        if lesson.steps.filter({ $0.t == .find }).isEmpty { fail(lesson.id, "no find") }

        var current: Position?
        let starts = lesson.startPositions()
        for (i, step) in lesson.steps.enumerated() {
            let w = "\(lesson.id) step\(i + 1) \(step.t.rawValue)"
            count(step.t.rawValue)
            text(step.say, w, required: step.t != .test)
            text(step.after, w + " after")
            text(step.name, w + " name")
            if step.t == .test { checkTest(step, lesson, w); continue }
            if let fen = step.fen {
                current = position(fen, w)
            }
            if i < starts.count, starts[i]?.fen != current?.fen { fail(w, "startPositions disagrees with the walk") }
            guard let p = current else { fail(w, "no position"); continue }
            switch step.t {
            case .watch:
                guard let line = step.line, !line.isEmpty else { fail(w, "no line"); break }
                for u in line { current = play(u, on: current, w) }
                if step.mate == true, current?.isCheckmate != true { fail(w, "flagged mate") }
            case .guided:
                guard let uci = step.uci else { fail(w, "no uci"); break }
                current = play(uci, on: p, w)
                if step.mate == true, current?.isCheckmate != true { fail(w, "flagged mate") }
                if let reply = step.reply { current = play(reply, on: current, w + " reply") }
            case .find:
                current = checkFind(step, p, w)
                if (step.ok?.count ?? 0) > 1, i + 1 < lesson.steps.count, lesson.steps[i + 1].t != .test, lesson.steps[i + 1].fen == nil {
                    fail(w, "several ok moves and the next step has no fen")
                }
            case .tap:
                checkTap(step, p, w)
            case .choose:
                let options = step.options ?? []
                if !(2...4).contains(options.count) { fail(w, "\(options.count) options") }
                for (n, o) in options.enumerated() { text(o, w + " option\(n + 1)", required: true) }
                if !options.indices.contains(step.answer ?? -1) { fail(w, "answer out of range") }
                if step.after == nil { fail(w, "needs after") }
            case .recap:
                if step.card == nil || step.name == nil { fail(w, "needs card and name") }
                if step.fen == nil { fail(w, "needs fen") }
            default: break
            }
        }
    }

    static func position(_ fen: String, _ w: String) -> Position? {
        guard let p = Position(fen: fen) else { fail(w, "FEN does not parse: \(fen)"); return nil }
        count("fens")
        if p.king(of: .white) == nil || p.king(of: .black) == nil { fail(w, "missing king: \(fen)") }
        if let k = p.king(of: p.side.opposite), !p.attackers(of: k, by: p.side).isEmpty { fail(w, "side not to move is in check: \(fen)") }
        return p
    }

    @discardableResult
    static func checkFind(_ step: LessonStep, _ p: Position, _ w: String) -> Position? {
        guard let ok = step.ok, !ok.isEmpty else { fail(w, "empty ok"); return nil }
        for (i, u) in ok.enumerated() where i > 0 { _ = play(u, on: p, w) }
        for (u, b) in step.bad ?? [:] {
            count("bad")
            if ok.contains(u) { fail(w, "\(u) is both ok and bad") }
            let after = play(u, on: p, w + " bad")
            if let r = b.reply { _ = play(r, on: after, w + " bad reply") }
            text(b.say, w + " bad \(u)", required: true)
        }
        for h in step.hints ?? [] { text(h.say, w + " hint") }
        var next = play(ok[0], on: p, w)
        if step.mate == true, next?.isCheckmate != true { fail(w, "flagged mate") }
        if let r = step.reply { next = play(r, on: next, w + " reply") }
        return next
    }

    static func checkTest(_ step: LessonStep, _ lesson: Lesson, _ w: String) {
        guard let n = step.n, let pass = step.pass, pass <= n else { fail(w, "needs n and pass"); return }
        if let items = step.items {
            if !Self.handTests.contains(lesson.id) { fail(w, "hand-written test outside \(Self.handTests.sorted())") }
            if items.count < n { fail(w, "\(items.count) items for n \(n)") }
            if !items.contains(where: { $0.decoy == true }) { fail(w, "no decoy") }
            for (j, item) in items.enumerated() {
                let iw = "\(w) item\(j + 1)"
                count("test items")
                text(item.say, iw)
                text(item.after, iw + " after")
                guard let fen = item.fen, let p = position(fen, iw) else { fail(iw, "needs fen"); continue }
                checkFind(item, p, iw)
            }
        } else {
            if Self.handTests.contains(lesson.id) { fail(w, "needs hand-written items") }
            guard let q = step.query, !q.any.isEmpty else { fail(w, "no query"); return }
            if (step.decoys ?? 0) < 1 { fail(w, "no decoy") }
            count("test queries")
            _ = q
        }
    }

    // Tap answers recomputed from the position.
    static func checkTap(_ step: LessonStep, _ p: Position, _ w: String) {
        guard let squares = step.squares, !squares.isEmpty else { fail(w, "no squares"); return }
        let want = Set(squares.compactMap(square(named:)))
        if want.count != squares.count { fail(w, "bad square in \(squares)") }
        guard let rule = step.rule else { fail(w, "no rule, answer unverified"); return }
        guard let got = compute(rule, p) else { fail(w, "unknown rule \(rule.rule)"); return }
        count("taps verified")
        if got != want { fail(w, "\(squares.sorted()) but rule gives \(got.map(squareName).sorted())") }
    }

    static func compute(_ r: LessonTapRule, _ p: Position) -> Set<Square>? {
        func side(_ s: String?) -> Side { s == "b" ? .black : .white }
        func moves(from: String?) -> [Move] { from.flatMap(square(named:)).map { p.legalMoves(from: $0) } ?? p.legalMoves() }
        switch r.rule {
        case "knightFork":
            let hops = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
            let sets = (r.targets ?? []).compactMap(square(named:)).map { t -> Set<Square> in
                Set(hops.compactMap { h -> Square? in
                    let f = t % 8 + h.0, rk = t / 8 + h.1
                    return (0..<8).contains(f) && (0..<8).contains(rk) ? rk * 8 + f : nil
                })
            }
            return sets.dropFirst().reduce(sets.first ?? []) { $0.intersection($1) }
        case "attackers":
            return square(named: r.of ?? "").map { Set(p.attackers(of: $0, by: side(r.by))) }
        case "loose":
            let s = side(r.side)
            return Set((0..<64).filter { q in
                guard let piece = p.piece(at: q), piece.side == s, piece.kind != .king, piece.kind != .pawn else { return false }
                return p.attackers(of: q, by: s).isEmpty && (r.attacked != true || !p.attackers(of: q, by: s.opposite).isEmpty)
            })
        case "mateSquares":
            return Set(p.legalMoves().filter { p.applying($0).isCheckmate }.map(\.to))
        case "checks":
            return Set(moves(from: r.from).filter { p.applying($0).inCheck }.map(\.to))
        case "dests":
            return Set(moves(from: r.from).map(\.to))
        case "pinned":
            // Pinned means: the piece stands on a line to its own king, and some enemy slider behind it would then attack the king.
            return pinned(p, side(r.side))
        case "keySquares":
            guard let pawn = square(named: r.pawn ?? "") else { return nil }
            let white = side(r.side) == .white, f = pawn % 8, rk = pawn / 8, d = white ? 1 : -1
            if f == 0 || f == 7 {
                let ff = f == 0 ? 1 : 6
                return [(white ? 7 : 0) * 8 + ff, (white ? 6 : 1) * 8 + ff]
            }
            let relative = white ? rk : 7 - rk
            let ranks = relative <= 3 ? [rk + 2 * d] : [rk + d, rk + 2 * d]
            return Set(ranks.flatMap { x in [f - 1, f, f + 1].filter { (0..<8).contains($0) }.map { x * 8 + $0 } })
        case "forkSquares":
            guard let from = square(named: r.from ?? "") else { return nil }
            let targets = (r.targets ?? []).compactMap(square(named:))
            return Set(p.legalMoves(from: from).filter { m in
                let n = p.applying(m)
                return targets.allSatisfy { n.attackers(of: $0, by: p.side).contains(m.to) }
            }.map(\.to))
        default:
            return nil
        }
    }

    static func pinned(_ p: Position, _ s: Side) -> Set<Square> {
        guard let k = p.king(of: s) else { return [] }
        var out = Set<Square>()
        let rays = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        for (df, dr) in rays {
            var f = k % 8 + df, r = k / 8 + dr
            var own: Square?
            while (0..<8).contains(f), (0..<8).contains(r) {
                let q = r * 8 + f
                if let piece = p.piece(at: q) {
                    if piece.side == s {
                        if own != nil { break }
                        own = q
                    } else {
                        let straight = df == 0 || dr == 0
                        if let own, piece.kind == .queen || piece.kind == (straight ? .rook : .bishop), p.piece(at: own)?.kind != .king { out.insert(own) }
                        break
                    }
                }
                f += df; r += dr
            }
        }
        return out
    }
}
