import SwiftUI

/// Plays one lesson. Step semantics are documented at the top of Lesson.swift.
@MainActor @Observable final class LessonRun {
    let lesson: Lesson
    let reexposure: LessonReviews.Due?
    let board = BoardModel()
    var index = -1                     // -1 is the opening card
    var message: String?
    var messageIsBad = false
    var canContinue = false
    var hintIndex = 0
    var testItems: [TestItem] = []
    var testIndex = 0
    var testSolved: [Bool] = []
    var testDone = false
    var finished = false
    /// Shown once the last step is done, before closing: the seal.
    var completed = false
    /// How the last answer went, shown in the panel that rises from the bottom.
    var feedback: Feedback?
    var picked: Int?
    private(set) var answered = 0
    private(set) var firstTry = 0
    let started = Date()
    /// Steps in the order they're played. A missed find, tap or choose is added again before the test.
    private(set) var order: [Int]
    private(set) var cursor = -1
    @ObservationIgnored private var retried = Set<Int>()
    private let starts: [Position?]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var run: PuzzleRun?
    @ObservationIgnored private var tapped = Set<Square>()
    @ObservationIgnored private var failedThis = false

    enum TestItem { case puzzle(Puzzle), step(LessonStep) }

    struct Feedback: Equatable {
        let good: Bool
        let firstTry: Bool
        /// The right option, when a wrong one was picked.
        var answer: String?
        let text: String?
    }

    init(lesson: Lesson, reexposure: LessonReviews.Due?) {
        self.lesson = lesson
        self.reexposure = reexposure
        starts = lesson.startPositions()
        order = Array(lesson.steps.indices)
        board.interactive = false
        if let first = starts.compactMap({ $0 }).first { board.set(first, animated: false) }
        // Orient for the side that plays the first find.
        if let i = lesson.steps.firstIndex(where: { $0.t == .find || $0.t == .guided }), let p = starts[i] { board.orientation = p.side }
        if reexposure != nil { startTest(reexposureCount: lesson.review.n) }
    }

    var step: LessonStep? { lesson.steps[safe: index] }
    var progress: Double { completed ? 1 : Double(max(cursor, 0)) / Double(max(order.count, 1)) }
    var isRetry: Bool { cursor > 0 && order[..<cursor].contains(index) }
    /// Its place in the whole syllabus, for the numeral on its seal.
    var number: Int { (LessonLibrary.sections.flatMap(\.lessonIDs).firstIndex(of: lesson.id) ?? 0) + 1 }
    var title: String? {
        if reexposure != nil { return nil }      // these puzzles are blind
        if index < 0 { return lesson.title.text }
        if step?.t == .recap { return step?.name?.text }
        if step?.t == .test { return testDone ? nil : String(localized: "Prova") }
        return nil
    }

    func next() {
        task?.cancel()
        count()
        let c = cursor + 1
        guard c < order.count else { finish(); return }
        cursor = c
        enter(order[c])
    }

    private func count() {
        guard let s = step, cursor >= 0, [.find, .tap, .choose].contains(s.t) else { return }
        if !isRetry { answered += 1; if !failedThis { firstTry += 1 } }
        guard failedThis, !retried.contains(index) else { return }
        retried.insert(index)
        let end = order.indices.first { $0 > cursor && [.test, .recap].contains(lesson.steps[order[$0]].t) } ?? order.count
        order.insert(index, at: end)
    }

    func cancel() { task?.cancel() }

    func skipToTest() {
        guard let c = order.firstIndex(where: { lesson.steps[$0].t == .test }) else { next(); return }
        cursor = c
        enter(order[c])
    }

    private func clear() {
        message = nil; messageIsBad = false; canContinue = false; hintIndex = 0; failedThis = false; feedback = nil; picked = nil
        board.arrows = []; board.marks = []; board.hint = nil; board.onTapSquare = nil; board.onMove = nil; board.interactive = false
        board.lastMove = nil; tapped = []
    }

    private func applyShapes(_ shapes: [LessonShape]?) {
        board.arrows = (shapes ?? []).compactMap(\.arrow)
        board.marks = (shapes ?? []).compactMap(\.mark)
    }

