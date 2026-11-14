import SwiftUI

struct PuzzleView: View {
    /// Set when opened as a short themed set from Avui, which also brings a way out.
    var focus: Set<String>?
    @State private var session: PuzzleSession
    @Environment(\.dismiss) private var dismiss
    @State private var idea: String?
    @State private var board = BoardModel()
    @State private var run: PuzzleRun?
    @State private var context: AttemptContext = .blind
    @State private var phase: Phase = .loading
    @State private var delta: Double = 0
    @State private var failed = false
    @State private var hinted = false
    @State private var hintLevel = 0
    @State private var over = false
    @State private var recommended: Recommender.Pick?
    @State private var streak = 0
    @State private var replyTask: Task<Void, Never>?
    @State private var openLesson: LessonMeta?
    @State private var showChart = false

    init(focus: Set<String>? = nil) {
        self.focus = focus
        _session = State(initialValue: PuzzleSession(progress: .shared, store: .shared, focus: focus))
    }

    enum Phase { case loading, yourMove, wrong, solved, revealed }
    private var progress: Progress { .shared }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if focus != nil {
                        CloseButton { dismiss() }.padding(.horizontal, 8)
                    } else {
                        HStack {
                            Spacer()
                            Button { showChart = true } label: {
                                Label { Text("La carta") } icon: { Image("icon.rose").renderingMode(.template).resizable().frame(width: 18, height: 18) }
                                    .font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    header.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 14)
                    BoardView(board)
                    controls.padding(.horizontal, 20).padding(.top, 16)
                    if over { sessionEnd.padding(.horizontal, 20).padding(.top, 22) }
                    Spacer(minLength: 24)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .fieldBackground()
        .sheet(item: $openLesson) { l in LessonRunnerView(meta: l) }
        .fullScreenCover(isPresented: $showChart) { ChartView() }
        .task { if run == nil && !over { load() } }
    }

    private var title: String {
        switch phase {
        case .loading: return " "
        case .yourMove: return run?.puzzle.solverSide == .white ? String(localized: "Juguen les blanques") : String(localized: "Juguen les negres")
        case .wrong: return String(localized: "No és aquesta")
        case .solved: return failed ? String(localized: "Ara ja la saps") : motif
        case .revealed: return motif
        }
    }

    /// "Puzzles · 1.520", or the theme when it's a themed set.
    private var rubric: String {
        let name = focus.flatMap { $0.count == 1 ? $0.first.map(ThemeNames.name) : nil } ?? String(localized: "Puzzles")
        return progress.isProvisional ? name : name + " · " + Int(progress.rating.rounded()).formatted()
    }

    private var motif: String {
        guard let p = run?.puzzle else { return "" }
        return ThemeNames.primary(of: p.themes)
    }

    private var subtitle: String {
        if let idea, phase == .yourMove || phase == .wrong { return String(localized: "Pensa en això: \(idea).") }
        switch phase {
        case .wrong: return String(localized: "Torna-hi, o mira la solució.")
        case .solved where delta > 0.5: return String(localized: "Resolt. +\(Int(delta.rounded()))")
        case .solved where hinted: return String(localized: "Resolt amb pista. No compta per a la puntuació.")
        case .solved: return String(localized: "Resolt.")
        case .revealed where delta < -0.5: return String(localized: "\(Int(delta.rounded()))")
        case .revealed: return " "
        default: return " "
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Rubric(verbatim: rubric)
                Spacer(minLength: 8)
                SessionTrack(results: session.results, current: session.current)
            }
            BoardHeader(title: Text(verbatim: title), subtitle: Text(verbatim: subtitle), warn: phase == .wrong)
        }
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    private var controls: some View {
        HStack {
            switch phase {
            case .yourMove, .wrong:
                Button { hint() } label: { Text("Pista").font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44) }
                Spacer()
                Button { reveal() } label: { Text("Solució").font(Theme.text(17, .semibold)).foregroundStyle(Theme.tin).frame(minHeight: 44) }
            case .solved, .revealed:
                if !over {
                    Button { load() } label: {
                        Text("Següent")
                    }
                    .buttonStyle(.cartouche)
                }
            case .loading:
                Color.clear.frame(height: 44)
            }
        }
    }

