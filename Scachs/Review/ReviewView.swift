import SwiftUI

@MainActor @Observable final class ReviewModel {
    let game: ImportedGame
    let board = BoardModel()
    var review: GameReview?
    var replay: GameReplay?
    var running = false
    var progress = 0.0
    var liveEvals: [Score?] = []
    var failure: String?
    var walking = false
    var ply = 0 { didSet { engineTask?.cancel(); analysisRun += 1; lines = [] } }
    var lines: [EngineLine] = []
    var showLines = false
    /// Moves tried on the board from a position of the game, each judged by the engine once it has looked.
    var branch: [Step] = []
    /// How many of the branch's moves are on the board.
    var branchAt = 0
    struct Step { var move: Move; var san: String; var after: Position; var verdict: BranchVerdict? }
    var retrying = false
    var retryState: RetryState = .idle
    var retryIdea: String?
    var showingLine = false
    /// The ply of your move to go back and play from, when asked.
    var replayFrom: Int?
    enum RetryState { case idle, thinking, wrong, right }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    @ObservationIgnored private var lineTask: Task<Void, Never>?
    @ObservationIgnored private var analysisRun = 0
    @ObservationIgnored private var retryHints = 0
    /// Moments already put to you, so walking back and forth doesn't ask twice.
    @ObservationIgnored private var asked: Set<Int> = []
    @ObservationIgnored private var holdsAuto = false
    @ObservationIgnored private var ratings = Ratings()
    @ObservationIgnored private var branchRoot = Position.start
    /// The game ply whose position the branch grows from, when it does.
    @ObservationIgnored private var branchRootPly: Int?
    @ObservationIgnored private var searches: [Position: [EngineLine]] = [:]

    init(game: ImportedGame) {
        self.game = game
        board.orientation = game.mySide ?? .white
        board.interactive = false
    }

    private var pgn: PGNGame? { PGN.parse(game.pgn).first }
    var move: GameReview.ReviewedMove? { ply > 0 ? review?.moves[safe: ply - 1] : nil }
    var graph: [Double?] {
        if let g = review?.graph, !g.isEmpty { return g }
        return liveEvals.enumerated().map { i, s in s.map { Accuracy.winPercent($0) } }
    }

    func start() {
        guard review == nil, task == nil else { return }
        guard let pgn, let r = try? GameReplay(pgn) else { failure = String(localized: "Aquesta partida no es pot llegir."); return }
        replay = r
        ratings = Ratings(game: pgn, fallback: Int(Progress.shared.rating))
        board.set(r.positions[0], animated: false)
        if let saved = GameLibrary.shared.review(for: game.id), saved.isComplete { review = saved.relocalized(replay: r); return }
        runEngine(pgn)
    }

    private func runEngine(_ pgn: PGNGame) {
        running = true; failure = nil
        if !holdsAuto { holdsAuto = true; AutoReview.shared.hold() }
        let ratings = Ratings(game: pgn, fallback: Int(Progress.shared.rating))
        let id = game.id
        task = Task { [weak self] in
            do {
                let result = try await ReviewEngine.review(game: pgn, ratings: ratings, evals: { e in
                    Task { @MainActor in self?.liveEvals = e; self?.followEngine() }
                }, progress: { p in
                    Task { @MainActor in self?.progress = p }
                })
                guard let self else { return }
                try? GameLibrary.shared.save(result, for: id)
                withAnimation(.easeOut(duration: 0.3)) { self.review = result; self.running = false }
                Haptics.place()
            } catch is CancellationError {
                self?.running = false
            } catch {
                self?.running = false
                self?.failure = String(localized: "L'anàlisi s'ha aturat. Torna-ho a provar.")
            }
            self?.task = nil
        }
    }

    /// The board replays the game as the engine reads it, so the wait has something to watch.
    private func followEngine() {
        guard let r = replay, !walking else { return }
        let done = liveEvals.prefix { $0 != nil }.count - 1
        if done > ply, done < r.positions.count, ply < r.moves.count, board.position == r.positions[ply] {
            board.play(r.moves[ply], quiet: true)
            ply += 1
        }
    }

    func stop() {
        task?.cancel(); task = nil; engineTask?.cancel(); lineTask?.cancel()
        if holdsAuto { holdsAuto = false; AutoReview.shared.release() }
    }
    func retryEngine() { if let pgn { runEngine(pgn) } }