    private func enter(_ i: Int) {
        clear()
        index = i
        guard let s = lesson.steps[safe: i] else { return }
        if let p = starts[i], s.t != .test { board.set(p, animated: true) }
        message = s.say?.text
        switch s.t {
        case .explain, .recap:
            applyShapes(s.draw); canContinue = true
        case .choose:
            applyShapes(s.draw)
        case .watch:
            applyShapes(s.draw)
            watch(s)
        case .guided:
            applyShapes(s.draw)
            board.interactive = true
            board.onMove = { [weak self] m in self?.guided(s, m) }
        case .find:
            playFind(s) { [weak self] in self?.canContinue = true }
        case .tap:
            board.onTapSquare = { [weak self] sq in self?.tap(s, sq) }
        case .test:
            startTest(reexposureCount: nil)
        }
    }

    private func watch(_ s: LessonStep) {
        task = Task { [weak self] in
            for (n, uci) in (s.line ?? []).enumerated() {
                try? await Task.sleep(for: .milliseconds(760))
                guard !Task.isCancelled, let self else { return }
                if let m = self.board.position.move(uci: uci) {
                    self.board.play(m)
                    if s.shows?.mistakeAt == n { self.board.marks = [BoardMark(square: m.to, role: .bad)] }
                }
            }
            guard !Task.isCancelled, let self else { return }
            if s.mate == true, let m = self.board.lastMove { self.board.reflex(from: m.to) }
            self.canContinue = true
        }
    }

    private func guided(_ s: LessonStep, _ m: Move) {
        guard m.uci == s.uci || board.position.move(uci: s.uci ?? "") == m else { Haptics.tap(0.2, sharpness: 0.2); return }
        board.arrows = []; board.marks = []
        board.play(m)
        board.interactive = false
        task = Task { [weak self] in
            if let r = s.reply {
                try? await Task.sleep(for: .milliseconds(460))
                guard !Task.isCancelled, let self else { return }
                if let mv = self.board.position.move(uci: r) { self.board.play(mv) }
            }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    // MARK: Find

    private func playFind(_ s: LessonStep, solved: @escaping () -> Void) {
        board.interactive = true
        let start = board.position
        board.onMove = { [weak self] m in self?.findMove(s, m, start: start, solved: solved) }
    }

    private func findMove(_ s: LessonStep, _ m: Move, start: Position, solved: @escaping () -> Void) {
        if (s.ok ?? []).contains(where: { start.move(uci: $0) == m }) { succeed(s, m, solved: solved); return }
        board.play(m)
        board.interactive = false
        if let bad = (s.bad ?? [:]).first(where: { start.move(uci: $0.key) == m })?.value {
            failedThis = true
            message = bad.say?.text; messageIsBad = true
            task = Task { [weak self] in
                if let r = bad.reply {
                    try? await Task.sleep(for: .milliseconds(520))
                    guard !Task.isCancelled, let self else { return }
                    if let mv = self.board.position.move(uci: r) { self.board.play(mv) }
                }
                try? await Task.sleep(for: .milliseconds(1400))
                guard !Task.isCancelled, let self else { return }
                self.reset(start)
            }
            return
        }
        if let goal = s.goal {
            task = Task { [weak self] in
                let ok = await Self.meets(goal, position: start, move: m)
                guard !Task.isCancelled, let self else { return }
                if ok { self.succeed(s, m, played: true, solved: solved) } else { self.wrong(start, m) }
            }
            return
        }
        wrong(start, m)
    }

    private func wrong(_ start: Position, _ m: Move) {
        failedThis = true
        board.flashWrong(m.to)
        message = String(localized: "Aquesta no. Mira-ho un altre cop.")
        messageIsBad = true
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(620))
            guard !Task.isCancelled else { return }
            self?.reset(start)
        }
    }

    private func reset(_ p: Position) {
        board.set(p, animated: true); board.lastMove = nil; board.interactive = true
    }

