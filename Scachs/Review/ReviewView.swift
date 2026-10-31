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
    var variation: [Move] = []
    var retrying = false
    var retryState: RetryState = .idle
    var showingLine = false
    enum RetryState { case idle, thinking, wrong, right }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    @ObservationIgnored private var lineTask: Task<Void, Never>?
    @ObservationIgnored private var analysisRun = 0

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
        board.set(r.positions[0], animated: false)
        if let saved = GameLibrary.shared.review(for: game.id), saved.isComplete { review = saved; return }
        runEngine(pgn)
    }

    private func runEngine(_ pgn: PGNGame) {
        running = true; failure = nil
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

    func stop() { task?.cancel(); task = nil; engineTask?.cancel(); lineTask?.cancel() }
    func retryEngine() { if let pgn { runEngine(pgn) } }

    // MARK: Walking through

    func beginWalk() { walking = true; go(firstKey() ?? 1) }
    private func firstKey() -> Int? { review?.moves.first { $0.isKey }.map { $0.ply + 1 } }

    func go(_ target: Int, sound: Bool = true) {
        guard let r = replay else { return }
        let n = max(0, min(r.positions.count - 1, target))
        lineTask?.cancel(); showingLine = false
        retrying = false; retryState = .idle; variation = []
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
        if showLines { analyseHere() }
    }

    func decorate() {
        guard let m = move else { board.arrows = []; board.marks = []; board.badge = nil; return }
        board.arrows = m.coach?.arrows ?? []
        board.marks = m.coach?.marks ?? []
        if let c = m.moveClass, let mv = Move(uci: m.uci) { board.badge = (mv.to, c) } else { board.badge = nil }
    }

    func next() { go(ply + 1) }
    func previous() { go(ply - 1, sound: false) }
    func nextKey() {
        if let k = review?.moves.first(where: { $0.isKey && $0.ply + 1 > ply }) { go(k.ply + 1) } else { go((replay?.positions.count ?? 1) - 1) }
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
        retrying = true; retryState = .idle
        board.set(r.positions[ply - 1], animated: true)
        board.arrows = []; board.marks = []; board.badge = nil; board.lastMove = nil
        board.interactive = true
        board.onMove = { [weak self] m in self?.retryMove(m) }
    }

    private func retryMove(_ m: Move) {
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
        if showLines { analyseHere() } else { engineTask?.cancel(); lines = [] }
    }

    private func exploreMove(_ m: Move) {
        variation.append(m)
        board.play(m)
        board.arrows = []; board.marks = []; board.badge = nil
        if showLines { analyseHere() }
    }

    func backToGame() { go(ply, sound: false) }

    func analyseHere() {
        engineTask?.cancel()
        // What the board shows, which isn't always the game's position: a best-move preview or a coach line.
        let fen = board.position.fen
        lines = []
        analysisRun += 1
        let run = analysisRun
        engineTask = Task { [weak self] in
            let result = try? await Engine.shared.analyse(startFEN: fen, moves: [], multiPV: 3, nodes: nil, movetimeMs: 15000, searchMoves: nil) { lines in
                Task { @MainActor in if self?.analysisRun == run { self?.lines = lines } }
            }
            if let result, !Task.isCancelled, self?.analysisRun == run { self?.lines = result }
        }
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

struct ReviewView: View {
    @State private var model: ReviewModel
    init(game: ImportedGame) { _model = State(initialValue: ReviewModel(game: game)) }

    var body: some View {
        Group {
            if model.walking, model.review != nil { WalkthroughView(model: model) }
            else if let r = model.review { ReviewSummary(model: model, review: r) }
            else { ReviewProgress(model: model) }
        }
        .background(Theme.field.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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
            EvalGraph(values: paddedGraph).frame(height: 96)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: review.opening?.name ?? String(localized: "Revisió")).font(Theme.display(38)).foregroundStyle(Theme.tin)
                        .lineLimit(3).minimumScaleFactor(0.7)
                    Text(verbatim: "\(model.game.white) – \(model.game.black) · \(model.game.result)").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                }
                EvalGraph(values: review.graph, marks: keyMarks).frame(height: 96)
                players
                table
                if !review.phases.isEmpty { phases }
                Button { model.beginWalk() } label: {
                    Text("Revisa la partida").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
                }
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
        VStack(alignment: a, spacing: 2) {
            Text(verbatim: name).font(Theme.text(15)).foregroundStyle(Theme.quiet).lineLimit(1)
            Text(verbatim: p.accuracy.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
                .font(Theme.text(50, .medium)).foregroundStyle(Theme.tin)
            if let r = p.gameRating {
                Text("Nivell d'aquesta partida: \(r)").font(Theme.text(13)).foregroundStyle(Theme.quiet)
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            ForEach(Self.order, id: \.self) { c in
                let w = review.white.counts[c] ?? 0, b = review.black.counts[c] ?? 0
                HStack {
                    Text(verbatim: "\(w)").font(Theme.text(17, .medium)).foregroundStyle(w > 0 ? c.fill : Theme.quiet.opacity(0.5)).frame(width: 34, alignment: .leading)
                    Spacer()
                    Text(verbatim: c.displayName).font(Theme.text(15)).foregroundStyle(Theme.tin.opacity(0.86))
                    MoveClassBadge(cls: c, size: 20)
                    Spacer()
                    Text(verbatim: "\(b)").font(Theme.text(17, .medium)).foregroundStyle(b > 0 ? c.fill : Theme.quiet.opacity(0.5)).frame(width: 34, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
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
            moveStrip.padding(.top, 8)
            controls.padding(.horizontal, 16).padding(.vertical, 6)
        }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var marks: [(ply: Int, cls: MoveClass)] {
        (model.review?.moves ?? []).compactMap { m in
            guard let c = m.moveClass, [.brilliant, .great, .miss, .blunder, .mistake].contains(c) else { return nil }
            return (m.ply + 1, c)
        }
    }

    private var currentWin: Double {
        guard let g = model.review?.graph, model.ply < g.count, let v = g[model.ply] else { return 50 }
        return v
    }

    private var evalLabel: String {
        guard let e = model.move?.evalAfter else { return "" }
        return e.whiteLabel(sideToMove: .white)
    }

    @ViewBuilder private var coach: some View {
        if model.retrying {
            VStack(alignment: .leading, spacing: 8) {
                Text(retryTitle).font(Theme.display(32)).foregroundStyle(Theme.tin)
                if model.retryState == .right || model.retryState == .wrong {
                    Button("Torna a la partida") { model.backToGame() }.font(Theme.text(16, .semibold))
                }
                if model.retryState == .wrong {
                    Button("Mostra la millor") { model.go(model.ply, sound: false); model.showBest() }.font(Theme.text(16, .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.variation.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Variant").font(Theme.display(32)).foregroundStyle(Theme.tin)
                Button("Torna a la partida") { model.backToGame() }.font(Theme.text(16, .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    if model.canRetry { Button("Reintenta") { model.beginRetry() } }
                }
                .font(Theme.text(15, .semibold)).foregroundStyle(Theme.gold)
            }
        } else {
            Text("Posició inicial").font(Theme.display(32)).foregroundStyle(Theme.tin).frame(maxWidth: .infinity, alignment: .leading)
        }
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
                HStack(spacing: 8) {
                    Text(verbatim: scoreLabel(l)).font(Theme.text(14, .semibold)).foregroundStyle(Theme.gold).frame(width: 46, alignment: .leading)
                    Text(verbatim: sanLine(l)).font(Theme.text(14)).foregroundStyle(Theme.tin).lineLimit(1)
                }
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
                            HStack(spacing: 3) {
                                if m.side == .white { Text(verbatim: "\(m.ply / 2 + 1).").font(Theme.text(13)).foregroundStyle(Theme.quiet) }
                                SANText(san: m.san, size: 15).foregroundStyle(m.ply + 1 == model.ply ? Theme.ink : Theme.tin)
                                if let c = m.moveClass, ![.best, .excellent, .good, .book, .forced].contains(c) { MoveClassBadge(cls: c, size: 13) }
                            }
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(m.ply + 1 == model.ply ? Theme.tin : .clear))
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
                Text("Següent clau").font(Theme.text(16, .semibold)).foregroundStyle(Theme.ink).padding(.horizontal, 14).frame(height: 40).background(Capsule().fill(Theme.tin))
            }
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