    // MARK: Walking through

    func beginWalk() { walking = true; visit(firstKey() ?? 1) }

    /// Going to a key moment of your own asks before it tells: seeing the answer on demand costs real learning.
    /// Stepping through by hand stays free, so nothing is ever hidden behind a question.
    private func visit(_ target: Int) {
        guard game.mySide != nil, let m = review?.moves[safe: target - 1], m.side == game.mySide, m.bestMove != nil,
              let c = m.moveClass, [.mistake, .miss, .blunder].contains(c), asked.insert(target).inserted else { go(target); return }
        branch = []; branchAt = 0
        ply = target
        beginRetry()
    }
    private func firstKey() -> Int? { review?.moves.first { $0.isKey }.map { $0.ply + 1 } }

    func go(_ target: Int, sound: Bool = true) {
        guard let r = replay else { return }
        let n = max(0, min(r.positions.count - 1, target))
        lineTask?.cancel(); showingLine = false
        retrying = false; retryState = .idle; branch = []; branchAt = 0; board.hint = nil
        board.interactive = true
        board.onMove = { [weak self] m in self?.exploreMove(m) }
        if n == ply + 1, board.position == r.positions[ply] {
            board.play(r.moves[ply], quiet: !sound)
        } else {
            board.set(r.positions[n], animated: abs(n - ply) < 6)
            board.lastMove = n > 0 ? r.moves[n - 1] : nil
        }
        ply = n
        decorate()
        if showLines { think() }
    }

    func decorate() {
        if !branch.isEmpty {
            guard branchAt > 0, let v = branch[branchAt - 1].verdict else { board.arrows = []; board.marks = []; board.badge = nil; return }
            board.arrows = v.note.arrows; board.marks = v.note.marks; board.badge = (branch[branchAt - 1].move.to, v.moveClass)
            return
        }
        guard let m = move else { board.arrows = []; board.marks = []; board.badge = nil; return }
        board.arrows = m.coach?.arrows ?? []
        board.marks = m.coach?.marks ?? []
        if let c = m.moveClass, let mv = Move(uci: m.uci) { board.badge = (mv.to, c) } else { board.badge = nil }
    }

    func next() { branch.isEmpty ? go(ply + 1) : stepBranch(to: branchAt + 1) }
    func previous() { branch.isEmpty ? go(ply - 1, sound: false) : branchAt == 0 ? backToGame() : stepBranch(to: branchAt - 1) }
    func nextKey() {
        if let k = review?.moves.first(where: { $0.isKey && $0.ply + 1 > ply }) { visit(k.ply + 1) } else { go((replay?.positions.count ?? 1) - 1) }
    }

    func showBest() {
        guard let m = move, let b = m.bestMove else { return }
        lineTask?.cancel(); showingLine = false
        if let r = replay { board.set(r.positions[ply - 1], animated: true); board.lastMove = nil }
        board.badge = nil; board.marks = []
        board.arrows = [BoardArrow(from: b.from, to: b.to, role: .best)]
    }

    /// The Show button: plays the coach's line on the board, then waits.
    func playCoachLine() {
        guard let m = move, let note = m.coach, let r = replay else { return }
        lineTask?.cancel()
        showingLine = true
        let start = note.lineStartsAfterMove ? r.positions[ply] : r.positions[ply - 1]
        board.set(start, animated: true); board.arrows = []; board.badge = nil; board.marks = []
        lineTask = Task { [weak self] in
            for mv in note.line {
                try? await Task.sleep(for: .milliseconds(620))
                guard !Task.isCancelled, let self else { return }
                self.board.play(mv)
            }
        }
    }
    func hideCoachLine() { lineTask?.cancel(); showingLine = false; go(ply, sound: false); }

    // MARK: Retry

    var canRetry: Bool {
        guard let m = move, let c = m.moveClass, m.bestMove != nil else { return false }
        return [.inaccuracy, .mistake, .miss, .blunder].contains(c) && (game.mySide == nil || m.side == game.mySide)
    }

    func beginRetry() {
        guard let r = replay, ply > 0 else { return }
        lineTask?.cancel(); showingLine = false; engineTask?.cancel(); lines = []; showLines = false
        retrying = true; retryState = .idle; retryIdea = nil; retryHints = 0
        board.hint = nil
        board.set(r.positions[ply - 1], animated: true)
        board.arrows = []; board.marks = []; board.badge = nil; board.lastMove = nil
        board.interactive = true
        board.onMove = { [weak self] m in self?.retryMove(m) }
    }