    private func succeed(_ s: LessonStep, _ m: Move, played: Bool = false, solved: @escaping () -> Void) {
        if !played { board.play(m) }
        board.interactive = false
        board.reflex(from: m.to)
        messageIsBad = false
        if step?.t == .test {
            message = s.after?.text ?? String(localized: "Això mateix.")
        } else {
            message = s.say?.text
            feedback = Feedback(good: true, firstTry: !failedThis, text: s.after?.text)
        }
        task = Task { [weak self] in
            if let r = s.reply {
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled, let self else { return }
                if let mv = self.board.position.move(uci: r) { self.board.play(mv) }
            }
            guard !Task.isCancelled else { return }
            solved()
        }
    }

    /// Is the played move good enough for the step's goal? Mate in N, a kept win or a held draw.
    private static func meets(_ goal: LessonGoal, position: Position, move: Move) async -> Bool {
        let lines = try? await Engine.shared.analyse(startFEN: position.fen, moves: [move], multiPV: 1, nodes: 800_000, movetimeMs: 2500, searchMoves: nil, onUpdate: nil)
        guard let score = lines?.first?.score else { return false }
        // The score belongs to the side now to move, so the mover wants it negative.
        switch score {
        case .mate(let n):
            if n <= 0 { return goal.mate.map { -n + 1 <= $0 } ?? (goal.win == true || goal.draw == true) }
            return false
        case .cp(let c):
            if goal.mate != nil { return false }
            if goal.win == true { return c < -250 }
            if goal.draw == true { return c < 70 }
            return false
        }
    }

    func hint() {
        guard let s = currentFind, let hints = s.hints, hintIndex < hints.count else { return }
        let h = hints[hintIndex]; hintIndex += 1
        if let t = h.say?.text { message = t; messageIsBad = false }
        if let d = h.draw { applyShapes(d) }
        failedThis = true
        Haptics.tap(0.2, sharpness: 0.3)
    }
    var hasHint: Bool { (currentFind?.hints?.count ?? 0) > hintIndex && !canContinue }
    private var currentFind: LessonStep? { step?.t == .find ? step : nil }

    // MARK: Tap

    private func tap(_ s: LessonStep, _ sq: Square) {
        let answers = Set((s.squares ?? []).compactMap(square(named:)))
        if answers.contains(sq) {
            tapped.insert(sq)
            board.marks.append(BoardMark(square: sq, role: .good))
            Sound.place(); Haptics.place()
            if tapped == answers {
                board.onTapSquare = nil
                board.reflex(from: sq)
                feedback = Feedback(good: true, firstTry: !failedThis, text: s.after?.text)
                canContinue = true
            }
        } else {
            failedThis = true
            board.flashWrong(sq)
        }
    }

    // MARK: Choose

    func choose(_ option: Int) {
        guard let s = step, s.t == .choose, picked == nil, let options = s.options else { return }
        picked = option
        let right = option == s.answer
        if right { Sound.place(); Haptics.place() } else { failedThis = true; Sound.wrong(); Haptics.wrong() }
        feedback = Feedback(good: right, firstTry: right, answer: right ? nil : options[safe: s.answer ?? 0]?.text, text: s.after?.text)
        canContinue = true
    }

    // MARK: Test

    func startTest(reexposureCount: Int?) {
        let testStep = lesson.steps.first { $0.t == .test }
        guard let testStep else { finish(); return }
        if let items = testStep.items {
            let count = reexposureCount ?? items.count
            let exposure = reexposure?.exposure ?? 0
            testItems = (0..<min(count, items.count)).map { .step(items[(exposure * 2 + $0) % items.count]) }
        } else {
            var t = testStep
            if let c = reexposureCount { t.n = c; t.decoys = 0 }
            let store = PuzzleStore.shared
            testItems = t.drawTest(rating: Progress.shared.rating, store: store, played: { Progress.shared.played($0) }).map { .puzzle($0) }
        }
        testIndex = 0; testSolved = []; testDone = false
        if reexposureCount != nil { index = lesson.steps.count - 1 }
        playTestItem()
    }

