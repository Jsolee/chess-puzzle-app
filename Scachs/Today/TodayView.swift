import SwiftUI

/// One moment of your own game at a time: the board asks first, the answer comes after.
@MainActor @Observable final class TodayModel {
    enum Phase { case asking, wrong, found, shown }

    let board = BoardModel()
    private(set) var card: MistakeCard?
    private(set) var phase: Phase = .asking
    private(set) var idea: String?
    @ObservationIgnored private var hintLevel = 0
    @ObservationIgnored private var missed = false
    @ObservationIgnored private var answered = false

    /// Only fills an empty board: things finishing in the background must not pull an answer away while you read it.
    func load() {
        guard card == nil else { return }
        card = Progress.shared.nextMistake().map(GameLibrary.shared.relocalized)
        guard let card, let position = Position(fen: card.fen) else { return }
        phase = .asking; idea = nil; hintLevel = 0; missed = false; answered = false
        board.arrows = []; board.hint = nil; board.marks = []
        board.orientation = card.side
        board.set(position, animated: true)
        board.lastMove = card.lastMove.flatMap(Move.init(uci:))
        board.interactive = true
        board.onMove = { [weak self] m in self?.attempt(m) }
    }

    func next() {
        card = nil
        load()
    }

    private func attempt(_ m: Move) {
        guard let card else { return }
        if m.uci == card.bestUCI || board.position.applying(m).isCheckmate {
            board.hint = nil
            board.play(m)
            board.interactive = false
            board.reflex(from: m.to)
            answer(solved: !missed)
            phase = .found
        } else {
            board.flashWrong(m.to)
            missed = true
            phase = .wrong
        }
    }

    private func answer(solved: Bool) {
        guard let card, !answered else { return }
        answered = true
        Progress.shared.answerMistake(card, solved: solved)
    }

    func hint() {
        guard let card, let best = Move(uci: card.bestUCI) else { return }
        hintLevel += 1
        missed = true
        if hintLevel == 1, let motif = card.motif, ThemeNames.idea(of: [motif]) != nil {
            idea = ThemeNames.name(motif)
        } else {
            board.hint = best.from
            Haptics.tap(0.2, sharpness: 0.3)
        }
    }

    func reveal() {
        guard let card, let best = Move(uci: card.bestUCI) else { return }
        board.interactive = false
        board.hint = nil
        board.arrows = [BoardArrow(from: best.from, to: best.to, role: .best)]
        answer(solved: false)
        phase = .shown
    }
}

/// The home screen: what's worth doing today, in the order it helps, and nothing about what wasn't done.
struct TodayView: View {
    @State private var model = TodayModel()
    @State private var dailyBoard = BoardModel()
    @State private var openLesson: LessonMeta?
    @State private var focus: FocusedPuzzles?
    @State private var cover: Cover?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("showStreak") private var showStreak = true
    @AppStorage("chartHeld") private var chartHeld = ""
    private var library: GameLibrary { .shared }
    private var auto: AutoReview { .shared }