    /// The idea first, then the piece. The move itself only comes from asking for it.
    func retryHint() {
        guard let m = move, let best = m.bestMove, let r = replay else { return }
        retryHints += 1
        if retryHints == 1, let tag = GameLibrary.motifTag(on: r.positions[ply - 1], line: m.bestLine) {
            retryIdea = ThemeNames.name(tag)
        } else {
            board.hint = best.from
            Haptics.tap(0.2, sharpness: 0.3)
        }
    }

    private func retryMove(_ m: Move) {
        board.hint = nil
        engineTask?.cancel()
        guard let r = replay, let rm = move, let best = rm.evalBefore else { return }
        let isBest = rm.bestMove == m
        board.play(m)
        board.interactive = false
        if isBest { accept(m); return }
        retryState = .thinking
        let rating = rm.side == .white ? r.game.tags["WhiteElo"].flatMap(Int.init) : r.game.tags["BlackElo"].flatMap(Int.init)
        let bestForMover = rm.side == .white ? best : best.flipped
        engineTask = Task { [weak self] in
            let ok = (try? await RetryCheck.check(m, startFEN: r.startFEN, moves: Array(r.moves.prefix(rm.ply)), best: bestForMover, rating: rating)) ?? false
            guard let self, !Task.isCancelled else { return }
            if ok { self.accept(m) } else {
                self.retryState = .wrong
                self.board.flashWrong(m.to)
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                self.board.set(r.positions[rm.ply], animated: true); self.board.lastMove = nil
                self.board.interactive = true
            }
        }
    }

    private func accept(_ m: Move) {
        retryState = .right
        board.reflex(from: m.to)
    }

    // MARK: Free analysis

    func toggleLines() {
        guard retryState != .thinking else { return }
        showLines.toggle()
        think()
    }

    /// A move on the board starts a branch, or grows it from the move shown, dropping what came after.
    private func exploreMove(_ m: Move) {
        let before = board.position
        if branch.isEmpty {
            branchRoot = before
            branchRootPly = replay.flatMap { r in [ply, ply - 1].first { r.positions.indices.contains($0) && r.positions[$0] == before } }
        }
        branch.removeSubrange(branchAt...)
        branch.append(Step(move: m, san: before.san(m), after: before.applying(m)))
        branchAt = branch.count
        board.play(m)
        decorate()
        think()
    }

    func stepBranch(to target: Int) {
        let n = max(0, min(branch.count, target))
        guard n != branchAt else { return }
        if n == branchAt + 1 { board.play(branch[branchAt].move) } else {
            board.set(n == 0 ? branchRoot : branch[n - 1].after, animated: abs(n - branchAt) < 6)
            board.lastMove = n > 0 ? branch[n - 1].move : nil
        }
        branchAt = n
        decorate()
        think()
    }

    /// White's score where the board stands in the branch, once the engine has looked.
    var branchEval: Score? {
        if branchAt > 0, let v = branch[branchAt - 1].verdict { return v.evalAfter }
        return searches[board.position]?.first.map { $0.score.whitePOV(sideToMove: board.position.side) }
    }

    /// Taps on a candidate line play its first move as a variation, to look further from there.
    func tryCandidate(_ line: EngineLine) {
        guard !retrying, let m = line.pv.first, board.position.isLegal(m) else { return }
        exploreMove(m)
    }

    func backToGame() { go(ply, sound: false) }

    /// One queue for the engine: the branch's verdicts, oldest first, then the open-ended look for the lines.
    private func think() {
        engineTask?.cancel()
        analysisRun += 1
        let run = analysisRun
        lines = searches[board.position] ?? []
        engineTask = Task { [weak self] in
            while let i = self?.branch.firstIndex(where: { $0.verdict == nil }) {
                guard let v = await self?.judge(i), !Task.isCancelled, self?.analysisRun == run else { return }
                self?.branch[i].verdict = v
                self?.decorate()
                if let me = self, me.lines.isEmpty { me.lines = me.searches[me.board.position] ?? [] }
            }
            // What the board shows, which isn't always the game's position: a best-move preview or a coach line.
            guard self?.showLines == true, let fen = self?.board.position.fen else { return }
            let result = try? await Engine.shared.analyse(startFEN: fen, moves: [], multiPV: 3, nodes: nil, movetimeMs: 15000, searchMoves: nil) { lines in
                Task { @MainActor in if self?.analysisRun == run { self?.lines = lines } }
            }
            if let result, !Task.isCancelled, self?.analysisRun == run { self?.lines = result }
        }
    }