    private func playTestItem() {
        clear()
        guard let item = testItems[safe: testIndex] else { endTest(); return }
        switch item {
        case .puzzle(let p):
            board.orientation = p.solverSide
            board.set(p.start, animated: true)
            run = PuzzleRun(p)
            task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled, let self else { return }
                self.board.play(p.line[0])
                self.board.interactive = true
                self.board.onMove = { [weak self] m in self?.testPuzzleMove(p, m) }
            }
        case .step(let s):
            if let f = s.fen, let pos = Position(fen: f) {
                board.orientation = pos.side
                board.set(pos, animated: true)
            }
            message = s.say?.text
            playFind(s) { [weak self] in self?.finishTestItem(solved: !(self?.failedThis ?? true)) }
        }
    }

    private func testPuzzleMove(_ p: Puzzle, _ m: Move) {
        guard var r = run else { return }
        let outcome = r.attempt(m, on: board.position)
        run = r
        switch outcome {
        case .correct(let reply):
            board.play(m); board.interactive = false
            task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled, let self else { return }
                if let reply { self.board.play(reply) }
                self.board.interactive = true
            }
        case .solved:
            board.play(m); board.interactive = false
            board.reflex(from: m.to)
            let solved = !failedThis
            if solved { _ = Progress.shared.record(p, solved: true, hinted: false, context: .lesson) }
            task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1100))
                guard !Task.isCancelled else { return }
                self?.finishTestItem(solved: solved)
            }
        case .wrong:
            board.flashWrong(m.to)
            if !failedThis {
                failedThis = true
                _ = Progress.shared.record(p, solved: false, hinted: false, context: .lesson)
                message = String(localized: "Aquesta no. Torna-hi.")
                messageIsBad = true
            }
        }
    }

    private func finishTestItem(solved: Bool) {
        testSolved.append(solved)
        testIndex += 1
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            self?.playTestItem()
        }
    }

    private func endTest() {
        if reexposure != nil {
            if !testSolved.isEmpty { LessonReviews.shared.record(lesson.id, solved: testSolved) }
            finished = true
            return
        }
        testDone = true
        let good = testSolved.filter { $0 }.count
        answered += testSolved.count
        firstTry += good
        let pass = lesson.steps.first { $0.t == .test }?.pass ?? 0
        message = good >= pass
            ? String(localized: "\(good) de \(testSolved.count). Ho tens. Ho tornaràs a veure d'aquí a uns dies.")
            : String(localized: "\(good) de \(testSolved.count). Ho tornaràs a veure d'aquí a uns dies, sense pressa.")
        messageIsBad = false
        canContinue = true
    }

    private func finish() {
        Progress.shared.completedLessons.insert(lesson.id)
        Progress.shared.save()
        LessonReviews.shared.markCompleted(lesson.id, days: lesson.review.days)
        completed = true
    }
}