    private enum Cover: Int, Identifiable { case daily, blindfold, sunday, atlas, chart; var id: Int { rawValue } }
    private struct FocusedPuzzles: Identifiable { let themes: Set<String>; var id: String { themes.sorted().joined() } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    rows.padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 28)
                }
            }
            .fieldBackground()
            .topBar(Text("Avui").foregroundColor(.clear)) {
                Image("Wordmark").renderingMode(.template).resizable().scaledToFit().frame(height: 26).foregroundStyle(Theme.tin)
                    .padding(.leading, 12).accessibilityLabel("Scachs")
            } trailing: {
                hud.padding(.trailing, 14)
            }
            .sheet(item: $openLesson) { LessonRunnerView(meta: $0) }
            .fullScreenCover(item: $focus) { PuzzleView(focus: $0.themes) }
            .fullScreenCover(item: $cover) { cover in
                switch cover {
                case .daily: DailyPuzzleView()
                case .blindfold: BlindfoldView()
                case .sunday: SundayGameView()
                case .atlas: AtlasView()
                case .chart: ChartView()
                }
            }
            .onChange(of: cover) { _, now in if now == nil { showDaily() } }
            .task { await refresh() }
            #if DEBUG
            .onAppear { if ScreenshotScene.is("atlas") { cover = .atlas }; if ScreenshotScene.is("chart") { cover = .chart } }
            #endif
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
            .onChange(of: auto.finished) { _, _ in model.load() }
        }
    }

    private func refresh() async {
        library.harvestOldReviews()
        model.load()
        showDaily()
        await library.refreshIfStale()
        auto.kick()
        WidgetSnapshot.write()
    }

    /// The streak, if it's shown, and the puzzle rating once it's settled.
    private var hud: some View {
        let streak = DailyStreak(days: Progress.shared.dailyDays, today: PuzzleStore.dayNumber(Date()))
        return HStack(spacing: 14) {
            if showStreak && streak.current > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(Color(hex: 0xEF8A3C))
                    Text(verbatim: "\(streak.current)")
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(Text("Ratxa de \(streak.current)"))
            }
            if !Progress.shared.isProvisional {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill").foregroundStyle(Theme.gold)
                    Text(verbatim: "\(Int(Progress.shared.rating.rounded()))")
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(Text("Puntuació de puzzles: \(Int(Progress.shared.rating.rounded()))"))
            }
        }
        .font(Theme.text(16, .semibold)).foregroundStyle(Theme.tin)
    }

    /// "Avui · dimecres, 11 de novembre": the screen's name and the date in one line, so the board comes up.
    private var rubric: Text {
        Text(verbatim: String(localized: "Avui") + " · " + Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
    }

    // MARK: The board

    @ViewBuilder private var hero: some View {
        if let card = model.card {
            moment(card)
        } else {
            dailyHero
        }
    }

    private func moment(_ card: MistakeCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BoardHeader(rubric: rubric, title: Text(momentTitle), subtitle: Text(verbatim: momentSubtitle(card)), warn: model.phase == .wrong)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            .animation(.easeOut(duration: 0.2), value: model.phase)
            BoardView(model.board).boardFrame()
            Group {
                switch model.phase {
                case .asking, .wrong:
                    HStack(spacing: 6) {
                        Button { model.hint() } label: { Label("Pista", systemImage: "lightbulb.fill") }.buttonStyle(.tool)
                        Button { model.reveal() } label: { Label("Solució", systemImage: "eye.fill") }.buttonStyle(.tool)
                        Spacer()
                    }
                case .found, .shown:
                    VStack(alignment: .leading, spacing: 12) {
                        if let note = card.note, !note.isEmpty {
                            SANText.prose(note, size: 16).font(Theme.text(16, .medium)).foregroundStyle(Theme.tin)
                                .fixedSize(horizontal: false, vertical: true).accessibilityLabel(note)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .panel(model.phase == .found ? Theme.goodPanel : Theme.panel)
                        }
                        Button { model.next() } label: {
                            Text("Següent")
                        }
                        .buttonStyle(.plaque)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12)
        }
    }

    private var momentTitle: LocalizedStringKey {
        switch model.phase {
        case .asking: "Aquí hi havia més"
        case .wrong: "Aquesta no"
        case .found: "Ben trobat"
        case .shown: "Era aquesta"
        }
    }

    private func momentSubtitle(_ card: MistakeCard) -> String {
        if let idea = model.idea, model.phase == .asking || model.phase == .wrong { return String(localized: "Pensa en això: \(idea).") }
        switch model.phase {
        case .asking: return String(localized: "Contra \(card.opponent) vas jugar \(card.playedSAN). Troba'n una de millor.")
        case .wrong: return String(localized: "Torna-hi, o mira la solució.")
        case .found, .shown: return String(localized: "A la partida vas jugar \(card.playedSAN).")
        }
    }

    private var dailyHero: some View {
        let solved = Progress.shared.dailyDays.contains(PuzzleStore.dayNumber(Date()))
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                BoardHeader(rubric: rubric, title: Text("Puzzle del dia"), subtitle: Text(solved ? "Resolt." : "Toca el tauler per començar."))
                if let game = auto.current {
                    Text("Analitzant la partida contra \(game.mySide == .white ? game.black : game.white). \(Int(auto.progress * 100)) %")
                        .font(Theme.text(14)).foregroundStyle(Theme.quiet).lineLimit(1).contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            BoardView(dailyBoard).boardFrame()
                .contentShape(Rectangle())
                .onTapGesture { cover = .daily }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Puzzle del dia")
            if !library.hasAccounts {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vincula el teu compte i aquí sortiran els moments de les teves partides.").font(Theme.text(16)).foregroundStyle(Theme.tin)
                    AccountFields()
                }
                .padding(.horizontal, 16).padding(.top, 18)
            }
        }
    }

    private func showDaily() {
        let p = PuzzleStore.shared.daily(for: Date())
        dailyBoard.interactive = false
        dailyBoard.orientation = p.solverSide
        let afterSetup = p.start.applying(p.start.move(uci: p.line[0].uci) ?? p.line[0])
        dailyBoard.set(afterSetup, animated: false)
        dailyBoard.lastMove = p.line[0]
    }

    // MARK: What else

    private var rows: some View {
        let pick = Recommender.next(progress: .shared, lessons: LessonLibrary.shared.metas, reviewEvidence: library.missedTacticEvidence)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Per avui").padding(.bottom, 4)
            if model.card != nil { DailyRow { cover = .daily } }
            if let pick {
                row("Lliçó", icon: Image("tab.lessons"), color: Color(hex: 0xE8705F), detail: pick.lesson.title) { openLesson = pick.lesson }
                row("Tres puzzles", icon: Image("tab.puzzles"), detail: pick.lesson.title) { focus = FocusedPuzzles(themes: Set(pick.lesson.tags.keys)) }
            }
            chartCard
            row("La partida del diumenge", icon: Image("tab.games"), color: Theme.good, detail: SundayGames.current().title.current) { cover = .sunday }
            row("A cegues, amb auriculars", icon: Image(systemName: "headphones"), color: Theme.muted, detail: nil) { cover = .blindfold }
            row("L'Atles de les teves obertures", icon: Image("icon.rose"), color: Color(hex: 0x6FA8DC), detail: nil) { cover = .atlas }
        }
    }

    /// The chart of themes as an ink map: as much of it lit as you've brought out of the fog.
    private var chartCard: some View {
        let standings = SeaChart.standings(Progress.shared.attempts)
        let held = Set(chartHeld.split(separator: ",").map(String.init))
        let total = SeaChart.themes.count
        let explored = SeaChart.themes.filter { held.contains($0) || (standings[$0]?.state ?? .fog) != .fog }.count
        return Button { cover = .chart } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("La carta dels temes").font(Theme.title(17)).foregroundStyle(Theme.tin)
                    Text("\(explored) de \(total) terres").font(Theme.text(13, .semibold)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                InkChart(lit: CGFloat(explored) / CGFloat(max(total, 1)))
            }
            .panel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("La carta dels temes: \(explored) de \(total) terres"))
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ title: LocalizedStringKey, icon: Image, color: Color = Theme.gold, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Medallion(image: icon, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.text(16, .semibold)).foregroundStyle(Theme.tin)
                    if let detail { Text(verbatim: detail).font(Theme.text(14)).foregroundStyle(Theme.muted).lineLimit(1) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .panel(padding: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An ink map in the manner of an old chart: coast, a wood, hills, a range of mountains, a river, and a dotted road to a tower.
/// What's been explored is drawn in full gold; the rest waits faded. Drawn on a 260 by 60 grid.
private struct InkChart: View {
    let lit: CGFloat

    var body: some View {
        GeometryReader { g in
            let k = g.size.width / 260
            let end = InkMap.route.trimmedPath(from: 0, to: max(0.02, min(1, lit))).currentPoint ?? CGPoint(x: 8, y: 32)
            let ink = ZStack(alignment: .topLeading) {
                InkMap.land.applying(CGAffineTransform(scaleX: k, y: k)).stroke(Theme.gold, style: StrokeStyle(lineWidth: 0.9 * k, lineCap: .round, lineJoin: .round))
                InkMap.route.applying(CGAffineTransform(scaleX: k, y: k)).stroke(Theme.gold, style: StrokeStyle(lineWidth: 1.7 * k, lineCap: .round, dash: [0.1, 3.4 * k]))
                InkMap.tower.applying(CGAffineTransform(scaleX: k, y: k)).fill(Theme.gold)
                Image("icon.rose").renderingMode(.template).resizable().frame(width: 15 * k, height: 15 * k).foregroundStyle(Theme.gold)
                    .position(x: 250.5 * k, y: 49.5 * k)
            }
            ZStack(alignment: .topLeading) {
                ink.opacity(0.3)
                ink.mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: min(1, (end.x + 4) / 260)),
                                                .init(color: .clear, location: min(1, (end.x + 22) / 260))], startPoint: .leading, endPoint: .trailing))
                Circle().stroke(Theme.gold.opacity(0.5), lineWidth: 1).frame(width: 10 * k, height: 10 * k).position(x: end.x * k, y: end.y * k)
                Rectangle().fill(Theme.gold).frame(width: 5 * k, height: 5 * k).rotationEffect(.degrees(45)).position(x: end.x * k, y: end.y * k)
            }
        }
        .aspectRatio(260 / 60, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private enum InkMap {
    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static let land = Path { p in
        p.move(to: pt(0, 44))
        p.addCurve(to: pt(44, 48), control1: pt(14, 40), control2: pt(26, 50))
        p.addCurve(to: pt(92, 56), control1: pt(62, 46), control2: pt(74, 54))
        p.addCurve(to: pt(114, 60), control1: pt(110, 58), control2: pt(108, 59))
        for (x, y) in [(8.0, 53.0), (26, 57), (48, 58)] {
            p.move(to: pt(x, y))
            p.addQuadCurve(to: pt(x + 4, y), control: pt(x + 2, y - 2))
            p.addQuadCurve(to: pt(x + 8, y), control: pt(x + 6, y + 2))
        }
        for (x0, y, n) in [(22.0, 29.0, 5), (17, 40, 6)] {
            for i in 0..<n {
                let x = x0 + CGFloat(i) * 9
                p.move(to: pt(x, y)); p.addLine(to: pt(x, y - 3))
                p.addCurve(to: pt(x, y - 14), control1: pt(x - 3.8, y - 3), control2: pt(x - 4.2, y - 8.2))
                p.addCurve(to: pt(x, y - 3), control1: pt(x + 4.2, y - 8.2), control2: pt(x + 3.8, y - 3))
            }
        }
        for (x, y) in [(80.0, 30.0), (92, 24), (102, 32)] {
            p.move(to: pt(x, y)); p.addQuadCurve(to: pt(x + 10, y), control: pt(x + 5, y - 6))
        }
        for (x, y, s) in [(130.0, 36.0, 14.0), (141, 32, 17), (154, 36, 13), (164, 30, 18), (178, 34, 15), (190, 28, 19), (204, 33, 15), (216, 36, 12)] {
            p.move(to: pt(x, y)); p.addLine(to: pt(x + s / 2, y - s)); p.addLine(to: pt(x + s, y))
            for t in [0.3, 0.55, 0.8] {
                let a = pt(x + s / 2 + t * s / 2, y - s + t * s)
                p.move(to: a); p.addLine(to: pt(a.x - s * 0.1, a.y + s * (1 - t) * 0.75))
            }
        }
        p.move(to: pt(160, 38))
        p.addCurve(to: pt(130, 48), control1: pt(152, 44), control2: pt(140, 40))
        p.addCurve(to: pt(102, 58), control1: pt(120, 56), control2: pt(110, 52))
    }

    static let route = Path { p in
        p.move(to: pt(8, 32))
        p.addCurve(to: pt(66, 38), control1: pt(26, 42), control2: pt(46, 42))
        p.addCurve(to: pt(116, 44), control1: pt(86, 34), control2: pt(98, 34))
        p.addCurve(to: pt(168, 46), control1: pt(134, 54), control2: pt(146, 52))
        p.addCurve(to: pt(220, 44), control1: pt(190, 40), control2: pt(198, 40))
        p.addCurve(to: pt(238, 31), control1: pt(242, 48), control2: pt(234, 38))
    }

    static let tower = Path { p in
        p.addLines([pt(232, 31), pt(244, 31), pt(242.5, 28), pt(242.5, 22), pt(244, 20.5), pt(244, 17), pt(241.6, 17), pt(241.6, 18.8),
                    pt(239.8, 18.8), pt(239.8, 17), pt(237.4, 17), pt(237.4, 18.8), pt(235.6, 18.8), pt(235.6, 17), pt(233.2, 17),
                    pt(233.2, 20.5), pt(234.7, 22), pt(234.7, 28)])
        p.closeSubpath()
    }

}