    private func judge(_ i: Int) async -> BranchVerdict? {
        guard let r = replay, branch.indices.contains(i) else { return nil }
        let step = branch[i]
        let before = i == 0 ? branchRoot : branch[i - 1].after
        guard let b = await search(before), let a = await search(step.after),
              branch.indices.contains(i), branch[i].after == step.after else { return nil }
        var trail = [branchRoot], moves: [Move] = []
        if let k = branchRootPly { trail = Array(r.positions[...k]); moves = Array(r.moves[..<k]) }
        trail += branch[..<i].map(\.after); moves += branch[..<i].map(\.move)
        var previous: MoveFacts.Previous?
        if trail.count > 1 {
            let earlier = trail[trail.count - 2], game = review?.moves[safe: trail.count - 2]
            previous = MoveFacts.Previous(
                before: earlier, move: moves[moves.count - 1],
                epLost: (i > 0 ? branch[i - 1].verdict?.epLost : game?.epLost) ?? 0,
                evalBefore: i > 0 ? searches[earlier]?.first?.score.flipped : game?.evalBefore?.whitePOV(sideToMove: before.side))
        }
        return BranchJudge.judge(trail: trail, moves: moves, move: step.move, rating: ratings.rating(for: before.side),
                                 before: b, after: a, previous: previous)
    }