struct LessonRunnerView: View {
    let meta: LessonMeta
    var reexposure: LessonReviews.Due?
    @State private var run: LessonRun?
    @State private var stamped = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let run {
                if run.completed { seal(run) } else { content(run) }
            } else { Theme.field }
        }
        .background(Theme.field.ignoresSafeArea())
        .onAppear {
            guard run == nil, let l = LessonLibrary.shared.lesson(id: meta.id) else { return }
            run = LessonRun(lesson: l, reexposure: reexposure)
            #if DEBUG
            // The screenshot of a lesson: its first question, answered wrong, so the panel shows the right one and why.
            if ScreenshotScene.is("lesson"), let r = run, let q = l.steps.firstIndex(where: { $0.t == .choose }) {
                while r.index != q { r.next() }
                r.choose(((l.steps[q].answer ?? 0) + 1) % (l.steps[q].options?.count ?? 1))
            }
            #endif
        }
        .onChange(of: run?.finished ?? false) { _, done in if done { dismiss() } }
    }

    private func content(_ r: LessonRun) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.tin).frame(width: 44, height: 44) }
                    .accessibilityLabel("Tanca")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule().fill(Theme.gold).frame(width: max(g.size.width * r.progress, r.progress > 0 ? 8 : 0))
                            .animation(.easeOut(duration: 0.25), value: r.progress)
                    }
                }
                .frame(height: 8)
                .padding(.trailing, 12)
                .accessibilityElement().accessibilityLabel("Progrés").accessibilityValue(Text(r.progress, format: .percent.precision(.fractionLength(0))))
            }
            .padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if r.isRetry { Text("Un altre cop").font(Theme.text(15, .semibold)).foregroundStyle(Theme.gold) }
                    if let t = r.title { Text(verbatim: t).font(Theme.display(40)).foregroundStyle(Theme.tin).fixedSize(horizontal: false, vertical: true) }
                    if r.index < 0 {
                        Text("\(meta.minutes) minuts").font(Theme.text(17)).foregroundStyle(Theme.quiet)
                    }
                    if let m = r.message {
                        SANText.prose(m, size: 19).font(Theme.text(19)).foregroundStyle(r.messageIsBad ? Color(hex: 0xEF7D6C) : Theme.tin).accessibilityLabel(m)
                            .fixedSize(horizontal: false, vertical: true).contentTransition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 6)
            }
            .frame(height: 138)
            .animation(.easeOut(duration: 0.2), value: r.message)
            BoardView(r.board)
            bottom(r).padding(.horizontal, 20).padding(.top, 14)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            if let f = r.feedback {
                FeedbackPanel(feedback: f) { r.next() }.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: r.feedback)
        .onDisappear { r.cancel() }
    }

    @ViewBuilder private func bottom(_ r: LessonRun) -> some View {
        if r.index < 0 && r.reexposure == nil {
            VStack(spacing: 8) {
                primary("Comença") { r.next() }
                if r.lesson.steps.contains(where: { $0.t == .test }) {
                    Button("Ja ho sé: vés a la prova") { r.skipToTest() }.font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                }
            }
        } else if r.feedback != nil {
            EmptyView()
        } else if r.step?.t == .choose, let options = r.step?.options {
            VStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { i in
                    Button { r.choose(i) } label: {
                        Text(verbatim: options[i].text).font(Theme.text(17)).foregroundStyle(Theme.tin).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 16)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.tin.opacity(0.28), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if r.canContinue {
            primary(r.cursor >= r.order.count - 1 ? "Acaba" : "Continua") { r.next() }
        } else if r.hasHint {
            Button("Pista") { r.hint() }.font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
        }
    }

    /// The end of a lesson: a seal pressed into wax, and how it went.
    private func seal(_ r: LessonRun) -> some View {
        let minutes = max(1, Int((Date().timeIntervalSince(r.started) / 60).rounded()))
        return VStack(spacing: 0) {
            Spacer()
            WaxSeal(numeral: Roman.numeral(r.number), size: 176)
                .scaleEffect(stamped ? 1 : 1.35).opacity(stamped ? 1 : 0)
            Text("Lliçó apresa").font(Theme.display(46)).foregroundStyle(Theme.tin).padding(.top, 30)
            Text(verbatim: r.lesson.title.text).font(Theme.text(19)).foregroundStyle(Theme.quiet).multilineTextAlignment(.center).padding(.top, 2)
            if r.answered > 0 {
                Text("\(r.firstTry) de \(r.answered) a la primera, en \(minutes) min.").font(Theme.text(17)).foregroundStyle(Theme.gold).padding(.top, 18)
            }
            Spacer()
            primary("Continua") { r.finished = true }.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { stamped = true }
            Haptics.capture(); Sound.capture()
        }
    }

    private func primary(_ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
        }
    }
}

/// Rises from the bottom after an answer: right or not, the right one, and why.
private struct FeedbackPanel: View {
    let feedback: LessonRun.Feedback
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(feedback.good ? (feedback.firstTry ? "Això mateix" : "Ara sí") : "No ben bé")
                .font(Theme.display(30)).foregroundStyle(feedback.good ? Theme.gold : Color(hex: 0xEF7D6C))
            if let answer = feedback.answer {
                Text("La bona: \(answer)").font(Theme.text(17, .semibold)).foregroundStyle(Theme.tin).fixedSize(horizontal: false, vertical: true)
            }
            if let text = feedback.text {
                SANText.prose(text, size: 17).font(Theme.text(17)).foregroundStyle(Theme.tin.opacity(0.88)).accessibilityLabel(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: next) {
                Text("Continua").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(feedback.good ? Theme.gold : Theme.tin))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fieldDeep.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
    }
}
