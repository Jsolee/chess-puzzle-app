import SwiftUI

struct PuzzleView: View {
    @State private var session = PuzzleSession(progress: .shared, store: .shared)
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
    @State private var showDaily = false

    enum Phase { case loading, yourMove, wrong, solved, revealed }
    private var progress: Progress { .shared }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DailyRow { showDaily = true }.padding(.horizontal, 20)
                    Spacer(minLength: 8)
                    header.padding(.horizontal, 20).padding(.bottom, 14)
                    BoardView(board)
                    controls.padding(.horizontal, 20).padding(.top, 16)
                    if over { sessionEnd.padding(.horizontal, 20).padding(.top, 22) }
                    Spacer(minLength: 24)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.field.ignoresSafeArea())
        .sheet(item: $openLesson) { l in LessonRunnerView(meta: l) }
        .fullScreenCover(isPresented: $showDaily) { DailyPuzzleView() }
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

    private var motif: String {
        guard let p = run?.puzzle else { return "" }
        return ThemeNames.primary(of: p.themes)
    }

    private var subtitle: String {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title).font(Theme.display(46)).foregroundStyle(Theme.tin)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                if !progress.isProvisional {
                    Text(verbatim: "\(Int(progress.rating.rounded()))").font(Theme.text(17, .medium)).foregroundStyle(Theme.quiet).accessibilityLabel("Puntuació \(Int(progress.rating.rounded()))")
                }
            }
            HStack(alignment: .center) {
                Text(verbatim: subtitle).font(Theme.text(16)).foregroundStyle(phase == .wrong ? Color(hex: 0xEF7D6C) : Theme.quiet).contentTransition(.opacity)
                Spacer()
                SessionTrack(results: session.results, current: session.current)
            }
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
                        Text("Següent").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
                    }
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
                session = PuzzleSession(progress: .shared, store: .shared)
                over = false; recommended = nil; load()
            } label: {
                Text("Deu més").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
            }
        }
    }

    // MARK: Flow

    private func load() {
        replyTask?.cancel()
        session.harderBias = UserDefaults.standard.integer(forKey: "difficulty")
        guard let (p, ctx) = session.next() else { endSession(); return }
        run = PuzzleRun(p); context = ctx; failed = false; hinted = false; hintLevel = 0; delta = 0
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
        if hintLevel == 1 { board.hint = e.from; Haptics.tap(0.2, sharpness: 0.3) }
        else { board.arrows = [BoardArrow(from: e.from, to: e.to, role: .idea)] }
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