    private var sessionEnd: some View {
        let solved = session.results.compactMap { $0 }.filter { $0 }.count
        return VStack(alignment: .leading, spacing: 16) {
            Text("\(solved) de \(session.results.count)").font(Theme.display(40)).foregroundStyle(Theme.tin)
            if let r = recommended {
                Button { openLesson = r.lesson } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.weak ? "Aquí se t'escapen" : "Següent al teu camí").font(Theme.text(15)).foregroundStyle(Theme.quiet)
                        Text(verbatim: r.lesson.title).font(Theme.display(32)).foregroundStyle(Theme.gold).multilineTextAlignment(.leading)
                        Text("\(r.lesson.minutes) minuts").font(Theme.text(15)).foregroundStyle(Theme.quiet)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                session = PuzzleSession(progress: .shared, store: .shared, focus: focus)
                over = false; recommended = nil; load()
            } label: {
                Text(focus == nil ? "Deu més" : "Tres més")
            }
            .buttonStyle(.cartouche)
        }
    }

    // MARK: Flow

    private func load() {
        replyTask?.cancel()
        session.harderBias = UserDefaults.standard.integer(forKey: "difficulty")
        guard let (p, ctx) = session.next() else { endSession(); return }
        run = PuzzleRun(p); context = ctx; failed = false; hinted = false; hintLevel = 0; delta = 0; idea = nil
        phase = .loading
        board.interactive = false; board.arrows = []; board.hint = nil; board.lastMove = nil
        board.orientation = p.solverSide
        board.set(p.start, animated: true)
        board.onMove = { m in userMove(m) }
        replyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(560))
            guard !Task.isCancelled else { return }
            board.play(p.line[0])
            phase = .yourMove
            board.interactive = true
        }
    }

    private func userMove(_ m: Move) {
        guard var r = run else { return }
        let outcome = r.attempt(m, on: board.position)
        run = r
        switch outcome {
        case .correct(let reply):
            board.hint = nil; board.arrows = []; hintLevel = 0
            board.play(m)
            board.interactive = false
            if phase == .wrong { phase = .yourMove }
            replyTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                if let reply { board.play(reply) }
                board.interactive = true
            }
        case .solved:
            board.hint = nil; board.arrows = []
            board.play(m)
            board.interactive = false
            if !failed {
                delta = Progress.shared.record(r.puzzle, solved: true, hinted: hinted, context: context)
                streak += 1
            } else { streak = 0 }
            session.finish(solved: !failed)
            phase = .solved
            board.reflex(from: m.to, step: streak)
            checkOver()
        case .wrong:
            board.flashWrong(m.to)
            if !failed {
                failed = true
                delta = Progress.shared.record(r.puzzle, solved: false, hinted: hinted, context: context)
                streak = 0
            }
            phase = .wrong
        }
    }

    private func hint() {
        guard let r = run, let e = r.expected else { return }
        hintLevel += 1
        hinted = true
        if hintLevel == 1, let name = ThemeNames.idea(of: r.puzzle.themes) { idea = name }
        else { board.hint = e.from; Haptics.tap(0.2, sharpness: 0.3) }
    }

    private func reveal() {
        guard let r = run else { return }
        board.interactive = false; board.hint = nil; board.arrows = []
        if !failed {
            failed = true
            delta = Progress.shared.record(r.puzzle, solved: false, hinted: hinted, context: context)
        }
        streak = 0
        session.finish(solved: false)
        replyTask?.cancel()
        phase = .revealed
        // A correct move's reply may still be pending on the board; the run has already moved past it.
        let pending = board.position.side != r.puzzle.solverSide ? [r.puzzle.line[r.step - 1]] : []
        replyTask = Task { @MainActor in
            for m in pending + r.remaining {
                guard !Task.isCancelled else { return }
                board.play(m)
                try? await Task.sleep(for: .milliseconds(620))
            }
            guard !Task.isCancelled else { return }
            checkOver()
        }
    }

    private func checkOver() {
        if session.results.allSatisfy({ $0 != nil }) { endSession() }
    }

    private func endSession() {
        over = true
        recommended = Recommender.next(progress: .shared, lessons: LessonLibrary.shared.metas, reviewEvidence: GameLibrary.shared.missedTacticEvidence)
    }
}

/// Ten small tiles: the session, drawn as a board edge.
struct SessionTrack: View {
    let results: [Bool?]
    let current: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(results.indices, id: \.self) { i in
                Rectangle()
                    .fill(results[i] == true ? Theme.gold : results[i] == false ? Color(hex: 0xEF7D6C).opacity(0.75) : (i == current ? Theme.tin.opacity(0.55) : Theme.tin.opacity(0.14)))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityElement().accessibilityLabel("Puzzle \(current + 1) de \(results.count)")
    }
}