    private func search(_ p: Position) async -> [EngineLine]? {
        if let s = searches[p] { return s }
        guard let lines = try? await Engine.shared.analyse(
            startFEN: p.fen, moves: [], multiPV: 3, nodes: Engine.budget(BranchJudge.nodes),
            movetimeMs: BranchJudge.movetimeMs, searchMoves: nil, onUpdate: nil), !lines.isEmpty, !Task.isCancelled else { return nil }
        searches[p] = lines
        return lines
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

private struct ReplayStart: Identifiable { let ply: Int; var id: Int { ply } }

struct ReviewView: View {
    @State private var model: ReviewModel
    init(game: ImportedGame) { _model = State(initialValue: ReviewModel(game: game)) }

    var body: some View {
        Group {
            if model.walking, model.review != nil { WalkthroughView(model: model) }
            else if let r = model.review { ReviewSummary(model: model, review: r) }
            else { ReviewProgress(model: model) }
        }
        .fieldBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: Binding(get: { model.replayFrom.map(ReplayStart.init) }, set: { model.replayFrom = $0?.ply })) { start in
            if let replay = model.replay { ReplayGameView(game: model.game, replay: replay, ply: start.ply) }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

/// While the engine works: the graph draws itself as evaluations arrive.
struct ReviewProgress: View {
    let model: ReviewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analitzant").font(Theme.display(52)).foregroundStyle(Theme.tin)
            Text(verbatim: "\(Int(model.progress * 100)) %").font(Theme.text(22, .medium)).foregroundStyle(Theme.gold).contentTransition(.numericText())
            EvalGraph(values: paddedGraph).frame(height: 92).wireFrame()
            BoardView(model.board, showCoordinates: false).padding(.horizontal, -20).padding(.vertical, 6)
            if let f = model.failure {
                Text(verbatim: f).font(Theme.text(16)).foregroundStyle(Color(hex: 0xEF7D6C))
                Button("Torna-ho a provar") { model.retryEngine() }.font(Theme.text(17, .semibold))
            } else {
                Text("Stockfish corre al teu iPhone. Pots sortir: seguirà on ho ha deixat.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
            }
            Spacer()
        }
        .padding(20)
    }
    private var paddedGraph: [Double?] {
        let g = model.graph
        let n = model.replay?.positions.count ?? g.count
        return g + Array(repeating: nil, count: max(0, n - g.count))
    }
}

struct ReviewSummary: View {
    let model: ReviewModel
    let review: GameReview
    private static let order: [MoveClass] = [.brilliant, .great, .best, .excellent, .good, .book, .inaccuracy, .mistake, .miss, .blunder]
    @State private var allClasses = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: review.opening.map { OpeningNames.local($0.name) } ?? String(localized: "Revisió")).font(Theme.display(32)).foregroundStyle(Theme.tin)
                        .lineLimit(3).minimumScaleFactor(0.7)
                    Text(verbatim: "\(model.game.white) – \(model.game.black) · \(model.game.result) · \(model.game.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(Theme.text(15)).foregroundStyle(Theme.quiet)
                }
                EvalGraph(values: review.graph, marks: keyMarks).frame(height: 92).wireFrame()
                players
                table
                if !review.phases.isEmpty { phases }
                Button { model.beginWalk() } label: {
                    Text("Revisa la partida")
                }
                .buttonStyle(.cartouche)
                HStack(spacing: 18) {
                    ShareLink(item: model.game.pgn, preview: SharePreview("\(model.game.white) – \(model.game.black)")) {
                        Text("Comparteix el PGN")
                    }
                    Button("Torna-la a jugar") { model.replayFrom = review.moves.first { $0.isKey && $0.side == model.game.mySide }?.ply ?? 0 }
                }
                .font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold)
                Text("Etiquetes i precisió calculades per aquesta app amb \(review.engine.name). Poden no coincidir amb les d'altres serveis.")
                    .font(Theme.text(13)).foregroundStyle(Theme.quiet)
            }
            .padding(20)
        }
    }

    private var keyMarks: [(ply: Int, cls: MoveClass)] {
        review.moves.compactMap { m in
            guard let c = m.moveClass, [.brilliant, .great, .miss, .blunder, .mistake].contains(c) else { return nil }
            return (m.ply + 1, c)
        }
    }

    private var players: some View {
        HStack(alignment: .top) {
            playerColumn(model.game.white, review.white, .leading)
            Spacer()
            playerColumn(model.game.black, review.black, .trailing)
        }
    }

    private func playerColumn(_ name: String, _ p: GameReview.PlayerReview, _ a: HorizontalAlignment) -> some View {
        let white = a == .leading
        let won = model.game.result == (white ? "1-0" : "0-1")
        return VStack(alignment: a, spacing: 2) {
            HStack(spacing: 7) {
                if !white { Text(verbatim: name).foregroundStyle(won ? Theme.gold : Theme.quiet) }
                Rectangle().fill(white ? Theme.tin : Theme.ink).frame(width: 9, height: 9)
                    .overlay(Rectangle().strokeBorder(Theme.tin.opacity(white ? 0 : 0.5), lineWidth: 1))
                if white { Text(verbatim: name).foregroundStyle(won ? Theme.gold : Theme.quiet) }
            }
            .font(Theme.text(15)).lineLimit(1)
            Text(verbatim: p.accuracy.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
                .font(Theme.text(50, .medium)).foregroundStyle(Theme.tin)
            if let r = p.gameRating {
                Text("Nivell d'aquesta partida: \(r)").font(Theme.text(13)).foregroundStyle(Theme.quiet)
            }
        }
    }

    /// Each class as two bars facing each other, one per player, on the same scale. Empty classes stay out until asked for.
    private var table: some View {
        let counts = Self.order.map { (c: $0, w: review.white.counts[$0] ?? 0, b: review.black.counts[$0] ?? 0) }
        let top = CGFloat(max(counts.map { max($0.w, $0.b) }.max() ?? 1, 1))
        let shown = allClasses ? counts : counts.filter { $0.w + $0.b > 0 }
        return VStack(spacing: 0) {
            ForEach(shown, id: \.c) { r in
                HStack(spacing: 8) {
                    Text(verbatim: "\(r.w)").font(Theme.text(17, .medium)).foregroundStyle(r.w > 0 ? r.c.fill : Theme.quiet.opacity(0.5)).frame(width: 26, alignment: .leading)
                    bar(r.w, of: top, r.c.fill).frame(maxWidth: .infinity, alignment: .trailing)
                    HStack(spacing: 6) {
                        Text(verbatim: r.c.displayName).font(Theme.text(15)).foregroundStyle(Theme.tin.opacity(0.86))
                        MoveClassBadge(cls: r.c, size: 20)
                    }
                    .fixedSize()
                    bar(r.b, of: top, r.c.fill).frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: "\(r.b)").font(Theme.text(17, .medium)).foregroundStyle(r.b > 0 ? r.c.fill : Theme.quiet.opacity(0.5)).frame(width: 26, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            if counts.contains(where: { $0.w + $0.b == 0 }) {
                Button { withAnimation(.easeOut(duration: 0.2)) { allClasses.toggle() } } label: {
                    Text(allClasses ? "Amaga les classes buides" : "Mostra les deu classes").font(Theme.text(15, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                }
            }
        }
    }

    private func bar(_ n: Int, of top: CGFloat, _ color: Color) -> some View {
        Rectangle().fill(color).frame(width: n > 0 ? max(4, 48 * CGFloat(n) / top) : 0, height: 6)
    }

    private var phases: some View {
        VStack(spacing: 0) {
            ForEach(review.phases) { ph in
                HStack {
                    phaseBadge(ph.white).frame(width: 34, alignment: .leading)
                    Spacer()
                    Text(verbatim: ph.phase.displayName).font(Theme.text(15)).foregroundStyle(Theme.tin.opacity(0.86))
                    Spacer()
                    phaseBadge(ph.black).frame(width: 34, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder private func phaseBadge(_ g: GameReview.PhaseReview.Grade) -> some View {
        if let c = g.grade { MoveClassBadge(cls: c, size: 22) } else { Text(verbatim: "–").foregroundStyle(Theme.quiet) }
    }
}

struct WalkthroughView: View {
    @Bindable var model: ReviewModel
    @AppStorage("branchTried") private var branchTried = false

    var body: some View {
        ScrollView {
        VStack(spacing: 0) {
            coach.frame(minHeight: 118, alignment: .topLeading).padding(.horizontal, 16).padding(.bottom, 8)
            HStack(spacing: 0) {
                EvalBar(winPercent: currentWin, label: evalLabel, flipped: model.board.orientation == .black).frame(width: 12)
                BoardView(model.board)
            }
            .fixedSize(horizontal: false, vertical: true)
            if model.showLines { engineLines }
            EvalGraph(values: model.review?.graph ?? [], marks: marks, current: model.ply) { i in
                if i != model.ply { model.go(i, sound: false); Haptics.step() }
            }
            .frame(height: 46).padding(.horizontal, 16).padding(.top, 10)
            Group { if model.branch.isEmpty { moveStrip } else { branchStrip } }.padding(.top, 8)
            controls.padding(.horizontal, 16).padding(.vertical, 6)
            if !branchTried, model.branch.isEmpty, !model.retrying {
                Text("Mou qualsevol peça per explorar una altra jugada.").font(Theme.text(14)).foregroundStyle(Theme.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: model.branch.isEmpty) { _, empty in if !empty { branchTried = true } }
    }

    private var marks: [(ply: Int, cls: MoveClass)] {
        (model.review?.moves ?? []).compactMap { m in
            guard let c = m.moveClass, [.brilliant, .great, .miss, .blunder, .mistake].contains(c) else { return nil }
            return (m.ply + 1, c)
        }
    }

    private var currentWin: Double {
        if !model.branch.isEmpty, let e = model.branchEval { return Accuracy.winPercent(e) }
        // While it's your turn to try, the bar must not give away how the played move turned out.
        let shown = model.retrying ? max(model.ply - 1, 0) : model.ply
        guard let g = model.review?.graph, shown < g.count, let v = g[shown] else { return 50 }
        return v
    }

    private var evalLabel: String {
        if !model.branch.isEmpty { return model.branchEval?.whiteLabel(sideToMove: .white) ?? "" }
        guard let e = model.retrying ? model.move?.evalBefore : model.move?.evalAfter else { return "" }
        return e.whiteLabel(sideToMove: .white)
    }

    @ViewBuilder private var coach: some View {
        if model.retrying {
            VStack(alignment: .leading, spacing: 8) {
                Text(retryTitle).font(Theme.display(32)).foregroundStyle(Theme.tin)
                if let idea = model.retryIdea, model.retryState != .right {
                    Text("Pensa en això: \(idea).").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                }
                HStack(spacing: 18) {
                    if model.retryState == .idle || model.retryState == .wrong {
                        Button("Una pista") { model.retryHint() }
                    }
                    if model.retryState == .wrong {
                        Button("Mostra la millor") { model.go(model.ply, sound: false); model.showBest() }
                    }
                    Button(model.retryState == .right ? "Mira què va passar" : "Passa") { model.backToGame() }
                }
                .font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.branch.isEmpty {
            branchCoach
        } else if let m = model.move {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let c = m.moveClass { MoveClassBadge(cls: c, size: 26) }
                    SANText(san: m.san, size: 20).foregroundStyle(Theme.tin)
                    if let c = m.moveClass { Text(verbatim: c.displayName).font(Theme.text(18, .medium)).foregroundStyle(c.fill) }
                    Spacer()
                    if let e = m.evalAfter { Text(verbatim: e.whiteLabel(sideToMove: .white)).font(Theme.text(16, .medium)).foregroundStyle(Theme.quiet) }
                }
                if let t = m.coach?.text, !t.isEmpty {
                    ScrollView { SANText.prose(t, size: 16).font(Theme.text(16)).foregroundStyle(Theme.tin.opacity(0.92)).accessibilityLabel(t).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 66)
                }
                HStack(spacing: 18) {
                    if let s = m.coach?.show, !(m.coach?.line.isEmpty ?? true) {
                        Button(model.showingLine ? String(localized: "Amaga") : s.title) { model.showingLine ? model.hideCoachLine() : model.playCoachLine() }
                    }
                    if m.bestMove != nil, m.moveClass != .best, m.moveClass != .book, m.moveClass != .forced { Button("La millor") { model.showBest() } }
                    if model.canRetry {
                        Button("Reintenta") { model.beginRetry() }
                        Button("Torna-la a jugar") { model.replayFrom = m.ply }
                    }
                }
                .font(Theme.text(15, .semibold)).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.75)
            }
        } else {
            Text("Posició inicial").font(Theme.display(32)).foregroundStyle(Theme.tin).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The analysis board: the move tried, how the engine rates it, and why, in the review's own words.
    private var branchCoach: some View {
        let step = model.branch[safe: model.branchAt - 1]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Rubric("Variant")
                Spacer()
                Button("Torna a la partida") { model.backToGame() }.font(Theme.text(15, .semibold)).foregroundStyle(Theme.gold)
            }
            HStack(spacing: 8) {
                if let step {
                    if let c = step.verdict?.moveClass { MoveClassBadge(cls: c, size: 26) }
                    SANText(san: step.san, size: 20).foregroundStyle(Theme.tin)
                    if let c = step.verdict?.moveClass { Text(verbatim: c.displayName).font(Theme.text(18, .medium)).foregroundStyle(c.fill) }
                }
                Spacer()
                if let e = model.branchEval { Text(verbatim: e.whiteLabel(sideToMove: .white)).font(Theme.text(16, .medium)).foregroundStyle(Theme.quiet) }
            }
            if let t = step?.verdict?.note.text {
                ScrollView { SANText.prose(t, size: 16).font(Theme.text(16)).foregroundStyle(Theme.tin.opacity(0.92)).accessibilityLabel(t).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 66)
            } else {
                Text(step == nil ? "Mou qualsevol peça per explorar una altra jugada." : "El motor pensa").font(Theme.text(16)).foregroundStyle(Theme.quiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var retryTitle: LocalizedStringKey {
        switch model.retryState {
        case .idle: "Troba una jugada millor"
        case .thinking: "Mirant-ho"
        case .wrong: "Aquesta no"
        case .right: "Ben trobat"
        }
    }

    private var engineLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.lines, id: \.multipv) { l in
                Button { model.tryCandidate(l) } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: scoreLabel(l)).font(Theme.text(14, .semibold)).foregroundStyle(Theme.gold).frame(width: 46, alignment: .leading)
                        Text(verbatim: sanLine(l)).font(Theme.text(14)).foregroundStyle(Theme.tin).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if model.lines.isEmpty { Text("El motor pensa").font(Theme.text(14)).foregroundStyle(Theme.quiet) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 8)
    }

    private func scoreLabel(_ l: EngineLine) -> String { l.score.whiteLabel(sideToMove: model.board.position.side) }
    private func sanLine(_ l: EngineLine) -> String {
        var p = model.board.position; var out: [String] = []
        for m in l.pv.prefix(7) { guard p.isLegal(m) else { break }; out.append(p.san(m)); p = p.applying(m) }
        return out.joined(separator: " ")
    }

    private var moveStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(model.review?.moves ?? []) { m in
                        Button { model.go(m.ply + 1) } label: {
                            chip(m.side == .white ? "\(m.ply / 2 + 1)." : nil, m.san, m.moveClass, current: m.ply + 1 == model.ply)
                        }
                        .buttonStyle(.plain).id(m.ply + 1)
                    }
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: model.ply) { _, p in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(max(p, 1), anchor: .center) } }
        }
        .frame(height: 34)
    }

    /// The branch's moves in place of the game's, numbered from where it left the game.
    private var branchStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(Array(model.branch.enumerated()), id: \.offset) { i, s in
                        // Full moves count up after Black's, so a White move's number is the one after it.
                        let white = s.after.side == .black
                        Button { model.stepBranch(to: i + 1) } label: {
                            chip(white ? "\(s.after.fullmoveNumber)." : i == 0 ? "\(s.after.fullmoveNumber - 1)…" : nil,
                                 s.san, s.verdict?.moveClass, current: i + 1 == model.branchAt)
                        }
                        .buttonStyle(.plain).id(i + 1)
                    }
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: model.branchAt) { _, p in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(max(p, 1), anchor: .center) } }
        }
        .frame(height: 34)
    }

    private func chip(_ number: String?, _ san: String, _ cls: MoveClass?, current: Bool) -> some View {
        HStack(spacing: 3) {
            if let number { Text(verbatim: number).font(Theme.text(13)).foregroundStyle(current ? Theme.ink.opacity(0.6) : Theme.quiet) }
            SANText(san: san, size: 15).foregroundStyle(current ? Theme.ink : Theme.tin)
            if let c = cls, ![.best, .excellent, .good, .book, .forced].contains(c) { MoveClassBadge(cls: c, size: 13) }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(current ? Theme.tin : .clear))
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { model.toggleLines() } label: { Image(systemName: model.showLines ? "cpu.fill" : "cpu").frame(width: 44, height: 44) }
                .foregroundStyle(model.showLines ? Theme.gold : Theme.tin).accessibilityLabel("Motor")
            Button { model.walking = false } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }
                .foregroundStyle(Theme.tin).accessibilityLabel("Resum")
            Spacer()
            Button { model.previous() } label: { Image(systemName: "chevron.left").frame(width: 56, height: 44) }.foregroundStyle(Theme.tin).accessibilityLabel("Jugada anterior")
            Button { model.next() } label: { Image(systemName: "chevron.right").frame(width: 56, height: 44) }.foregroundStyle(Theme.tin).accessibilityLabel("Jugada següent")
            Spacer()
            Button { model.nextKey() } label: {
                Text("Següent clau").padding(.horizontal, 16)
            }
            .buttonStyle(CartoucheButtonStyle(compact: true))
        }
        .font(.system(size: 18, weight: .medium))
    }
}

/// SAN with figurines, so notation needs no translation. The string stays plain SAN for VoiceOver.
struct SANText: View {
    let san: String
    var size: CGFloat = 16
    var body: some View {
        Self.text(san, size: size).font(Theme.text(size, .medium)).accessibilityLabel(san)
    }
    static func text(_ san: String, size: CGFloat) -> Text {
        guard let first = san.first, "KQRBN".contains(first) else { return Text(verbatim: san) }
        let letter = ["K": "k", "Q": "q", "R": "r", "B": "b", "N": "n"][String(first)]!
        let image = figurine(letter, size: size)
        return Text("\(Image(uiImage: image).renderingMode(.template))\(Text(verbatim: String(san.dropFirst())))")
    }
    /// Running text with SAN inside it: every piece letter becomes its figurine, so a sentence needs no translated notation.
    static func prose(_ text: String, size: CGFloat) -> Text {
        let pattern = /\b[KQRBN][a-h1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?/
        var out = Text(verbatim: "")
        var rest = Substring(text)
        while let m = rest.firstMatch(of: pattern) {
            out = Text("\(out)\(Text(verbatim: String(rest[..<m.range.lowerBound])))\(Self.text(String(m.output), size: size))")
            rest = rest[m.range.upperBound...]
        }
        return Text("\(out)\(Text(verbatim: String(rest)))")
    }

    private static var cache: [String: UIImage] = [:]
    private static func figurine(_ letter: String, size: CGFloat) -> UIImage {
        let key = "\(letter)\(size)"
        if let c = cache[key] { return c }
        let base = PieceImage.load("fig" + letter)
        let h = size * 1.02, w = h * base.size.width / max(base.size.height, 1)
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in base.draw(in: CGRect(x: 0, y: 0, width: w, height: h)) }
            .withRenderingMode(.alwaysTemplate).withBaselineOffset(fromBottom: size * 0.1)
        cache[key] = img
        return img
    }
}
